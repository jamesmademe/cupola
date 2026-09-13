import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_breakpoints.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';

/// One entry in the settings section list.
typedef SettingsSection = ({String label, String location, IconData icon});

/// Settings, side by side: the sections on the left, the one you picked on the
/// right.
///
/// On a phone Settings is a drill-down, and that is correct — one screen, one
/// job, a back button. On a desktop window the same structure means Connections
/// is three taps from Appearance and you can never see both, so the sections
/// become a list that stays put and the page beside it changes.
///
/// Navigates with `go`, not `push`, and reads the current section straight off
/// the location. That is what keeps this a *layout* rather than a second
/// navigation model: the URL is the same URL the phone has, every page is still
/// its own route, deep links still resolve from the path alone, and the window
/// strip's breadcrumb keeps working because nothing was pushed onto a stack it
/// cannot see.
class SettingsMasterDetail extends StatelessWidget {
  const SettingsMasterDetail({super.key, required this.child});

  /// The page. Shown alone on a phone, and to the right of the list otherwise.
  final Widget child;

  /// Wide enough for the list to be free rather than paid for out of the page.
  ///
  /// 232 for the list and the rest for the page: below this the page would be
  /// narrower than the forms it holds, which is the point at which a
  /// master-detail stops being a convenience and starts being a squeeze.
  static const double _listWidth = 232;

  static const List<SettingsSection> sections = [
    (label: 'Settings', location: '/settings', icon: Icons.tune_rounded),
    (
      label: 'Connections',
      location: '/settings/services',
      icon: Icons.dns_outlined,
    ),
    (
      label: 'Trusted certificates',
      location: '/settings/certificates',
      icon: Icons.verified_user_outlined,
    ),
    (
      label: 'Background search',
      location: '/settings/background-search',
      icon: Icons.travel_explore_rounded,
    ),
    (
      label: 'Appearance',
      location: '/settings/appearance',
      icon: Icons.palette_rounded,
    ),
    (
      label: 'Region',
      location: '/settings/region',
      icon: Icons.language_rounded,
    ),
    (
      label: 'Hints',
      location: '/settings/hints',
      icon: Icons.tips_and_updates_outlined,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    if (!AppBreakpoints.isDesktopShell ||
        MediaQuery.sizeOf(context).width < AppBreakpoints.desktopCompact) {
      return child;
    }

    final colorScheme = Theme.of(context).colorScheme;
    final location = GoRouterState.of(context).uri.path;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: _listWidth,
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
                for (final section in sections)
                  _SectionRow(
                    section: section,
                    // Longest match wins, so `/settings/services/radarr` still
                    // lights Connections rather than falling back to the root.
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

  static bool _isSelected(SettingsSection section, String location) {
    final best = sections
        .where(
          (s) =>
              location == s.location || location.startsWith('${s.location}/'),
        )
        .fold<SettingsSection?>(
          null,
          (longest, s) =>
              longest == null || s.location.length > longest.location.length
              ? s
              : longest,
        );
    return best?.location == section.location;
  }
}

class _SectionRow extends StatefulWidget {
  const _SectionRow({required this.section, required this.selected});

  final SettingsSection section;
  final bool selected;

  @override
  State<_SectionRow> createState() => _SectionRowState();
}

class _SectionRowState extends State<_SectionRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected = widget.selected;
    return Semantics(
      button: true,
      selected: selected,
      label: widget.section.label,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: () => GoRouter.of(context).go(widget.section.location),
          child: Container(
            height: 40,
            margin: const EdgeInsets.only(bottom: 2),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md - 1),
            decoration: BoxDecoration(
              color: selected
                  ? colorScheme.primary.withValues(alpha: 0.14)
                  : (_hovered
                        ? colorScheme.onSurface.withValues(alpha: 0.05)
                        : null),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: selected
                  ? Border.all(
                      color: colorScheme.primary.withValues(alpha: 0.4),
                    )
                  : null,
            ),
            child: Row(
              children: [
                Icon(
                  widget.section.icon,
                  size: 17,
                  color: selected
                      ? colorScheme.onSurface
                      : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.md - 1),
                Expanded(
                  child: Text(
                    widget.section.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected
                          ? colorScheme.onSurface
                          : AppColors.onSurfaceDimDark,
                    ),
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
