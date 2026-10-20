import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/features/activity/data/activity_live.dart';
import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/network/connection_failure.dart'
    show ServiceFailureReason;
import 'package:cupola/core/providers/navigation_refresh_provider.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/widgets/floating_nav_rail.dart';
import 'package:cupola/features/onboarding/data/onboarding_provider.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/nav_tab.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/shell/domain/portal_hints.dart';
import 'package:cupola/features/shell/domain/shell_branches.dart';
import 'package:cupola/features/shell/domain/shell_shortcuts.dart';
import 'package:cupola/features/shell/presentation/branch_transition.dart';
import 'package:cupola/features/shell/presentation/desktop/command_deck.dart';
import 'package:cupola/features/shell/presentation/desktop/desktop_nav_rail.dart';
import 'package:cupola/features/shell/presentation/desktop/inspector_pane.dart';
import 'package:cupola/features/shell/presentation/desktop/window_chrome.dart';
import 'package:cupola/features/shell/presentation/shell_screen.dart';
import 'package:cupola/features/search/presentation/global_search_provider.dart';

import '../../../test_helpers/fake_secure_settings_store.dart';

/// The window shell, asked for by platform rather than by width.
///
/// Every test here overrides [debugDefaultTargetPlatformOverride], which is the
/// point: on a developer's Mac `dart:io` would answer "desktop" for the whole
/// suite and silently re-point the phone tests at this layout, so the shell asks
/// [defaultTargetPlatform] and each shell is tested by naming it.
void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('a desktop window gets one strip, the sidebar and the page: '
      'no deck, no status bar', (tester) async {
    await onPlatform(TargetPlatform.macOS, () async {
      await _pumpShell(tester, overrides: await _world());

      expect(find.byType(WindowChrome), findsOneWidget);
      expect(find.byType(DesktopNavRail), findsOneWidget);
      // The page starts under the one strip and reaches the window's foot.
      final page = tester.getRect(find.byType(Placeholder).first);
      expect(page.top, WindowChrome.height);
      expect(page.bottom, 900, reason: 'no status bar at the foot');

      // And none of the touch navigation, at the same size.
      expect(find.byType(FloatingBottomNavBar), findsNothing);
      expect(find.byType(FloatingNavRail), findsNothing);
    });
  });

  testWidgets('desktop navigation controls expose semantic actions', (
    tester,
  ) async {
    await onPlatform(TargetPlatform.macOS, () async {
      final semantics = tester.ensureSemantics();
      try {
        await _pumpShell(tester, overrides: await _world());

        final activity = find.bySemanticsLabel('Activity');
        expect(activity, findsOneWidget);
        final activitySemantics = tester
            .getSemantics(activity)
            .getSemanticsData();
        expect(activitySemantics.flagsCollection.isButton, isTrue);
        expect(activitySemantics.hasAction(SemanticsAction.tap), isTrue);
        // The strip's own key: the sidebar does not repeat it.
        expect(find.bySemanticsLabel('Jump to anything, ⌘K'), findsOneWidget);
        // The inspector's switch says its key and whether the pane is open.
        expect(
          tester.getSemantics(find.bySemanticsLabel('Inspector, ⌥I')),
          containsSemantics(
            isButton: true,
            hasTapAction: true,
            hasToggledState: true,
            isToggled: false,
          ),
        );
      } finally {
        semantics.dispose();
      }
    });
  });

  testWidgets('the same window on a touch platform keeps the rail', (
    tester,
  ) async {
    await onPlatform(TargetPlatform.android, () async {
      await _pumpShell(tester, overrides: await _world());

      expect(find.byType(FloatingNavRail), findsOneWidget);
      expect(find.byType(WindowChrome), findsNothing);
    });
  });

  testWidgets('a window under the compact artboard gets the phone layout', (
    tester,
  ) async {
    await onPlatform(TargetPlatform.macOS, () async {
      await _pumpShell(
        tester,
        viewport: const Size(400, 800),
        overrides: await _world(),
      );

      expect(find.byType(FloatingBottomNavBar), findsOneWidget);
      expect(find.byType(WindowChrome), findsNothing);
      expect(find.byType(DesktopNavRail), findsNothing);
      // Still a frameless window: the strip keeps the lights' gutter and the
      // drag region above the phone layout.
      expect(find.byType(WindowDragStrip), findsOneWidget);

      // And dragging it wide again brings the window shell back.
      tester.view.physicalSize = const Size(1440, 900);
      await tester.pumpAndSettle();
      expect(find.byType(WindowChrome), findsOneWidget);
      expect(find.byType(FloatingBottomNavBar), findsNothing);
      expect(find.byType(WindowDragStrip), findsNothing);
    });
  });

  testWidgets('the breadcrumb is the window title, service and all', (
    tester,
  ) async {
    await onPlatform(TargetPlatform.macOS, () async {
      await _pumpShell(
        tester,
        initialLocation: '/stack/radarr',
        overrides: await _world(),
      );

      final chrome = find.byType(WindowChrome);
      expect(
        // The breadcrumb IS the URL, and the root crumb is the tab's label.
        find.descendant(of: chrome, matching: find.text('Stack')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: chrome, matching: find.text('Radarr')),
        findsOneWidget,
      );
    });
  });

  testWidgets('the full window carries the way to anything and the '
      "inspector's switch", (tester) async {
    await onPlatform(TargetPlatform.macOS, () async {
      await _pumpShell(tester, overrides: await _world());

      final chrome = find.byType(WindowChrome);
      expect(
        find.descendant(of: chrome, matching: find.text('Jump to…')),
        findsOneWidget,
      );
      expect(find.byTooltip('Inspector  ⌥I'), findsOneWidget);
      // The stack's health is the sidebar's and Stack's, not the strip's.
      expect(find.textContaining('/ 1'), findsNothing);
    });
  });

  testWidgets('a compact window keeps the way to anything, and no switch for '
      'a pane it cannot show', (tester) async {
    await onPlatform(TargetPlatform.macOS, () async {
      await _pumpShell(
        tester,
        // Below `AppBreakpoints.desktopCompact` the inspector is never laid
        // out, so a switch for it would do nothing anyone could see.
        viewport: const Size(720, 450),
        overrides: await _world(),
      );

      final chrome = find.byType(WindowChrome);
      expect(
        find.descendant(of: chrome, matching: find.text('Jump')),
        findsOneWidget,
      );
      expect(find.byTooltip('Inspector  ⌥I'), findsNothing);
    });
  });

  testWidgets('the switch opens the inspector and lights while it is open', (
    tester,
  ) async {
    await onPlatform(TargetPlatform.macOS, () async {
      await _pumpShell(tester, overrides: await _world());

      await tester.tap(find.byTooltip('Inspector  ⌥I'));
      await tester.pumpAndSettle();
      expect(find.byType(InspectorPane), findsOneWidget);

      await tester.tap(find.byTooltip('Inspector  ⌥I'));
      await tester.pumpAndSettle();
      expect(find.byType(InspectorPane), findsNothing);
      // The pane's poll stops a frame behind the pane.
      await tester.pump(const Duration(milliseconds: 1));
    });
  });

  testWidgets('⌥I opens the inspector and closes it again', (tester) async {
    await onPlatform(TargetPlatform.macOS, () async {
      await _pumpShell(tester, overrides: await _world());

      expect(find.byType(InspectorPane), findsNothing);

      await _press(tester, LogicalKeyboardKey.keyI, alt: true);
      expect(find.byType(InspectorPane), findsOneWidget);
      expect(find.byType(InspectorSplitHandle), findsOneWidget);

      await _press(tester, LogicalKeyboardKey.keyI, alt: true);
      expect(find.byType(InspectorPane), findsNothing);
      // The pane's poll stops a frame behind the pane.
      await tester.pump(const Duration(milliseconds: 1));
    });
  });

  testWidgets('⌘K opens the deck, esc closes it', (tester) async {
    await onPlatform(TargetPlatform.macOS, () async {
      await _pumpShell(tester, overrides: await _world());

      expect(find.byType(CommandDeck), findsNothing);

      await _press(tester, LogicalKeyboardKey.keyK, meta: true);
      expect(find.byType(CommandDeck), findsOneWidget);
      // The deck offers its own connections by name, so a connection is
      // reachable without knowing where it lives. One Radarr is just Radarr:
      // the `4K` it kept from a sibling since removed is not printed.
      expect(
        find.descendant(
          of: find.byType(CommandDeck),
          matching: find.text('Radarr'),
        ),
        findsOneWidget,
      );
      expect(find.text('Radarr\u00A0· 4K'), findsNothing);
      final radarr = find.bySemanticsLabel('Radarr, four-k.lan');
      expect(radarr, findsOneWidget);
      final semantics = tester.getSemantics(radarr).getSemanticsData();
      expect(semantics.flagsCollection.isButton, isTrue);
      expect(semantics.hasAction(SemanticsAction.tap), isTrue);

      await _press(tester, LogicalKeyboardKey.escape);
      expect(find.byType(CommandDeck), findsNothing);
    });
  });

  testWidgets('a click on the way to anything opens the deck', (tester) async {
    await onPlatform(TargetPlatform.macOS, () async {
      await _pumpShell(tester, overrides: await _world());

      await tester.tap(find.text('Jump to…'));
      await tester.pumpAndSettle();
      expect(find.byType(CommandDeck), findsOneWidget);
    });
  });

  testWidgets('a word the deck cannot open runs the global search', (
    tester,
  ) async {
    await onPlatform(TargetPlatform.macOS, () async {
      await _pumpShell(tester, overrides: await _world());
      await _press(tester, LogicalKeyboardKey.keyK, meta: true);
      await tester.enterText(
        find.descendant(
          of: find.byType(CommandDeck),
          matching: find.byType(EditableText),
        ),
        'Nosferatu',
      );
      await tester.pump();
      await _press(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(Scaffold).first),
      );
      expect(container.read(globalSearchQueryProvider), 'Nosferatu');
      expect(find.byType(CommandDeck), findsNothing);
    });
  });

  testWidgets('the deck panel keeps the field\'s width with no results', (
    tester,
  ) async {
    // Its columns centred their children, so the footer and its hairline drew
    // as a strip narrower than the panel, and an empty result shrank the whole
    // panel to the footer's width.
    await onPlatform(TargetPlatform.macOS, () async {
      await _pumpShell(tester, overrides: await _world());
      await _press(tester, LogicalKeyboardKey.keyK, meta: true);

      await tester.enterText(
        find.descendant(
          of: find.byType(CommandDeck),
          matching: find.byType(EditableText),
        ),
        'zzzz nothing',
      );
      await tester.pump();
      // A word that names nothing is offered to the global search (F-deck).
      expect(find.text('Search everything for “zzzz nothing”'), findsOneWidget);

      final deck = tester.getRect(find.byType(CommandDeck));
      final footer = tester.getRect(
        find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_DeckFooter',
        ),
      );
      // The panel hangs 16 in from each side of the deck, inside a 1px border.
      expect(footer.width, closeTo(deck.width - 2 * 16 - 2, 1));
    });
  });

  group("Activity's strip says who of its sources answered", () {
    DashboardDecisions decisions(SourceCoverage coverage) =>
        (decisions: const <DashboardDecision>[], coverage: coverage);
    const radarr = CoverageSource(ServiceKey.radarr, instanceId: 'radarr');
    const sonarr = CoverageSource(ServiceKey.sonarr, instanceId: 'sonarr');

    testWidgets('all of them, and when; a click asks them again', (
      tester,
    ) async {
      await onPlatform(TargetPlatform.macOS, () async {
        await _pumpShell(
          tester,
          initialLocation: '/activity',
          overrides: [
            ...await _world(),
            dashboardDecisionsProvider.overrideWithValue(
              decisions(SourceCoverage(answered: {radarr, sonarr})),
            ),
            stallClockProvider.overrideWithValue(
              () => DateTime(2026, 10, 9, 20, 53),
            ),
          ],
        );

        final line = find.text('All 2 answered at 20:53');
        expect(line, findsOneWidget);
        final container = ProviderScope.containerOf(
          tester.element(find.byType(ShellScreen)),
        );
        final before = container.read(
          navigationRefreshProvider(NavigationSection.activity),
        );
        await tester.tap(line);
        await tester.pumpAndSettle();
        expect(
          container.read(navigationRefreshProvider(NavigationSection.activity)),
          before + 1,
        );
      });
    });

    testWidgets('one that did not answer: how many did, in red', (
      tester,
    ) async {
      await onPlatform(TargetPlatform.macOS, () async {
        await _pumpShell(
          tester,
          initialLocation: '/activity',
          overrides: [
            ...await _world(),
            dashboardDecisionsProvider.overrideWithValue(
              decisions(
                SourceCoverage(
                  answered: {radarr},
                  failed: {sonarr: ServiceFailureReason.unreachable},
                ),
              ),
            ),
          ],
        );

        expect(find.text('1 of 2 answered'), findsOneWidget);
        expect(
          find.byTooltip(RegExp('^Sonarr did not answer')),
          findsOneWidget,
        );
      });
    });

    testWidgets('elsewhere the strip has no answer line', (tester) async {
      await onPlatform(TargetPlatform.macOS, () async {
        await _pumpShell(
          tester,
          overrides: [
            ...await _world(),
            dashboardDecisionsProvider.overrideWithValue(
              decisions(SourceCoverage(answered: {radarr, sonarr})),
            ),
          ],
        );
        expect(find.textContaining('answered'), findsNothing);
      });
    });
  });

  group('the chrome names a connection only when there are two', () {
    testWidgets('one Radarr: no label, whatever it kept from a sibling', (
      tester,
    ) async {
      await onPlatform(TargetPlatform.macOS, () async {
        await _pumpShell(
          tester,
          initialLocation: '/stack/radarr/library/item/42',
          overrides: await _world(),
        );
        expect(find.text('4K'), findsNothing);
        expect(find.textContaining('Lens: '), findsNothing);
      });
    });

    testWidgets('two Radarr, the lens unnamed: called by its place', (
      tester,
    ) async {
      await onPlatform(TargetPlatform.macOS, () async {
        await _pumpShell(
          tester,
          initialLocation: '/stack/radarr/library/item/42',
          overrides: await _world(instances: _twoRadarr),
        );
        expect(find.textContaining('Lens: Radarr 1'), findsOneWidget);
      });
    });
  });

  testWidgets('a page opened with ?i= names the connection it reads, not '
      'the lens', (tester) async {
    await onPlatform(TargetPlatform.macOS, () async {
      // The lens rests on the first Radarr; the movie is the 4K's.
      await _pumpShell(
        tester,
        initialLocation: '/stack/radarr/library/item/42?i=radarr-4k00001',
        overrides: await _world(instances: _twoRadarr),
      );
      expect(find.textContaining('Lens: 4K'), findsOneWidget);
      expect(find.textContaining('Radarr 1'), findsNothing);
    });
  });

  testWidgets('a window between 720 and 839 keeps the Portal demo owed', (
    tester,
  ) async {
    // Narrower than the rail and still the window shell: there is no bar to
    // lift here, so the one-shot demo must not be spent here either. It used
    // to be, on the timer, and never came back.
    await onPlatform(TargetPlatform.macOS, () async {
      await _pumpShell(
        tester,
        viewport: const Size(760, 900),
        overrides: await _world(),
      );
      expect(find.byType(FloatingBottomNavBar), findsNothing);

      // Well past the demo's breath after the first frame.
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellScreen)),
      );
      expect(container.read(portalHintsProvider).demoBouncePending, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('portal_hint_demo_shown'), isNot(isTrue));
    });
  });

  testWidgets('⌘2 crosses to another section', (tester) async {
    await onPlatform(TargetPlatform.macOS, () async {
      final harness = await _pumpShell(tester, overrides: await _world());

      await _press(tester, LogicalKeyboardKey.digit2, meta: true);

      // Discover is the second tab.
      expect(
        harness.routerDelegate.currentConfiguration.uri.path,
        NavTab.discover.routePath,
      );
    });
  });

  testWidgets('⌘1 to ⌘4 follow the operator\'s bar, in its order', (
    tester,
  ) async {
    await onPlatform(TargetPlatform.macOS, () async {
      final harness = await _pumpShell(tester, overrides: await _world());
      final bar = NavTab.barFor(Audience.operator);

      // Backwards, so every key crosses to a section the window is not on.
      for (final (index, key) in [
        LogicalKeyboardKey.digit4,
        LogicalKeyboardKey.digit3,
        LogicalKeyboardKey.digit2,
        LogicalKeyboardKey.digit1,
      ].indexed) {
        await _press(tester, key, meta: true);

        expect(
          harness.routerDelegate.currentConfiguration.uri.path,
          bar[bar.length - 1 - index].routePath,
          reason: '⌘${4 - index}',
        );
      }
      // Home, Discover, Activity, Stack: not the order of the branches under
      // them, which also hold Requests and Settings.
      expect(bar.map((tab) => tab.label), [
        'Home',
        'Discover',
        'Activity',
        'Stack',
      ]);
    });
  });

  testWidgets('⌘, opens Settings, which the bar has no number for', (
    tester,
  ) async {
    await onPlatform(TargetPlatform.macOS, () async {
      final harness = await _pumpShell(tester, overrides: await _world());

      await _press(tester, LogicalKeyboardKey.comma, meta: true);

      expect(
        harness.routerDelegate.currentConfiguration.uri.path,
        NavTab.settings.routePath,
      );
    });
  });

  testWidgets('the rail ends in Settings, lit while it is on screen', (
    tester,
  ) async {
    await onPlatform(TargetPlatform.macOS, () async {
      final harness = await _pumpShell(tester, overrides: await _world());

      // The sidebar's row for [label], found by the name it prints.
      Finder railButton(String label) => find.descendant(
        of: find.byType(DesktopNavRail),
        matching: find.text(label),
      );
      bool lit(String label) =>
          tester
              .widget<Semantics>(
                find
                    .ancestor(
                      of: railButton(label),
                      matching: find.byType(Semantics),
                    )
                    .first,
              )
              .properties
              .selected ??
          false;

      // Its key is in its hint, and printed only under the pointer.
      expect(
        find.descendant(
          of: find.byType(DesktopNavRail),
          matching: find.bySemanticsLabel('Settings'),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Semantics>(
              find
                  .ancestor(
                    of: railButton('Settings'),
                    matching: find.byType(Semantics),
                  )
                  .first,
            )
            .properties
            .hint,
        ShellShortcuts.settings,
      );
      expect(lit('Settings'), isFalse);
      expect(lit('Home'), isTrue, reason: 'the window opens on the Home');

      await tester.tap(railButton('Settings'));
      await tester.pumpAndSettle();

      expect(
        harness.routerDelegate.currentConfiguration.uri.path,
        NavTab.settings.routePath,
      );
      expect(lit('Settings'), isTrue);
      // And no section of the bar is lit beside it.
      for (final tab in NavTab.barFor(Audience.operator)) {
        expect(lit(tab.label), isFalse, reason: tab.label);
      }
    });
  });
}

/// Runs [body] as if the app were on [platform], and always puts the override
/// back.
///
/// Inside the body rather than in `tearDown`: the test binding verifies that no
/// foundation debug variable is still set when the body returns, which is
/// earlier than any tear-down runs.
Future<void> onPlatform(
  TargetPlatform platform,
  Future<void> Function() body,
) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

const _instances = [
  ServiceInstance(
    id: 'radarr',
    service: ServiceKey.radarr,
    label: '4K',
    url: 'https://four-k.lan:7878',
    credential: 'k',
  ),
];

/// Two Radarr, the first one nobody named.
const _twoRadarr = [
  ServiceInstance(
    id: 'radarr',
    service: ServiceKey.radarr,
    url: 'https://hd.lan:7878',
    credential: 'k',
  ),
  ServiceInstance(
    id: 'radarr-4k00001',
    service: ServiceKey.radarr,
    label: '4K',
    url: 'https://four-k.lan:7878',
    credential: 'k',
  ),
];

/// One configured connection, already answered, so nothing reaches a socket.
Future<List<Override>> _world({
  List<ServiceInstance> instances = _instances,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return [
    sharedPreferencesProvider.overrideWithValue(prefs),
    secureSettingsStoreProvider.overrideWithValue(FakeSecureSettingsStore()),
    initialSettingsProvider.overrideWithValue(
      SettingsModel(instances: instances),
    ),
    for (final instance in instances)
      instanceSummaryProvider((
        service: instance.service,
        instanceId: instance.id,
      )).overrideWith(
        (ref) async => ServiceSummary(
          service: instance.service,
          status: ServiceSummaryStatus.online,
          host: 'four-k.lan',
          version: '5.0',
        ),
      ),
  ];
}

Future<void> _press(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool meta = false,
  bool alt = false,
}) async {
  if (meta) await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  if (alt) await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  await tester.sendKeyEvent(key);
  if (alt) await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  if (meta) await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await tester.pumpAndSettle();
}

class _Harness {
  const _Harness(this.routerDelegate);

  final GoRouterDelegate routerDelegate;
}

Future<_Harness> _pumpShell(
  WidgetTester tester, {
  String initialLocation = '/home',
  Size viewport = const Size(1440, 900),
  List<Override> overrides = const [],
}) async {
  final container = ProviderContainer(
    overrides: [
      // The shell reads who it is drawn for, which waits on onboarding.
      initialOnboardingCompletedProvider.overrideWithValue(true),
      // The sidebar's "In flight" thirty-second poll: a test about the shell
      // ends before the container that holds its timer is disposed.
      sidebarInFlightPollProvider.overrideWith((ref) {}),
      ...overrides,
    ],
  );
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
              GoRoute(path: '/home', builder: (_, _) => const Placeholder()),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: branchNavigatorKeyFor(NavTab.discover),
            routes: [
              GoRoute(
                path: '/discover',
                builder: (_, _) => const Placeholder(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: branchNavigatorKeyFor(NavTab.activity),
            routes: [
              GoRoute(
                path: '/activity',
                builder: (_, _) => const Placeholder(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: branchNavigatorKeyFor(NavTab.stack),
            routes: [
              GoRoute(
                path: '/stack',
                builder: (_, _) => const Placeholder(),
                routes: [
                  GoRoute(
                    path: ':service',
                    builder: (_, _) => const Placeholder(),
                    routes: [
                      GoRoute(
                        path: ':tab',
                        builder: (_, _) => const Placeholder(),
                        routes: [
                          GoRoute(
                            path: 'item/:id',
                            builder: (_, _) => const Placeholder(),
                          ),
                        ],
                      ),
                    ],
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
                builder: (_, _) => const Placeholder(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: branchNavigatorKeyFor(NavTab.settings),
            routes: [
              GoRoute(
                path: '/settings',
                builder: (_, _) => const Placeholder(),
              ),
            ],
          ),
        ],
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

  return _Harness(router.routerDelegate);
}
