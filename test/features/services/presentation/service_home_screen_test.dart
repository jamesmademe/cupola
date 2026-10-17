import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/features/services/presentation/service_home_screen.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

void main() {
  testWidgets('pushes a service home from the stack and pops back', (
    tester,
  ) async {
    final router = _buildRouter('/stack');
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        // The app bar reads settings now: it has to know whether this service
        // has a second connection before it decides to show a lens badge.
        overrides: [
          currentSettingsProvider.overrideWith((ref) => const SettingsModel()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('open-service-radarr')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('service-home-title-radarr')),
      findsOneWidget,
    );
    expect(find.text('Radarr body'), findsOneWidget);

    // The title is the room's name, not a control: the dropdown picker it
    // used to open was retired when the Portal became the one switcher.
    expect(find.byKey(const ValueKey('service-home-switcher')), findsNothing);

    await tester.tap(find.byTooltip('Back to Stack'));
    await tester.pumpAndSettle();

    expect(router.state.uri.toString(), '/stack');
    expect(find.text('Stack home'), findsOneWidget);
  });

  testWidgets('back and activity actions navigate to parent routes', (
    tester,
  ) async {
    final router = _buildRouter('/stack');
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        // The app bar reads settings now: it has to know whether this service
        // has a second connection before it decides to show a lens badge.
        overrides: [
          currentSettingsProvider.overrideWith((ref) => const SettingsModel()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('open-service-lidarr')));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Activity'));
    await tester.pumpAndSettle();

    expect(router.state.uri.toString(), '/activity');
    expect(find.text('Activity page'), findsOneWidget);

    router.go('/stack/lidarr');
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Back to Stack'));
    await tester.pumpAndSettle();

    expect(router.state.uri.toString(), '/stack');
    expect(find.text('Stack home'), findsOneWidget);
  });

  testWidgets('with nothing beneath it, back goes to Stack', (tester) async {
    // A service home that is the first page of its navigator has nothing to
    // pop, and the button used to go to the service itself: it did nothing.
    final router = GoRouter(
      initialLocation: '/stack/lidarr',
      routes: [
        GoRoute(
          path: '/stack',
          builder: (_, _) => const Scaffold(body: Text('Stack home')),
        ),
        GoRoute(
          path: '/stack/lidarr',
          builder: (_, _) => const ServiceHomeScreen(
            service: ServiceKey.lidarr,
            child: Scaffold(body: Text('Lidarr body')),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentSettingsProvider.overrideWith((ref) => const SettingsModel()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Back to Stack'));
    await tester.pumpAndSettle();

    expect(router.state.uri.toString(), '/stack');
    expect(find.text('Stack home'), findsOneWidget);
  });

  testWidgets('the activity action sits on the gutter, not short of it', (
    tester,
  ) async {
    // A Flexible title beside a Spacer split the free width in half and kept
    // what it did not use, so the action sat ~56pt in from the edge on a
    // 390pt phone in Inter. The test font's glyphs are a full em wide, so the
    // bar is widened until the title is shorter than its half again.
    tester.view.physicalSize = const Size(600, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = _buildRouter('/stack/plex');
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentSettingsProvider.overrideWith((ref) => const SettingsModel()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    final action = tester.getRect(
      find.ancestor(
        of: find.byTooltip('Activity'),
        matching: find.byType(IconButton),
      ),
    );
    expect(action.right, closeTo(600 - AppSpacing.lg, 0.5));
  });
}

GoRouter _buildRouter(String initialLocation) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/stack',
        builder: (context, state) => Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                const Text('Stack home'),
                for (final service in ServiceKey.values)
                  TextButton(
                    key: ValueKey('open-service-${service.routeParam}'),
                    onPressed: () =>
                        context.push('/stack/${service.routeParam}'),
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
              builder: (context, state) => ServiceHomeScreen(
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
