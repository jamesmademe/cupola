import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_provider.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/domain/seerr_arr_server.dart';
import 'package:cupola/features/discover/domain/seerr_media_copy.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:cupola/features/media/domain/media_collection.dart';
import 'package:cupola/features/media/domain/media_copies.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/media/domain/media_reading.dart';
import 'package:cupola/features/media/domain/media_rows.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/plex/presentation/plex_provider.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/domain/stream_external_match.dart';

/// One source of a Media page: a title, read through one connection.
///
/// A record, so a family keyed on it compares structurally.
typedef MediaSource = ({MediaKey key, String connectionId});

/// The connections of [service] that are set up enough to ask, in the order
/// the settings keep them.
List<ServiceInstance> _configured(Ref ref, ServiceKey service) => ref
    .watch(currentSettingsProvider)
    .instancesOf(service)
    .where((instance) => instance.isConfigured)
    .toList(growable: false);

/// The arr that holds titles of [key]'s kind.
ServiceKey _arrOf(MediaKey key) =>
    key.isMovie ? ServiceKey.radarr : ServiceKey.sonarr;

/// What the Radarr [MediaSource.connectionId] holds of the film: one
/// `movie?tmdbId=` read, and that Radarr's own queue.
///
/// A failure travels (`RadarrService.getMovieByTmdbId`): a Radarr that did
/// not answer is never a film it does not hold. The queue never fails the
/// copy: a queue that did not answer is a snapshot that says so, and the badge
/// waits for it.
final mediaRadarrCopyProvider = FutureProvider.autoDispose
    .family<MediaAnswer<MediaRadarrCopy>, MediaSource>((ref, source) async {
      final tmdbId = source.key.tmdbId;
      if (!source.key.isMovie || tmdbId == null) {
        throw ArgumentError.value(source.key, 'key', 'not a movie');
      }
      final radarr = ref.watch(radarrServiceForProvider(source.connectionId));
      final movie = await radarr.getMovieByTmdbId(tmdbId);
      final queue = movie == null
          ? ArrQueueSnapshot.empty
          : await ref.watch(
              radarrQueueSnapshotForProvider(source.connectionId).future,
            );
      return MediaAnswer(
        MediaRadarrCopy(movie: movie, queue: queue),
        DateTime.now(),
      );
    }, retry: noProviderRetry);

/// TVDB's id of the series [MediaKey] names: what Sonarr is asked by.
///
/// The key's own, else the first Seerr that answers with TMDB's record of the
/// series, else the first Sonarr whose library carries the TMDB id (Sonarr v4
/// records it; v3 does not, and a v3 Sonarr then cannot be matched without a
/// Seerr). Null when nobody can say.
final mediaTvdbIdProvider = FutureProvider.autoDispose.family<int?, MediaKey>((
  ref,
  key,
) async {
  if (key.isMovie) return null;
  final own = key.tvdbId;
  if (own != null) return own;
  for (final seerr in _configured(ref, ServiceKey.seerr)) {
    try {
      final record = await ref.watch(
        mediaSeerrRecordProvider((key: key, connectionId: seerr.id)).future,
      );
      final tvdb = record.value.tvdbId;
      if (tvdb != null) return tvdb;
    } catch (_) {
      // That Seerr's failure is on its own row; another may still say.
    }
  }
  for (final sonarr in _configured(ref, ServiceKey.sonarr)) {
    try {
      final library = await ref
          .watch(sonarrServiceForProvider(sonarr.id))
          .getSeriesOrThrow();
      for (final series in library) {
        if (series.tmdbId == key.tmdbId && series.tvdbId > 0) {
          return series.tvdbId;
        }
      }
    } catch (_) {
      // That Sonarr's failure is on its own row.
    }
  }
  return null;
}, retry: noProviderRetry);

/// What the Sonarr [MediaSource.connectionId] holds of the series: one
/// `series?tvdbId=` read, and that Sonarr's own queue by series.
///
/// A series whose TVDB id nobody can name reads as one this Sonarr does not
/// track ([mediaTvdbIdProvider] says when that is honest).
final mediaSonarrCopyProvider = FutureProvider.autoDispose
    .family<MediaAnswer<MediaSonarrCopy>, MediaSource>((ref, source) async {
      if (source.key.isMovie) {
        throw ArgumentError.value(source.key, 'key', 'not a series');
      }
      final sonarr = ref.watch(sonarrServiceForProvider(source.connectionId));
      final tvdbId = await ref.watch(mediaTvdbIdProvider(source.key).future);
      final series = tvdbId == null
          ? null
          : await sonarr.getSeriesByTvdbId(tvdbId);
      final queue = series == null
          ? ArrQueueSnapshot.empty
          : await ref.watch(
              sonarrQueueSnapshotForProvider(source.connectionId).future,
            );
      return MediaAnswer(
        MediaSonarrCopy(series: series, queue: queue),
        DateTime.now(),
      );
    }, retry: noProviderRetry);

/// What the media server [MediaSource.connectionId] answers about the title,
/// looked up by its ids and checked again here, as `streamAvailabilityProvider`
/// does: a client that forgets to verify cannot put a wrong Play on the page.
final mediaStreamCopyProvider = FutureProvider.autoDispose
    .family<MediaAnswer<MediaStreamCopy>, MediaSource>((ref, source) async {
      final connection = ref
          .watch(currentSettingsProvider)
          .instanceById(source.connectionId);
      final client = switch (connection?.service) {
        ServiceKey.jellyfin => ref.watch(
          jellyfinClientForProvider(source.connectionId),
        ),
        ServiceKey.plex => ref.watch(
          plexClientForProvider(source.connectionId),
        ),
        _ => throw ArgumentError.value(
          source.connectionId,
          'connectionId',
          'not a media server',
        ),
      };
      final key = source.key;
      final query = StreamExternalQuery(
        tmdbId: key.tmdbId?.toString(),
        tvdbId: key.tvdbId?.toString(),
        kind: key.isMovie ? StreamItemKind.movie : StreamItemKind.series,
      );
      final cancelToken = CancelToken();
      ref.onDispose(cancelToken.cancel);
      final lookup = await client.lookupByExternalId(
        tmdbId: query.tmdbId,
        tvdbId: query.tvdbId,
        kind: query.kind,
        cancelToken: cancelToken,
      );
      final item = lookup.item;
      final copy = switch (lookup.outcome) {
        StreamLookupOutcome.found
            when item != null &&
                streamExternalMatchScore(item, query) != null =>
          MediaStreamCopy.found(item),
        StreamLookupOutcome.notInLibrary =>
          const MediaStreamCopy.notInLibrary(),
        _ => const MediaStreamCopy.notVerified(),
      };
      return MediaAnswer(copy, DateTime.now());
    }, retry: noProviderRetry);

/// What the Seerr [MediaSource.connectionId] knows of the title: its record
/// and, when the connection may read them, the servers of the arr that holds
/// this kind of title.
final mediaSeerrRecordProvider = FutureProvider.autoDispose
    .family<MediaAnswer<MediaSeerrRecord>, MediaSource>((ref, source) async {
      final tmdbId = source.key.tmdbId;
      if (tmdbId == null) {
        throw ArgumentError.value(source.key, 'key', 'Seerr needs a TMDB id');
      }
      final seerr = ref.watch(seerrServiceForProvider(source.connectionId));
      final details = source.key.isMovie
          ? await seerr.getMovie(tmdbId)
          : await seerr.getTv(tmdbId);
      List<SeerrArrServer>? servers;
      try {
        servers = await seerr.getArrServers(_arrOf(source.key));
      } catch (_) {
        // An account without ADMIN may not read them, and a failed read is
        // no list either: no copy is bound, and nothing is claimed.
        servers = null;
      }
      return MediaAnswer(
        MediaSeerrRecord(details: details, arrServers: servers),
        DateTime.now(),
      );
    }, retry: noProviderRetry);

/// Whether [path], [title] and [year] Bazarr holds name the same copy as the
/// arr's: the same path, or the same title and year.
bool _sameCopy({
  required String? bazarrPath,
  required String? bazarrTitle,
  required int? bazarrYear,
  required String? path,
  required String title,
  required int year,
}) {
  if ((bazarrPath ?? '').isNotEmpty && bazarrPath == path) return true;
  final normalised = normaliseStreamTitle(bazarrTitle);
  return normalised != null &&
      normalised == normaliseStreamTitle(title) &&
      bazarrYear == year;
}

/// What the Bazarr [MediaSource.connectionId] holds of the title: the one arr
/// copy it follows, checked against that copy's path, or its title and year.
///
/// Bazarr follows one Radarr and one Sonarr and speaks in their ids, so every
/// tracked copy is asked by its id and the answer verified; the first that
/// matches is the copy Bazarr covers. A copy whose arr did not answer is
/// skipped: it is the arr's failure, already on the arr's own row.
final mediaBazarrCopyProvider = FutureProvider.autoDispose
    .family<MediaAnswer<MediaBazarrCopy?>, MediaSource>((ref, source) async {
      final bazarr = ref.watch(bazarrServiceForProvider(source.connectionId));
      final key = source.key;
      for (final arr in _configured(ref, _arrOf(key))) {
        final arrSource = (key: key, connectionId: arr.id);
        // The arr's copy, or nothing to ask Bazarr about. The arr's failure is
        // on its own row and skips the copy here; Bazarr's own fails this one.
        final ({int id, String? path, String title, int year})? copy;
        try {
          copy = key.isMovie
              ? switch ((await ref.watch(
                  mediaRadarrCopyProvider(arrSource).future,
                )).value.movie) {
                  final movie? => (
                    id: movie.id,
                    path: movie.path,
                    title: movie.title,
                    year: movie.year,
                  ),
                  null => null,
                }
              : switch ((await ref.watch(
                  mediaSonarrCopyProvider(arrSource).future,
                )).value.series) {
                  final series? => (
                    id: series.id,
                    path: series.path,
                    title: series.title,
                    year: series.year,
                  ),
                  null => null,
                };
        } catch (_) {
          continue;
        }
        if (copy == null) continue;
        if (key.isMovie) {
          final followed = await bazarr.getMovieById(copy.id);
          if (followed != null &&
              _sameCopy(
                bazarrPath: followed.path,
                bazarrTitle: followed.title,
                bazarrYear: followed.year,
                path: copy.path,
                title: copy.title,
                year: copy.year,
              )) {
            return MediaAnswer(
              MediaBazarrCopy(arrConnectionId: arr.id, movie: followed),
              DateTime.now(),
            );
          }
        } else {
          final followed = await bazarr.getSeriesById(copy.id);
          if (followed != null &&
              _sameCopy(
                bazarrPath: followed.path,
                bazarrTitle: followed.title,
                bazarrYear: followed.year,
                path: copy.path,
                title: copy.title,
                year: copy.year,
              )) {
            return MediaAnswer(
              MediaBazarrCopy(arrConnectionId: arr.id, series: followed),
              DateTime.now(),
            );
          }
        }
      }
      return MediaAnswer<MediaBazarrCopy?>(null, DateTime.now());
    }, retry: noProviderRetry);

/// The "On your server" rows of a title, one per fact, in the page's order:
/// the media servers, the arr copies (or Seerr's claims about them), Bazarr,
/// Seerr.
///
/// Every connection is read on its own, and no row waits for another: a
/// connection that did not answer costs its own row, never the page (rule 1).
/// What is not set up is decided from the settings alone, before anything is
/// asked (rule 3). A media server's unverified match draws nothing (rule 7).
final mediaRowsProvider = Provider.autoDispose.family<List<MediaRow>, MediaKey>(
  (ref, key) {
    final rows = <MediaRow>[];
    MediaSource sourceOf(ServiceInstance connection) =>
        (key: key, connectionId: connection.id);

    for (final service in const [ServiceKey.jellyfin, ServiceKey.plex]) {
      for (final connection in _configured(ref, service)) {
        final reading = MediaReading.of(
          ref.watch(mediaStreamCopyProvider(sourceOf(connection))),
        );
        if (reading case MediaReadingAnswered(
          :final answer,
        ) when answer.value.outcome == StreamLookupOutcome.notVerified) {
          continue;
        }
        rows.add(MediaConnectionRow<MediaStreamCopy>(connection, reading));
      }
    }

    // Seerr needs TMDB's id: a series known only by TVDB's is not asked.
    final seerrs = key.tmdbId == null
        ? const <ServiceInstance>[]
        : _configured(ref, ServiceKey.seerr);
    final seerrReadings = [
      for (final seerr in seerrs)
        (
          connection: seerr,
          reading: MediaReading.of(
            ref.watch(mediaSeerrRecordProvider(sourceOf(seerr))),
          ),
        ),
    ];

    final arr = _arrOf(key);
    final arrs = _configured(ref, arr);
    for (final connection in arrs) {
      rows.add(
        key.isMovie
            ? MediaConnectionRow<MediaRadarrCopy>(
                connection,
                MediaReading.of(
                  ref.watch(mediaRadarrCopyProvider(sourceOf(connection))),
                ),
              )
            : MediaConnectionRow<MediaSonarrCopy>(
                connection,
                MediaReading.of(
                  ref.watch(mediaSonarrCopyProvider(sourceOf(connection))),
                ),
              ),
      );
    }
    final claims = [
      for (final seerr in seerrReadings)
        if (seerr.reading case MediaReadingAnswered(:final answer))
          for (final copy in answer.value.copies)
            if (SeerrBoundCopy.of(
                  copy,
                  arr: arr,
                  servers: answer.value.arrServers,
                  connections: arrs,
                )
                case final bound when bound.isKnownOnlyToSeerr)
              MediaThroughSeerrRow(
                seerr: seerr.connection,
                copy: bound,
                mediaInfo: answer.value.mediaInfo,
              ),
    ];
    rows.addAll(claims);
    if (arrs.isEmpty && claims.isEmpty) rows.add(MediaNotSetUpRow(arr));

    for (final connection in _configured(ref, ServiceKey.bazarr)) {
      rows.add(
        MediaConnectionRow<MediaBazarrCopy?>(
          connection,
          MediaReading.of(
            ref.watch(mediaBazarrCopyProvider(sourceOf(connection))),
          ),
        ),
      );
    }

    for (final seerr in seerrReadings) {
      rows.add(
        MediaConnectionRow<MediaSeerrRecord>(seerr.connection, seerr.reading),
      );
    }
    if (_configured(ref, ServiceKey.seerr).isEmpty) {
      rows.add(const MediaNotSetUpRow(ServiceKey.seerr));
    }
    return rows;
  },
);

/// "More like this": TMDB's recommendations through the Seerr
/// [MediaSource.connectionId], read when the page asks for them.
final mediaRecommendationsProvider = FutureProvider.autoDispose
    .family<List<MediaPreview>, MediaSource>((ref, source) async {
      final tmdbId = source.key.tmdbId;
      if (tmdbId == null) return const [];
      return ref
          .watch(seerrServiceForProvider(source.connectionId))
          .getRecommendations(source.key.isMovie ? 'movie' : 'tv', tmdbId);
    }, retry: noProviderRetry);

/// The collection a title belongs to, counted on the household's server
/// through the Seerr [connectionId]; null when Seerr has no such collection.
final mediaCollectionHeldProvider = FutureProvider.autoDispose
    .family<MediaCollectionHeld?, ({String connectionId, int collectionId})>((
      ref,
      collection,
    ) async {
      final seerr = ref.watch(seerrServiceForProvider(collection.connectionId));
      final json = await seerr.getCollection(collection.collectionId);
      return mediaCollectionHeld(json, numbering: await seerr.numbering());
    }, retry: noProviderRetry);

/// One Radarr copy's history, read when History opens.
final mediaRadarrHistoryProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, ({String connectionId, int movieId})>((
      ref,
      copy,
    ) {
      return ref
          .watch(radarrServiceForProvider(copy.connectionId))
          .getMovieHistory(copy.movieId);
    }, retry: noProviderRetry);

/// Asks [row]'s connection again, and only it: a failed row's `Retry`.
void retryMediaRow(WidgetRef ref, MediaKey key, MediaRow row) {
  if (row is! MediaConnectionRow) return;
  final source = (key: key, connectionId: row.connection.id);
  switch (row.service) {
    case ServiceKey.jellyfin || ServiceKey.plex:
      ref.invalidate(mediaStreamCopyProvider(source));
    case ServiceKey.radarr:
      ref.invalidate(mediaRadarrCopyProvider(source));
    case ServiceKey.sonarr:
      ref.invalidate(mediaSonarrCopyProvider(source));
    case ServiceKey.bazarr:
      ref.invalidate(mediaBazarrCopyProvider(source));
    case ServiceKey.seerr:
      ref.invalidate(mediaSeerrRecordProvider(source));
    default:
      break;
  }
}
