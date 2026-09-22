import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/nav_tab.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/shell/domain/shell_branches.dart';
import 'package:cupola/features/shell/presentation/branch_transition.dart';
import 'package:cupola/features/shell/presentation/desktop/command_deck.dart';
import 'package:cupola/features/shell/presentation/desktop/desktop_nav_rail.dart';
import 'package:cupola/features/shell/presentation/desktop/inspector_pane.dart';
import 'package:cupola/features/shell/presentation/desktop/service_deck.dart';
import 'package:cupola/features/shell/presentation/desktop/shell_freshness.dart';
import 'package:cupola/features/shell/presentation/desktop/window_chrome.dart';
import 'package:cupola/features/shell/presentation/shell_screen.dart';

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

  testWidgets('a desktop window gets chrome, rail and deck — no status bar', (
    tester,
  ) async {
    await onPlatform(TargetPlatform.macOS, () async {
      await _pumpShell(tester, overrides: await _world());

      expect(find.byType(WindowChrome), findsOneWidget);
      expect(find.byType(DesktopNavRail), findsOneWidget);
      expect(find.byType(ServiceDeck), findsOneWidget);
      // The foot of the window is the page's: the status bar's one fact of its
      // own, the sample's age, lives in the deck.
      expect(find.byType(ShellFreshness), findsOneWidget);
      expect(
        tester.getBottomLeft(find.byType(Placeholder).first).dy,
        900,
        reason: 'the content reaches the bottom edge of the window',
      );

      // And none of the touch navigation, at the same size.
      expect(find.byType(FloatingBottomNavBar), findsNothing);
      expect(find.byType(NavigationRail), findsNothing);
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
        expect(find.bySemanticsLabel('Jump to anything, ⌘K'), findsNWidgets(2));
        // The deck speaks the stack as one sentence, the one the Dashboard
        // header prints, rather than seventeen glyphs one by one.
        expect(
          find.bySemanticsLabel(RegExp(r'^1 of 1 answering')),
          findsOneWidget,
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

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(WindowChrome), findsNothing);
      expect(find.byType(ServiceDeck), findsNothing);
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
      expect(find.byType(ServiceDeck), findsNothing);
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
        initialLocation: '/dashboard/radarr',
        overrides: await _world(),
      );

      final chrome = find.byType(WindowChrome);
      expect(
        // The breadcrumb IS the URL, and the root crumb is the tab's label.
        find.descendant(of: chrome, matching: find.text('Dashboard')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: chrome, matching: find.text('Radarr')),
        findsOneWidget,
      );
    });
  });

  testWidgets('the full window shows the aggregate, not seventeen glyphs', (
    tester,
  ) async {
    // The Room Light Rule: one health figure in the deck, the services on ⌘K.
    await onPlatform(TargetPlatform.macOS, () async {
      await _pumpShell(tester, overrides: await _world());

      final deck = tester.widget<ServiceDeck>(find.byType(ServiceDeck));
      expect(deck.compact, isFalse);
      expect(
        find.descendant(
          of: find.byType(ServiceDeck),
          matching: find.textContaining('/ 1'),
        ),
        findsOneWidget,
      );
      expect(find.byTooltip('Radarr · 4K · online'), findsNothing);
    });
  });

  testWidgets('the compact window keeps the same aggregate', (tester) async {
    await onPlatform(TargetPlatform.macOS, () async {
      await _pumpShell(
        tester,
        // The compact artboard. Below `AppBreakpoints.desktopCompact` the deck
        // shows fewer things, not smaller ones.
        viewport: const Size(720, 450),
        overrides: await _world(),
      );

      final deck = tester.widget<ServiceDeck>(find.byType(ServiceDeck));
      expect(deck.compact, isTrue);
      // The aggregate the bands added up to, in the deck's own strip.
      expect(
        find.descendant(
          of: find.byType(ServiceDeck),
          matching: find.textContaining('/ 1'),
        ),
        findsOneWidget,
      );
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
    });
  });

  testWidgets('⌘K opens the deck, esc closes it', (tester) async {
    await onPlatform(TargetPlatform.macOS, () async {
      await _pumpShell(tester, overrides: await _world());

      expect(find.byType(CommandDeck), findsNothing);

      await _press(tester, LogicalKeyboardKey.keyK, meta: true);
      expect(find.byType(CommandDeck), findsOneWidget);
      // The deck offers its own connections by name, so a service with a labelled
      // connection is reachable without knowing where it lives.
      expect(find.text('Radarr · 4K'), findsOneWidget);
      final radarr = find.bySemanticsLabel('Radarr · 4K, four-k.lan');
      expect(radarr, findsOneWidget);
      final semantics = tester.getSemantics(radarr).getSemanticsData();
      expect(semantics.flagsCollection.isButton, isTrue);
      expect(semantics.hasAction(SemanticsAction.tap), isTrue);

      await _press(tester, LogicalKeyboardKey.escape);
      expect(find.byType(CommandDeck), findsNothing);
    });
  });

  testWidgets('⌘R dates the sample in the deck', (tester) async {
    await onPlatform(TargetPlatform.macOS, () async {
      await _pumpShell(tester, overrides: await _world());
      expect(find.textContaining('Refreshed'), findsNothing);

      await _press(tester, LogicalKeyboardKey.keyR, meta: true);

      expect(find.text('Refreshed just now'), findsOneWidget);
    });
  });

  group('the deck names the room only when the page does not', () {
    testWidgets('a service tab root: the tab row names it, the deck does not', (
      tester,
    ) async {
      await onPlatform(TargetPlatform.macOS, () async {
        final semantics = tester.ensureSemantics();
        try {
          await _pumpShell(
            tester,
            initialLocation: '/dashboard/radarr/library',
            overrides: await _world(),
          );
          expect(find.bySemanticsLabel('Viewing Radarr, 4K'), findsNothing);
        } finally {
          semantics.dispose();
        }
      });
    });

    testWidgets('a pushed page has no tab row, so the deck keeps the chip', (
      tester,
    ) async {
      await onPlatform(TargetPlatform.macOS, () async {
        final semantics = tester.ensureSemantics();
        try {
          await _pumpShell(
            tester,
            initialLocation: '/dashboard/radarr/library/item/42',
            overrides: await _world(),
          );
          expect(find.bySemanticsLabel('Viewing Radarr, 4K'), findsOneWidget);
        } finally {
          semantics.dispose();
        }
      });
    });

    testWidgets('TrueNAS keeps its band, so the deck keeps the chip', (
      tester,
    ) async {
      await onPlatform(TargetPlatform.macOS, () async {
        final semantics = tester.ensureSemantics();
        try {
          await _pumpShell(
            tester,
            initialLocation: '/dashboard/truenas',
            overrides: await _world(),
          );
          expect(find.bySemanticsLabel('Viewing TrueNAS'), findsOneWidget);
        } finally {
          semantics.dispose();
        }
      });
    });
  });

  testWidgets('⌘2 crosses to another section', (tester) async {
    await onPlatform(TargetPlatform.macOS, () async {
      final harness = await _pumpShell(tester, overrides: await _world());

      await _press(tester, LogicalKeyboardKey.digit2, meta: true);

      expect(
        harness.routerDelegate.currentConfiguration.uri.path,
        NavTab.activity.routePath,
      );
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

/// One configured connection, already answered, so nothing reaches a socket.
Future<List<Override>> _world() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return [
    sharedPreferencesProvider.overrideWithValue(prefs),
    secureSettingsStoreProvider.overrideWithValue(FakeSecureSettingsStore()),
    initialSettingsProvider.overrideWithValue(
      const SettingsModel(instances: _instances),
    ),
    for (final instance in _instances)
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
  String initialLocation = '/dashboard',
  Size viewport = const Size(1440, 900),
  List<Override> overrides = const [],
}) async {
  final container = ProviderContainer(overrides: overrides);
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      StatefulShellRoute(
        navigatorContainerBuilder: buildBranchTransition,
        builder: (context, state, navigationShell) =>
            ShellScreen(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            navigatorKey: branchNavigatorKeyFor(NavTab.dashboard),
            routes: [
              GoRoute(
                path: '/dashboard',
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
            navigatorKey: branchNavigatorKeyFor(NavTab.activity),
            routes: [
              GoRoute(
                path: '/activity',
                builder: (_, _) => const Placeholder(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: branchNavigatorKeyFor(NavTab.search),
            routes: [
              GoRoute(path: '/search', builder: (_, _) => const Placeholder()),
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
