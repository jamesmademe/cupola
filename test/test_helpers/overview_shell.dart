/// A service's own tab shell around the Overview under test, so a test can
/// tell where a row's door went without the app's whole router.
///
/// The shape is the production one for what a door does: the service's tabs
/// are the branches of a `StatefulShellRoute`, in `tabsFor` order, the first
/// of them (Overview) drawing the screen under test; a tab switch is
/// `goBranch`, so [OverviewShell.branch] is the tab the user is on. A page a
/// door pushes (a download's, a stack's) is a plain route at the root that
/// draws its own location, since the test asks where it went and not what it
/// holds.
///
/// ```dart
/// final shell = OverviewShell(ServiceKey.prowlarr, const ProwlarrOverviewScreen());
/// await tester.pumpWidget(ProviderScope(overrides: [...], child: shell.app));
/// await tester.tap(find.text('3 indexers failing'));
/// expect(shell.tab, ServiceTab.indexers);
/// ```
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Locations a door may push, which the host answers with a page that says
/// where it is.
const _pushable = [
  ServiceRoutes.activityDownloadPath,
  '${ServiceRoutes.dockge}/stacks/stack/:name',
  '${ServiceRoutes.prowlarr}/indexers/indexer/:id',
];

/// The routed host of an Overview.
class OverviewShell {
  OverviewShell(this.service, Widget overview) {
    final tabs = tabsFor(service)!;
    router = GoRouter(
      initialLocation: '${ServiceRoutes.stack}/${service.routeParam}/overview',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) {
            _shell = shell;
            return shell;
          },
          branches: [
            for (final tab in tabs)
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path:
                        '${ServiceRoutes.stack}/${service.routeParam}/'
                        '${tab.segment}',
                    builder: (_, _) => tab == ServiceTab.overview
                        ? overview
                        : Scaffold(
                            body: Center(child: Text('tab ${tab.label}')),
                          ),
                  ),
                ],
              ),
          ],
        ),
        for (final path in _pushable)
          GoRoute(
            path: path,
            builder: (_, state) =>
                Scaffold(body: Center(child: Text('page ${state.uri}'))),
          ),
      ],
    );
    app = MaterialApp.router(
      theme: AppTheme.darkTheme(),
      themeAnimationDuration: Duration.zero,
      routerConfig: router,
    );
  }

  final ServiceKey service;
  late final GoRouter router;

  /// The app to pump, inside the test's own `ProviderScope`.
  late final Widget app;

  StatefulNavigationShell? _shell;

  /// The tab the shell is showing.
  ServiceTab get tab => tabsFor(service)![_shell!.currentIndex];

  /// The location of the page on top: where a pushed page went.
  String get location => router.state.uri.toString();
}
