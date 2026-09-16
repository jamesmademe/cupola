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
    return Container(
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
            Container(width: 26, height: 1, color: colorScheme.outlineVariant),
            const SizedBox(height: AppSpacing.sm + 2),
            _DeckKeyHint(onPressed: onCommandDeck),
          ],
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

    final glyph = Icon(
      widget.selected ? destination.selectedIcon : destination.icon,
      size: 21,
      color: widget.selected
          ? colorScheme.onSurface
          : (_hovered ? colorScheme.onSurface : colorScheme.onSurfaceVariant),
    );

    return Tooltip(
      message: destination.badgeSemanticLabel == null
          ? '${destination.label}  ${widget.shortcut}'
          : '${destination.label} · ${destination.badgeSemanticLabel}  ${widget.shortcut}',
      waitDuration: const Duration(milliseconds: 500),
      child: Semantics(
        button: true,
        selected: widget.selected,
        label: destination.badgeSemanticLabel == null
            ? destination.label
            : '${destination.label}, ${destination.badgeSemanticLabel}',
        excludeSemantics: true,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: widget.onPressed,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: widget.selected
                    ? primary.withValues(alpha: 0.16)
                    : (_hovered
                          ? colorScheme.onSurface.withValues(alpha: 0.06)
                          : null),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: widget.selected
                    ? Border.all(color: primary.withValues(alpha: 0.42))
                    : null,
              ),
              child: destination.badgeCount <= 0
                  ? Center(child: glyph)
                  : Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        glyph,
                        Positioned(
                          top: -2,
                          right: -2,
                          child: _RailBadge(destination: destination),
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

/// The count, in its destination's own accent — never a status tone.
class _RailBadge extends StatelessWidget {
  const _RailBadge({required this.destination});

  final FloatingNavDestination destination;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
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
          '${destination.badgeCount}',
          style: AppTheme.chrome(
            context,
            size: 11,
            weight: FontWeight.w700,
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
    return Tooltip(
      message: 'Jump to anything  ${ShellShortcuts.commandDeck}',
      waitDuration: const Duration(milliseconds: 500),
      child: Semantics(
        button: true,
        label: 'Jump to anything, ${ShellShortcuts.commandDeck}',
        excludeSemantics: true,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: widget.onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs,
                vertical: AppSpacing.xs,
              ),
              child: Text(
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
