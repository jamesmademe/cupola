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

  /// Extra paths this door owns, beyond [route].
  ///
  /// One door, two paths is a transitional state, not the model: Virtualization
  /// is a single section (decision 36) whose containers and VMs still live at
  /// `/containers` and `/vms` because collapsing them into one
  /// `virtualization?kind=` route is a `router.dart` change, and `router.dart`
  /// is not this file's to make. Without this the VMs deep link lit no rail row
  /// at all.
  final List<String> alsoMatches;

  const TrueNasSection({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.route,
    this.alsoMatches = const [],
  });

  /// Every path that should light this row, longest first.
  List<String> get routes => [route, ...alsoMatches];
}

/// The nine doors of the console, in the order the design draws them.
///
/// Two things this list used to get wrong. It had **ten** rows: `Containers`
/// and `Virtual Machines` were separate doors for what is one question, which
/// decision 36 merges into a single Virtualization section with pills inside
/// it. And the order ran … Data protection → Containers → VMs → Apps, putting
/// the two least-used doors between the two most-used ones.
///
/// The subtitles are still constants. Every one of them is a live count on the
/// boards (`2 pools · 8 disks`, `SMB 6 · NFS 2 · iSCSI 1`, `11 running · 1
/// stopped`) and every one of those counts is a data-layer addition — the
/// dataset query does not ask for `snapshot_count`, the pool query does not
/// return per-member capacity. A wrong count is worse than a description, so
/// these stay descriptions until the queries can answer.
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
    title: 'Apps',
    subtitle: 'Installed applications',
    icon: Icons.apps_rounded,
    route: ServiceRoutes.truenasApps,
  ),
  TrueNasSection(
    title: 'Virtualization',
    subtitle: 'Incus containers & VMs',
    icon: Icons.inventory_2_rounded,
    route: ServiceRoutes.truenasContainers,
    alsoMatches: [ServiceRoutes.truenasVms],
  ),
  TrueNasSection(
    title: 'Data Protection',
    subtitle: 'Snapshots & replication',
    icon: Icons.shield_rounded,
    route: ServiceRoutes.truenasDataProtection,
  ),
  TrueNasSection(
    title: 'Reporting',
    subtitle: 'Historical graphs',
    icon: Icons.insights_rounded,
    route: ServiceRoutes.truenasReporting,
  ),
  TrueNasSection(
    title: 'System',
    subtitle: 'Services, credentials & power',
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
    if (!AppBreakpoints.isDesktopShell(context)) return child;

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
    String? best;
    TrueNasSection? owner;
    for (final s in trueNasSections) {
      for (final route in s.routes) {
        if (location != route && !location.startsWith('$route/')) continue;
        if (best == null || route.length > best.length) {
          best = route;
          owner = s;
        }
      }
    }
    return identical(owner, section);
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
      container: true,
      enabled: true,
      selected: selected,
      label: section.title,
      onTap: () => GoRouter.of(context).go(section.route),
      child: ExcludeSemantics(
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
                    style: AppTheme.chrome(
                      context,
                      size: 11,
                      weight: FontWeight.w600,
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
      container: true,
      enabled: true,
      selected: selected,
      label: widget.section.title,
      onTap: () => GoRouter.of(context).go(widget.section.route),
      child: ExcludeSemantics(
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
                          style: AppTheme.chrome(
                            context,
                            size: 12,
                            weight: selected
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: selected
                                ? colorScheme.onSurface
                                : CupolaThemeColors.of(context).dimText,
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
                          style: AppTheme.chrome(
                            context,
                            size: 11,
                            color: CupolaThemeColors.of(context).dimText,
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
      ),
    );
  }
}
