import 'package:flutter/material.dart' show Color, IconData, Icons;
import 'package:material_symbols_icons/symbols.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';

/// The four canonical tabs.
///
/// Accents are the app's own indigo throughout. They used to vary per tab —
/// Activity borrowed the Radarr amber while its content is Seerr-indigo, and
/// Settings used `onSurfaceVariantDark`, a dark-mode token that rendered the
/// selected pill as washed-out grey in light mode and read as disabled. The
/// per-service accents belong to service surfaces; the app shell is one colour.
enum NavTab {
  /// The app home.
  dashboard(
    label: 'Dashboard',
    icon: Icons.view_list_outlined,
    selectedIcon: Icons.view_list_rounded,
    railIcon: Symbols.view_list_rounded,
    routePath: ServiceRoutes.dashboard,
    accentColor: AppColors.navDashboard,
  ),
  activity(
    label: 'Activity',
    icon: Icons.monitor_heart_outlined,
    selectedIcon: Icons.monitor_heart_rounded,
    railIcon: Symbols.monitor_heart_rounded,
    routePath: '/activity',
    accentColor: AppColors.navActivity,
  ),
  search(
    label: 'Search',
    icon: Icons.search_outlined,
    selectedIcon: Icons.search_rounded,
    railIcon: Symbols.search_rounded,
    routePath: '/search',
    accentColor: AppColors.navSearch,
  ),
  settings(
    label: 'Settings',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
    railIcon: Symbols.settings_rounded,
    routePath: '/settings',
    accentColor: AppColors.navSettings,
  );

  const NavTab({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.railIcon,
    required this.routePath,
    required this.accentColor,
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
  final Color accentColor;
}
