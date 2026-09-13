import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_breakpoints.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/theme.dart';

class TrueNasSection {
  final String title;
  final String subtitle;
  final IconData icon;
  final String route;
  final bool experimental;

  const TrueNasSection({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.route,
    this.experimental = false,
  });
}

const trueNasSections = <TrueNasSection>[
  TrueNasSection(
    title: 'Dashboard',
    subtitle: 'CPU, memory & network',
    icon: Icons.speed_rounded,
    route: ServiceRoutes.truenasDashboard,
  ),
  TrueNasSection(
    title: 'Storage',
    subtitle: 'Pools & topology',
    icon: Icons.dns_rounded,
    route: ServiceRoutes.truenasStorage,
  ),
  TrueNasSection(
    title: 'Datasets',
    subtitle: 'ZFS datasets & snapshots',
    icon: Icons.account_tree_rounded,
    route: ServiceRoutes.truenasDatasets,
  ),
  TrueNasSection(
    title: 'Shares',
    subtitle: 'SMB, NFS & iSCSI',
    icon: Icons.folder_shared_rounded,
    route: ServiceRoutes.truenasShares,
  ),
  TrueNasSection(
    title: 'Data Protection',
    subtitle: 'Snapshots & replication',
    icon: Icons.shield_rounded,
    route: ServiceRoutes.truenasDataProtection,
  ),
  TrueNasSection(
    title: 'Containers',
    subtitle: 'LXC instances',
    icon: Icons.inventory_2_rounded,
    route: ServiceRoutes.truenasContainers,
    experimental: true,
  ),
  TrueNasSection(
    title: 'Virtual Machines',
    subtitle: 'Incus VMs',
    icon: Icons.desktop_windows_rounded,
    route: ServiceRoutes.truenasVms,
  ),
  TrueNasSection(
    title: 'Apps',
    subtitle: 'Installed applications',
    icon: Icons.apps_rounded,
    route: ServiceRoutes.truenasApps,
  ),
  TrueNasSection(
    title: 'Reporting',
    subtitle: 'Historical graphs',
    icon: Icons.insights_rounded,
    route: ServiceRoutes.truenasReporting,
  ),
  TrueNasSection(
    title: 'System',
    subtitle: 'Settings & services',
    icon: Icons.settings_rounded,
    route: ServiceRoutes.truenasSystem,
  ),
];

/// TrueNAS on a desktop window: the sub-app it actually is.
///
/// The archetype furthest from the phone. On a phone TrueNAS is a hub of nine
/// cards and one tap per level, which is right for a phone and hopeless on a
/// 1440pt window — three levels of hierarchy, one at a time, in a room with
/// space for all three.
///
/// So the nine areas become a list that stays put, and the area beside it
/// changes. Below [AppBreakpoints.desktopCompact] the list would eat a third of
/// the window, so it collapses to a scrolling chip row: the same nine doors,
/// one line instead of one column.
///
/// Navigates with `go` and reads the current area off the location, for the same
/// reasons the settings master-detail does: one set of routes, deep links intact,
/// and a window breadcrumb that still knows where it is.
class TrueNasConsoleShell extends StatelessWidget {
  const TrueNasConsoleShell({super.key, required this.child});

  final Widget child;

  static const double listWidth = 232;

  @override
  Widget build(BuildContext context) {
    if (!AppBreakpoints.isDesktopShell) return child;

    final location = GoRouterState.of(context).uri.path;
    final compact =
        MediaQuery.sizeOf(context).width < AppBreakpoints.desktopCompact;

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AreaChips(location: location),
          Expanded(child: child),
        ],
      );
    }

    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: listWidth,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.55),
                ),
              ),
            ),
            child: ListView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.md,
              ),
              children: [
                for (final section in trueNasSections)
                  _AreaRow(
                    section: section,
                    selected: _isSelected(section, location),
                  ),
              ],
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }

  /// Longest route match, so a pool detail still lights Storage.
  static bool _isSelected(TrueNasSection section, String location) {
    final best = trueNasSections
        .where((s) => location == s.route || location.startsWith('${s.route}/'))
        .fold<TrueNasSection?>(
          null,
          (longest, s) =>
              longest == null || s.route.length > longest.route.length
              ? s
              : longest,
        );
    return best?.route == section.route;
  }
}

class _AreaChips extends StatelessWidget {
  const _AreaChips({required this.location});

  final String location;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.55),
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            for (final section in trueNasSections)
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: _AreaChip(
                  section: section,
                  selected: TrueNasConsoleShell._isSelected(section, location),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AreaChip extends StatelessWidget {
  const _AreaChip({required this.section, required this.selected});

  final TrueNasSection section;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accent = AppColors.truenas;
    return Semantics(
      button: true,
      selected: selected,
      label: section.title,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => GoRouter.of(context).go(section.route),
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            decoration: BoxDecoration(
              color: selected
                  ? accent.withValues(alpha: 0.16)
                  : colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(AppRadius.full),
              border: Border.all(
                color: selected
                    ? accent.withValues(alpha: 0.45)
                    : colorScheme.outlineVariant,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  section.icon,
                  size: 14,
                  color: selected ? accent : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  section.title,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? colorScheme.onSurface
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AreaRow extends StatefulWidget {
  const _AreaRow({required this.section, required this.selected});

  final TrueNasSection section;
  final bool selected;

  @override
  State<_AreaRow> createState() => _AreaRowState();
}

class _AreaRowState extends State<_AreaRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected = widget.selected;
    final accent = AppColors.truenas;
    return Semantics(
      button: true,
      selected: selected,
      label: widget.section.title,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: () => GoRouter.of(context).go(widget.section.route),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md - 1,
              vertical: AppSpacing.sm,
            ),
            margin: const EdgeInsets.only(bottom: 2),
            decoration: BoxDecoration(
              color: selected
                  ? accent.withValues(alpha: 0.14)
                  : (_hovered
                        ? colorScheme.onSurface.withValues(alpha: 0.05)
                        : null),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: selected
                  ? Border.all(color: accent.withValues(alpha: 0.4))
                  : null,
            ),
            child: Row(
              children: [
                Icon(
                  widget.section.icon,
                  size: 17,
                  color: selected ? accent : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.md - 1),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.section.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: selected
                              ? colorScheme.onSurface
                              : AppColors.onSurfaceDimDark,
                        ),
                      ),
                      // The subtitle earns its place here in a way it does not
                      // on a phone card: this list is read once and then only
                      // glanced at, so the second line is what makes `Datasets`
                      // and `Data Protection` tell themselves apart.
                      Text(
                        widget.section.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.onSurfaceDimDark,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
