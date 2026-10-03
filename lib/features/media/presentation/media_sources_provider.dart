import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_provider.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/domain/seerr_arr_server.dart';
import 'package:cupola/features/discover/domain/seerr_media_copy.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:cupola/features/media/domain/media_copies.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/media/domain/media_reading.dart';
import 'package:cupola/features/media/domain/media_rows.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/plex/presentation/plex_provider.dart';
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
        throw ArgumentError.value(source.key, 'key', 'not a film');
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

/// What the media server [MediaSource.connectionId] answers about the title,
/// looked up by its ids and checked again here, as `streamAvailabilityProvider`
/// does: a client that forgets to verify cannot put a wrong Play on the page.
final mediaStreamCopyProvider = FutureProvider.autoDispose
    .family<MediaAnswer<MediaStreamCopy>, MediaSource>((ref, source) async {
      final settings = ref.watch(currentSettingsProvider);
      final connection = settings.instanceById(source.connectionId);
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
/// and, when the connection may read them, the Radarr servers it places
/// films on.
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
      if (source.key.isMovie) {
        try {
          servers = await seerr.getArrServers(ServiceKey.radarr);
        } catch (_) {
          // An account without ADMIN may not read them, and a failed read is
          // no list either: no copy is bound, and nothing is claimed.
          servers = null;
        }
      }
      return MediaAnswer(
        MediaSeerrRecord(details: details, radarrServers: servers),
        DateTime.now(),
      );
    }, retry: noProviderRetry);

/// What the Bazarr [MediaSource.connectionId] holds of the film: the one
/// Radarr copy it follows, checked against that copy's path, or its title and
/// year.
///
/// Bazarr follows one Radarr and speaks in its ids, so every tracked copy is
/// asked by its movie id and the answer verified; the first that matches is
/// the copy Bazarr covers. A copy whose Radarr did not answer is skipped: it is
/// Radarr's failure, already on Radarr's own row.
final mediaBazarrCopyProvider = FutureProvider.autoDispose
    .family<MediaAnswer<MediaBazarrCopy?>, MediaSource>((ref, source) async {
      final bazarr = ref.watch(bazarrServiceForProvider(source.connectionId));
      final settings = ref.watch(currentSettingsProvider);
      for (final radarr
          in settings
              .instancesOf(ServiceKey.radarr)
              .where((instance) => instance.isConfigured)) {
        final MediaAnswer<MediaRadarrCopy> answer;
        try {
          answer = await ref.watch(
            mediaRadarrCopyProvider((
              key: source.key,
              connectionId: radarr.id,
            )).future,
          );
        } catch (_) {
          continue;
        }
        final movie = answer.value.movie;
        if (movie == null) continue;
        final followed = await bazarr.getMovieById(movie.id);
        if (followed == null) continue;
        final samePath =
            (followed.path ?? '').isNotEmpty && followed.path == movie.path;
        final title = normaliseStreamTitle(followed.title);
        final sameTitle =
            title != null &&
            title == normaliseStreamTitle(movie.title) &&
            followed.year == movie.year;
        if (samePath || sameTitle) {
          return MediaAnswer(
            MediaBazarrCopy(radarrConnectionId: radarr.id, movie: followed),
            DateTime.now(),
          );
        }
      }
      return MediaAnswer<MediaBazarrCopy?>(null, DateTime.now());
    }, retry: noProviderRetry);

/// The "On your server" rows of a film, one per fact, in the page's order:
/// the media servers, the Radarr copies (or Seerr's claims about them), Bazarr,
/// Seerr.
///
/// Every connection is read on its own, and no row waits for another: a
/// connection that did not answer costs its own row, never the page (rule 1).
/// What is not set up is decided from the settings alone, before anything is
/// asked (rule 3). A media server's unverified match draws nothing (rule 7).
final mediaMovieRowsProvider = Provider.autoDispose
    .family<List<MediaRow>, MediaKey>((ref, key) {
      final settings = ref.watch(currentSettingsProvider);
      List<ServiceInstance> configured(ServiceKey service) => settings
          .instancesOf(service)
          .where((instance) => instance.isConfigured)
          .toList(growable: false);

      final rows = <MediaRow>[];
      MediaSource sourceOf(ServiceInstance connection) =>
          (key: key, connectionId: connection.id);

      for (final service in const [ServiceKey.jellyfin, ServiceKey.plex]) {
        for (final connection in configured(service)) {
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

      final seerrs = configured(ServiceKey.seerr);
      final seerrReadings = [
        for (final seerr in seerrs)
          (
            connection: seerr,
            reading: MediaReading.of(
              ref.watch(mediaSeerrRecordProvider(sourceOf(seerr))),
            ),
          ),
      ];

      final radarrs = configured(ServiceKey.radarr);
      for (final connection in radarrs) {
        rows.add(
          MediaConnectionRow<MediaRadarrCopy>(
            connection,
            MediaReading.of(
              ref.watch(mediaRadarrCopyProvider(sourceOf(connection))),
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
                    arr: ServiceKey.radarr,
                    servers: answer.value.radarrServers,
                    connections: radarrs,
                  )
                  case final bound when bound.isKnownOnlyToSeerr)
                MediaThroughSeerrRow(
                  seerr: seerr.connection,
                  copy: bound,
                  mediaInfo: answer.value.mediaInfo,
                ),
      ];
      rows.addAll(claims);
      if (radarrs.isEmpty && claims.isEmpty) {
        rows.add(const MediaNotSetUpRow(ServiceKey.radarr));
      }

      for (final connection in configured(ServiceKey.bazarr)) {
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
      if (seerrs.isEmpty) rows.add(const MediaNotSetUpRow(ServiceKey.seerr));
      return rows;
    });
