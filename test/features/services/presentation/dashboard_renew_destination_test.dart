/// Home's Renew lands where a certificate is renewed.
///
/// It opened Nginx Proxy Manager's root, which is its Overview, and the
/// Overview offers no writes at all: Renew lands on a page with nothing to
/// renew on it. It now opens the Certificates tab, where Renew and its
/// confirmation are.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/services/presentation/dashboard_screen.dart';
import 'package:cupola/features/services/presentation/dashboard_sections.dart';

import '../../../test_helpers/profiles/profiles.dart';

void main() {
  testWidgets('Renew opens the Certificates tab', (tester) async {
    final harness = await ProfileHarness.start(
      Profiles.p3.withConnection(WorldConnections.npm),
    );
    harness.network.on(
      'npm',
      'GET',
      '/api/nginx/certificates',
      (r) => NetworkReply.json([
        {
          'id': 7,
          'provider': 'letsencrypt',
          'nice_name': 'jellyfin.example.com',
          'domain_names': ['jellyfin.example.com'],
          'expires_on': harness.network.now
              .add(const Duration(days: 10))
              .toUtc()
              .toIso8601String(),
        },
      ]),
    );

    String? opened;
    Widget landed(BuildContext context, GoRouterState state) {
      opened = state.uri.path;
      return const SizedBox.shrink();
    }

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const DashboardScreen(),
        ),
        GoRoute(path: ServiceRoutes.nginxProxyManager, builder: landed),
        GoRoute(path: ServiceRoutes.npmOverview, builder: landed),
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

    await tester.tap(
      find.descendant(
        of: find.byType(DashboardDecisionsSection),
        matching: find.text('Renew'),
      ),
    );
    await harness.settle(tester);

    expect(opened, ServiceRoutes.npmCertificates);
    await harness.unmount(tester);
  });
}
