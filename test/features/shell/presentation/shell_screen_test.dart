import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/core/providers/navigation_refresh_provider.dart';
import 'package:cupola/core/utils/a11y_announce.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/features/onboarding/data/onboarding_provider.dart';
import 'package:cupola/features/release_search/presentation/release_search_jobs_provider.dart';
import 'package:cupola/features/release_search/presentation/release_search_lifecycle.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/presentation/service_matrix.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/nav_tab.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/shell/domain/portal_hints.dart';
import 'package:cupola/features/shell/domain/shell_branches.dart';
import 'package:cupola/features/shell/presentation/branch_transition.dart';
import 'package:cupola/features/shell/presentation/portal_announcement.dart';
import 'package:cupola/features/shell/presentation/service_portal.dart';
import 'package:cupola/features/shell/presentation/shell_screen.dart';

import '../../../test_helpers/fake_secure_settings_store.dart';
import '../../../test_helpers/semantics_announcements.dart';

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('ShellScreen', () {
    testWidgets('renders the floating nav bar with the operator\'s four', (
      tester,
    ) async {
      await _pumpShell(tester);

      expect(find.byType(FloatingBottomNavBar), findsOneWidget);
      expect(_navItem('Home'), findsOneWidget);
      expect(_navItem('Discover'), findsOneWidget);
      expect(_navItem('Activity'), findsOneWidget);
      expect(_navItem('Stack'), findsOneWidget);
      // Settings is a branch with no place in the bar: it opens from Stack's
      // gear. Requests is the requester's third tab, not the operator's.
      expect(_navItem('Settings'), findsNothing);
      expect(_navItem('Requests'), findsNothing);
      final bar = tester.widget<FloatingBottomNavBar>(
        find.byType(FloatingBottomNavBar),
      );
      expect(bar.destinations.map((destination) => destination.label), [
        'Home',
        'Discover',
        'Activity',
        'Stack',
      ]);
    });

    testWidgets('selects Home for the /home route', (tester) async {
      await _pumpShell(tester, initialLocation: '/home');

      expect(find.text('HomePage'), findsOneWidget);
      expect(find.byIcon(Icons.home_rounded), findsOneWidget);
      expect(find.byIcon(Icons.home_outlined), findsNothing);
    });

    testWidgets('selects Stack for the /stack route', (tester) async {
      await _pumpShell(tester, initialLocation: '/stack');

      expect(find.text('StackPage'), findsOneWidget);
      expect(find.byIcon(Icons.layers_rounded), findsOneWidget);
      expect(find.byIcon(Icons.layers_outlined), findsNothing);
    });

    testWidgets('selects Stack for service room routes', (tester) async {
      await _pumpShell(tester, initialLocation: '/stack/radarr/movie/42');

      expect(find.text('MovieDetailPage'), findsOneWidget);
      expect(find.byIcon(Icons.layers_rounded), findsOneWidget);
    });

    testWidgets('Settings is on screen with no tab of the bar selected', (
      tester,
    ) async {
      await _pumpShell(tester, initialLocation: '/settings');

      expect(find.text('SettingsPage'), findsOneWidget);
      final bar = tester.widget<FloatingBottomNavBar>(
        find.byType(FloatingBottomNavBar),
      );
      expect(bar.selectedIndex, -1);
      // Every glyph is the resting one: nothing in the bar is lit.
      expect(find.byIcon(Icons.home_rounded), findsNothing);
      expect(find.byIcon(Icons.explore_rounded), findsNothing);
      expect(find.byIcon(Icons.layers_rounded), findsNothing);
      expect(find.byIcon(Icons.settings_rounded), findsNothing);
    });

    // Replaces "does not select a tab for unmatched shell routes". There is no
    // such thing any more: every route inside the shell belongs to a branch by
    // construction, and a page with no tab of its own — the manual-import flow,
    // the activity drill-down — is a route above the shell, which the bar is not
    // part of at all.
    testWidgets('a route outside the shell has no nav bar to select in', (
      tester,
    ) async {
      await _pumpShell(tester, initialLocation: '/outside');

      expect(find.text('OutsidePage'), findsOneWidget);
      expect(find.byType(FloatingBottomNavBar), findsNothing);
      expect(find.byType(ShellScreen), findsNothing);
    });

    testWidgets('tapping Discover navigates to /discover', (tester) async {
      final harness = await _pumpShell(tester);

      await tester.tap(_navItem('Discover'));
      await tester.pumpAndSettle();

      expect(harness.router.state.uri.path, '/discover');
      expect(find.text('DiscoverPage'), findsOneWidget);
      expect(find.byIcon(Icons.explore_rounded), findsOneWidget);
    });

    for (final (label, path, section) in [
      ('Home', '/home', NavigationSection.home),
      ('Stack', '/stack', NavigationSection.stack),
    ]) {
      testWidgets('tapping the current $label tab triggers a refresh', (
        tester,
      ) async {
        final harness = await _pumpShell(tester, initialLocation: path);

        expect(harness.container.read(navigationRefreshProvider(section)), 0);

        await tester.tap(_navItem(label));
        await tester.pumpAndSettle();

        expect(harness.router.state.uri.path, path);
        expect(harness.container.read(navigationRefreshProvider(section)), 1);
        // And only its own: the other tabs' counters did not move.
        for (final other in NavigationSection.values.where(
          (value) => value != section,
        )) {
          expect(
            harness.container.read(navigationRefreshProvider(other)),
            0,
            reason: '$label must refresh $label, not ${other.name}',
          );
        }
      });
    }

    testWidgets(
      'tapping selected Stack from a nested room returns to root without refreshing',
      (tester) async {
        final harness = await _pumpShell(
          tester,
          initialLocation: '/stack/radarr/movie/42',
        );

        await tester.tap(_navItem('Stack'));
        await tester.pumpAndSettle();

        expect(harness.router.state.uri.path, '/stack');
        expect(find.text('StackPage'), findsOneWidget);
        expect(
          harness.container.read(
            navigationRefreshProvider(NavigationSection.stack),
          ),
          0,
        );
      },
    );

    // ── What the navigators buy, and what they must not cost ───────────────

    testWidgets('each branch keeps its own stack across a switch', (
      tester,
    ) async {
      final harness = await _pumpShell(
        tester,
        initialLocation: '/stack/radarr/movie/42',
      );

      await tester.tap(_navItem('Discover'));
      await tester.pumpAndSettle();
      expect(find.text('DiscoverPage'), findsOneWidget);

      await tester.tap(_navItem('Stack'));
      await tester.pumpAndSettle();

      // Not the tab's root: the page that was open when it was left.
      expect(harness.router.state.uri.path, '/stack/radarr/movie/42');
      expect(find.text('MovieDetailPage'), findsOneWidget);
    });

    testWidgets('a switched-away branch is kept alive, not rebuilt', (
      tester,
    ) async {
      await _pumpShell(tester);
      expect(_ProbePage.mounts['HomePage'], 1);

      await tester.tap(_navItem('Discover'));
      await tester.pumpAndSettle();
      await tester.tap(_navItem('Home'));
      await tester.pumpAndSettle();

      // Still one: this is the whole performance claim. A return costs no
      // construction, and everything the page had subscribed to stayed
      // subscribed — the 26 provider fetches a rebuilt first page used to
      // re-run never happen.
      expect(_ProbePage.mounts['HomePage'], 1);
      expect(_ProbePage.mounts['DiscoverPage'], 1);
    });

    testWidgets('returning to a branch root pops it and refreshes nothing', (
      tester,
    ) async {
      // The contract most easily broken by a future refactor: `goBranch` with
      // `initialLocation: true` must be a navigation, never a refresh.
      final harness = await _pumpShell(
        tester,
        initialLocation: '/stack/radarr/movie/42',
      );

      await tester.tap(_navItem('Stack'));
      await tester.pumpAndSettle();

      expect(harness.router.state.uri.path, '/stack');
      for (final section in NavigationSection.values) {
        expect(
          harness.container.read(navigationRefreshProvider(section)),
          0,
          reason: 'popping a branch must not fetch anything',
        );
      }
    });

    testWidgets('a re-tap deep in a branch pops it whatever the location says', (
      tester,
    ) async {
      // With four stacks the location can belong to a branch other than the
      // visible one, which is why the shell asks the navigator rather than the
      // path. The Stack is deep here while Discover shows: tapping the Stack must
      // land on its own root.
      final harness = await _pumpShell(
        tester,
        initialLocation: '/stack/radarr/movie/42',
      );
      await tester.tap(_navItem('Discover'));
      await tester.pumpAndSettle();

      await tester.tap(_navItem('Stack'));
      await tester.pumpAndSettle();
      expect(find.text('MovieDetailPage'), findsOneWidget);

      await tester.tap(_navItem('Stack'));
      await tester.pumpAndSettle();

      expect(harness.router.state.uri.path, '/stack');
      expect(find.text('StackPage'), findsOneWidget);
    });

    testWidgets('crossing the rail breakpoint keeps every branch stack', (
      tester,
    ) async {
      final harness = await _pumpShell(
        tester,
        initialLocation: '/stack/radarr/movie/42',
      );

      // Widen past 840 so the bar becomes the rail, then narrow back. The shell
      // is re-parented rather than rebuilt, which the single-navigator shell
      // could not do.
      tester.view.physicalSize = const Size(1200, 900);
      await tester.pumpAndSettle();
      expect(find.byType(FloatingBottomNavBar), findsNothing);

      tester.view.physicalSize = const Size(400, 900);
      await tester.pumpAndSettle();

      expect(harness.router.state.uri.path, '/stack/radarr/movie/42');
      expect(find.text('MovieDetailPage'), findsOneWidget);
    });

    testWidgets('re-tapping the active Stack tab announces the refresh', (
      tester,
    ) async {
      // A re-tap refresh changes nothing on screen — no spinner, no route
      // change — so without this the tap is indistinguishable from a no-op for a
      // screen-reader user.
      final announcements = SemanticsAnnouncementRecorder.install(tester);
      final harness = await _pumpShell(tester, initialLocation: '/stack');

      await tester.tap(_navItem('Stack'));
      await tester.pumpAndSettle();

      expect(announcements.messages, ['Refreshing Stack']);
      expect(
        harness.container.read(
          navigationRefreshProvider(NavigationSection.stack),
        ),
        1,
      );
    });

    testWidgets(
      'on Android the refresh is spoken through the live region',
      (tester) async {
        // TalkBack's engine has no announcement channel.
        final native = SemanticsAnnouncementRecorder.install(
          tester,
          supportsAnnounce: false,
        );
        await _pumpShell(tester, initialLocation: '/stack');

        await tester.tap(_navItem('Stack'));
        await tester.pumpAndSettle();

        expect(
          find.semantics.byLabel('Refreshing Stack'),
          containsSemantics(isLiveRegion: true),
        );
        expect(native.messages, isEmpty);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );

    testWidgets('switching tabs does not announce', (tester) async {
      // Replacing the whole screen is its own feedback, and an announcement
      // interrupts the reader's speech queue. This guards an over-eager
      // announce() in the navigate branch.
      final announcements = SemanticsAnnouncementRecorder.install(tester);
      await _pumpShell(tester, initialLocation: '/stack');

      await tester.tap(_navItem('Discover'));
      await tester.pumpAndSettle();

      expect(announcements.messages, isEmpty);
    });

    testWidgets('switching tabs fires one selection haptic, not two', (
      tester,
    ) async {
      // The bar used to fire a selection click of its own on top of the shell's,
      // so a tab change buzzed twice.
      final haptics = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'HapticFeedback.vibrate') {
              haptics.add(call.arguments as String);
            }
            return null;
          });

      await _pumpShell(tester, initialLocation: '/stack');
      haptics.clear();

      await tester.tap(_navItem('Discover'));
      await tester.pumpAndSettle();

      expect(haptics, ['HapticFeedbackType.selectionClick']);
    });

    testWidgets('leaving Settings by the bar refreshes nothing', (
      tester,
    ) async {
      // Settings has no tab to re-tap and no refresh section of its own: its
      // refresh is a command ("Test all"). The way out of it is a tab of the
      // bar, and that is a navigation, never a fetch.
      final harness = await _pumpShell(tester, initialLocation: '/settings');

      await tester.tap(_navItem('Stack'));
      await tester.pumpAndSettle();

      expect(harness.router.state.uri.path, '/stack');
      for (final section in NavigationSection.values) {
        expect(
          harness.container.read(navigationRefreshProvider(section)),
          0,
          reason: '${section.name} must not refresh on arrival',
        );
      }
    });
  });

  group('ShellScreen at rail width', () {
    testWidgets('still observes the app lifecycle', (tester) async {
      // The rail branch used to return a bare Scaffold outside
      // ReleaseSearchLifecycle, so on macOS and tablet nothing observed the
      // lifecycle at all: appInForegroundProvider stayed permanently true, and a
      // search the OS killed while the app was away was blamed on the network
      // instead of on leaving Cupola.
      final harness = await _pumpShell(tester, viewport: _railViewport);

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(ReleaseSearchLifecycle), findsOneWidget);
      expect(harness.container.read(appInForegroundProvider), isTrue);

      await _sendLifecycle(tester, AppLifecycleState.paused);
      expect(harness.container.read(appInForegroundProvider), isFalse);

      await _sendLifecycle(tester, AppLifecycleState.resumed);
      expect(harness.container.read(appInForegroundProvider), isTrue);
    });

    testWidgets('crossing the breakpoint keeps one observer, not two', (
      tester,
    ) async {
      // The lifecycle wrapper sits above the layout branch precisely so that
      // dragging a window past 840pt does not mount or unmount the observer
      // mid-session.
      final harness = await _pumpShell(tester, viewport: _railViewport);
      expect(find.byType(ReleaseSearchLifecycle), findsOneWidget);

      tester.view.physicalSize = const Size(400, 900);
      await tester.pumpAndSettle();

      expect(find.byType(FloatingBottomNavBar), findsOneWidget);
      expect(find.byType(ReleaseSearchLifecycle), findsOneWidget);

      await _sendLifecycle(tester, AppLifecycleState.paused);
      expect(harness.container.read(appInForegroundProvider), isFalse);
    });

    testWidgets('shows the finished-search badge the bottom bar shows', (
      tester,
    ) async {
      // The badge is the channel that has to keep working when notifications
      // are denied, off, or missed — and the rail was the one surface where it
      // never appeared, because it built its destinations itself.
      await _pumpShell(
        tester,
        viewport: _railViewport,
        overrides: [
          ...await _lensOverrides(instances: const []),
          unseenReleaseSearchCountProvider.overrideWithValue(3),
        ],
      );

      expect(
        find.descendant(
          of: find.byType(NavigationRail),
          matching: find.byType(Badge),
        ),
        findsOneWidget,
      );
      // A number painted on an icon is invisible to a screen reader, so it has
      // to reach the spoken label too — the same string the bottom bar speaks.
      final activityLabel = tester.widget<Text>(
        find.descendant(
          of: find.byType(NavigationRail),
          matching: find.text('Activity'),
        ),
      );
      expect(
        activityLabel.semanticsLabel,
        'Activity, 3 finished searches to look at',
      );
    });

    testWidgets('no waiting searches means no badge', (tester) async {
      await _pumpShell(tester, viewport: _railViewport);

      expect(
        find.descendant(
          of: find.byType(NavigationRail),
          matching: find.byType(Badge),
        ),
        findsNothing,
      );
    });
  });

  // The Portal closes when what sits under its card moves. The route half of
  // that has always worked; the lens half is what multi-instance added, and it
  // is invisible to a path comparison — which is exactly how it would have
  // shipped.
  group('the Portal and the lens', () {
    testWidgets('moving a lens closes the Portal over the stale page', (
      tester,
    ) async {
      final harness = await _pumpShell(
        tester,
        overrides: await _lensOverrides(),
        // Deliberately the phone: the rail has no vertical drag to open the
        // Portal with, so the wide window cannot exercise this at all.
        viewport: const Size(390 * 3, 844 * 3),
        devicePixelRatio: 3,
      );

      await _openPortal(tester);
      expect(
        find.byType(ServiceMatrix),
        findsOneWidget,
        reason: 'the floor is only in the tree while the Portal is open',
      );

      // No navigation at all — the same thing the picker cell does after
      // `go` resolves to the path it is already on.
      await harness.container
          .read(activeInstancesProvider.notifier)
          .select(ServiceKey.radarr, 'radarr-hd11111');
      await tester.pumpAndSettle();

      expect(
        find.byType(ServiceMatrix),
        findsNothing,
        reason:
            'the page under the card now reads a different Radarr, so the '
            'snapshot the Portal is holding is of a library nobody is looking '
            'at any more',
      );
    });

    testWidgets('an unrelated settings write leaves the Portal alone', (
      tester,
    ) async {
      // The counterweight. Closing on *any* rebuild would be a Portal that
      // shuts itself the first time a poll lands.
      final harness = await _pumpShell(
        tester,
        overrides: await _lensOverrides(),
        viewport: const Size(390 * 3, 844 * 3),
        devicePixelRatio: 3,
      );

      await _openPortal(tester);
      expect(find.byType(ServiceMatrix), findsOneWidget);

      await harness.container
          .read(settingsProvider.notifier)
          .updateSettings(
            const SettingsModel(instances: _lensInstances, region: 'IT'),
          );
      await tester.pumpAndSettle();

      expect(find.byType(ServiceMatrix), findsOneWidget);
    });

    // The hook above is REACTIVE — it closes because the content under the card
    // moved. A tap on the cell the lens already points at, from the page that
    // cell leads to, moves neither the path nor the lens, so nothing reacted
    // and the Portal sat there over a snapshot looking broken. Closing on the
    // *act* is the fix, and it lives at the cell.
    testWidgets('tapping the cell the lens is already on closes the Portal', (
      tester,
    ) async {
      final harness = await _pumpShell(
        tester,
        initialLocation: '/stack/radarr',
        overrides: await _lensOverrides(),
        viewport: const Size(390 * 3, 844 * 3),
        devicePixelRatio: 3,
      );

      // The lens is PARKED on the first connection, not merely defaulting to
      // it. Without this the map has no entry for Radarr, `select` writes one,
      // and the hook below closes the Portal on a lens that did move — which
      // is how a green test would have covered a defect the device reproduces
      // at will.
      await harness.container
          .read(activeInstancesProvider.notifier)
          .select(ServiceKey.radarr, 'radarr');
      await tester.pumpAndSettle();

      await _openPortal(tester);
      expect(find.byType(ServiceMatrix), findsOneWidget);
      expect(
        harness.container.read(activeInstanceProvider(ServiceKey.radarr))?.id,
        'radarr',
      );

      await tester.tap(
        find.byKey(const ValueKey('service-matrix-cell-radarr-radarr')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byType(ServiceMatrix),
        findsNothing,
        reason:
            'a tap on a picker cell is an act on the Portal and must close it '
            'even when it moves nothing underneath',
      );
      // And it really was a no-op underneath: neither input the hook watches
      // changed, which is why the hook could never have caught this.
      expect(harness.router.state.uri.path, '/stack/radarr');
      expect(
        harness.container.read(activeInstanceProvider(ServiceKey.radarr))?.id,
        'radarr',
      );
    });

    testWidgets('a cell that does move the lens still closes exactly once', (
      tester,
    ) async {
      // The counterweight to the fix: with the cell closing on the act AND the
      // hook closing on the lens moving, the same close must not be started
      // twice — a second spring launched from the first one's current value
      // with no velocity is a visible hitch.
      final harness = await _pumpShell(
        tester,
        initialLocation: '/stack/radarr',
        overrides: await _lensOverrides(),
        viewport: const Size(390 * 3, 844 * 3),
        devicePixelRatio: 3,
      );

      await _openPortal(tester);
      await tester.tap(
        find.byKey(const ValueKey('service-matrix-cell-radarr-radarr-hd11111')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ServiceMatrix), findsNothing);
      expect(
        harness.container.read(activeInstanceProvider(ServiceKey.radarr))?.id,
        'radarr-hd11111',
      );
    });
  });

  // Back over an open Portal means "put the page back". It used to reach the
  // branch navigator first, which popped the room under the card and left the
  // Portal to be closed by the route hook a frame later — over a page the user
  // never chose to leave.
  group('the Portal and back', () {
    testWidgets('system back closes the Portal and leaves the room alone', (
      tester,
    ) async {
      final harness = await _pumpShell(
        tester,
        initialLocation: '/stack/radarr/movie/42',
        overrides: await _lensOverrides(),
        viewport: const Size(390 * 3, 844 * 3),
        devicePixelRatio: 3,
      );

      await _openPortal(tester);
      expect(find.byType(ServiceMatrix), findsOneWidget);

      await _systemBack(tester);

      expect(find.byType(ServiceMatrix), findsNothing);
      expect(
        harness.router.state.uri.path,
        '/stack/radarr/movie/42',
        reason: 'the room the Portal lifted is the one it puts back',
      );
      expect(find.text('MovieDetailPage'), findsOneWidget);

      // And with the Portal gone, back is back again.
      await _systemBack(tester);
      expect(harness.router.state.uri.path, '/stack');
    });

    testWidgets('on a tab root, back closes the Portal instead of the app', (
      tester,
    ) async {
      final platformCalls = _recordPlatformCalls();
      await _pumpShell(
        tester,
        overrides: await _lensOverrides(),
        viewport: const Size(390 * 3, 844 * 3),
        devicePixelRatio: 3,
      );

      await _openPortal(tester);
      await _systemBack(tester);

      expect(find.byType(ServiceMatrix), findsNothing);
      expect(
        platformCalls.map((call) => call.method),
        isNot(contains('SystemNavigator.pop')),
        reason: 'nothing under the Portal could pop, and the app stayed open',
      );
    });

    testWidgets('Android is told the app wants back only while it is open', (
      tester,
    ) async {
      // With predictive back the system keeps a back to itself unless the app
      // has claimed it, and on a tab root the navigators never do: the back
      // would close the app from under an open Portal.
      final platformCalls = _recordPlatformCalls();
      await _pumpShell(
        tester,
        overrides: await _lensOverrides(),
        viewport: const Size(390 * 3, 844 * 3),
        devicePixelRatio: 3,
      );
      // The app only reports to the engine once it is running.
      await _sendLifecycle(tester, AppLifecycleState.resumed);
      bool? lastClaim() =>
          platformCalls
                  .lastWhere(
                    (call) =>
                        call.method ==
                        'SystemNavigator.setFrameworkHandlesBack',
                  )
                  .arguments
              as bool?;

      await _openPortal(tester);
      expect(lastClaim(), isTrue);

      await tester.tap(_navItem('Stack'));
      await tester.pumpAndSettle();
      expect(find.byType(ServiceMatrix), findsNothing);
      expect(
        lastClaim(),
        isFalse,
        reason: 'closed on a tab root, back belongs to the system again',
      );
    });

    testWidgets('closing over a pushed room keeps back with the app', (
      tester,
    ) async {
      // The counterweight: a claim released as a flat "no" would leave the
      // room unpoppable by the system back.
      final platformCalls = _recordPlatformCalls();
      await _pumpShell(
        tester,
        initialLocation: '/stack/radarr/movie/42',
        overrides: await _lensOverrides(),
        viewport: const Size(390 * 3, 844 * 3),
        devicePixelRatio: 3,
      );
      await _sendLifecycle(tester, AppLifecycleState.resumed);

      await _openPortal(tester);
      await _systemBack(tester);

      expect(
        platformCalls
            .lastWhere(
              (call) =>
                  call.method == 'SystemNavigator.setFrameworkHandlesBack',
            )
            .arguments,
        isTrue,
      );
    });

    testWidgets('Escape closes it in a narrow desktop window', (tester) async {
      // Under the compact artboard a desktop window gets the phone layout, and
      // the Portal with it; the keyboard's back is Escape.
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final harness = await _pumpShell(
          tester,
          initialLocation: '/stack/radarr/movie/42',
          overrides: await _lensOverrides(),
          viewport: const Size(390 * 3, 844 * 3),
          devicePixelRatio: 3,
        );

        await _openPortal(tester);
        expect(find.byType(ServiceMatrix), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();

        expect(find.byType(ServiceMatrix), findsNothing);
        expect(harness.router.state.uri.path, '/stack/radarr/movie/42');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  // A screen reader cannot drag, so the drag is off under one and the tab bar
  // carries the Portal as an action instead. Opening it — either way — says
  // once what the floor holds.
  group('the Portal without the gesture', () {
    testWidgets('the Stack tab carries an action that opens it', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final announcements = SemanticsAnnouncementRecorder.install(tester);
      // The reader is running, which is what takes the drag away.
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(
            accessibleNavigation: true,
            supportsAnnounce: true,
          );
      final harness = await _pumpShell(
        tester,
        initialLocation: '/stack/radarr/movie/42',
        overrides: await _lensOverrides(),
        viewport: const Size(390 * 3, 844 * 3),
        devicePixelRatio: 3,
      );
      // The Stack, where the services are, has already asked every
      // connection. Without that the sentence says what is true at that
      // moment — "2 checking" — which the sentence's own test covers.
      harness.container.listen(portalFloorCensusProvider, (_, _) {});
      await tester.pumpAndSettle();

      final stackTab = find.semantics.byLabel(RegExp(r'^Stack\n'));
      expect(
        tester.getSemantics(_navItem('Stack')),
        containsSemantics(customActions: const [ShellScreen.openPortalAction]),
      );
      expect(
        find.semantics.byPredicate(_offersPortal),
        findsOne,
        reason: 'one tab carries it, not four',
      );

      tester.semantics.customAction(stackTab, ShellScreen.openPortalAction);
      await tester.pumpAndSettle();

      expect(find.byType(ServiceMatrix), findsOneWidget);
      expect(announcements.messages, [
        'Portal open. 2 services, none with a fault.',
      ]);

      // The card is a picture of the page, and inert: the reader cannot walk
      // into it. The floor's own way back is named instead.
      expect(find.semantics.byLabel('MovieDetailPage'), findsNothing);
      final close = find.semantics.byLabel('Close the Portal');
      expect(close, findsOne);

      // A second activation while open neither restarts it nor speaks again.
      tester.semantics.customAction(stackTab, ShellScreen.openPortalAction);
      await tester.pumpAndSettle();
      expect(announcements.messages, hasLength(1));

      tester.semantics.tap(close);
      await tester.pumpAndSettle();
      expect(find.byType(ServiceMatrix), findsNothing);
      expect(find.semantics.byLabel('MovieDetailPage'), findsOne);
      semantics.dispose();
    });

    testWidgets(
      'on Android the opening sentence reaches TalkBack',
      (tester) async {
        final native = SemanticsAnnouncementRecorder.install(
          tester,
          supportsAnnounce: false,
        );
        // TalkBack is running: the drag is withheld, and the engine has no
        // announcement channel.
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(accessibleNavigation: true);
        final harness = await _pumpShell(
          tester,
          overrides: await _lensOverrides(),
          viewport: const Size(390 * 3, 844 * 3),
          devicePixelRatio: 3,
        );
        harness.container.listen(portalFloorCensusProvider, (_, _) {});
        await tester.pumpAndSettle();

        tester.semantics.customAction(
          find.semantics.byLabel(RegExp(r'^Stack\n')),
          ShellScreen.openPortalAction,
        );
        await tester.pumpAndSettle();

        expect(find.byType(ServiceMatrix), findsOneWidget);
        // The Portal hides the page under it from the reader; the sentence is
        // drawn above every route, where that cannot reach it.
        expect(
          find.semantics.byLabel('Portal open. 2 services, none with a fault.'),
          containsSemantics(isLiveRegion: true),
        );
        expect(native.messages, isEmpty);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );

    testWidgets('a fault on the floor is counted in the sentence', (
      tester,
    ) async {
      final announcements = SemanticsAnnouncementRecorder.install(tester);
      await _pumpShell(
        tester,
        // The HD connection did not answer: the red pip on its cell.
        overrides: await _lensOverrides(silent: {'radarr-hd11111'}),
        viewport: const Size(390 * 3, 844 * 3),
        devicePixelRatio: 3,
      );

      await _openPortal(tester);

      expect(announcements.messages, [
        'Portal open. 2 services, 1 with a fault.',
      ]);
    });

    testWidgets('opening by the finger announces once too', (tester) async {
      final announcements = SemanticsAnnouncementRecorder.install(tester);
      await _pumpShell(
        tester,
        overrides: await _lensOverrides(),
        viewport: const Size(390 * 3, 844 * 3),
        devicePixelRatio: 3,
      );

      await _openPortal(tester);

      expect(announcements.messages, [
        'Portal open. 2 services, none with a fault.',
      ]);
    });

    testWidgets('the rail offers no Portal to open', (tester) async {
      // No Portal is drawn beside a rail, so there is nothing to promise.
      final semantics = tester.ensureSemantics();
      await _pumpShell(
        tester,
        overrides: await _lensOverrides(),
        viewport: _railViewport,
      );

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.semantics.byPredicate(_offersPortal), findsNothing);
      semantics.dispose();
    });
  });

  // The one-shot demo is spent only where it is seen. The window that could
  // not see it is asked in the desktop shell's own tests.
  group('the Portal demo', () {
    testWidgets('plays once on the phone and is then marked seen', (
      tester,
    ) async {
      final harness = await _pumpShell(
        tester,
        overrides: await _lensOverrides(demoDue: true),
        viewport: const Size(390 * 3, 844 * 3),
        devicePixelRatio: 3,
      );
      expect(
        harness.container.read(portalHintsProvider).demoBouncePending,
        isTrue,
      );

      await tester.pump(const Duration(milliseconds: 700));
      // The bounce is under way: the page has begun to recede.
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.byType(ServiceMatrix), findsOneWidget);
      // The lift ends, then the hold — a timer, which settling alone does not
      // run — then the release settles.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      expect(
        harness.container.read(portalHintsProvider).demoBouncePending,
        isFalse,
      );
      expect(find.byType(ServiceMatrix), findsNothing);
    });

    testWidgets('a finger on the bar when it is due keeps it owed', (
      tester,
    ) async {
      final harness = await _pumpShell(
        tester,
        overrides: await _lensOverrides(demoDue: true),
        viewport: const Size(390 * 3, 844 * 3),
        devicePixelRatio: 3,
      );

      // The user is already dragging when the breath runs out: the bounce
      // cannot play, so it has not been shown.
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(FloatingBottomNavBar)),
      );
      await gesture.moveBy(const Offset(0, -60));
      await gesture.moveBy(const Offset(0, -60));
      await tester.pump(const Duration(milliseconds: 800));

      expect(
        harness.container.read(portalHintsProvider).demoBouncePending,
        isTrue,
      );
      await gesture.up();
      await tester.pumpAndSettle();
    });
  });

  // The coach mark's evidence of need: a switch from the Stack to a service
  // that went round the Portal. Counted only where a Portal is drawn.
  group('the Portal coach mark\'s journeys', () {
    testWidgets('a Stack to service switch on the phone is one', (
      tester,
    ) async {
      final harness = await _pumpShell(
        tester,
        initialLocation: '/stack',
        overrides: await _lensOverrides(),
        viewport: const Size(390 * 3, 844 * 3),
        devicePixelRatio: 3,
      );
      expect(harness.container.read(portalHintsProvider).manualJourneys, 0);

      harness.router.go('/stack/radarr');
      await tester.pumpAndSettle();

      expect(find.text('ServiceRoom'), findsOneWidget);
      expect(harness.container.read(portalHintsProvider).manualJourneys, 1);
    });

    testWidgets('the same switch beside a rail is not, there is no Portal', (
      tester,
    ) async {
      // The count is persisted and the window is not: a wide window that
      // counted its own navigation would hand the coach mark to a phone that
      // never lacked the Portal.
      final harness = await _pumpShell(
        tester,
        initialLocation: '/stack',
        overrides: await _lensOverrides(),
        viewport: _railViewport,
      );
      expect(find.byType(NavigationRail), findsOneWidget);

      harness.router.go('/stack/radarr');
      await tester.pumpAndSettle();

      expect(find.text('ServiceRoom'), findsOneWidget);
      expect(harness.container.read(portalHintsProvider).manualJourneys, 0);
    });
  });

  // The single-animation half of the story above, asked of the machine rather
  // than of the tree: the tree only shows that it ended closed.
  group('ServicePortalController', () {
    testWidgets('a close already under way is not restarted', (tester) async {
      // Two identical closes, one interrupted halfway by a second request. A
      // restarted spring throws away the velocity it had built, so it is
      // measurably further from home at the same instant — which on the device
      // is the hitch the user sees.
      Future<double> valueAfter({required bool closeTwice}) async {
        final controller = ServicePortalController(vsync: const TestVSync());
        addTearDown(controller.dispose);
        controller.portal.value = 1;
        controller.closeFromUi();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        if (closeTwice) controller.closeFromUi();
        await tester.pump(const Duration(milliseconds: 60));
        final value = controller.portal.value;
        // Read first, then let the spring finish: a ticker still running when
        // the test ends is an error of its own, and it would mask this one.
        await tester.pumpAndSettle();
        return value;
      }

      final once = await valueAfter(closeTwice: false);
      final twice = await valueAfter(closeTwice: true);

      expect(once, lessThan(1));
      expect(
        twice,
        closeTo(once, 1e-6),
        reason: 'the second request must leave the first spring alone',
      );
    });
  });
}

const _lensInstances = [
  ServiceInstance(
    id: 'radarr',
    service: ServiceKey.radarr,
    label: '4K',
    url: 'https://four-k.lan:7878',
    credential: 'k',
  ),
  ServiceInstance(
    id: 'radarr-hd11111',
    service: ServiceKey.radarr,
    label: 'HD',
    url: 'https://hd.lan:7879',
    credential: 'k',
  ),
];

/// Enough of a world for the Portal's floor to build: two connections, and a
/// health answer for each so no cell reaches for a socket. The ids in [silent]
/// answer that they did not answer.
///
/// The one-shot demo is marked shown, because a fresh install owes it and it
/// would play 700 ms into any test that pumps that long, folding the page
/// mid-assertion. The tests of the demo itself ask for it with [demoDue].
Future<List<Override>> _lensOverrides({
  Set<String> silent = const {},
  bool demoDue = false,
  List<ServiceInstance> instances = _lensInstances,
}) async {
  SharedPreferences.setMockInitialValues({
    if (!demoDue) 'portal_hint_demo_shown': true,
  });
  final prefs = await SharedPreferences.getInstance();
  return [
    sharedPreferencesProvider.overrideWithValue(prefs),
    secureSettingsStoreProvider.overrideWithValue(FakeSecureSettingsStore()),
    initialSettingsProvider.overrideWithValue(
      SettingsModel(instances: instances),
    ),
    initialOnboardingCompletedProvider.overrideWithValue(true),
    for (final instance in instances)
      instanceSummaryProvider((
        service: instance.service,
        instanceId: instance.id,
      )).overrideWith(
        (ref) async => ServiceSummary(
          service: instance.service,
          status: silent.contains(instance.id)
              ? ServiceSummaryStatus.offline
              : ServiceSummaryStatus.online,
          host: 'somewhere',
          version: '5.0',
        ),
      ),
  ];
}

/// Opens the Portal the way a finger does. A flick, not a slow drag: the
/// release only completes past the safe zone or beyond the flick gate, and a
/// velocity well over the gate is the one input that does not depend on how
/// many pixels the viewport happens to give the gesture.
Future<void> _openPortal(WidgetTester tester) async {
  await tester.fling(
    find.byType(FloatingBottomNavBar),
    const Offset(0, -260),
    2000,
  );
  await tester.pumpAndSettle();
}

/// Whether [node] offers the tab bar's way into the Portal.
bool _offersPortal(SemanticsNode node) =>
    node.getSemanticsData().customSemanticsActionIds?.contains(
      CustomSemanticsAction.getIdentifier(ShellScreen.openPortalAction),
    ) ??
    false;

/// The Android back button, sent down the channel the platform uses.
Future<void> _systemBack(WidgetTester tester) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.navigation.name,
    SystemChannels.navigation.codec.encodeMethodCall(
      const MethodCall('popRoute'),
    ),
    (_) {},
  );
  await tester.pumpAndSettle();
}

/// Every call the app makes on the platform channel, in order.
///
/// Installed over the file's silent default; the file's `tearDown` removes it.
List<MethodCall> _recordPlatformCalls() {
  final calls = <MethodCall>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        calls.add(call);
        return null;
      });
  return calls;
}

/// Wide enough for the rail: the breakpoint is Material's 840pt expanded window.
const Size _railViewport = Size(1200, 900);

/// Drives the real lifecycle channel rather than calling the binding's
/// protected handler, so the test exercises the same path the platform uses.
Future<void> _sendLifecycle(
  WidgetTester tester,
  AppLifecycleState state,
) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/lifecycle',
    const StringCodec().encodeMessage(state.toString()),
    (_) {},
  );
  await tester.pumpAndSettle();
}

/// A harness page that counts its own mounts.
///
/// The point of four navigators is that leaving a tab no longer destroys it, and
/// "was it destroyed?" is not a question a `Text` can answer. Each mount is one
/// full construction of the page — the cost this migration exists to stop
/// paying, and the moment every provider the page watches would be re-read.
class _ProbePage extends StatefulWidget {
  const _ProbePage(this.label);

  final String label;

  /// Mounts per label, reset by [_pumpShell].
  static final Map<String, int> mounts = {};

  @override
  State<_ProbePage> createState() => _ProbePageState();
}

class _ProbePageState extends State<_ProbePage> {
  @override
  void initState() {
    super.initState();
    _ProbePage.mounts.update(
      widget.label,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
  }

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Text(widget.label, textDirection: TextDirection.ltr));
}

Future<_ShellHarness> _pumpShell(
  WidgetTester tester, {
  String initialLocation = '/home',
  // Phone width by default, so the shell renders the FloatingBottomNavBar rather
  // than the wide-window NavigationRail (the rail breakpoint is 840).
  Size viewport = const Size(400, 900),
  // The matrix resolves its columns against a preferred cell width, so the one
  // test that opens the Portal needs a viewport in real device pixels rather
  // than the logical-pixel shorthand the rest of this file uses.
  double devicePixelRatio = 1.0,
  // The shell reads who it is drawn for, which waits on the saved settings and
  // on onboarding: a test that brings no world of its own gets one with no
  // connection in it (and the demo spent, as in every world here).
  List<Override>? overrides,
}) async {
  _ProbePage.mounts.clear();
  final container = ProviderContainer(
    overrides: overrides ?? await _lensOverrides(instances: const []),
  );
  // Mirrors production's shape, because that shape is what the shell now reads:
  // six branches in `NavTab` order, each with its own navigator key, behind the
  // real cross-fade container. `/outside` sits at ROOT, where the manual-import
  // flow and the activity drill-down live — a route with no tab of its own is
  // now a route outside the shell, not an unmatched route inside it.
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      StatefulShellRoute(
        navigatorContainerBuilder: buildBranchTransition,
        builder: (context, state, navigationShell) =>
            ShellScreen(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            navigatorKey: branchNavigatorKeyFor(NavTab.home),
            routes: [
              GoRoute(
                path: '/home',
                builder: (_, _) => const _ProbePage('HomePage'),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: branchNavigatorKeyFor(NavTab.discover),
            routes: [
              GoRoute(
                path: '/discover',
                builder: (_, _) => const _ProbePage('DiscoverPage'),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: branchNavigatorKeyFor(NavTab.activity),
            routes: [
              GoRoute(
                path: '/activity',
                builder: (_, _) => const _ProbePage('ActivityPage'),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: branchNavigatorKeyFor(NavTab.stack),
            routes: [
              GoRoute(
                path: '/stack',
                builder: (_, _) => const _ProbePage('StackPage'),
                routes: [
                  GoRoute(
                    path: 'radarr/movie/:id',
                    builder: (_, _) => const _ProbePage('MovieDetailPage'),
                  ),
                  // Where a matrix cell lands. One segment, so it cannot
                  // swallow the two-segment detail route above it.
                  GoRoute(
                    path: ':service',
                    builder: (_, _) => const _ProbePage('ServiceRoom'),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: branchNavigatorKeyFor(NavTab.requests),
            routes: [
              GoRoute(
                path: '/requests',
                builder: (_, _) => const _ProbePage('RequestsPage'),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: branchNavigatorKeyFor(NavTab.settings),
            routes: [
              GoRoute(
                path: '/settings',
                builder: (_, _) => const _ProbePage('SettingsPage'),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/outside',
        builder: (_, _) => const _ProbePage('OutsidePage'),
      ),
    ],
  );

  addTearDown(() {
    router.dispose();
    container.dispose();
  });

  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        // Where `CupolaApp` mounts it: the live region Android's reader hears
        // announcements through.
        builder: (context, child) => AnnouncementHost(child: child!),
      ),
    ),
  );
  await tester.pumpAndSettle();

  return _ShellHarness(container: container, router: router);
}

Finder _navItem(String label) {
  return find.descendant(
    of: find.byType(FloatingBottomNavBar),
    matching: find.byKey(ValueKey('floating-nav-item-${label.toLowerCase()}')),
  );
}

class _ShellHarness {
  const _ShellHarness({required this.container, required this.router});

  final ProviderContainer container;
  final GoRouter router;
}
