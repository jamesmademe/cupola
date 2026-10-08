/// Home offers Renew only for a certificate Nginx Proxy Manager can renew.
///
/// NPM renews a Let's Encrypt certificate and nothing else: an uploaded one is
/// replaced by whoever issued it. Home offered Renew for both, and for an
/// uploaded certificate it landed on a tab with no Renew for it, a promise
/// the app cannot keep. Its row now says the truth, that it expires and must
/// be replaced in NPM, and its control opens the certificates without the
/// word Renew.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/cross_service_action.dart';
import 'package:cupola/features/home/presentation/home_screen.dart';
import 'package:cupola/features/services/presentation/dashboard_sections.dart';

import '../../../test_helpers/profiles/profiles.dart';

const _open = 'Open certificates';

/// One certificate of [provider] (`letsencrypt` or `other`, NPM's own
/// words) five days from lapsing.
void _script(ProfileNetwork network, String provider) => network.on(
  'npm',
  'GET',
  '/api/nginx/certificates',
  (r) => NetworkReply.json([
    {
      'id': 9,
      'provider': provider,
      'nice_name': 'nas.example.net',
      'domain_names': ['nas.example.net'],
      'expires_on': network.now
          .add(const Duration(days: 5, hours: 1))
          .toUtc()
          .toIso8601String(),
    },
  ]),
);

Future<(ProfileHarness, List<String>)> _pumpHome(
  WidgetTester tester, {
  required String provider,
  ConnectionBehaviour behaviour = ConnectionBehaviour.answers,
}) async {
  final harness = await ProfileHarness.start(
    Profiles.p3.withConnection(WorldConnections.npm.withBehaviour(behaviour)),
  );
  _script(harness.network, provider);

  final opened = <String>[];
  Widget landed(BuildContext context, GoRouterState state) {
    opened.add(state.uri.path);
    return const SizedBox.shrink();
  }

  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
      GoRoute(path: ServiceRoutes.nginxProxyManager, builder: landed),
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
  return (harness, opened);
}

Finder _inDecisions(Finder matching) => find.descendant(
  of: find.byType(DashboardDecisionsSection),
  matching: matching,
);

void main() {
  testWidgets('an uploaded certificate: the row names it as uploaded, and the '
      'control opens the certificates without the word Renew', (tester) async {
    final (harness, opened) = await _pumpHome(tester, provider: 'other');

    expect(_inDecisions(find.text('nas.example.net')), findsOneWidget);
    expect(
      _inDecisions(find.text('Uploaded certificate expires in 5 days')),
      findsOneWidget,
    );
    expect(_inDecisions(find.textContaining('Renew')), findsNothing);
    expect(_inDecisions(find.text(_open)), findsOneWidget);

    await tester.tap(_inDecisions(find.text(_open)));
    await harness.settle(tester);
    expect(opened, [ServiceRoutes.npmCertificates]);
    await harness.unmount(tester);
  });

  testWidgets('an uploaded certificate on a view-only account: opening is a '
      'read, so the control is not dimmed', (tester) async {
    final (harness, _) = await _pumpHome(
      tester,
      provider: 'other',
      behaviour: ConnectionBehaviour.readOnly,
    );

    final open = _inDecisions(find.text(_open));
    expect(open, findsOneWidget);
    expect(
      tester
          .widgetList<Opacity>(
            find.ancestor(of: open, matching: find.byType(Opacity)),
          )
          .where((o) => o.opacity == GatedAffordance.dimmedOpacity),
      isEmpty,
    );
    await harness.unmount(tester);
  });

  testWidgets('a Let\'s Encrypt certificate: Renew, opening the certificates', (
    tester,
  ) async {
    final (harness, opened) = await _pumpHome(tester, provider: 'letsencrypt');

    expect(
      _inDecisions(
        find.text('Certificate expires in 5 days · Nginx Proxy Manager'),
      ),
      findsOneWidget,
    );
    expect(_inDecisions(find.text(_open)), findsNothing);
    await tester.tap(_inDecisions(find.text('Renew')));
    await harness.settle(tester);
    expect(opened, [ServiceRoutes.npmCertificates]);
    await harness.unmount(tester);
  });
}
