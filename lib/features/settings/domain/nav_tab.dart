import 'package:flutter/material.dart' show Color, IconData, Icons;

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
    routePath: ServiceRoutes.dashboard,
    accentColor: AppColors.navDashboard,
  ),
  activity(
    label: 'Activity',
    icon: Icons.monitor_heart_outlined,
    selectedIcon: Icons.monitor_heart_rounded,
    routePath: '/activity',
    accentColor: AppColors.navActivity,
  ),
  search(
    label: 'Search',
    icon: Icons.search_outlined,
    selectedIcon: Icons.search_rounded,
    routePath: '/search',
    accentColor: AppColors.navSearch,
  ),
  settings(
    label: 'Settings',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
    routePath: '/settings',
    accentColor: AppColors.navSettings,
  );

  const NavTab({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.routePath,
    required this.accentColor,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String routePath;
  final Color accentColor;
}
