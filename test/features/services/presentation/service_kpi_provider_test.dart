import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/api/base_arr_service.dart';
import 'package:cupola/core/models/service_kpi.dart';
import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/jellyfin/data/jellyfin_client.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/plex/data/plex_client.dart';
import 'package:cupola/features/plex/presentation/plex_provider.dart';
import 'package:cupola/features/readarr/data/readarr_service.dart';
import 'package:cupola/features/readarr/presentation/readarr_provider.dart';
import 'package:cupola/features/sabnzbd/domain/models/sabnzbd_models.dart';
import 'package:cupola/features/sabnzbd/presentation/sabnzbd_provider.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/fake_api_client.dart';
import '../../../test_helpers/capturing_http_adapter.dart';

SeerrRequest _request({
  required int id,
  RequestStatus status = RequestStatus.completed,
  SeerrMediaAvailability mediaStatus = SeerrMediaAvailability.unknown,
}) => SeerrRequest(
  id: id,
  status: status,
  media: RequestMedia(title: 'Title $id', tmdbId: id, status: mediaStatus),
  createdAt: '2024-01-01T00:00:00Z',
  type: 'movie',
);

Future<Map<String, String>> _seerrKpis(List<SeerrRequest> requests) async {
  final container = ProviderContainer(
    overrides: [requestsProvider.overrideWith((ref) async => requests)],
  );
  addTearDown(container.dispose);

  final kpis = await container.read(
    serviceKpiProvider(ServiceKey.seerr).future,
  );
  return {for (final ServiceKpi kpi in kpis) kpi.label: kpi.value};
}

/// A real service over a client that fails every GET.
///
/// The gap the defect lives in is between "the library is empty" and "nobody
/// answered", and the only way to stand in it is to let the transport fail the
/// way it fails in the field. A hand-written fake that returns `[]` *is* the
/// bug, so it cannot be the harness that catches it.
FakeApiClient _deadClient() =>
    FakeApiClient()..getException = Exception('unreachable');

/// Answers the author list and refuses the queue, which is the half-broken
/// Readarr the queue KPI had no way to draw: `getQueue` swallowed its own
/// failure, so the rail read `Queue 0` over a queue nobody had read.
class _ReadarrClientWithDeadQueue extends FakeApiClient {
  @override
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    Duration? receiveTimeout,
  }) {
    if (path.contains('queue')) throw Exception('queue unreachable');
    return super.get(
      path,
      queryParameters: queryParameters,
      cancelToken: cancelToken,
      receiveTimeout: receiveTimeout,
    );
  }
}

Map<String, ServiceKpi> _byLabel(List<ServiceKpi> kpis) => {
  for (final kpi in kpis) kpi.label: kpi,
};

Future<Map<String, ServiceKpi>> _kpisFor(
  ServiceKey service,
  List<Override> overrides,
) async {
  final container = ProviderContainer(overrides: overrides);
  addTearDown(container.dispose);
  return _byLabel(await container.read(serviceKpiProvider(service).future));
}

void main() {
  group('Seerr KPIs', () {
    test('counts pending approvals off the request, not the media', () async {
      // The trap: `displayStatus` checks `media.status` first, so a request
      // still awaiting a human reports "Available" the moment Radarr has the
      // file. Counting off it showed "Pending 0" on the dashboard while
      // /activity was offering an Approve button for the same record.
      final pendingButAvailable = _request(
        id: 1,
        status: RequestStatus.pendingApproval,
        mediaStatus: SeerrMediaAvailability.available,
      );
      expect(pendingButAvailable.displayStatus.label, 'Available');

      final kpis = await _seerrKpis([pendingButAvailable]);

      expect(kpis['Waiting for approval'], '1');
      // Its media really is available, and that tile is about the media.
      expect(kpis['Available'], '1');
      expect(kpis['Requests'], '1');
    });

    test('counts an ordinary pending request once', () async {
      final kpis = await _seerrKpis([
        _request(id: 1, status: RequestStatus.pendingApproval),
      ]);

      expect(kpis['Waiting for approval'], '1');
      expect(kpis['Processing'], '0');
      expect(kpis['Available'], '0');
    });

    test('does not count settled requests as pending', () async {
      final kpis = await _seerrKpis([
        _request(
          id: 1,
          status: RequestStatus.approved,
          mediaStatus: SeerrMediaAvailability.processing,
        ),
        _request(
          id: 2,
          status: RequestStatus.completed,
          mediaStatus: SeerrMediaAvailability.available,
        ),
        _request(id: 3, status: RequestStatus.declined),
      ]);

      expect(kpis['Waiting for approval'], '0');
      expect(kpis['Processing'], '1');
      expect(kpis['Available'], '1');
      expect(kpis['Requests'], '3');
    });
  });

  group('a *arr that did not answer states nothing', () {
    // Every figure below is derived from a library fetch that swallows its own
    // failure into `[]`. An unreachable server therefore resolved the rail
    // *successfully* with a full set of confident zeros, printed on the
    // Dashboard card and on the service home directly under an identity band
    // whose own probe already read Unreachable.

    test('Sonarr prints em dashes, not "Series 0"', () async {
      final kpis = await _kpisFor(ServiceKey.sonarr, [
        sonarrServiceProvider.overrideWithValue(SonarrService(_deadClient())),
      ]);

      expect(kpis['Series']!.value, ServiceKpi.unavailableValue);
      expect(kpis['Episodes']!.value, ServiceKpi.unavailableValue);
      expect(kpis['Missing']!.value, ServiceKpi.unavailableValue);
      expect(kpis['Monitored']!.value, ServiceKpi.unavailableValue);
      // One card says why; the other three keep their own labels, because four
      // identical reasons is a rail nobody can read a figure off.
      expect(kpis['Series']!.note, isNotNull);
      // Untoned on purpose: an absence is neither a fault nor a backlog.
      expect(kpis.values.every((kpi) => kpi.tone == null), isTrue);
    });

    test('Radarr prints em dashes, not "Movies 0"', () async {
      final kpis = await _kpisFor(ServiceKey.radarr, [
        radarrServiceProvider.overrideWithValue(RadarrService(_deadClient())),
      ]);

      expect(kpis['Movies']!.value, ServiceKpi.unavailableValue);
      expect(kpis['Monitored']!.value, ServiceKpi.unavailableValue);
      expect(kpis['Missing']!.value, ServiceKpi.unavailableValue);
      // The queue figure is a count off the same dark server: a snapshot that
      // degrades to empty cannot be told from a queue that drained.
      expect(kpis['Queue']!.value, ServiceKpi.unavailableValue);
    });

    test('Lidarr prints em dashes, not "Artists 0"', () async {
      final kpis = await _kpisFor(ServiceKey.lidarr, [
        lidarrServiceProvider.overrideWithValue(LidarrService(_deadClient())),
      ]);

      expect(kpis['Artists']!.value, ServiceKpi.unavailableValue);
      expect(kpis['Albums']!.value, ServiceKpi.unavailableValue);
      expect(kpis['Tracks']!.value, ServiceKpi.unavailableValue);
      expect(kpis['Missing']!.value, ServiceKpi.unavailableValue);
    });

    test('Readarr prints em dashes, not "Authors 0"', () async {
      final kpis = await _kpisFor(ServiceKey.readarr, [
        readarrServiceProvider.overrideWithValue(ReadarrService(_deadClient())),
      ]);

      expect(kpis['Authors']!.value, ServiceKpi.unavailableValue);
      expect(kpis['Books']!.value, ServiceKpi.unavailableValue);
      expect(kpis['Missing']!.value, ServiceKpi.unavailableValue);
      expect(kpis['Queue']!.value, ServiceKpi.unavailableValue);
    });

    test('a library that really is empty still reads zero', () async {
      // The other half of the pair. An em dash for an answered-and-empty
      // library would be the same lie pointing the other way.
      final client = FakeApiClient()..getResponseData = <dynamic>[];
      final kpis = await _kpisFor(ServiceKey.sonarr, [
        sonarrServiceProvider.overrideWithValue(SonarrService(client)),
      ]);

      expect(kpis['Series']!.value, '0');
      expect(kpis['Series']!.note, isNull);
    });
  });

  group('stream server KPIs preserve reachability', () {
    test(
      'an answered empty Jellyfin server still reports real zeroes',
      () async {
        final client = JellyfinClient(
          baseUrl: 'https://jellyfin.test',
          apiKey: 'key',
          deviceName: 'test',
          deviceId: 'test-device',
        );
        client.dio.httpClientAdapter = CapturingHttpAdapter(response: const []);
        addTearDown(client.close);

        final container = ProviderContainer(
          overrides: [jellyfinClientProvider.overrideWithValue(client)],
        );
        addTearDown(container.dispose);

        final kpis = _byLabel(
          await container.read(serviceKpiProvider(ServiceKey.jellyfin).future),
        );
        expect(kpis['Streams']!.value, '0');
        expect(kpis['Transcodes']!.value, '0');
        expect(kpis['Libraries']!.value, '0');
      },
    );

    test('Jellyfin transport failure reaches the KPI provider', () async {
      final client = JellyfinClient(
        baseUrl: 'https://jellyfin.test',
        apiKey: 'key',
        deviceName: 'test',
        deviceId: 'test-device',
      );
      client.dio.httpClientAdapter = CapturingHttpAdapter(
        response: '',
        statusCode: 500,
      );
      addTearDown(client.close);

      final container = ProviderContainer(
        overrides: [jellyfinClientProvider.overrideWithValue(client)],
      );
      addTearDown(container.dispose);

      await expectLater(
        container.read(serviceKpiProvider(ServiceKey.jellyfin).future),
        throwsA(isA<DioException>()),
      );
    });

    test('an answered empty Plex server still reports real zeroes', () async {
      final client = PlexClient(
        url: 'https://plex.test:32400',
        token: 'token',
        clientIdentifier: 'test-client',
        platform: 'macOS',
      );
      client.api.dio.httpClientAdapter = CapturingHttpAdapter(
        response: const {
          'MediaContainer': {'size': 0},
        },
      );
      addTearDown(client.close);

      final container = ProviderContainer(
        overrides: [plexClientProvider.overrideWithValue(client)],
      );
      addTearDown(container.dispose);

      final kpis = _byLabel(
        await container.read(serviceKpiProvider(ServiceKey.plex).future),
      );
      expect(kpis['Streams']!.value, '0');
      expect(kpis['Transcodes']!.value, '0');
      expect(kpis['Libraries']!.value, '0');
    });

    test('Plex transport failure reaches the KPI provider', () async {
      final client = PlexClient(
        url: 'https://plex.test:32400',
        token: 'token',
        clientIdentifier: 'test-client',
        platform: 'macOS',
      );
      client.api.dio.httpClientAdapter = CapturingHttpAdapter(
        response: '',
        statusCode: 500,
      );
      addTearDown(client.close);

      final container = ProviderContainer(
        overrides: [plexClientProvider.overrideWithValue(client)],
      );
      addTearDown(container.dispose);

      await expectLater(
        container.read(serviceKpiProvider(ServiceKey.plex).future),
        throwsA(isA<PlexException>()),
      );
    });

    test('a named Plex connection reads its own KPI source', () async {
      const lens = ServiceInstance(
        id: 'plex',
        service: ServiceKey.plex,
        label: 'Home',
        url: 'https://plex-home.test',
        credential: 'home-token',
      );
      const other = ServiceInstance(
        id: 'plex-away',
        service: ServiceKey.plex,
        label: 'Away',
        url: 'https://plex-away.test',
        credential: 'away-token',
      );

      PlexClient client({required int libraryCount}) {
        final value = PlexClient(
          url: 'https://plex.test:32400',
          token: 'token',
          clientIdentifier: 'test-client',
          platform: 'macOS',
        );
        value.api.dio.httpClientAdapter = CapturingHttpAdapter(
          byPath: {
            '/status/sessions': const {
              'MediaContainer': {'size': 0, 'Metadata': []},
            },
            '/library/sections': {
              'MediaContainer': {
                'size': libraryCount,
                'Directory': [
                  for (var i = 0; i < libraryCount; i++)
                    {'key': '$i', 'type': 'movie', 'title': 'Library $i'},
                ],
              },
            },
          },
        );
        addTearDown(value.close);
        return value;
      }

      final homeClient = client(libraryCount: 1);
      final awayClient = client(libraryCount: 3);
      final container = ProviderContainer(
        overrides: [
          currentSettingsProvider.overrideWithValue(
            const SettingsModel(instances: [lens, other]),
          ),
          plexClientProvider.overrideWithValue(homeClient),
          plexClientForProvider.overrideWith((ref, instanceId) => awayClient),
        ],
      );
      addTearDown(container.dispose);

      final kpis = await container.read(
        serviceKpiForProvider((
          service: ServiceKey.plex,
          instanceId: other.id,
        )).future,
      );

      expect(kpis, isNotNull);
      expect(kpis!.firstWhere((kpi) => kpi.label == 'Libraries').value, '3');
    });
  });

  group('Readarr queue', () {
    test('a queue endpoint that is down reads "—", not an idle 0', () async {
      // The library answers and the queue does not, which is the ordinary
      // shape of a half-broken Readarr. Three figures are real; only the
      // fourth is unknown, and only the fourth says so.
      final client = _ReadarrClientWithDeadQueue()
        ..getResponseData = <dynamic>[
          {
            'id': 1,
            'authorName': 'Le Guin',
            'statistics': {'bookCount': 4, 'bookFileCount': 4},
          },
        ];
      final kpis = await _kpisFor(ServiceKey.readarr, [
        readarrServiceProvider.overrideWithValue(ReadarrService(client)),
      ]);

      expect(kpis['Authors']!.value, '1');
      expect(kpis['Queue']!.value, ServiceKpi.unavailableValue);
      expect(kpis['Queue']!.note, isNotNull);
      // The reason belongs to the figure that has it: naming the whole service
      // here would read as "Readarr is down" over three figures Readarr just
      // answered.
      expect(kpis['Authors']!.note, isNull);
    });
  });

  group('a queue figure is only as much as the walk read', () {
    // A proxy that drops `totalRecords` stops the queue walk on its first
    // full page. The rails counted the rows and stated them as the queue.
    final fullPage = [
      for (var i = 0; i < 200; i++) {'id': i, 'movieId': i + 1},
    ];

    test('Readarr states the server\'s own count over the rows', () async {
      final kpis = await _kpisFor(ServiceKey.readarr, [
        readarrKpiLibraryProvider.overrideWith((ref) async => const []),
        readarrQueueProvider.overrideWith(
          (ref) async => ArrRecordPage(
            records: fullPage.take(3).toList(),
            total: 340,
            cutShort: true,
          ),
        ),
      ]);

      expect(kpis['Queue']!.value, '340');
    });

    test('Readarr reads 200+ for a full page with no count', () async {
      final kpis = await _kpisFor(ServiceKey.readarr, [
        readarrKpiLibraryProvider.overrideWith((ref) async => const []),
        readarrQueueProvider.overrideWith(
          (ref) async =>
              ArrRecordPage(records: fullPage, total: null, cutShort: true),
        ),
      ]);

      expect(kpis['Queue']!.value, '200+');
      expect(kpis['Queue']!.semanticLabel, 'Queue: at least 200');
    });

    test('Radarr reads 200+ over a queue snapshot cut short', () async {
      final kpis = await _kpisFor(ServiceKey.radarr, [
        radarrKpiLibraryProvider.overrideWith((ref) async => const []),
        radarrQueueSnapshotProvider.overrideWith(
          (ref) async => ArrQueueSnapshot.fromQueueItems(
            fullPage,
            idsFor: (item) => [item['movieId'] as int],
            cutShort: true,
          ),
        ),
      ]);

      expect(kpis['Queue']!.value, '200+');
    });

    test('Radarr reads the queue it read to the end as it is', () async {
      final kpis = await _kpisFor(ServiceKey.radarr, [
        radarrKpiLibraryProvider.overrideWith((ref) async => const []),
        radarrQueueSnapshotProvider.overrideWith(
          (ref) async => ArrQueueSnapshot.fromQueueItems(
            fullPage.take(3),
            idsFor: (item) => [item['movieId'] as int],
          ),
        ),
      ]);

      expect(kpis['Queue']!.value, '3');
    });

    test('Radarr: a queue that did not answer under a library that did '
        'reads "—" with its own reason, never Queue 0', () async {
      final kpis = await _kpisFor(ServiceKey.radarr, [
        radarrKpiLibraryProvider.overrideWith((ref) async => const []),
        radarrQueueSnapshotProvider.overrideWith(
          (ref) async => ArrQueueSnapshot.failed(Exception('queue down')),
        ),
      ]);

      expect(kpis['Movies']!.value, '0');
      expect(kpis['Queue']!.value, ServiceKpi.unavailableValue);
      expect(kpis['Queue']!.note, startsWith('Queue · '));
      expect(kpis['Movies']!.note, isNull);
    });
  });

  group('SABnzbd queue depth', () {
    SabnzbdQueue queue({required int slots, int? reportedSlots}) =>
        SabnzbdQueue(
          paused: false,
          status: 'Downloading',
          kbPerSec: 0,
          mbLeft: 0,
          mb: 0,
          timeLeft: '0:00:00',
          slots: List.generate(
            slots,
            (i) => SabnzbdQueueSlot.fromJson({
              'nzo_id': '$i',
              'filename': 'job $i',
            }),
          ),
          reportedSlots: reportedSlots,
        );

    test('counts the queue, not the page the client asked for', () async {
      // The client asks for 50 slots. A 62-job queue therefore arrives as 50
      // rows plus a `noofslots_total` of 62, and a count off `slots.length`
      // reads 50 for every queue deeper than the page — a figure that stops
      // moving exactly when it matters.
      final kpis = await _kpisFor(ServiceKey.sabnzbd, [
        sabnzbdQueueProvider.overrideWith(
          (ref) async => queue(slots: 50, reportedSlots: 62),
        ),
      ]);

      expect(kpis['Queue']!.value, '62');
    });

    test(
      'falls back to the rows in hand when the server gave no total',
      () async {
        final kpis = await _kpisFor(ServiceKey.sabnzbd, [
          sabnzbdQueueProvider.overrideWith((ref) async => queue(slots: 3)),
        ]);

        expect(kpis['Queue']!.value, '3');
      },
    );
  });
}
