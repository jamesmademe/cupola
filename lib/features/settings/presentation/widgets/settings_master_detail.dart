import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_identity.dart';
import 'package:cupola/core/app_breakpoints.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/settings/domain/nav_tab.dart';

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
  /// 300 for the list and the rest for the page: below this the page would be
  /// narrower than the forms it holds, which is the point at which a
  /// master-detail stops being a convenience and starts being a squeeze. It was
  /// 232, which is what a label-only row needs — the rows are readouts now
  /// ("16 of 17 set up · 14 answering"), and 232 truncated every one of them.
  static const double _listWidth = 300;

  /// Whether this build and this window are showing the rail.
  ///
  /// Public because the root pane has to ask: below the threshold `/settings`
  /// *is* the index list, and above it the same route is the summary beside the
  /// rail. Two screens reading one predicate, so they cannot disagree about
  /// which of the two the user is looking at.
  static bool showsRail(BuildContext context) =>
      AppBreakpoints.isDesktopShell(context) &&
      MediaQuery.sizeOf(context).width >= AppBreakpoints.desktopCompact;

  static const List<SettingsSection> sections = [
    // Overview, not "Settings": the rail already sits under a Settings eyebrow,
    // and a first row repeating it reads as the parent of the nine under it
    // rather than as the one row that is a readout instead of a form.
    (label: 'Overview', location: '/settings', icon: Icons.tune_rounded),
    (
      label: 'Connections',
      // `/settings/services` is a legacy path that only ever redirects here, so
      // pointing the row at it meant the location never matched, the longest
      // match fell back to the root, and Connections could not be lit even
      // while you were standing on it.
      location: '/settings/connections',
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
    if (!showsRail(context)) return child;

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
            // A Column over the scroller rather than a last child inside it:
            // the footer belongs to the rail, not to the list, so it stays put
            // while the sections scroll past it.
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.md,
                    ),
                    children: [
                      for (final section in sections)
                        _SectionRow(
                          section: section,
                          // Longest match wins, so `/settings/service/radarr`
                          // still lights Connections rather than falling back
                          // to the root.
                          selected: _isSelected(section, location),
                        ),
                    ],
                  ),
                ),
                // What the app is, at the foot of the one rail that is about
                // the app rather than about the stack. It reads a const in
                // `lib/core`: the project refuses `package_info_plus` by name,
                // and a test measures the const against the pubspec so the
                // number cannot drift the way Plex's hand-tracked copy did.
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.sm,
                    AppSpacing.md,
                    AppSpacing.md,
                  ),
                  child: Text(
                    kAppIdentityLine,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: CupolaThemeColors.of(context).dimText,
                    ),
                  ),
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

  /// Settings' own accent, the one the tab and the ambient room already carry.
  static final Color _accent = NavTab.settings.accentColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected = widget.selected;
    return Semantics(
      button: true,
      container: true,
      enabled: true,
      selected: selected,
      label: widget.section.label,
      onTap: () => GoRouter.of(context).go(widget.section.location),
      child: ExcludeSemantics(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: () => GoRouter.of(context).go(widget.section.location),
            child: Container(
              height: 46,
              margin: const EdgeInsets.only(bottom: 2),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md - 1,
              ),
              decoration: BoxDecoration(
                // The tab's own accent, not `colorScheme.primary`. Primary is the
                // brand indigo (it is Seerr's accent), so the selected row was
                // painted in the colour of one of the services listed two rows
                // below it — on the one surface where indigo means "Seerr".
                color: selected
                    ? _accent.withValues(alpha: 0.14)
                    : (_hovered
                          ? colorScheme.onSurface.withValues(alpha: 0.05)
                          : null),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: selected
                    ? Border.all(color: _accent.withValues(alpha: 0.36))
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
                      style: AppTheme.chrome(
                        context,
                        size: 13,
                        weight: selected ? FontWeight.w600 : FontWeight.w500,
                        color: selected
                            ? colorScheme.onSurface
                            : CupolaThemeColors.of(context).dimText,
                      ),
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
