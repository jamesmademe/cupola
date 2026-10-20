import 'package:flutter/material.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/settings/domain/nav_tab.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/shell/domain/shell_shortcuts.dart';

/// The window's sidebar: the person's sections, the services with what each
/// needs, what is in flight, and Settings at the foot.
///
/// Takes the *same* [FloatingNavDestination] list the phone's bar does rather
/// than rebuilding one from `NavTab`. That is the whole point: badge counts and
/// their spoken labels are set in one place, so a desktop window cannot end up
/// as the one form factor where a finished search is never announced.
///
/// At full width each item is its glyph and its name; its key (`⌘1`) shows
/// while the pointer is on it and is always in its hint, so the keys are there
/// to learn without a column of them on every row. Stack says how many of the
/// services answer. The services follow in Stack's domains, each a way into
/// its room, with a number where something waits on the person (amber: things
/// to fix; blue: requests to answer), a light where a fault has no count, and
/// `Did not answer` in red under a service that is silent. A calm service
/// carries nothing, so the one that does is seen. The requester's sidebar has
/// no services: she reads no service.
///
/// [footer] sits above Settings: the shell puts what is in flight there, so
/// the downloads stay one glance away without a column of their own.
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
    this.stackFigure,
    this.footer,
    this.header,
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

  /// Beside Stack: how many services answer (`12/12`), and how that is heard.
  final ({String text, String spoken})? stackFigure;

  /// Above Settings on the full sidebar: what is in flight.
  final Widget? footer;

  /// Above the sections on the full sidebar: a Mac's sidebar runs the
  /// window's height, and its head holds the traffic lights and the switch
  /// that hides it ([SidebarHead]).
  final Widget? header;

  static const double fullWidth = 240;
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
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ?header,
                  Expanded(child: _full(context, dim)),
                ],
              ),
      ),
    );
  }

  Widget _full(BuildContext context, Color dim) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.row,
      vertical: AppSpacing.sm,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < destinations.length; i++) _destinationItem(i),
        Expanded(
          child: services.isEmpty
              ? const SizedBox.shrink()
              : ListView(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  children: [
                    for (final domain in ServiceDomain.values)
                      ..._domainRows(context, domain, dim),
                  ],
                ),
        ),
        if (footer case final footer?) ...[
          const SizedBox(height: AppSpacing.sm),
          footer,
          const SizedBox(height: AppSpacing.xs),
        ],
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
  );

  Widget _destinationItem(int i) {
    final destination = destinations[i];
    final badge = destination.badgeCount > 0 ? destination.badgeLabel : null;
    // Stack's figure only where no badge speaks for the row.
    final figure = badge == null && destination.label == NavTab.stack.label
        ? stackFigure
        : null;
    final spoken = [
      destination.label,
      ?destination.badgeSemanticLabel,
      ?figure?.spoken,
    ].join(', ');
    return _SidebarItem(
      glyph: _destinationGlyph(destination),
      label: destination.label,
      spoken: spoken,
      // A count in a tone is the services' pill, whole as theirs (`18`): the
      // 9+ cap is the disc's, on a 20pt glyph. The ink disc otherwise.
      badge: destination.badgeTone == null ? badge : null,
      count: destination.badgeTone == null || badge == null
          ? null
          : destination.badgeFloor
          ? '${destination.badgeCount}+'
          : '${destination.badgeCount}',
      countTone: destination.badgeTone,
      figure: figure?.text,
      shortcut: ShellShortcuts.section(i),
      selected: i == selectedIndex && selectedService == null,
      onPressed: () => onDestinationSelected(i),
    );
  }

  /// One domain's heading and its services, or nothing when none of its
  /// services is set up: a heading over no row is a promise of a room.
  List<Widget> _domainRows(
    BuildContext context,
    ServiceDomain domain,
    Color dim,
  ) {
    final rows = [
      for (final row in services)
        if (row.service.domain == domain) row,
    ];
    if (rows.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.row,
          AppSpacing.md,
          AppSpacing.row,
          AppSpacing.xs,
        ),
        child: Semantics(
          header: true,
          child: Text(
            domain.label,
            textScaler: _SidebarItem.scalerOf(context),
            style: AppType.meta.copyWith(color: dim),
          ),
        ),
      ),
      for (final row in rows)
        _SidebarItem(
          glyph: Icon(row.service.icon, size: 20, weight: 300, opticalSize: 20),
          label: row.service.title,
          spoken: row.state == null
              ? row.service.title
              : '${row.service.title}, ${row.state}',
          count: row.count,
          // A silent service says so in words; a counted one in its number.
          light: row.tone == StatusTone.error || row.count != null
              ? null
              : row.tone,
          countTone: row.tone,
          silent: row.tone == StatusTone.error,
          selected: row.service == selectedService,
          onPressed: () => onService?.call(row.service),
        ),
    ];
  }

  static Widget _destinationGlyph(FloatingNavDestination destination) => Icon(
    destination.railIcon ?? destination.icon,
    size: 20,
    weight: 300,
    fill: 0,
    opticalSize: 20,
  );
}

/// A service of the sidebar: its tone, if it needs a look, what that says
/// aloud, and the number it prints, when there is one to print.
typedef DesktopRailService = ({
  ServiceKey service,
  StatusTone? tone,
  String? state,
  String? count,
});

/// One row of the full sidebar: the glyph, the name, then what it has to say
/// at its end: a count, a figure, a light, or its key while the pointer is on
/// it.
class _SidebarItem extends StatefulWidget {
  const _SidebarItem({
    required this.glyph,
    required this.label,
    required this.spoken,
    required this.selected,
    required this.onPressed,
    this.shortcut,
    this.badge,
    this.figure,
    this.light,
    this.count,
    this.countTone,
    this.silent = false,
  });

  final Widget glyph;
  final String label;
  final String spoken;
  final bool selected;
  final VoidCallback onPressed;

  /// The row's key, shown while the pointer is on it and always in its hint.
  final String? shortcut;

  /// The count of the section's badge, in ink.
  final String? badge;

  /// A quiet figure at the end: Stack's `12/12`.
  final String? figure;

  /// The service's light, or null when it is calm or says it in a number.
  final StatusTone? light;

  /// The things waiting on the person in this service, in [countTone].
  final String? count;
  final StatusTone? countTone;

  /// Whether the service did not answer: said under its name, in red.
  final bool silent;

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
    // The key while the pointer is on the row, and only then: a column of
    // `⌘1`…`⌘4` on every row was a keyboard map nobody had asked to read.
    final shortcut = _hovered ? widget.shortcut : null;
    final badge = widget.badge;
    final count = widget.count;
    final countTone = widget.countTone ?? StatusTone.warning;
    final figure = shortcut == null ? widget.figure : null;
    final name = Text(
      widget.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textScaler: _SidebarItem.scalerOf(context),
      style: AppType.row.copyWith(
        color: widget.silent && !widget.selected && !_hovered ? dim : ink,
      ),
    );

    return Semantics(
      button: true,
      container: true,
      enabled: true,
      selected: widget.selected,
      label: widget.spoken,
      hint: widget.shortcut,
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
                    child: widget.silent
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              name,
                              Text(
                                'Did not answer',
                                key: ValueKey(
                                  'desktop-rail-silent-${widget.label}',
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textScaler: _SidebarItem.scalerOf(context),
                                style: AppType.meta.copyWith(
                                  color: statusToneColor(
                                    colorScheme,
                                    StatusTone.error,
                                  ),
                                ),
                              ),
                            ],
                          )
                        : name,
                  ),
                  if (badge != null) ...[
                    const SizedBox(width: AppSpacing.sm),
                    _RailBadge(label: badge),
                  ],
                  if (count != null) ...[
                    const SizedBox(width: AppSpacing.sm),
                    _CountPill(
                      key: ValueKey('desktop-rail-count-${widget.label}'),
                      label: count,
                      tone: countTone,
                    ),
                  ],
                  if (figure != null) ...[
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      figure,
                      textScaler: _SidebarItem.scalerOf(context),
                      style: AppTheme.chrome(
                        context,
                        size: 12,
                        color: dim,
                      ).tabular,
                    ),
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
    // else in the shell. The phone's bar keeps the fill: there the label and
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
                child: _RailBadge(
                  label: destination.badgeLabel,
                  tone: destination.badgeTone,
                ),
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

/// A service's count: the number in its tone, on a quiet wash of the same.
///
/// The tone is the five-arm rule's (amber things to fix, blue requests to
/// answer), painted through [statusToneColor] like every tone in the window;
/// the wash keeps the number legible without a solid disc that would outweigh
/// the section badges above it.
class _CountPill extends StatelessWidget {
  const _CountPill({super.key, required this.label, required this.tone});

  final String label;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = statusToneColor(colorScheme, tone);
    return Container(
      constraints: const BoxConstraints(minWidth: 22, minHeight: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        textScaler: MediaQuery.textScalerOf(
          context,
        ).clamp(maxScaleFactor: _RailBadge.maxScale),
        style: AppTheme.chrome(
          context,
          size: 11,
          weight: FontWeight.w600,
          color: color,
          height: 1,
        ).tabular,
      ),
    );
  }
}

/// The count, on the ink disc: never a status tone, never a section's colour.
class _RailBadge extends StatelessWidget {
  const _RailBadge({required this.label, this.tone});

  /// The disc's tone (`navBadgeColors`); null for the ink disc.
  final StatusTone? tone;

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
    final colors = navBadgeColors(context, tone);
    return Container(
      key: const ValueKey('desktop-rail-badge'),
      // 18, not the 15 this was. DESIGN.md's type floor is enforced rather than
      // asserted, and it records that this badge grew precisely so it would not
      // need a 9px numeral: the phone's did, and the rail's was left behind.
      // Where the geometry cannot take 11px, the geometry yields.
      //
      // A floor, not a height, as the phone bar's badge: at 200% a fixed 18pt
      // disc cut the numeral off. The numeral grows with the reading size to
      // [maxScale] and no further, as far as the 56pt rail holds the disc.
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: colors.fill,
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
            color: colors.ink,
            height: 1,
          ).tabular,
        ),
      ),
    );
  }
}
