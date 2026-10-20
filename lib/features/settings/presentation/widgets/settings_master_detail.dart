import 'package:flutter/cupertino.dart' show CupertinoRouteTransitionMixin;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_identity.dart';
import 'package:cupola/core/app_breakpoints.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/shell/domain/shell_audience.dart';

/// One entry in the settings section list.
typedef SettingsSection = ({String label, String location, IconData icon});

/// Settings, side by side: the sections on the left, the one you picked on the
/// right.
///
/// On a phone Settings is a drill-down, and that is correct: one screen, one
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
class SettingsMasterDetail extends ConsumerWidget {
  const SettingsMasterDetail({super.key, required this.child});

  /// The page. Shown alone on a phone, and to the right of the list otherwise.
  final Widget child;

  /// Wide enough for the list to be free rather than paid for out of the page.
  ///
  /// 300 for the list and the rest for the page: below this the page would be
  /// narrower than the forms it holds, which is the point at which a
  /// master-detail stops being a convenience and starts being a squeeze. It was
  /// 232, which is what a label-only row needs. The rows are readouts now
  /// ("16 of 17 set up · 14 answering"), and 232 truncated every one of them.
  static const double _listWidth = 300;

  /// Whether this build and this window are showing the rail: a desktop
  /// window from [AppBreakpoints.desktopCompact], a touch build from
  /// [AppBreakpoints.touchSplit] (a tablet on its side, where the rail of the
  /// shell leaves the page about 1080 wide: 300 for the list, the rest for a
  /// form that is still wider than a phone's).
  ///
  /// Public because the root pane has to ask: below the threshold `/settings`
  /// *is* the index list, and above it the same route is the summary beside the
  /// rail. Two screens reading one predicate, so they cannot disagree about
  /// which of the two the user is looking at.
  static bool showsRail(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return AppBreakpoints.isDesktopPlatform
        ? AppBreakpoints.isDesktopShell(context) &&
              width >= AppBreakpoints.desktopCompact
        : width >= AppBreakpoints.touchSplit;
  }

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
    (label: 'Home', location: '/settings/home', icon: Icons.home_outlined),
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

  /// The requester's rail: her account first, then what she sets for
  /// herself. No connections, trust store or release search, which are the
  /// operator's; no Hints, which teach the Portal, which her app has not.
  static const List<SettingsSection> requesterSections = [
    (label: 'Overview', location: '/settings', icon: Icons.tune_rounded),
    (
      label: 'Account',
      location: '/settings/account',
      icon: Icons.person_outline_rounded,
    ),
    (
      label: 'Appearance',
      location: '/settings/appearance',
      icon: Icons.palette_rounded,
    ),
    (label: 'Home', location: '/settings/home', icon: Icons.home_outlined),
    (
      label: 'Region',
      location: '/settings/region',
      icon: Icons.language_rounded,
    ),
  ];

  /// The rail of whoever the app is for.
  static List<SettingsSection> sectionsFor(Audience audience) =>
      switch (audience) {
        Audience.operator => sections,
        Audience.requester => requesterSections,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!showsRail(context)) return child;
    final sections = sectionsFor(ref.watch(shellAudienceProvider));

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
                          selected: _isSelected(sections, section, location),
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

  static bool _isSelected(
    List<SettingsSection> sections,
    SettingsSection section,
    String location,
  ) {
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
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              decoration: BoxDecoration(
                // The room's strong fill, the selected pill of the tab bar and
                // the rail: monochrome, so the selected row says "here" and
                // nothing else. A hue here was once the colour of one of the
                // services listed two rows below it.
                color: selected
                    ? CupolaRoom.of(context).fillStrong
                    : (_hovered
                          ? colorScheme.onSurface.withValues(alpha: 0.05)
                          : null),
                borderRadius: BorderRadius.circular(AppRadius.md),
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
                  const SizedBox(width: AppSpacing.md),
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

/// A section of Settings, the page a row of the list opens.
///
/// Beside the list ([SettingsMasterDetail.showsRail]) one section takes the
/// place of the other where it stands: no slide, which carried the list away
/// with the page, and no back button, since the list beside it is the way
/// between sections (Overview is its first row). Where the list is not drawn
/// it is the drill-down every other page is.
class SettingsSectionPage extends Page<void> {
  const SettingsSectionPage({
    required LocalKey super.key,
    super.name,
    required this.child,
  });

  final Widget child;

  @override
  Route<void> createRoute(BuildContext context) =>
      SettingsMasterDetail.showsRail(context)
      ? _BesideTheList(settings: this)
      : _DrillDown(settings: this);
}

/// The page every other settings page is: the platform's slide. Built from
/// the page as `CupertinoPage` builds it, so a new location (another
/// account's `?i=`) redraws it.
class _DrillDown extends PageRoute<void>
    with CupertinoRouteTransitionMixin<void> {
  _DrillDown({required SettingsSectionPage super.settings});

  @override
  Widget buildContent(BuildContext context) =>
      (settings as SettingsSectionPage).child;

  @override
  String? get title => null;

  @override
  bool get maintainState => true;
}

class _BesideTheList extends PageRoute<void> {
  _BesideTheList({required SettingsSectionPage super.settings});

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => Duration.zero;

  /// The list is the way back, not a button.
  @override
  bool get impliesAppBarDismissal => false;

  @override
  bool get maintainState => true;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => (settings as SettingsSectionPage).child;
}
