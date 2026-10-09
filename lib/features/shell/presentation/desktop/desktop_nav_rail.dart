import 'package:flutter/material.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/shell/domain/shell_shortcuts.dart';

/// The window's sidebar: the person's sections with their keys, the services
/// with what each needs, and Settings at the foot.
///
/// Takes the *same* [FloatingNavDestination] list the phone's bar does rather
/// than rebuilding one from `NavTab`. That is the whole point: badge counts and
/// their spoken labels are set in one place, so a desktop window cannot end up
/// as the one form factor where a finished search is never announced.
///
/// At full width each item is its glyph, its name and its key (`⌘1`), so the
/// sidebar is where the keyboard map is learnt. The services follow under
/// their heading, each a way into its room with a light only where it needs a
/// look: amber for a fault, red for one that did not answer, blue for
/// requests that wait. A calm service carries no light, so the one that does
/// is seen. The requester's sidebar has no services: she reads no service.
///
/// Narrower than [AppBreakpoints.desktopCompact] the sidebar folds to its
/// 56pt rail: the sections and Settings as glyphs, each with a tooltip that
/// says its name and key. The services stay on Stack and the deck.
class DesktopNavRail extends StatelessWidget {
  const DesktopNavRail({
    super.key,
    required this.selectedIndex,
    required this.destinations,
    required this.onDestinationSelected,
    required this.settings,
    required this.settingsSelected,
    required this.onSettings,
    this.compact = false,
    this.services = const [],
    this.selectedService,
    this.onService,
  });

  final int selectedIndex;
  final List<FloatingNavDestination> destinations;
  final ValueChanged<int> onDestinationSelected;

  /// Settings, at the foot: it is no section of the bar, and on a Mac it is
  /// where the window's settings always are, one `⌘,` away.
  final FloatingNavDestination settings;
  final bool settingsSelected;
  final VoidCallback onSettings;

  /// The folded rail of a narrow window.
  final bool compact;

  /// The configured services in Stack's order, each with its light. Empty for
  /// the requester, and not drawn on the folded rail.
  final List<DesktopRailService> services;

  /// The service whose room the window is in, lit in place of Stack.
  final ServiceKey? selectedService;
  final ValueChanged<ServiceKey>? onService;

  static const double fullWidth = 232;
  static const double compactWidth = 56;

  static double widthFor({required bool compact}) =>
      compact ? compactWidth : fullWidth;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final dim = CupolaThemeColors.of(context).dimText;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Section navigation',
      child: Container(
        width: widthFor(compact: compact),
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.55),
            ),
          ),
        ),
        child: compact
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Column(
                  children: [
                    for (var i = 0; i < destinations.length; i++)
                      Padding(
                        padding: EdgeInsets.only(
                          bottom: i == destinations.length - 1
                              ? 0
                              : AppSpacing.sm,
                        ),
                        child: _RailItem(
                          destination: destinations[i],
                          selected: i == selectedIndex,
                          shortcut: ShellShortcuts.section(i),
                          onPressed: () => onDestinationSelected(i),
                        ),
                      ),
                    const Spacer(),
                    _RailItem(
                      destination: settings,
                      selected: settingsSelected,
                      shortcut: ShellShortcuts.settings,
                      onPressed: onSettings,
                    ),
                  ],
                ),
              )
            : Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.row,
                  vertical: AppSpacing.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < destinations.length; i++)
                      _SidebarItem(
                        glyph: _destinationGlyph(destinations[i]),
                        label: destinations[i].label,
                        spoken: destinations[i].badgeSemanticLabel == null
                            ? destinations[i].label
                            : '${destinations[i].label}, '
                                  '${destinations[i].badgeSemanticLabel}',
                        badge: destinations[i].badgeCount > 0
                            ? destinations[i].badgeLabel
                            : null,
                        shortcut: ShellShortcuts.section(i),
                        selected: i == selectedIndex && selectedService == null,
                        onPressed: () => onDestinationSelected(i),
                      ),
                    Expanded(
                      child: services.isEmpty
                          ? const SizedBox.shrink()
                          : ListView(
                              padding: const EdgeInsets.only(
                                top: AppSpacing.md,
                              ),
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    AppSpacing.row,
                                    0,
                                    AppSpacing.row,
                                    AppSpacing.xs,
                                  ),
                                  child: Semantics(
                                    header: true,
                                    child: Text(
                                      'Services',
                                      textScaler: _SidebarItem.scalerOf(
                                        context,
                                      ),
                                      style: AppType.meta.copyWith(color: dim),
                                    ),
                                  ),
                                ),
                                for (final row in services)
                                  _SidebarItem(
                                    glyph: Icon(
                                      row.service.icon,
                                      size: 20,
                                      weight: 300,
                                      opticalSize: 20,
                                    ),
                                    label: row.service.title,
                                    spoken: row.state == null
                                        ? row.service.title
                                        : '${row.service.title}, ${row.state}',
                                    light: row.tone,
                                    selected: row.service == selectedService,
                                    onPressed: () =>
                                        onService?.call(row.service),
                                  ),
                              ],
                            ),
                    ),
                    _SidebarItem(
                      glyph: _destinationGlyph(settings),
                      label: settings.label,
                      spoken: settings.label,
                      shortcut: ShellShortcuts.settings,
                      selected: settingsSelected,
                      onPressed: onSettings,
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  static Widget _destinationGlyph(FloatingNavDestination destination) => Icon(
    destination.railIcon ?? destination.icon,
    size: 20,
    weight: 300,
    fill: 0,
    opticalSize: 20,
  );
}

/// A service of the sidebar: its light, if it needs a look, and what the
/// light says aloud.
typedef DesktopRailService = ({
  ServiceKey service,
  StatusTone? tone,
  String? state,
});

/// One row of the full sidebar: the glyph, the name, then the key or the
/// light at its end.
class _SidebarItem extends StatefulWidget {
  const _SidebarItem({
    required this.glyph,
    required this.label,
    required this.spoken,
    required this.selected,
    required this.onPressed,
    this.shortcut,
    this.badge,
    this.light,
  });

  final Widget glyph;
  final String label;
  final String spoken;
  final bool selected;
  final VoidCallback onPressed;
  final String? shortcut;

  /// The count of the section's badge, in ink, before its key.
  final String? badge;

  /// The service's light, or null when it is calm.
  final StatusTone? light;

  /// A row: the 44pt target of every control in the window.
  static const double height = 44;

  /// The names grow with the reading size as far as the phone's bar lets
  /// its own, and no further: the sidebar is chrome, its width fixed, and a
  /// name cut short at twice the size says less than one a little smaller.
  static TextScaler scalerOf(BuildContext context) => MediaQuery.textScalerOf(
    context,
  ).clamp(maxScaleFactor: FloatingNavBarMetrics.maxTextScaleFactor);

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final room = CupolaRoom.of(context);
    final dim = CupolaThemeColors.of(context).dimText;
    final ink = widget.selected || _hovered
        ? colorScheme.onSurface
        : colorScheme.onSurfaceVariant;
    final light = widget.light;
    final shortcut = widget.shortcut;
    final badge = widget.badge;

    return Semantics(
      button: true,
      container: true,
      enabled: true,
      selected: widget.selected,
      label: widget.spoken,
      hint: shortcut,
      onTap: widget.onPressed,
      child: ExcludeSemantics(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed,
            child: AnimatedContainer(
              duration: AppAnimation.durationXs,
              constraints: const BoxConstraints(minHeight: _SidebarItem.height),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.row),
              decoration: BoxDecoration(
                color: widget.selected
                    ? room.fillStrong
                    : (_hovered ? room.fillQuiet : Colors.transparent),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Row(
                children: [
                  IconTheme.merge(
                    data: IconThemeData(color: ink),
                    child: widget.glyph,
                  ),
                  const SizedBox(width: AppSpacing.row),
                  Expanded(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textScaler: _SidebarItem.scalerOf(context),
                      style: AppType.row.copyWith(color: ink),
                    ),
                  ),
                  if (badge != null) ...[
                    const SizedBox(width: AppSpacing.sm),
                    _RailBadge(label: badge),
                  ],
                  if (shortcut != null) ...[
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      shortcut,
                      textScaler: _SidebarItem.scalerOf(context),
                      style: AppTheme.chrome(
                        context,
                        size: 12,
                        color: dim,
                      ).mono,
                    ),
                  ],
                  if (light != null) ...[
                    const SizedBox(width: AppSpacing.sm),
                    Container(
                      key: ValueKey('desktop-rail-light-${widget.label}'),
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: statusToneColor(colorScheme, light),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RailItem extends StatefulWidget {
  const _RailItem({
    required this.destination,
    required this.selected,
    required this.shortcut,
    required this.onPressed,
  });

  final FloatingNavDestination destination;
  final bool selected;
  final String shortcut;
  final VoidCallback onPressed;

  @override
  State<_RailItem> createState() => _RailItemState();
}

class _RailItemState extends State<_RailItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final destination = widget.destination;
    // The shell is monochrome: the selected item is the room's strong fill
    // under the primary ink, the pill of the phone's bar, and no section or
    // service carries a colour of its own. See `NavTab`.
    final selectedFill = CupolaRoom.of(context).fillStrong;

    // The outline in both states, never a filled glyph. The pill behind it
    // already says which section is current; filling the glyph too said it
    // twice, and on a rail of four the one solid shape outweighed everything
    // else in the shell. The phone's bar keeps the fill — there the label and
    // the fill are the whole of the selected state.
    //
    // Weight 300 through Material Symbols' `wght` axis: Material Icons has one
    // stroke, and at rail size it read heavier than the type beside it.
    final glyph = Icon(
      destination.railIcon ?? destination.icon,
      size: 20,
      weight: 300,
      fill: 0,
      opticalSize: 20,
      color: widget.selected
          ? colorScheme.onSurface
          : (_hovered ? colorScheme.onSurface : colorScheme.onSurfaceVariant),
    );

    final semanticLabel = destination.badgeSemanticLabel == null
        ? destination.label
        : '${destination.label}, ${destination.badgeSemanticLabel}';
    final tooltip = '$semanticLabel  ${widget.shortcut}';
    final icon = destination.badgeCount <= 0
        ? glyph
        : Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              glyph,
              // Anchored by its LEFT edge, just right of the glyph's centre,
              // so a wider count grows away from the glyph instead of across
              // it: the badge only ever sits on the glyph's top-right corner.
              // Anchored by its right edge 2pt past the glyph's, the 18pt badge
              // covered most of a 20pt glyph and "12" hid it outright.
              Positioned(
                top: _RailBadge.top,
                left: _RailBadge.left,
                child: _RailBadge(label: destination.badgeLabel),
              ),
            ],
          );

    // This is intentionally a real Material button, rather than a painted
    // GestureDetector wrapped in Semantics. The latter works in Flutter's
    // widget tree but disappears from the native macOS AX tree in the shell,
    // which makes the control clickable by coordinate yet unreachable to
    // keyboard and assistive input. The target remains 40pt; only the control
    // semantics implementation changes.
    return Semantics(
      button: true,
      container: true,
      enabled: true,
      selected: widget.selected,
      label: semanticLabel,
      onTap: widget.onPressed,
      child: ExcludeSemantics(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: IconButton(
            tooltip: tooltip,
            onPressed: widget.onPressed,
            isSelected: widget.selected,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 40, height: 40),
            style: ButtonStyle(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const WidgetStatePropertyAll(EdgeInsets.zero),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
              ),
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
              backgroundColor: WidgetStatePropertyAll(
                widget.selected
                    ? selectedFill
                    : (_hovered
                          ? colorScheme.onSurface.withValues(alpha: 0.06)
                          : Colors.transparent),
              ),
            ),
            icon: icon,
          ),
        ),
      ),
    );
  }
}

/// The count, on the ink disc — never a status tone, never a section's colour.
class _RailBadge extends StatelessWidget {
  const _RailBadge({required this.label});

  /// The count as [FloatingNavDestination.badgeLabel] prints it.
  final String label;

  /// Offset of the badge's top-left corner from the 20pt glyph's.
  ///
  /// With the widest label a badge can print (`9+`, see
  /// [FloatingNavDestination.badgeLabel]) the badge still ends inside the 56pt
  /// rail, short of its hairline; the glyph keeps its left half and its whole
  /// lower half.
  static const double left = 12;
  static const double top = -8;

  /// The largest reading size the numeral takes: chrome, like the glyph it
  /// sits on, which does not scale at all.
  static const double maxScale = 1.2;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('desktop-rail-badge'),
      // 18, not the 15 this was. DESIGN.md's type floor is enforced rather than
      // asserted, and it records that this badge grew precisely so it would not
      // need a 9px numeral — the phone's did, and the rail's was left behind.
      // Where the geometry cannot take 11px, the geometry yields.
      //
      // A floor, not a height, as the phone bar's badge: at 200% a fixed 18pt
      // disc cut the numeral off. The numeral grows with the reading size to
      // [maxScale] and no further, as far as the 56pt rail holds the disc.
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: colorScheme.primary,
        borderRadius: BorderRadius.circular(AppRadius.full),
        // A collar in the rail's own ground, so the badge reads as sitting on
        // top of the glyph rather than merging into it.
        border: Border.all(color: colorScheme.surfaceContainerLowest, width: 2),
      ),
      alignment: Alignment.center,
      child: Center(
        widthFactor: 1,
        heightFactor: 1,
        child: Text(
          label,
          textScaler: MediaQuery.textScalerOf(
            context,
          ).clamp(maxScaleFactor: maxScale),
          style: AppTheme.chrome(
            context,
            size: 11,
            weight: FontWeight.w600,
            color: colorScheme.onPrimary,
            height: 1,
          ).tabular,
        ),
      ),
    );
  }
}
