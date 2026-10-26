import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/api/base_arr_service.dart';
import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/services/domain/arr_import.dart';
import 'package:cupola/features/services/domain/download_client_faults.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/services/presentation/services_probe.dart';

/// How many history records each arr is asked for.
///
/// One page, unfiltered (see `domain/arr_import.dart` for why the brief's
/// `eventType` filter cannot be sent). Twenty rather than ten because the page is
/// unfiltered: a busy evening's history is mostly `grabbed`, and ten records can
/// contain no imports at all on a stack that is downloading faster than it
/// imports. Twenty is still one request and still one page.
const int servicesHistoryPageSize = 20;

/// Whether one page of history is a window onto more of it.
///
/// Home reads one page per connection, the newest [pageSize] records. A page
/// that came back short is every record there is. One that came back full is
/// not, unless the server's own total says it is: the records past it are
/// older imports and older failures nobody read, so what is counted over the
/// page is the least there is (`20+`). A full page with no total at all is a
/// window too, because nothing says otherwise.
bool historyPageIsWindow(ArrRecordPage page, {required int pageSize}) {
  if (page.records.length < pageSize) return false;
  final total = page.total;
  return total == null || total > page.records.length;
}

/// One \*arr history record, reduced to what the two regions that read it need.
///
/// A projection rather than the raw map, for the reason `RecentlyAddedItem` is
/// one: the map is heterogeneous per event type and every reader would have to
/// re-learn which keys mean what.
class ArrHistoryEntry {
  const ArrHistoryEntry({
    required this.service,
    required this.id,
    required this.mediaId,
    required this.title,
    required this.unitId,
    required this.detail,
    required this.posterUrl,
    required this.outcome,
    required this.at,
    required this.reason,
    this.instanceId = '',
    this.connectionName,
    this.tmdbId,
    this.backdropUrl = '',
    this.mediaAddedAt,
    this.fileName,
    this.downloadId,
  });

  final ServiceKey service;

  /// The download client's id for the transfer the record is about (the
  /// torrent hash, the usenet job's id), as the queue named it: what finds a
  /// download's import after it left the queue. Null when the record has none.
  final String? downloadId;

  /// The file an import record landed, as the library names it: the last
  /// segment of the record's `data.importedPath`, else the release's
  /// `sourceTitle`. Null on any other event, and on an import whose record
  /// carries neither.
  final String? fileName;

  /// The wide artwork of what the record is about (Radarr's and Sonarr's
  /// fanart, a Lidarr artist's), or empty: what Arrived's card shows.
  final String backdropUrl;

  /// When the movie, the series or the artist the record is about was added
  /// to its library, from the media it embeds. What tells a series new to the
  /// library from a new episode of one that was there.
  final DateTime? mediaAddedAt;

  /// TMDB's id for the film a Radarr record is about, from the film the
  /// record embeds: what opens the film's own page. Null elsewhere.
  final int? tmdbId;

  /// What tells [instanceId] apart from the service's other connections, by
  /// the app's one rule, or null while the service has only the one.
  final String? connectionName;

  /// The connection this record came off.
  ///
  /// A history record id and the media id in it are that server's: each
  /// Radarr numbers from one, so "film 3" names a different film on each. The
  /// manual import a failed record becomes has to open on this connection,
  /// never on whatever the lens is on when the user taps Fix. Empty only for a
  /// record built without one, which falls back to the lens.
  final String instanceId;

  /// The history record's own id. Unique per connection, and what the decision
  /// row is keyed on: a media id is not, since one film can fail twice.
  final int id;

  /// The library item this record is about, for the route. Zero when the record
  /// does not name one, which is normal for a failed grab of something the arr
  /// never added.
  final int mediaId;

  final String title;

  /// The season (Sonarr) or album id (Lidarr) the record belongs to: what
  /// Recently added folds on. Null on Radarr and when the record does not say.
  final int? unitId;

  /// The record's own piece: `S1 E3`, or the artist behind an album.
  final String? detail;

  final String posterUrl;
  final ArrImportOutcome outcome;
  final DateTime? at;

  /// Why it failed, when the record says. Null on an import.
  final String? reason;
}

/// One history page per arr, and which arrs answered for it.
typedef ArrHistory = ({List<ArrHistoryEntry> entries, SourceCoverage coverage});

/// One history page per arr, read once and shared by the two regions that need
/// it.
///
/// Recently added asks it what landed; the decisions region asks it what did
/// not. One provider so the answer is one request, and so the two regions cannot
/// disagree about the same record.
///
/// A dark arr still degrades to no records, and now also says so in
/// [ArrHistory.coverage]: the rail can show what the others answered, but the
/// count above it cannot claim to be the whole without knowing who is missing.
final servicesArrHistoryProvider = FutureProvider<ArrHistory>((ref) async {
  // Every configured connection of each arr, each on its own narrow watch:
  // watching the whole `SettingsModel` refetched every history page on any
  // settings write, a theme toggle included.
  Future<ArrHistory> from(MergeConnection source) async {
    try {
      // The page, not the bare records: whether the page holds the whole
      // history is what decides if a count over it is a total or a floor.
      final page = await switch (source.service) {
        ServiceKey.radarr =>
          ref
              .watch(radarrServiceForProvider(source.instanceId))
              .getHistoryPage(pageSize: servicesHistoryPageSize),
        ServiceKey.sonarr =>
          ref
              .watch(sonarrServiceForProvider(source.instanceId))
              .getHistoryPage(pageSize: servicesHistoryPageSize),
        // Lidarr's records DO arrive with their artist and their album:
        // `LidarrService` overrides `getHistoryPage`, which this `getHistory`
        // delegates through, and injects `includeArtist`/`includeAlbum` there.
        // So the title resolves to the album (`arrPrimaryMediaTitle` reads
        // `album` then `artist`) rather than falling back to the raw
        // `sourceTitle`, and the tile's artwork is the album cover: see
        // `_historyPosterUrl`.
        _ =>
          ref
              .watch(lidarrServiceForProvider(source.instanceId))
              .getHistoryPage(pageSize: servicesHistoryPageSize),
      };
      return (
        entries: page.records
            .whereType<Map>()
            .map(stringKeyMap)
            .map(
              (record) => _historyEntryFrom(
                source.service,
                record,
                // The connection these records come off, stamped on each, so
                // a remedy bound to one connection opens on this one, whatever
                // the lens is on when the user taps.
                instanceId: source.instanceId,
                connectionName: source.name,
                baseUrl: source.connection.url,
                apiKey: source.connection.apiKey,
              ),
            )
            .toList(growable: false),
        // A page that came back full is a window onto more history, so what
        // is counted over it is a floor (`20+`), never the total.
        coverage: SourceCoverage.answeredBy(
          source.service,
          cutShort: historyPageIsWindow(
            page,
            pageSize: servicesHistoryPageSize,
          ),
          instanceId: source.instanceId,
          name: source.name,
        ),
      );
    } catch (error) {
      // The convention: a browse degrades to `[]` rather than taking the region
      // down, but the failure is kept, classified, so the count above the
      // rail can leave this connection out by name instead of counting it as
      // zero. A second Radarr that did not answer leaves the first one's
      // imports on the rail.
      return (
        entries: const <ArrHistoryEntry>[],
        coverage: SourceCoverage.failure(
          source.service,
          error,
          instanceId: source.instanceId,
          name: source.name,
        ),
      );
    }
  }

  final results = await Future.wait([
    for (final service in const [
      ServiceKey.radarr,
      ServiceKey.sonarr,
      ServiceKey.lidarr,
    ])
      for (final source in watchMergeConnections(ref, service)) from(source),
  ]);

  return (
    entries: results.expand((result) => result.entries).toList(growable: false),
    coverage: SourceCoverage.merge(results.map((result) => result.coverage)),
  );
});

ArrHistoryEntry _historyEntryFrom(
  ServiceKey service,
  Map<String, dynamic> record, {
  required String instanceId,
  String? connectionName,
  required String baseUrl,
  required String apiKey,
}) {
  final data = mapOrNull(record['data']);
  final title =
      arrPrimaryMediaTitle(record) ?? arrReleaseTitle(record) ?? 'Unknown item';
  final outcome = classifyHistoryEvent(stringOrNull(record['eventType']));

  return ArrHistoryEntry(
    service: service,
    instanceId: instanceId,
    connectionName: connectionName,
    id: intOrNull(record['id']) ?? 0,
    mediaId:
        intOrNull(record['movieId']) ??
        intOrNull(record['seriesId']) ??
        intOrNull(record['artistId']) ??
        0,
    tmdbId: switch (service) {
      ServiceKey.radarr => intOrNull(mapOrNull(record['movie'])?['tmdbId']),
      ServiceKey.sonarr => intOrNull(mapOrNull(record['series'])?['tmdbId']),
      _ => null,
    },
    title: title,
    unitId: switch (service) {
      ServiceKey.sonarr => intOrNull(
        mapOrNull(record['episode'])?['seasonNumber'] ?? record['seasonNumber'],
      ),
      ServiceKey.lidarr => intOrNull(
        record['albumId'] ?? mapOrNull(record['album'])?['id'],
      ),
      _ => null,
    },
    detail: switch (service) {
      ServiceKey.sonarr => arrEpisodeCode(record),
      ServiceKey.lidarr => arrArtistName(record),
      _ => null,
    },
    posterUrl: _historyPosterUrl(record, baseUrl: baseUrl, apiKey: apiKey),
    backdropUrl: _historyBackdropUrl(record, baseUrl: baseUrl, apiKey: apiKey),
    mediaAddedAt: parseAddedTimestamp(
      stringOrNull(
        (mapOrNull(record['movie']) ??
            mapOrNull(record['series']) ??
            mapOrNull(record['artist']))?['added'],
      ),
    ),
    outcome: outcome,
    fileName: outcome == ArrImportOutcome.imported
        ? _importedFileName(record, data)
        : null,
    at: parseAddedTimestamp(stringOrNull(record['date'])),
    downloadId: stringOrNull(record['downloadId']),
    // `statusMessages` is where an \*arr puts the reason an import failed, and
    // `message` is where a failed *grab* puts it. Neither is always present, and
    // a decision row with no reason still says what it is.
    reason:
        stringOrNull(data?['statusMessages']) ?? stringOrNull(data?['message']),
  );
}

/// The name of the file an import record landed: the last segment of
/// `data.importedPath` (Radarr and Sonarr `downloadFolderImported`, Lidarr
/// `trackFileImported`, each recording the library path it moved the file to
/// under that key), else the record's `sourceTitle`, the release it came
/// from. Null when the record has neither.
///
/// A path from a Windows host reads on `\\` as well as `/`.
String? _importedFileName(
  Map<String, dynamic> record,
  Map<String, dynamic>? data,
) {
  final path = stringOrNull(data?['importedPath'])?.trim();
  if (path != null && path.isNotEmpty) {
    final segments = path.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty);
    if (segments.isNotEmpty) return segments.last;
  }
  final source = stringOrNull(record['sourceTitle'])?.trim();
  return source == null || source.isEmpty ? null : source;
}

/// The artwork a history record carries in its embedded media.
///
/// On Lidarr the album's cover comes first and the artist's poster second: the
/// Recently added row folds on the album, so the album is what it should look
/// like, and an album whose cover Lidarr has not fetched yet still has a face.
/// Both embeds are already on the record (`includeAlbum`/`includeArtist`), so
/// this costs no request.
String _historyPosterUrl(
  Map<String, dynamic> record, {
  required String baseUrl,
  required String apiKey,
}) {
  String from(Object? media, List<String> coverTypes) {
    final images = mapOrNull(media)?['images'];
    if (images is! List) return '';
    return ImageUtils.extractPosterUrl(
      images,
      baseUrl: baseUrl,
      apiKey: apiKey,
      coverTypes: coverTypes,
    ).url;
  }

  const posterTypes = ['poster', 'cover'];
  for (final (media, coverTypes) in [
    (record['movie'], posterTypes),
    (record['series'], posterTypes),
    (record['album'], const ['cover', 'disc']),
    (record['artist'], const ['poster', 'fanart']),
  ]) {
    final url = from(media, coverTypes);
    if (url.isNotEmpty) return url;
  }
  return '';
}

/// The wide artwork a history record carries in its embedded media: the
/// movie's or the series' fanart, a Lidarr album's artist's. Empty when the
/// arr has none, and the card falls back to the poster.
String _historyBackdropUrl(
  Map<String, dynamic> record, {
  required String baseUrl,
  required String apiKey,
}) {
  for (final media in [record['movie'], record['series'], record['artist']]) {
    final images = mapOrNull(media)?['images'];
    if (images is! List) continue;
    final url = ImageUtils.extractPosterUrl(
      images,
      baseUrl: baseUrl,
      apiKey: apiKey,
      coverTypes: const ['fanart'],
    ).url;
    if (url.isNotEmpty) return url;
  }
  return '';
}

/// How far back Arrived looks.
const arrivalsWindow = Duration(days: 7);

/// What the libraries imported in the last [arrivalsWindow]: one
/// `/history/since` per connection of Radarr, Sonarr and Lidarr, narrowed to
/// the import event and with the media embedded.
///
/// Not [servicesArrHistoryProvider]'s page of twenty, which on a busy evening
/// does not reach back a day: `/history/since` has no pages, so a count over
/// it is the week's total, and the module can say `4 new` rather than `4+`.
/// The import event is asked for by name and checked again on each record, so
/// a server that ignores the filter still gives only imports.
final servicesArrivalsProvider = FutureProvider.autoDispose<ArrHistory>(
  (ref) => _readHistorySince(
    ref,
    events: const {
      ServiceKey.radarr: 'downloadFolderImported',
      ServiceKey.sonarr: 'downloadFolderImported',
      ServiceKey.lidarr: 'trackFileImported',
    },
    keep: ArrImportOutcome.imported,
  ),
);

/// The downloads that failed in the last [arrivalsWindow]: one
/// `/history/since` per connection of Radarr, Sonarr and Lidarr, in the shape
/// of [servicesArrivalsProvider], read through the same clock
/// ([arrivalsSinceProvider]) and with the same coverage, so the week's
/// failures and the week's imports are one window and cannot drift.
///
/// `downloadFailed` is asked for by name and checked again on each record: a
/// server that ignores the filter, or a failed *import*, which is a decision
/// of its own, is not a failed download and is dropped.
final servicesFailuresSinceProvider = FutureProvider.autoDispose<ArrHistory>(
  (ref) => _readHistorySince(
    ref,
    events: const {
      ServiceKey.radarr: 'downloadFailed',
      ServiceKey.sonarr: 'downloadFailed',
      ServiceKey.lidarr: 'downloadFailed',
    },
    keep: ArrImportOutcome.failed,
    exactEvent: true,
  ),
);

/// The records of one kind that [arrivalsWindow] holds, per connection of the
/// arrs [events] names: the one body behind [servicesArrivalsProvider] and
/// [servicesFailuresSinceProvider].
///
/// [events] is the event type each arr is asked for, by name. A record is kept
/// when it classifies as [keep], and, with [exactEvent], only when it is the
/// very event asked for: an outcome can have more than one event
/// (`importFailed` is a failure too), and a read that wants the one must not
/// take the other. A connection that fails is named in the coverage and
/// takes nobody else's records with it.
Future<ArrHistory> _readHistorySince(
  Ref ref, {
  required Map<ServiceKey, String> events,
  required ArrImportOutcome keep,
  bool exactEvent = false,
}) async {
  final since = ref.watch(arrivalsSinceProvider);
  Future<ArrHistory> from(MergeConnection source) async {
    final event = events[source.service]!;
    try {
      final records = await switch (source.service) {
        ServiceKey.radarr =>
          ref
              .watch(radarrServiceForProvider(source.instanceId))
              .getHistorySince(
                since,
                queryParameters: {'eventType': event, 'includeMovie': true},
              ),
        ServiceKey.sonarr =>
          ref
              .watch(sonarrServiceForProvider(source.instanceId))
              .getHistorySince(
                since,
                queryParameters: {
                  'eventType': event,
                  'includeSeries': true,
                  'includeEpisode': true,
                },
              ),
        _ =>
          ref
              .watch(lidarrServiceForProvider(source.instanceId))
              .getHistorySince(
                since,
                queryParameters: {
                  'eventType': event,
                  'includeArtist': true,
                  'includeAlbum': true,
                },
              ),
      };
      return (
        entries: [
          for (final record in records.whereType<Map>().map(stringKeyMap))
            if (!exactEvent || stringOrNull(record['eventType']) == event)
              _historyEntryFrom(
                source.service,
                record,
                instanceId: source.instanceId,
                connectionName: source.name,
                baseUrl: source.connection.url,
                apiKey: source.connection.apiKey,
              ),
        ].where((entry) => entry.outcome == keep).toList(),
        coverage: SourceCoverage.answeredBy(
          source.service,
          instanceId: source.instanceId,
          name: source.name,
        ),
      );
    } catch (error) {
      return (
        entries: const <ArrHistoryEntry>[],
        coverage: SourceCoverage.failure(
          source.service,
          error,
          instanceId: source.instanceId,
          name: source.name,
        ),
      );
    }
  }

  final results = await Future.wait([
    for (final service in events.keys)
      for (final source in watchMergeConnections(ref, service)) from(source),
  ]);
  return (
    entries: results.expand((result) => result.entries).toList(growable: false),
    coverage: SourceCoverage.merge(results.map((result) => result.coverage)),
  );
}

/// The moment Arrived's week starts: [arrivalsWindow] before now, read once
/// per reading so every connection is asked the same window.
final arrivalsSinceProvider = Provider.autoDispose<DateTime>(
  (ref) => ref.watch(arrivalsClockProvider)().subtract(arrivalsWindow),
);

/// The clock a stall is measured by: a torrent is stuck once nothing has
/// arrived for [stuckAfter] before it. A test pins it.
final stallClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// The clock Arrived reads its week and its `2 h ago` by. A test pins it.
final arrivalsClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);
