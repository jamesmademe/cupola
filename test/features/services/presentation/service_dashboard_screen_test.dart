import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/features/services/presentation/service_dashboard_screen.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

void main() {
  testWidgets('pushes service dashboard from services home and pops back', (
    tester,
  ) async {
    final router = _buildRouter('/services');
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('open-service-radarr')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('service-dashboard-title-radarr')),
      findsOneWidget,
    );
    expect(find.text('Radarr body'), findsOneWidget);

    // The title is the room's name, not a control: the dropdown picker it
    // used to open was retired when the Portal became the one switcher.
    expect(find.byKey(const ValueKey('service-dashboard-switcher')), findsNothing);

    await tester.tap(find.byTooltip('Back to Services'));
    await tester.pumpAndSettle();

    expect(router.state.uri.toString(), '/services');
    expect(find.text('Services home'), findsOneWidget);
  });

  testWidgets('back and activity actions navigate to parent routes', (
    tester,
  ) async {
    final router = _buildRouter('/services');
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('open-service-lidarr')));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Activity'));
    await tester.pumpAndSettle();

    expect(router.state.uri.toString(), '/activity');
    expect(find.text('Activity page'), findsOneWidget);

    router.go('/services/lidarr');
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Back to Services'));
    await tester.pumpAndSettle();

    expect(router.state.uri.toString(), '/services');
    expect(find.text('Services home'), findsOneWidget);
  });
}

GoRouter _buildRouter(String initialLocation) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/services',
        builder: (context, state) => Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                const Text('Services home'),
                for (final service in ServiceKey.values)
                  TextButton(
                    key: ValueKey('open-service-${service.routeParam}'),
                    onPressed: () =>
                        context.push('/services/${service.routeParam}'),
                    child: Text('Open ${service.title}'),
                  ),
              ],
            ),
          ),
        ),
        routes: [
          for (final service in ServiceKey.values)
            GoRoute(
              path: service.routeParam,
              builder: (context, state) => ServiceDashboardScreen(
                service: service,
                child: Scaffold(body: Text('${service.title} body')),
              ),
            ),
        ],
      ),
      GoRoute(
        path: '/activity',
        builder: (context, state) =>
            const Scaffold(body: Text('Activity page')),
      ),
    ],
  );
}
