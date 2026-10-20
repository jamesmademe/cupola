import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/features/activity/data/activity_live.dart';
import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/providers/navigation_refresh_provider.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/nav_tab.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/shell/presentation/desktop/desktop_shell.dart';

import '../../../test_helpers/fake_secure_settings_store.dart';

/// ⌘R, on the one tab where it used to mean nothing.
///
/// `_refreshAll` mapped [NavTab.settings] to `null` and stopped there, so the
/// shortcut was a deliberate no-op on a quarter of the app, and it stayed one
/// after Settings grew a real "Test all" command, which meant the window strip's
/// own Refresh-all chip advertised a shortcut that did nothing on the pane where
/// it is most wanted. The two are one sentence (*ask every server again*), and
/// the point of this test is that they stay one sentence rather than drifting
/// into two implementations that disagree about what "every" covers.
void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('⌘R on the Settings tab tests every saved connection', (
    tester,
  ) async {
    await _onDesktop(() async {
      final container = await _container();
      addTearDown(container.dispose);

      await _pump(tester, container, tab: NavTab.settings);
      await _pressRefreshAll(tester);

      // The announcement names the set the command covered, which is the whole
      // reason `testAllConnections` returns a count: a command whose only
      // feedback is a spinner somewhere below the fold is a command people
      // press twice.
      expect(find.text('Testing the one connection…'), findsOneWidget);

      // And it did *not* quietly also refresh a section. Settings has no
      // section counter, and inventing one would be a second meaning for ⌘R on
      // the same tab.
      for (final section in NavigationSection.values) {
        expect(container.read(navigationRefreshProvider(section)), 0);
      }
    });
  });

  for (final (tab, section) in [
    (NavTab.home, NavigationSection.home),
    (NavTab.activity, NavigationSection.activity),
    (NavTab.stack, NavigationSection.stack),
  ]) {
    testWidgets(
      '⌘R on ${tab.label} still refreshes the section, not the connections',
      (tester) async {
        await _onDesktop(() async {
          final container = await _container();
          addTearDown(container.dispose);

          await _pump(tester, container, tab: tab);
          await _pressRefreshAll(tester);

          expect(container.read(navigationRefreshProvider(section)), 1);
          // And no other: each tab asks for its own.
          for (final other in NavigationSection.values.where(
            (value) => value != section,
          )) {
            expect(container.read(navigationRefreshProvider(other)), 0);
          }
          // No snack: a section refresh is visible in the section it
          // refreshed.
          expect(find.textContaining('Testing'), findsNothing);
        });
      },
    );
  }
}

/// Runs [body] as if the app were on macOS, and always puts the override back.
///
/// Inside the body rather than in `tearDown`: the test binding verifies that no
/// foundation debug variable is still set when the body returns, which is
/// earlier than any tear-down runs.
Future<void> _onDesktop(Future<void> Function() body) {
  debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
  return body().whenComplete(() {
    debugDefaultTargetPlatformOverride = null;
  });
}

/// `metaLeft`, not `meta`: the shortcut map is keyed on the physical modifier,
/// and the bare logical key never matches it.
Future<void> _pressRefreshAll(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<ProviderContainer> _container() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [
      // The sidebar's "In flight" poll outlives a test that ends before its
      // container is disposed.
      sidebarInFlightPollProvider.overrideWith((ref) {}),
      sharedPreferencesProvider.overrideWithValue(prefs),
      initialSettingsProvider.overrideWithValue(
        const SettingsModel(
          instances: [
            ServiceInstance(
              id: 'radarr',
              service: ServiceKey.radarr,
              label: '4K',
              url: 'https://four-k.lan:7878',
              credential: 'k',
            ),
          ],
        ),
      ),
      secureSettingsStoreProvider.overrideWithValue(FakeSecureSettingsStore()),
    ],
  );
}

Future<void> _pump(
  WidgetTester tester,
  ProviderContainer container, {
  required NavTab tab,
}) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final bar = NavTab.barFor(Audience.operator);
  final router = GoRouter(
    initialLocation: tab.routePath,
    routes: [
      for (final navTab in NavTab.values)
        GoRoute(
          path: navTab.routePath,
          builder: (context, state) => DesktopShell(
            // Autofocused: `Shortcuts` only sees a key event that reaches a
            // focused node, and in the real app the branch navigator supplies
            // one. Without it the shell is built, the map is installed, and no
            // key ever arrives.
            navigationShell: const Focus(
              autofocus: true,
              child: SizedBox.expand(),
            ),
            currentTab: navTab,
            // The operator's bar, and where this tab sits in it: none, for
            // Settings, which is no tab of the bar.
            destinations: [
              for (final t in bar)
                FloatingNavDestination(
                  icon: t.icon,
                  selectedIcon: t.selectedIcon,
                  label: t.label,
                ),
            ],
            selectedIndex: bar.indexOf(navTab),
            onDestinationSelected: (_) {},
            onSettings: () {},
          ),
        ),
    ],
  );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pump();
}
