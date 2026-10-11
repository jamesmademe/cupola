import 'package:dio/dio.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'package:cupola/features/import/data/manual_import_service.dart';
import 'package:cupola/features/import/domain/manual_import_models.dart';
import 'package:cupola/features/services/domain/in_flight.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import 'fake_api_client.dart';

/// The Review's world: a Sonarr that grabbed eighteen single-episode
/// downloads for Cosmos Laundromat and imported none. Twelve name their
/// episode (`Kosmische.Wasserette.S01E01.1080p.WEB`) and replace 720p files;
/// six do not (`Laundromat.Tapes.E01.720p.WEB`).

const blockedImportConnection = 'sonarr-1';

const cosmosMessage =
    'Found matching series via grab history, but release was matched to '
    'series by ID. Automatic import is not possible. See the FAQ for details.';

const cosmosSeries = <String, dynamic>{
  'id': 7,
  'title': 'Cosmos Laundromat',
  'tvdbId': 293712,
  'seasons': [
    {'seasonNumber': 0},
    {'seasonNumber': 1},
    {'seasonNumber': 2},
    {'seasonNumber': 3},
  ],
};

const _web1080 = <String, dynamic>{
  'quality': {'id': 3, 'name': 'WEBDL-1080p'},
};

const _web720 = <String, dynamic>{
  'quality': {'id': 5, 'name': 'WEBDL-720p'},
};

const _english = [
  {'id': 1, 'name': 'English'},
];

/// One of the twelve the arr would take: `S1 E1` … `S2 E2`.
Map<String, dynamic> cosmosClearFile(int season, int episode) {
  final code =
      'S${season.toString().padLeft(2, '0')}'
      'E${episode.toString().padLeft(2, '0')}';
  final name = 'Kosmische.Wasserette.$code.1080p.WEB';
  return {
    'id': season * 100 + episode,
    'path': '/downloads/$name/$name.mkv',
    'name': name,
    'size': 1200000000,
    'series': cosmosSeries,
    'seasonNumber': season,
    'episodes': [
      {
        'id': 1000 + season * 100 + episode,
        'seasonNumber': season,
        'episodeNumber': episode,
        'title': 'Episode $episode',
        'episodeFileId': 500 + season * 100 + episode,
      },
    ],
    'quality': _web1080,
    'languages': _english,
    'downloadId': cosmosDownloadId(season, episode),
    'rejections': const [],
  };
}

/// One of the six that do not say which episode they are.
Map<String, dynamic> cosmosTapeFile(int n) {
  final name = 'Laundromat.Tapes.E${n.toString().padLeft(2, '0')}.720p.WEB';
  return {
    'id': 9000 + n,
    'path': '/downloads/$name/$name.mkv',
    'name': name,
    'size': 700000000,
    'series': cosmosSeries,
    'episodes': const [],
    'quality': _web720,
    'languages': _english,
    'downloadId': 'tape-$n',
    'rejections': const [
      {'reason': 'Unable to identify episodes in file', 'type': 'permanent'},
    ],
  };
}

String cosmosDownloadId(int season, int episode) => 'clear-$season-$episode';

/// The twelve clear downloads' (season, episode), in the queue's order.
const cosmosClearEpisodes = [
  (1, 1),
  (1, 2),
  (1, 3),
  (1, 4),
  (1, 5),
  (1, 6),
  (1, 7),
  (1, 8),
  (1, 9),
  (1, 10),
  (2, 1),
  (2, 2),
];

/// The queue's eighteen blocked records, as Needs you counts them.
List<ServiceQueueItem> cosmosBlockedQueue({
  String instanceId = blockedImportConnection,
}) => [
  for (final (season, episode) in cosmosClearEpisodes)
    ServiceQueueItem(
      service: ServiceKey.sonarr,
      id: 'q-$season-$episode',
      title: 'Cosmos Laundromat',
      progress: 1,
      clientLabel: 'qBittorrent',
      fault: InFlightFault.needsImport,
      warning: cosmosMessage,
      downloadId: cosmosDownloadId(season, episode),
      instanceId: instanceId,
      mediaId: 7,
    ),
  for (var n = 1; n <= 6; n++)
    ServiceQueueItem(
      service: ServiceKey.sonarr,
      id: 'q-tape-$n',
      title: 'Cosmos Laundromat',
      progress: 1,
      clientLabel: 'qBittorrent',
      fault: InFlightFault.needsImport,
      warning: cosmosMessage,
      downloadId: 'tape-$n',
      instanceId: instanceId,
      mediaId: 7,
    ),
];

ServicesInFlight inFlightWithFaults(List<ServiceQueueItem> faults) => (
  preview: const [],
  activeCount: 0,
  movingCount: 0,
  queued: const [],
  faults: faults,
  held: 0,
  rateBytesPerSecond: null,
  clients: 1,
  coverage: SourceCoverage.none,
);

/// A Sonarr that answers the Review's reads from the world above.
class FakeBlockedImportService extends ManualImportService {
  FakeBlockedImportService()
    : super(client: FakeApiClient(), service: ServiceKey.sonarr);

  /// Each download's files, by the client's id for it.
  final files = <String, List<Map<String, dynamic>>>{
    for (final (season, episode) in cosmosClearEpisodes)
      cosmosDownloadId(season, episode): [cosmosClearFile(season, episode)],
    for (var n = 1; n <= 6; n++) 'tape-$n': [cosmosTapeFile(n)],
  };

  /// Downloads that will not list their files.
  final failing = <String>{};

  /// The library's episode files, by id: each clear file replaces a 720p.
  Map<int, String> qualities = {
    for (final (season, episode) in cosmosClearEpisodes)
      500 + season * 100 + episode: 'HDTV-720p',
  };

  final reads = <String>[];
  List<ManualImportItem>? posted;
  ManualImportCommandStatus command = ManualImportCommandStatus.fromJson(const {
    'id': 41,
    'name': 'ManualImport',
    'status': 'queued',
  });

  @override
  Future<List<ManualImportItem>> getDownloadImportItems({
    required String downloadId,
  }) async {
    reads.add(downloadId);
    if (failing.contains(downloadId)) {
      throw DioException(
        requestOptions: RequestOptions(path: '/api/v3/manualimport'),
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: RequestOptions(path: '/api/v3/manualimport'),
          statusCode: 500,
        ),
      );
    }
    return [
      for (final json in files[downloadId] ?? const <Map<String, dynamic>>[])
        ManualImportItem.fromJson(json),
    ];
  }

  @override
  Future<Map<int, String>> getEpisodeFileQualities(int seriesId) async =>
      qualities;

  @override
  Future<List<ManualImportEpisode>> getEpisodes({
    required int seriesId,
    int? seasonNumber,
  }) async => [
    for (var episode = 1; episode <= 10; episode++)
      if (seasonNumber == null || seasonNumber == 1 || episode <= 8)
        ManualImportEpisode.fromJson({
          'id': 2000 + (seasonNumber ?? 1) * 100 + episode,
          'seasonNumber': seasonNumber ?? 1,
          'episodeNumber': episode,
          'title': 'Episode $episode',
        }),
  ];

  @override
  Future<ManualImportCommandStatus> startManualImport(
    List<ManualImportItem> files, {
    required ManualImportMode importMode,
    bool replaceExistingFiles = false,
  }) async {
    posted = files;
    return command;
  }

  @override
  Future<ManualImportCommandStatus> getCommand(int commandId) async => command;
}

/// The overrides a Review of [fake] needs: the queue's faults, no lens, and
/// [fake] for the connection.
List<Override> blockedImportOverrides(
  FakeBlockedImportService fake, {
  List<ServiceQueueItem>? queue,
  String instanceId = blockedImportConnection,
}) => [
  servicesInFlightProvider.overrideWith(
    (ref) async => inFlightWithFaults(queue ?? cosmosBlockedQueue()),
  ),
  activeInstanceProvider(ServiceKey.sonarr).overrideWithValue(null),
  manualImportServiceForProvider((
    ServiceKey.sonarr,
    instanceId,
  )).overrideWith((ref) => fake),
  manualImportServiceProvider(ServiceKey.sonarr).overrideWith((ref) => fake),
];
