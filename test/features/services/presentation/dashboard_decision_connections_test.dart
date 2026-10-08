/// The failing indexers, exited stacks and expiring certificates the Home
/// leads with come off every connection, and each decision row's control acts
/// on the one its row came off.
///
/// The three were read through the lens alone, because Test, Start and Renew
/// called the lens: with two Prowlarr, two Dockge or two Nginx Proxy Manager,
/// the second one's faults never reached Home. Each connection is now its own
/// source, every row says which one it is on once there are two, and its
/// control reaches that server. The rows are mounted on their own: the Home
/// leads with one line (Needs you) and no longer lists the decisions.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/presentation/dashboard_sections.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/decision_rows.dart';
import '../../../test_helpers/profiles/profiles.dart';

/// Seerr alone, and then the two connections under test: no queue, so the
/// rows are theirs and the requests'.
ConfigProfile _two(ProfileConnection first, ProfileConnection second) =>
    Profiles.p3
        .without(ServiceKey.radarr)
        .without(ServiceKey.sonarr)
        .withConnection(first)
        .withConnection(second);

/// Indexer 3 failing on Prowlarr [id], since an hour ago.
void _failingIndexer(ProfileNetwork network, String id) => network.on(
  id,
  'GET',
  '/api/v1/indexerstatus',
  (_) => NetworkReply.json([
    {
      'indexerId': 3,
      'initialFailure': network.now
          .subtract(const Duration(hours: 1))
          .toUtc()
          .toIso8601String(),
      'mostRecentFailure': network.now.toUtc().toIso8601String(),
    },
  ]),
);

/// One Let's Encrypt certificate ten days from lapsing on NPM [id].
void _expiringCertificate(ProfileNetwork network, String id) => network.on(
  id,
  'GET',
  '/api/nginx/certificates',
  (_) => NetworkReply.json([
    {
      'id': 7,
      'provider': 'letsencrypt',
      'nice_name': 'jellyfin.example.com',
      'domain_names': ['jellyfin.example.com'],
      'expires_on': network.now
          .add(const Duration(days: 10))
          .toUtc()
          .toIso8601String(),
    },
  ]),
);

/// The decision rows of [profile] in a router whose other pages record where
/// a tap landed.
Future<(ProfileHarness, ValueGetter<String?>)> _pumpRows(
  WidgetTester tester,
  ConfigProfile profile, {
  void Function(ProfileNetwork network)? before,
}) async {
  final harness = await ProfileHarness.start(profile);
  before?.call(harness.network);

  String? opened;
  Widget landed(BuildContext context, GoRouterState state) {
    opened = state.uri.path;
    return const SizedBox.shrink();
  }

  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) =>
            const Scaffold(body: ProvidedDecisionRows()),
      ),
      GoRoute(
        path: '${ServiceRoutes.prowlarrIndexerBase}/:id',
        builder: landed,
      ),
      GoRoute(path: ServiceRoutes.npmCertificates, builder: landed),
    ],
  );
  addTearDown(router.dispose);

  await tester.binding.setSurfaceSize(const Size(430, 6000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: MaterialApp.router(
        theme: AppTheme.darkTheme(),
        routerConfig: router,
      ),
    ),
  );
  await harness.settle(tester);
  return (harness, () => opened);
}

/// The app's container, which outlives the rows once a tap has left them.
ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));

/// The control [label] on the decision row keyed [id].
Finder _control(String id, String label) => find.descendant(
  of: find.byKey(ValueKey('decision-$id')),
  matching: find.text(label),
);

Finder _detail(String text) =>
    find.descendant(of: find.byType(DecisionRow), matching: find.text(text));

void main() {
  group('two Prowlarr', () {
    test('each failing indexer is read off its own server, and says which '
        'one', () async {
      final harness = await ProfileHarness.start(
        _two(WorldConnections.prowlarr, WorldConnections.prowlarrTower),
      );
      _failingIndexer(harness.network, WorldIds.prowlarr);
      _failingIndexer(harness.network, WorldIds.prowlarrTower);
      final container = harness.container(retry: (_, _) => null);

      final read = await container.read(
        dashboardDecisionSourceProvider(DecisionSource.indexers).future,
      );

      expect(read.decisions.map((d) => d.instanceId), [
        WorldIds.prowlarr,
        WorldIds.prowlarrTower,
      ]);
      // Both are Cedar Index, indexer 3 on each server: two rows, two keys.
      expect(read.decisions.map((d) => d.title).toSet(), {'Cedar Index'});
      expect(read.decisions.map((d) => d.id).toSet(), hasLength(2));
      expect(read.decisions.map((d) => d.detail), [
        'Failing · Prowlarr 1',
        'Failing · Prowlarr Tower',
      ]);
      expect(read.coverage.answered, hasLength(2));
    });

    testWidgets('Test on the tower\'s row tests the tower\'s indexer', (
      tester,
    ) async {
      final (harness, _) = await _pumpRows(
        tester,
        _two(WorldConnections.prowlarr, WorldConnections.prowlarrTower),
        before: (network) {
          _failingIndexer(network, WorldIds.prowlarr);
          _failingIndexer(network, WorldIds.prowlarrTower);
        },
      );
      expect(_detail('Failing · Prowlarr Tower'), findsOne);

      await tester.tap(
        _control('prowlarr-${WorldIds.prowlarrTower}-3', 'Test'),
      );
      await harness.settle(tester);

      bool tested(String id) => harness.network
          .requestsTo(id)
          .any((r) => r.method == 'POST' && r.path == '/api/v1/indexer/test');
      expect(tested(WorldIds.prowlarrTower), isTrue);
      expect(tested(WorldIds.prowlarr), isFalse);

      await harness.unmount(tester);
    });

    testWidgets('the tower\'s row opens its indexer with the tower under the '
        'lens', (tester) async {
      final (harness, opened) = await _pumpRows(
        tester,
        _two(WorldConnections.prowlarr, WorldConnections.prowlarrTower),
        before: (network) => _failingIndexer(network, WorldIds.prowlarrTower),
      );

      await tester.tap(_detail('Failing · Prowlarr Tower'));
      await harness.settle(tester);

      expect(opened(), ServiceRoutes.prowlarrIndexer(3));
      expect(
        _container(
          tester,
        ).read(activeInstanceProvider(ServiceKey.prowlarr))?.id,
        WorldIds.prowlarrTower,
      );

      await harness.unmount(tester);
    });
  });

  testWidgets('two Dockge: Start on the tower\'s stack starts it on the '
      'tower', (tester) async {
    final (harness, _) = await _pumpRows(
      tester,
      _two(WorldConnections.dockge, WorldConnections.dockgeTower),
    );
    // `immich` exited on each, each named.
    expect(_detail('Stack stopped · Dockge 1'), findsOne);
    expect(_detail('Stack stopped · Dockge Tower'), findsOne);

    await tester.tap(
      _control('dockge-${WorldIds.dockgeTower}--immich', 'Start'),
    );
    await harness.settle(tester);

    expect(
      harness.network.rpcCalls,
      contains((WorldIds.dockgeTower, 'agent:startStack')),
    );
    expect(
      harness.network.rpcCalls,
      isNot(contains((WorldIds.dockge, 'agent:startStack'))),
    );

    await harness.unmount(tester);
  });

  testWidgets('two Nginx Proxy Manager: Renew on the second one\'s '
      'certificate opens the certificates with it under the lens', (
    tester,
  ) async {
    final (harness, opened) = await _pumpRows(
      tester,
      _two(WorldConnections.npm, WorldConnections.npmNas),
      before: (network) {
        _expiringCertificate(network, WorldConnections.npm.id);
        _expiringCertificate(network, WorldIds.npmNas);
      },
    );
    expect(
      _detail('Certificate expires in 9 days · Nginx Proxy Manager Home'),
      findsOne,
    );

    await tester.tap(_control('npm-cert-${WorldIds.npmNas}-7', 'Renew'));
    await harness.settle(tester);

    expect(opened(), ServiceRoutes.npmCertificates);
    expect(
      _container(
        tester,
      ).read(activeInstanceProvider(ServiceKey.nginxProxyManager))?.id,
      WorldIds.npmNas,
    );

    await harness.unmount(tester);
  });
}
