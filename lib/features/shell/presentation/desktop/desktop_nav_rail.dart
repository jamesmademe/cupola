import 'package:flutter/material.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/features/shell/domain/shell_shortcuts.dart';

/// The 56pt section rail: four glyphs, and the deck's key at the foot of it.
///
/// Takes the *same* [FloatingNavDestination] list the phone's bottom bar does
/// rather than rebuilding one from `NavTab`. That is the whole point: badge
/// counts and their spoken labels are set in one place, so a desktop window
/// cannot end up as the one form factor where a finished search is never
/// announced.
///
/// Icon-only, which is why every item carries a tooltip with its name *and* its
/// shortcut: the rail is the app's main teaching surface for the keyboard map,
/// and an unlabelled glyph with no tooltip is a guess.
class DesktopNavRail extends StatelessWidget {
  const DesktopNavRail({
    super.key,
    required this.selectedIndex,
    required this.destinations,
    required this.onDestinationSelected,
    required this.onCommandDeck,
  });

  final int selectedIndex;
  final List<FloatingNavDestination> destinations;
  final ValueChanged<int> onDestinationSelected;

  /// Opening the deck from the rail's own key hint, for a pointer that has
  /// never met the shortcut.
  final VoidCallback onCommandDeck;

  static const double width = 56;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Section navigation',
      child: Container(
        width: width,
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.55),
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Column(
            children: [
              for (var i = 0; i < destinations.length; i++)
                Padding(
                  padding: EdgeInsets.only(
                    bottom: i == destinations.length - 1 ? 0 : AppSpacing.sm,
                  ),
                  child: _RailItem(
                    destination: destinations[i],
                    selected: i == selectedIndex,
                    shortcut: ShellShortcuts.section(i),
                    onPressed: () => onDestinationSelected(i),
                  ),
                ),
              const Spacer(),
              Container(
                width: 26,
                height: 1,
                color: colorScheme.outlineVariant,
              ),
              const SizedBox(height: AppSpacing.sm + 2),
              _DeckKeyHint(onPressed: onCommandDeck),
            ],
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
    // The shell is one colour: the app's own indigo, never the per-service
    // accents, which belong to service surfaces. See `NavTab`.
    final primary = colorScheme.primary;

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
                child: _RailBadge(destination: destination),
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
                    ? primary.withValues(alpha: 0.16)
                    : (_hovered
                          ? colorScheme.onSurface.withValues(alpha: 0.06)
                          : Colors.transparent),
              ),
              side: WidgetStatePropertyAll(
                widget.selected
                    ? BorderSide(color: primary.withValues(alpha: 0.42))
                    : BorderSide.none,
              ),
            ),
            icon: icon,
          ),
        ),
      ),
    );
  }
}

/// The count, in its destination's own accent — never a status tone.
class _RailBadge extends StatelessWidget {
  const _RailBadge({required this.destination});

  final FloatingNavDestination destination;

  /// Offset of the badge's top-left corner from the 20pt glyph's.
  ///
  /// With the widest label a badge can print (`9+`, see
  /// [FloatingNavDestination.badgeLabel]) the badge still ends inside the 56pt
  /// rail, short of its hairline; the glyph keeps its left half and its whole
  /// lower half.
  static const double left = 12;
  static const double top = -8;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('desktop-rail-badge'),
      // 18, not the 15 this was. DESIGN.md's type floor is enforced rather than
      // asserted, and it records that this badge grew precisely so it would not
      // need a 9px numeral — the phone's did, and the rail's was left behind.
      // Where the geometry cannot take 11px, the geometry yields.
      constraints: const BoxConstraints(minWidth: 18),
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: destination.accentColor,
        borderRadius: BorderRadius.circular(AppRadius.full),
        // A collar in the rail's own ground, so the badge reads as sitting on
        // top of the glyph rather than merging into it.
        border: Border.all(color: colorScheme.surfaceContainerLowest, width: 2),
      ),
      child: Center(
        child: Text(
          destination.badgeLabel,
          style: AppTheme.chrome(
            context,
            size: 11,
            weight: FontWeight.w600,
            color: ServiceTheme.foregroundOn(destination.accentColor),
            height: 1,
          ).mono.tabular,
        ),
      ),
    );
  }
}

/// `⌘K` at the foot of the rail: the deck's key, and a button in its own right.
///
/// Both, deliberately. A shortcut nobody can click is invisible to everyone who
/// does not already know it, and a button with no key printed on it teaches
/// nothing — this is the one control in the shell whose job is to be read.
class _DeckKeyHint extends StatefulWidget {
  const _DeckKeyHint({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_DeckKeyHint> createState() => _DeckKeyHintState();
}

class _DeckKeyHintState extends State<_DeckKeyHint> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      container: true,
      enabled: true,
      label: 'Jump to anything, ${ShellShortcuts.commandDeck}',
      hint: 'Open the command deck',
      onTap: widget.onPressed,
      child: ExcludeSemantics(
        child: Tooltip(
          message: 'Jump to anything  ${ShellShortcuts.commandDeck}',
          waitDuration: const Duration(milliseconds: 500),
          excludeFromSemantics: true,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: IconButton(
              tooltip: 'Jump to anything, ${ShellShortcuts.commandDeck}',
              onPressed: widget.onPressed,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs,
                vertical: AppSpacing.xs,
              ),
              constraints: const BoxConstraints.tightFor(width: 40, height: 40),
              style: const ButtonStyle(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                overlayColor: WidgetStatePropertyAll(Colors.transparent),
              ),
              icon: Text(
                ShellShortcuts.commandDeck,
                style: AppTheme.chrome(
                  context,
                  size: 11,
                  color: _hovered
                      ? colorScheme.onSurface
                      : CupolaThemeColors.of(context).dimText,
                ).mono.tabular,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
