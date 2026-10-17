import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/profiles/profiles.dart';

/// The faults Needs you reads beside the downloads: TrueNAS's alerts, the
/// arrs' failing health checks, and connections that answered with a fault.
void main() {
  Future<List<DashboardDecision>> source(
    ProfileHarness harness,
    DecisionSource source,
  ) async {
    final container = harness.container();
    return (await container.read(
      dashboardDecisionSourceProvider(source).future,
    )).decisions;
  }

  test('a TrueNAS alert at warning or worse, in plain words', () async {
    final harness = await ProfileHarness.start(Profiles.p1);
    final alerts = await source(harness, DecisionSource.storage);
    expect(alerts.single.kind, DecisionKind.storageAlert);
    expect(alerts.single.title, 'Disk sdd reports 8 uncorrectable errors');
    expect(alerts.single.instanceId, WorldIds.truenas);
  });

  test('an Unraid slot the array flagged and an unread warning sit beside '
      'TrueNAS\'s alerts, each leading to its own page', () async {
    final harness = await ProfileHarness.start(
      Profiles.p1.withConnection(WorldConnections.unraid),
    );
    harness.network.on('unraid', 'POST', '/graphql', (r) {
      final query = '${(r.json as Map)['query']}';
      if (query.contains('array {')) {
        return NetworkReply.json({
          'data': {
            'array': {
              'state': 'STARTED',
              'parities': [
                {'name': 'parity', 'status': 'DISK_DSBL', 'temp': 34},
              ],
              'disks': [
                {'name': 'disk1', 'status': 'DISK_OK', 'temp': 38},
              ],
              'caches': const <Object?>[],
            },
          },
        });
      }
      return NetworkReply.json({
        'data': {
          'notifications': {
            'list': [
              {
                'id': 'n1',
                'title': 'Unraid Status',
                'subject': 'Warning [TOWER] - Disk 1 SMART health [5]',
                'description': 'ST4000VN008 (sdb)',
                'importance': 'WARNING',
                'type': 'UNREAD',
                'timestamp': '2026-10-17T09:00:00Z',
              },
            ],
          },
        },
      });
    });

    final alerts = await source(harness, DecisionSource.storage);
    final unraid = [
      for (final alert in alerts)
        if (alert.service == ServiceKey.unraid) alert,
    ];
    expect(unraid.map((a) => a.title), [
      'Parity is disabled',
      'Disk 1 SMART health [5]',
    ]);
    expect(unraid.map((a) => a.route), [
      ServiceRoutes.unraidArray,
      ServiceRoutes.unraidNotifications,
    ]);
    expect(unraid.every((a) => a.kind == DecisionKind.storageAlert), isTrue);
    expect(alerts.where((a) => a.service == ServiceKey.truenas), hasLength(1));
  });

  test('an arr\'s health check at the error level, in the app\'s words with '
      'its own kept; a warning is not a fault', () async {
    final harness = await ProfileHarness.start(Profiles.p1);
    harness.network.on(
      WorldIds.radarr,
      'GET',
      '/api/v3/health',
      (_) => NetworkReply.json([
        {
          'source': 'RootFolderCheck',
          'type': 'error',
          'message': 'Missing root folder: /movies',
        },
        {
          'source': 'UpdateCheck',
          'type': 'warning',
          'message': 'New update is available',
        },
      ]),
    );
    final checks = await source(harness, DecisionSource.health);
    expect(checks.single.kind, DecisionKind.serviceHealth);
    expect(checks.single.title, 'A library folder is missing');
    expect(checks.single.reason, 'Missing root folder: /movies');
    expect(checks.single.service, ServiceKey.radarr);
  });

  test('Bazarr\'s health issue is a fault, in the app\'s words with its own '
      'kept', () async {
    final harness = await ProfileHarness.start(Profiles.p1);
    harness.network.on(
      WorldIds.bazarr,
      'GET',
      '/api/system/health',
      (_) => NetworkReply.json({
        'data': [
          {
            'object': 'Missing languages profile',
            'issue':
                'You must create at least one languages profile and assign it '
                'to your content.',
          },
        ],
      }),
    );
    final checks = await source(harness, DecisionSource.health);
    final bazarr = checks.where((c) => c.service == ServiceKey.bazarr).single;
    expect(bazarr.kind, DecisionKind.serviceHealth);
    expect(bazarr.title, 'Bazarr has no languages profile');
    expect(bazarr.reason, startsWith('You must create'));
    expect(bazarr.route, ServiceRoutes.forService(ServiceKey.bazarr));
  });

  test('Readarr\'s health check at the error level is a fault', () async {
    final harness = await ProfileHarness.start(
      ConfigProfile(
        id: 'T-readarr',
        title: 'Readarr alone',
        summary: 'Readarr, answering.',
        cases: const {},
        connections: [WorldConnections.readarr],
      ),
    );
    harness.network.on(
      'readarr',
      'GET',
      '/api/v1/health',
      (_) => NetworkReply.json([
        {
          'source': 'RootFolderCheck',
          'type': 'error',
          'message': 'Missing root folder: /books',
        },
      ]),
    );
    final checks = await source(harness, DecisionSource.health);
    expect(checks.single.service, ServiceKey.readarr);
    expect(checks.single.title, 'A library folder is missing');
  });

  test('the same check failing on three arrs is one fault', () async {
    final harness = await ProfileHarness.start(Profiles.p1);
    for (final (id, path, arr) in [
      (WorldIds.radarr, '/api/v3/health', 'Radarr'),
      (WorldIds.sonarr, '/api/v3/health', 'Sonarr'),
      (WorldIds.lidarr, '/api/v1/health', 'Lidarr'),
    ]) {
      harness.network.on(
        id,
        'GET',
        path,
        (_) => NetworkReply.json([
          {
            'source': 'IndexerRssCheck',
            'type': 'error',
            'message':
                'No indexers available with RSS sync enabled, $arr will not '
                'grab new releases automatically',
          },
        ]),
      );
    }
    final checks = await source(harness, DecisionSource.health);
    expect(checks.single.title, 'No indexer is watching for new releases');
    expect(checks.single.members, hasLength(3));
    expect(checks.single.detail, endsWith(' and Lidarr'));
  });

  test('a connection that refused its key is a fault with the remedy its '
      'cause names', () async {
    final harness = await ProfileHarness.start(Profiles.p1);
    harness.network.on(
      WorldIds.radarr4k,
      'GET',
      '/api/v3/system/status',
      (_) => NetworkReply.json({'error': 'Unauthorized'}, status: 401),
    );
    final container = harness.container();
    await container.read(
      instanceSummaryProvider((
        service: ServiceKey.radarr,
        instanceId: WorldIds.radarr4k,
      )).future,
    );
    final faults = (await container.read(
      dashboardDecisionSourceProvider(DecisionSource.connections).future,
    )).decisions;
    final fault = faults.singleWhere(
      (decision) => decision.instanceId == WorldIds.radarr4k,
    );
    expect(fault.kind, DecisionKind.connectionFault);
    expect(fault.title, contains('refused the key'));
    expect(fault.remedy, 'Paste the key again');
    expect(
      decisionActionLabel(fault.kind, remedy: fault.remedy),
      'Paste the key again',
    );
  });
}
