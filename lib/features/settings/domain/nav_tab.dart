import 'package:flutter/material.dart' show IconData, Icons;
import 'package:material_symbols_icons/symbols.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/utils/service_routes.dart';

/// The app's top-level places: one branch navigator each, and the tabs a
/// person's bar shows ([barFor]).
///
/// Six branches, always: go_router fixes them when the router is built, so the
/// operator's four and the requester's three are subsets of one list rather
/// than two routers. Settings is a branch with no place in the phone's bar: it
/// opens from Stack's gear, from the requester's account button, from ⌘, and
/// from the foot of the desktop rail, and it keeps its own stack like any tab.
///
/// **No colour of their own.** The chrome is monochrome (Principle 3 of the brand book:
/// colour is information): the selected tab is the room's strong fill under the
/// primary ink in every section, on the phone's bar, the desktop rail and the
/// settings list alike. The four section accents that used to tint the pill
/// (`color.nav.*` in `design/tokens/core.json`) are retired from the interface;
/// the tokens stay until the palette cleanup, and nothing in `lib/` may read
/// them (`test/core/theme/monochrome_accent_test.dart`).
enum NavTab {
  /// The first tab: what is new, what is coming, what needs you.
  home(
    label: 'Home',
    icon: Icons.home_outlined,
    selectedIcon: Icons.home_rounded,
    railIcon: Symbols.home_rounded,
    routePath: ServiceRoutes.home,
  ),

  /// The catalogue: browsed at rest, searched by typing (it took the Search
  /// tab's place, and its search with it).
  discover(
    label: 'Discover',
    icon: Icons.explore_outlined,
    selectedIcon: Icons.explore_rounded,
    railIcon: Symbols.explore_rounded,
    routePath: ServiceRoutes.discover,
  ),
  activity(
    label: 'Activity',
    icon: Icons.monitor_heart_outlined,
    selectedIcon: Icons.monitor_heart_rounded,
    railIcon: Symbols.monitor_heart_rounded,
    routePath: '/activity',
  ),

  /// Every service, and the way into each one's room: the operator's.
  stack(
    label: 'Stack',
    icon: Icons.layers_outlined,
    selectedIcon: Icons.layers_rounded,
    railIcon: Symbols.layers_rounded,
    routePath: ServiceRoutes.stack,
  ),

  /// The requester's own requests: what she asked for and where each stands.
  requests(
    label: 'Requests',
    icon: Icons.inbox_outlined,
    selectedIcon: Icons.inbox_rounded,
    railIcon: Symbols.inbox_rounded,
    routePath: ServiceRoutes.requests,
  ),
  settings(
    label: 'Settings',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings_rounded,
    railIcon: Symbols.settings_rounded,
    routePath: '/settings',
  );

  const NavTab({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.railIcon,
    required this.routePath,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;

  /// The desktop rail's glyph: Material Symbols, drawn at a light weight.
  ///
  /// Material Icons has one stroke weight, and on a 56pt rail beside a window
  /// of dense chrome it read heavier than anything else in the shell. Symbols
  /// carries a `wght` axis, so the rail can draw the same glyph at 300. The
  /// phone's bar keeps [icon] and [selectedIcon], which already sit right at
  /// its size.
  final IconData railIcon;
  final String routePath;

  /// The tabs [audience]'s bar shows, in order.
  ///
  /// The operator's is the control room's: Home · Discover · Activity · Stack.
  /// The requester's has no control room in it: Home · Discover · Requests.
  /// Settings is in neither (see [NavTab]).
  static List<NavTab> barFor(Audience audience) => switch (audience) {
    Audience.operator => const [home, discover, activity, stack],
    Audience.requester => const [home, discover, requests],
  };
}
