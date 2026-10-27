import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/not_configured_placeholder.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Every `Set up X` goes to the same place: the service's own setup form.
///
/// It used to be three places for one verb: the matrix cell and the empty
/// Home opened the connections list, a cross-service control's toast opened
/// the form, and Streaming's "Set one up" opened the Dashboard. These pin the
/// surfaces that say it to [ServiceRoutes.setUp].
void main() {
  test('the destination is the service form, for every service', () {
    for (final service in ServiceKey.values) {
      expect(
        ServiceRoutes.setUp(service),
        '/settings/service/${service.routeParam}',
      );
    }
  });

  /// Pumps [page] under a router that records where a tap went.
  Future<Uri? Function()> pumpRouted(WidgetTester tester, Widget page) async {
    Uri? opened;
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (context, state) => page),
        GoRoute(
          path: '/settings/service/:service',
          builder: (context, state) {
            opened = state.uri;
            return const SizedBox.shrink();
          },
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();
    return () => opened;
  }

  testWidgets('a media server not set up names each one and opens its form', (
    tester,
  ) async {
    final opened = await pumpRouted(
      tester,
      Scaffold(
        body: Column(
          children: [
            NotConfiguredPlaceholder.forService(ServiceKey.jellyfin),
            NotConfiguredPlaceholder.forService(ServiceKey.plex),
          ],
        ),
      ),
    );

    expect(find.text('Set up Jellyfin'), findsOneWidget);
    await tester.tap(find.text('Set up Plex'));
    await tester.pumpAndSettle();

    expect(opened()?.path, ServiceRoutes.setUp(ServiceKey.plex));
  });
}
