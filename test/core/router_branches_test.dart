import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/router.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/features/activity/domain/service_type.dart';
import 'package:cupola/features/activity/presentation/activity_screen.dart';
import 'package:cupola/features/import/presentation/manual_import_routes.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/settings/domain/nav_tab.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/shell/presentation/shell_screen.dart';

import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../test_helpers/settings_scope.dart';

const _secondSeerr = ServiceInstance(
  id: 'seerr-2222222',
  service: ServiceKey.seerr,
  label: 'Anime',
  url: 'https://second.lan:5055',
  credential: 'key-2',
);

/// The shape of the shell, asserted against the real router.
///
/// `router_test.dart` covers what each path resolves to. This file covers the
/// structure that migration put in place and that nothing in a path assertion
/// would notice going wrong: which branches exist and in what order, what was
/// deliberately left outside them, and the invariants those choices rest on.
void main() {
  Future<GoRouter> pumpRouter(
    WidgetTester tester, {
    String? at,
    List<ServiceKey> configured = const [],
    SettingsModel Function(SettingsModel settings)? customize,
  }) async {
    // `settingsScopeOverrides` already marks onboarding complete, which is what
    // keeps the router off the onboarding gate.
    final container = ProviderContainer(
      overrides: await settingsScopeOverrides(
        configured: configured,
        customize: customize,
      ),
    );
    addTearDown(container.dispose);

    // A phone, not the 800x600 default: several destinations here are real
    // screens whose empty states are taller than that, and an overflow is noise
    // in a test about routing.
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = container.read(routerProvider);
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        // Reduce Motion, for the reason `router_test` states: a destination here
        // owns a continuous animation — the service ring sweeps forever by
        // design — so with motion on `pumpAndSettle` waits for a frame that
        // never stops coming. It also skips the branch cross-fade, which these
        // cases are not about.
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
        ),
      ),
    );
    if (at != null) {
      router.go(at);
      await tester.pumpAndSettle();
    } else {
      await tester.pumpAndSettle();
    }
    return router;
  }

  /// The shell route, found on the real configuration.
  StatefulShellRoute shellRouteOf(GoRouter router) =>
      router.configuration.routes.whereType<StatefulShellRoute>().single;

  /// Radarr's own node, walked to from the app shell rather than looked up.
  ///
  /// Walking is the point: reaching it means passing through the Dashboard
  /// branch, so a Radarr mounted anywhere else would not be found at all.
  GoRoute radarrRouteOf(GoRouter router) {
    final dashboard =
        shellRouteOf(router).branches[NavTab.dashboard.index].routes.single
            as GoRoute;
    return dashboard.routes.whereType<GoRoute>().firstWhere(
      (route) => route.path == ServiceKey.radarr.routeParam,
    );
  }

  StatefulShellRoute radarrShellOf(GoRouter router) =>
      radarrRouteOf(router).routes.whereType<StatefulShellRoute>().single;

  group('shell branches', () {
    testWidgets('there is one branch per tab, in NavTab order', (tester) async {
      final router = await pumpRouter(tester);
      final branches = shellRouteOf(router).branches;

      expect(branches, hasLength(NavTab.values.length));
      for (var i = 0; i < NavTab.values.length; i++) {
        final tab = NavTab.values[i];
        final root = branches[i].routes.single as GoRoute;
        expect(
          root.path,
          tab.routePath,
          reason:
              'The shell maps currentIndex onto NavTab.values[index], so branch '
              '$i must be ${tab.name}. Out of order it would select the wrong '
              'tab rather than fail.',
        );
      }
    });

    testWidgets('Radarr has one branch per tab, in tabsFor order', (
      tester,
    ) async {
      final router = await pumpRouter(tester);
      final tabs = tabsFor(ServiceKey.radarr)!;
      final branches = radarrShellOf(router).branches;

      expect(branches, hasLength(tabs.length));
      for (var i = 0; i < tabs.length; i++) {
        final tab = tabs[i];
        expect(
          (branches[i].routes.single as GoRoute).path,
          tab.segment,
          reason:
              'The bar is generated from the same list and taps it by index, '
              'so branch $i must be ${tab.name}. Out of order it would light '
              'one tab and show another rather than fail.',
        );
      }
    });

    testWidgets('the Radarr shell is nested inside the Dashboard branch', (
      tester,
    ) async {
      final router = await pumpRouter(tester);

      expect(
        router.configuration.routes.whereType<StatefulShellRoute>(),
        hasLength(1),
        reason:
            'A second shell beside the app one would replace the page the nav '
            'bar, the Portal and the whole desktop chrome hang off — opening a '
            'service would take the app\'s own navigation away with it.',
      );
      // Found only by walking down through the Dashboard branch, which is the
      // assertion: nothing else in this file could reach it.
      expect(radarrShellOf(router).branches, isNotEmpty);
    });

    testWidgets('the film detail is inside the Library branch', (tester) async {
      final router = await pumpRouter(tester);
      final tabs = tabsFor(ServiceKey.radarr)!;
      final library =
          radarrShellOf(
                router,
              ).branches[tabs.indexOf(ServiceTab.library)].routes.single
              as GoRoute;

      expect(
        library.routes.whereType<GoRoute>().map((route) => route.path),
        contains('movie/:id'),
        reason:
            'Pushed inside the branch, the film survives a switch away from '
            'Radarr and its Hero flies, because list and detail share one '
            'Navigator. Beside the branch it would be neither.',
      );

      // The same spelling still hangs off the service node, and that one is a
      // compatibility tail: it builds nothing and only forwards.
      final tail = radarrRouteOf(
        router,
      ).routes.whereType<GoRoute>().firstWhere((r) => r.path == 'movie/:id');
      expect(tail.builder, isNull);
      expect(tail.pageBuilder, isNull);
      expect(tail.redirect, isNotNull);
    });

    testWidgets('no branch is preloaded', (tester) async {
      final router = await pumpRouter(tester);

      for (final branch in shellRouteOf(router).branches) {
        expect(
          branch.preload,
          isFalse,
          reason:
              'Preloading builds a tab, and everything it fetches, before the '
              'user has asked for it — the opposite of the rule that only the '
              'page on screen may spend anything.',
        );
      }
    });
  });

  group('routes deliberately left outside the shell', () {
    /// Every path a branch can reach, flattened.
    List<String> pathsUnder(RouteBase route, [String prefix = '']) {
      final paths = <String>[];
      if (route is GoRoute) {
        final path = route.path.startsWith('/')
            ? route.path
            : '$prefix/${route.path}';
        paths.add(path);
        for (final child in route.routes) {
          paths.addAll(pathsUnder(child, path));
        }
      } else {
        for (final child in route.routes) {
          paths.addAll(pathsUnder(child, prefix));
        }
      }
      return paths;
    }

    testWidgets('the import flow is above the shell, not inside a branch', (
      tester,
    ) async {
      final router = await pumpRouter(tester);

      final inBranches = shellRouteOf(router).branches
          .expand((branch) => branch.routes.expand(pathsUnder))
          .toList(growable: false);
      final atRoot = router.configuration.routes
          .whereType<GoRoute>()
          .map((route) => route.path)
          .toList(growable: false);

      for (final path in [
        manualImportBrowsePath,
        manualImportReviewPath,
        manualImportProgressPath,
        manualImportFolderPath,
        manualImportMatchPath,
      ]) {
        expect(
          inBranches,
          isNot(contains(path)),
          reason:
              'Inside a branch, $path would be a page on that tab\'s stack: its '
              'flow state and its two-second command poll would survive a switch '
              'away from it.',
        );
        expect(
          atRoot,
          contains(path),
          reason: '$path must sit on the root navigator, above the shell',
        );
      }
    });

    testWidgets('the retired top-level locations are above the shell too', (
      tester,
    ) async {
      final router = await pumpRouter(tester);

      final atRoot = router.configuration.routes
          .whereType<GoRoute>()
          .map((route) => route.path)
          .toList(growable: false);

      // Redirect-only scaffolding: four dead trees inside the services branch
      // would read as part of that tab's subtree.
      expect(
        atRoot,
        containsAll(['/discover', '/movies', '/series', '/music']),
      );
      expect(
        atRoot,
        contains('/activity/:type'),
        reason: 'the drill-down was full-screen before and stays that way',
      );
    });

    testWidgets('pushing the import flow keeps the shell alive beneath it', (
      tester,
    ) async {
      final router = await pumpRouter(tester);
      expect(find.byType(ShellScreen), findsOneWidget);

      // `push`, which is how every entry point reaches this flow: a `go` would
      // replace the shell page in the root navigator and take all four branch
      // stacks with it.
      router.push('$manualImportBrowsePath?service=radarr&targetId=1');
      await tester.pumpAndSettle();

      expect(find.byType(FloatingBottomNavBar), findsNothing);
      expect(
        find.byType(ShellScreen, skipOffstage: false),
        findsOneWidget,
        reason: 'the shell, and every branch stack, is still underneath',
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'the station lays out inside a phone',
      );
    });

    testWidgets('leaving the import flow lands back on a branch', (
      tester,
    ) async {
      final router = await pumpRouter(tester);
      router.push('$manualImportBrowsePath?service=radarr&targetId=1');
      await tester.pumpAndSettle();

      // What the flow's own Done button does.
      router.go(NavTab.activity.routePath);
      await tester.pumpAndSettle();

      expect(router.state.uri.path, NavTab.activity.routePath);
      expect(find.byType(FloatingBottomNavBar), findsOneWidget);

      // Landing on Activity starts its Now poll, which is the correct
      // behaviour and a pending timer at teardown. Switching away closes that
      // gate — proof of the same mechanism, and it leaves the test tidy.
      router.go(NavTab.dashboard.routePath);
      await tester.pumpAndSettle();
    });

    testWidgets('the activity drill-down renders without a nav bar', (
      tester,
    ) async {
      // Radarr configured, because this destination builds a real client:
      // the assertion is about chrome, not about what the screen finds.
      await pumpRouter(
        tester,
        at: '/activity/movies',
        configured: const [ServiceKey.radarr],
      );

      expect(find.byType(FloatingBottomNavBar), findsNothing);
      expect(find.byType(ShellScreen), findsNothing);
    });

    // The requests drill-down is the one destination here that belongs to a
    // *connection*: /activity aggregates every Seerr, so a row that came off
    // the second one has to open the second one's list. The link carries the
    // connection in `?i=` and this asserts the route reads it — a parameter
    // nothing reads was removed from this route once already.
    testWidgets('the requests drill-down carries its connection', (
      tester,
    ) async {
      await pumpRouter(
        tester,
        at: '/activity/discover?i=${_secondSeerr.id}',
        configured: const [ServiceKey.seerr],
        // A real second connection, so the id in the link names something —
        // otherwise the assertion would hold even if the screen took the lens.
        customize: (settings) => settings.copyWithInstance(_secondSeerr),
      );

      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is ActivityScreen &&
              widget.instanceId == _secondSeerr.id &&
              widget.serviceType == ServiceType.discover,
        ),
        findsOneWidget,
      );
    });
  });
}
