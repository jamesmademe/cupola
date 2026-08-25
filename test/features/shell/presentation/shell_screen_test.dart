import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/providers/navigation_refresh_provider.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/features/release_search/presentation/release_search_jobs_provider.dart';
import 'package:cupola/features/release_search/presentation/release_search_lifecycle.dart';
import 'package:cupola/features/settings/domain/nav_tab.dart';
import 'package:cupola/features/shell/domain/shell_branches.dart';
import 'package:cupola/features/shell/presentation/branch_cross_fade.dart';
import 'package:cupola/features/shell/presentation/shell_screen.dart';

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
    testWidgets('renders the floating nav bar with four destinations', (
      tester,
    ) async {
      await _pumpShell(tester);

      expect(find.byType(FloatingBottomNavBar), findsOneWidget);
      expect(_navItem('Services'), findsOneWidget);
      expect(_navItem('Activity'), findsOneWidget);
      expect(_navItem('Search'), findsOneWidget);
      expect(_navItem('Settings'), findsOneWidget);
    });

    testWidgets('selects Services for the /services route', (tester) async {
      await _pumpShell(tester, initialLocation: '/services');

      expect(find.text('ServicesPage'), findsOneWidget);
      expect(find.byIcon(Icons.view_list_rounded), findsOneWidget);
      expect(find.byIcon(Icons.view_list_outlined), findsNothing);
    });

    testWidgets('selects Services for legacy detail routes', (tester) async {
      await _pumpShell(tester, initialLocation: '/services/radarr/movie/42');

      expect(find.text('MovieDetailPage'), findsOneWidget);
      expect(find.byIcon(Icons.view_list_rounded), findsOneWidget);
    });

    testWidgets('selects Settings for the /settings route', (tester) async {
      await _pumpShell(tester, initialLocation: '/settings');

      expect(find.text('SettingsPage'), findsOneWidget);
      expect(find.byIcon(Icons.settings), findsOneWidget);
      expect(find.byIcon(Icons.settings_outlined), findsNothing);
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

    testWidgets('tapping Search navigates to /search', (tester) async {
      final harness = await _pumpShell(tester);

      await tester.tap(_navItem('Search'));
      await tester.pumpAndSettle();

      expect(harness.router.state.uri.path, '/search');
      expect(find.text('SearchPage'), findsOneWidget);
      expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    });

    testWidgets('tapping the current Services tab triggers a refresh', (
      tester,
    ) async {
      final harness = await _pumpShell(tester, initialLocation: '/services');

      expect(
        harness.container.read(
          navigationRefreshProvider(NavigationSection.services),
        ),
        0,
      );

      await tester.tap(_navItem('Services'));
      await tester.pumpAndSettle();

      expect(harness.router.state.uri.path, '/services');
      expect(
        harness.container.read(
          navigationRefreshProvider(NavigationSection.services),
        ),
        1,
      );
    });

    testWidgets(
      'tapping selected Services from a nested services route returns to root without refreshing',
      (tester) async {
        final harness = await _pumpShell(
          tester,
          initialLocation: '/services/radarr/movie/42',
        );

        await tester.tap(_navItem('Services'));
        await tester.pumpAndSettle();

        expect(harness.router.state.uri.path, '/services');
        expect(find.text('ServicesPage'), findsOneWidget);
        expect(
          harness.container.read(
            navigationRefreshProvider(NavigationSection.services),
          ),
          0,
        );
      },
    );

    // ── What four navigators buy, and what they must not cost ──────────────

    testWidgets('each branch keeps its own stack across a switch', (
      tester,
    ) async {
      final harness = await _pumpShell(
        tester,
        initialLocation: '/services/radarr/movie/42',
      );

      await tester.tap(_navItem('Search'));
      await tester.pumpAndSettle();
      expect(find.text('SearchPage'), findsOneWidget);

      await tester.tap(_navItem('Services'));
      await tester.pumpAndSettle();

      // Not the tab's root: the page that was open when it was left.
      expect(harness.router.state.uri.path, '/services/radarr/movie/42');
      expect(find.text('MovieDetailPage'), findsOneWidget);
    });

    testWidgets('a switched-away branch is kept alive, not rebuilt', (
      tester,
    ) async {
      await _pumpShell(tester);
      expect(_ProbePage.mounts['ServicesPage'], 1);

      await tester.tap(_navItem('Search'));
      await tester.pumpAndSettle();
      await tester.tap(_navItem('Services'));
      await tester.pumpAndSettle();

      // Still one: this is the whole performance claim. A return costs no
      // construction, and everything the page had subscribed to stayed
      // subscribed — the 26 provider fetches a rebuilt /services used to re-run
      // never happen.
      expect(_ProbePage.mounts['ServicesPage'], 1);
      expect(_ProbePage.mounts['SearchPage'], 1);
    });

    testWidgets('returning to a branch root pops it and refreshes nothing', (
      tester,
    ) async {
      // The contract most easily broken by a future refactor: `goBranch` with
      // `initialLocation: true` must be a navigation, never a refresh.
      final harness = await _pumpShell(
        tester,
        initialLocation: '/services/radarr/movie/42',
      );

      await tester.tap(_navItem('Services'));
      await tester.pumpAndSettle();

      expect(harness.router.state.uri.path, '/services');
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
      // path. Services is deep here while Search shows: tapping Services must
      // land on its own root.
      final harness = await _pumpShell(
        tester,
        initialLocation: '/services/radarr/movie/42',
      );
      await tester.tap(_navItem('Search'));
      await tester.pumpAndSettle();

      await tester.tap(_navItem('Services'));
      await tester.pumpAndSettle();
      expect(find.text('MovieDetailPage'), findsOneWidget);

      await tester.tap(_navItem('Services'));
      await tester.pumpAndSettle();

      expect(harness.router.state.uri.path, '/services');
      expect(find.text('ServicesPage'), findsOneWidget);
    });

    testWidgets('crossing the rail breakpoint keeps every branch stack', (
      tester,
    ) async {
      final harness = await _pumpShell(
        tester,
        initialLocation: '/services/radarr/movie/42',
      );

      // Widen past 840 so the bar becomes the rail, then narrow back. The shell
      // is re-parented rather than rebuilt, which the single-navigator shell
      // could not do.
      tester.view.physicalSize = const Size(1200, 900);
      await tester.pumpAndSettle();
      expect(find.byType(FloatingBottomNavBar), findsNothing);

      tester.view.physicalSize = const Size(400, 900);
      await tester.pumpAndSettle();

      expect(harness.router.state.uri.path, '/services/radarr/movie/42');
      expect(find.text('MovieDetailPage'), findsOneWidget);
    });

    testWidgets('re-tapping the active Services tab announces the refresh', (
      tester,
    ) async {
      // A re-tap refresh changes nothing on screen — no spinner, no route
      // change — so without this the tap is indistinguishable from a no-op for a
      // screen-reader user.
      final announcements = SemanticsAnnouncementRecorder.install(tester);
      final harness = await _pumpShell(tester, initialLocation: '/services');

      await tester.tap(_navItem('Services'));
      await tester.pumpAndSettle();

      expect(announcements.messages, ['Refreshing Services']);
      expect(
        harness.container.read(
          navigationRefreshProvider(NavigationSection.services),
        ),
        1,
      );
    });

    testWidgets('switching tabs does not announce', (tester) async {
      // Replacing the whole screen is its own feedback, and an announcement
      // interrupts the reader's speech queue. This guards an over-eager
      // announce() in the navigate branch.
      final announcements = SemanticsAnnouncementRecorder.install(tester);
      await _pumpShell(tester, initialLocation: '/services');

      await tester.tap(_navItem('Search'));
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

      await _pumpShell(tester, initialLocation: '/services');
      haptics.clear();

      await tester.tap(_navItem('Search'));
      await tester.pumpAndSettle();

      expect(haptics, ['HapticFeedbackType.selectionClick']);
    });

    testWidgets('tapping the current Settings tab does not trigger refresh', (
      tester,
    ) async {
      final harness = await _pumpShell(tester, initialLocation: '/settings');

      await tester.tap(_navItem('Settings'));
      await tester.pumpAndSettle();

      expect(harness.router.state.uri.path, '/settings');
      expect(
        harness.container.read(
          navigationRefreshProvider(NavigationSection.services),
        ),
        0,
      );
      expect(
        harness.container.read(
          navigationRefreshProvider(NavigationSection.activity),
        ),
        0,
      );
      expect(
        harness.container.read(
          navigationRefreshProvider(NavigationSection.search),
        ),
        0,
      );
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
        overrides: [unseenReleaseSearchCountProvider.overrideWithValue(3)],
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
  String initialLocation = '/services',
  // Phone width by default, so the shell renders the FloatingBottomNavBar rather
  // than the wide-window NavigationRail (the rail breakpoint is 840).
  Size viewport = const Size(400, 900),
  List<Override> overrides = const [],
}) async {
  _ProbePage.mounts.clear();
  final container = ProviderContainer(overrides: overrides);
  // Mirrors production's shape, because that shape is what the shell now reads:
  // four branches in `NavTab` order, each with its own navigator key, behind the
  // real cross-fade container. `/outside` sits at ROOT, where the manual-import
  // flow and the activity drill-down live — a route with no tab of its own is
  // now a route outside the shell, not an unmatched route inside it.
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      StatefulShellRoute(
        navigatorContainerBuilder: buildBranchCrossFade,
        builder: (context, state, navigationShell) =>
            ShellScreen(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            navigatorKey: branchNavigatorKeyFor(NavTab.services),
            routes: [
              GoRoute(
                path: '/services',
                builder: (_, __) => const _ProbePage('ServicesPage'),
                routes: [
                  GoRoute(
                    path: 'radarr/movie/:id',
                    builder: (_, __) => const _ProbePage('MovieDetailPage'),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: branchNavigatorKeyFor(NavTab.activity),
            routes: [
              GoRoute(
                path: '/activity',
                builder: (_, __) => const _ProbePage('ActivityPage'),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: branchNavigatorKeyFor(NavTab.search),
            routes: [
              GoRoute(
                path: '/search',
                builder: (_, __) => const _ProbePage('SearchPage'),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: branchNavigatorKeyFor(NavTab.settings),
            routes: [
              GoRoute(
                path: '/settings',
                builder: (_, __) => const _ProbePage('SettingsPage'),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/outside',
        builder: (_, __) => const _ProbePage('OutsidePage'),
      ),
    ],
  );

  addTearDown(() {
    router.dispose();
    container.dispose();
  });

  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
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
