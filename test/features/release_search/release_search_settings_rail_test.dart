import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/features/release_search/presentation/release_search_entry.dart';
import 'package:cupola/features/release_search/presentation/release_search_settings_screen.dart';
import 'package:cupola/features/settings/presentation/widgets/settings_master_detail.dart';

import '../../test_helpers/settings_scope.dart';

/// Background search is a section of the settings rail, and it was the one
/// destination in that list not wrapped in [SettingsMasterDetail]: a bare
/// `GoRoute` with a `builder` where its six siblings are `_page`s. On a desktop
/// window that meant selecting Background search made the rail *disappear*: the
/// one control that got you here was the one control the page then hid.
Future<void> _pump(
  WidgetTester tester, {
  required Size size,
  required TargetPlatform platform,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: [
      ...await settingsScopeOverrides(),
      releaseSearchPlatformProvider.overrideWith((ref) => platform),
      notificationPermissionProvider.overrideWith((ref) async => null),
    ],
  );
  addTearDown(container.dispose);

  final router = GoRouter(
    initialLocation: '/settings/background-search',
    routes: [
      GoRoute(
        path: '/settings',
        builder: (_, _) => const SizedBox.shrink(),
        routes: [
          GoRoute(
            path: 'background-search',
            builder: (_, _) => const ReleaseSearchSettingsScreen(),
          ),
        ],
      ),
    ],
  );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.darkTheme(),
        routerConfig: router,
      ),
    ),
  );
  await tester.pump();
}

Future<void> _onPlatform(
  TargetPlatform platform,
  Future<void> Function() body,
) {
  debugDefaultTargetPlatformOverride = platform;
  return body().whenComplete(() {
    debugDefaultTargetPlatformOverride = null;
  });
}

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('keeps the settings rail on a desktop window', (tester) async {
    await _onPlatform(TargetPlatform.macOS, () async {
      await _pump(
        tester,
        size: const Size(1440, 900),
        platform: TargetPlatform.macOS,
      );

      expect(find.byType(SettingsMasterDetail), findsOneWidget);
      // The rail's own sections, beside the page rather than instead of it.
      expect(find.text('Connections'), findsOneWidget);
      expect(find.text('Appearance'), findsOneWidget);
      // And the page itself is still there.
      expect(find.text('Background search'), findsWidgets);
    });
  });

  // The wrapper is inert below the rail threshold and on every touch build,
  // where Settings is correctly a drill-down: one screen, one job, a back
  // button. A rail that appeared on a phone would be a second navigation model.
  testWidgets('shows no rail on a phone', (tester) async {
    await _onPlatform(TargetPlatform.android, () async {
      await _pump(
        tester,
        size: const Size(390, 844),
        platform: TargetPlatform.android,
      );

      expect(find.byType(SettingsMasterDetail), findsOneWidget);
      expect(find.text('Connections'), findsNothing);
      expect(find.text('Appearance'), findsNothing);
    });
  });

  // The rail's own `sections` list already pointed at this location; the route
  // is what could not carry it. If the two ever disagree the row goes dead
  // again, exactly as Connections did while it pointed at a redirect.
  test('the rail names the location the route serves', () {
    final section = SettingsMasterDetail.sections.firstWhere(
      (s) => s.label == 'Background search',
    );
    expect(section.location, '/settings/background-search');
  });
}
