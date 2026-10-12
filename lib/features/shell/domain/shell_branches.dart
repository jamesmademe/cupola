import 'package:flutter/widgets.dart';

import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/settings/domain/nav_tab.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// One [Navigator] per tab, keyed here rather than in either of the two files
/// that need them.
///
/// The shell has to inspect a branch's stack to answer "am I deep in this tab?",
/// and the router has to hand each branch its key. Keeping the keys in the domain
/// layer means the shell does not import the router and the router does not
/// import the shell.
///
/// Indexed by [NavTab.index]: the shell maps a bar tap and
/// `StatefulNavigationShell.currentIndex` straight onto `NavTab.values`, so the
/// branch order in the router is not cosmetic: the router asserts it.
final List<GlobalKey<NavigatorState>> shellBranchNavigatorKeys =
    List<GlobalKey<NavigatorState>>.unmodifiable([
      for (final tab in NavTab.values)
        GlobalKey<NavigatorState>(debugLabel: 'branch-${tab.name}'),
    ]);

/// The key for a branch's navigator, by tab.
GlobalKey<NavigatorState> branchNavigatorKeyFor(NavTab tab) =>
    shellBranchNavigatorKeys[tab.index];

/// One [Navigator] per *service tab*, for the shells nested inside the
/// Dashboard branch.
///
/// Built once at class load from the same table the bar and the router read, so
/// a key can only exist for a tab that exists: there is no way to hand a
/// branch a key for a view that is not on its service's bar.
///
/// Distinct objects from [shellBranchNavigatorKeys] and from each other, which
/// is not defensive: a service's shell is nested *inside* the Dashboard branch,
/// so both families are mounted at the same time and a shared key would be a
/// duplicate [GlobalKey] in one tree.
final Map<ServiceKey, Map<ServiceTab, GlobalKey<NavigatorState>>>
_serviceBranchNavigatorKeys =
    Map<ServiceKey, Map<ServiceTab, GlobalKey<NavigatorState>>>.unmodifiable({
      for (final entry in serviceTabs.entries)
        entry.key: Map<ServiceTab, GlobalKey<NavigatorState>>.unmodifiable({
          for (final tab in entry.value)
            tab: GlobalKey<NavigatorState>(
              debugLabel: 'branch-${entry.key.name}-${tab.name}',
            ),
        }),
    });

/// The key for one service tab's navigator.
///
/// Throws for a tab the service does not have, deliberately: the caller builds
/// its branches from [tabsFor], so asking for another one means the two have
/// already drifted and a null key would hide it until the first tap.
GlobalKey<NavigatorState> serviceBranchNavigatorKeyFor(
  ServiceKey service,
  ServiceTab tab,
) => _serviceBranchNavigatorKeys[service]![tab]!;

/// The page on top of each tab's stack, watched for the shell: a tab tapped
/// again at its root scrolls that page back to its top (`ShellScreen`).
///
/// Indexed by [NavTab.index], like [shellBranchNavigatorKeys], and handed to
/// each branch with its key.
final List<BranchTopRoute> shellBranchTopRoutes =
    List<BranchTopRoute>.unmodifiable([
      for (final _ in NavTab.values) BranchTopRoute(),
    ]);

/// The watcher of a branch's top page, by tab.
BranchTopRoute branchTopRouteFor(NavTab tab) => shellBranchTopRoutes[tab.index];

/// Follows the page on top of one navigator.
class BranchTopRoute extends NavigatorObserver {
  Route<dynamic>? _top;

  /// The page on top, null before the branch has built one.
  Route<dynamic>? get top => _top;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _top = route;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route == _top) _top = previousRoute;
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route == _top) _top = previousRoute;
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute == _top) _top = newRoute;
  }
}
