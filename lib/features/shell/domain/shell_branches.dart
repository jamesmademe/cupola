import 'package:flutter/widgets.dart';

import 'package:cupola/features/settings/domain/nav_tab.dart';

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
/// branch order in the router is not cosmetic — the router asserts it.
final List<GlobalKey<NavigatorState>> shellBranchNavigatorKeys =
    List<GlobalKey<NavigatorState>>.unmodifiable([
      for (final tab in NavTab.values)
        GlobalKey<NavigatorState>(debugLabel: 'branch-${tab.name}'),
    ]);

/// The key for a branch's navigator, by tab.
GlobalKey<NavigatorState> branchNavigatorKeyFor(NavTab tab) =>
    shellBranchNavigatorKeys[tab.index];
