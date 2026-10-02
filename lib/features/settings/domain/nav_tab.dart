import 'package:flutter/material.dart' show IconData, Icons;
import 'package:material_symbols_icons/symbols.dart';

import 'package:cupola/core/utils/service_routes.dart';

/// The four canonical tabs.
///
/// **No colour of their own.** The chrome is monochrome (Principle 3 of the brand book:
/// colour is information): the selected tab is the room's strong fill under the
/// primary ink in every section, on the phone's bar, the desktop rail and the
/// settings list alike. The four section accents that used to tint the pill
/// (`color.nav.*` in `design/tokens/core.json`) are retired from the interface;
/// the tokens stay until the palette cleanup, and nothing in `lib/` may read
/// them (`test/core/theme/monochrome_accent_test.dart`).
enum NavTab {
  /// The app home.
  dashboard(
    label: 'Dashboard',
    icon: Icons.view_list_outlined,
    selectedIcon: Icons.view_list_rounded,
    railIcon: Symbols.view_list_rounded,
    routePath: ServiceRoutes.dashboard,
  ),
  activity(
    label: 'Activity',
    icon: Icons.monitor_heart_outlined,
    selectedIcon: Icons.monitor_heart_rounded,
    railIcon: Symbols.monitor_heart_rounded,
    routePath: '/activity',
  ),
  search(
    label: 'Search',
    icon: Icons.search_outlined,
    selectedIcon: Icons.search_rounded,
    railIcon: Symbols.search_rounded,
    routePath: '/search',
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
}
