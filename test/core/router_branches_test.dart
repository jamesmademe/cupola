import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/router.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/features/import/presentation/manual_import_routes.dart';
import 'package:cupola/features/settings/domain/nav_tab.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/shell/presentation/shell_screen.dart';

import '../test_helpers/settings_scope.dart';

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
  }) async {
    // `settingsScopeOverrides` already marks onboarding complete, which is what
    // keeps the router off the onboarding gate.
    final container = ProviderContainer(
      overrides: await settingsScopeOverrides(configured: configured),
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
  });
}
