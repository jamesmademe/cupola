import 'package:flutter/material.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_elevation.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/front_room.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';

/// The phone's bar stood on its side, for a tablet: the person's sections in
/// one floating pill of glass at the leading edge, each its glyph over its
/// name, the one it is on lit by the room's strong fill.
///
/// It takes the same [FloatingNavDestination]s the bar does, so a badge and
/// its spoken count are set once for every shape of the app. It has no
/// gesture: the Portal is the phone's, and on a tablet Stack is one tap away.
class FloatingNavRail extends StatelessWidget {
  const FloatingNavRail({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final List<FloatingNavDestination> destinations;

  /// Where the person is in [destinations], or -1 for none: in Settings no
  /// section is lit.
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  /// Air between the pill and the screen's edge, and between it and the page.
  static const double margin = AppSpacing.lg;

  /// The glass's hairline, which the surface's size includes.
  static const double _edge = 1;

  /// Between the hairline and the items: the bar's six, less its edge, so
  /// the pill is the disc and twelve points of glass.
  static const double _inset = FloatingNavBarMetrics.surfacePadding - _edge;

  /// An item at the default reading size: the lit disc is this square.
  static const double _item = 60;

  /// Above and below the glyph and its name inside an item.
  static const double _itemPadding = AppSpacing.row;

  /// Between the glyph and its name.
  static const double _labelGap = AppSpacing.xs;

  static const double _iconSize = 20;

  /// The names are the bar's: `labelMedium`, a step heavier where lit.
  static TextStyle _labelStyle(BuildContext context, {required bool lit}) =>
      Theme.of(
        context,
      ).textTheme.labelMedium!.weight(lit ? FontWeight.w600 : FontWeight.w500);

  static TextScaler _scalerOf(BuildContext context) =>
      FloatingNavBarMetrics.effectiveTextScaler(context);

  /// The width of an item: the disc, or the longest name at the reading size
  /// with its air, whichever is wider.
  static double _itemWidthOf(
    BuildContext context,
    List<FloatingNavDestination> destinations,
  ) {
    final style = _labelStyle(context, lit: true);
    final scaler = _scalerOf(context);
    var widest = 0.0;
    for (final destination in destinations) {
      final painter = TextPainter(
        text: TextSpan(text: destination.label, style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      if (painter.width > widest) widest = painter.width;
    }
    final wanted = widest + AppSpacing.xs * 2;
    return wanted > _item ? wanted.ceilToDouble() : _item;
  }

  static double _itemHeightOf(BuildContext context) {
    final style = _labelStyle(context, lit: true);
    final line =
        _scalerOf(context).scale(style.fontSize ?? 12) * (style.height ?? 1.0);
    final wanted = _itemPadding * 2 + _iconSize + _labelGap + line;
    return wanted > _item ? wanted.ceilToDouble() : _item;
  }

  /// The strip the rail takes from the page: the pill and its margin on
  /// either side.
  static double gutterOf(
    BuildContext context,
    List<FloatingNavDestination> destinations,
  ) => _itemWidthOf(context, destinations) + (_inset + _edge) * 2 + margin * 2;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;
    // The bar's glass, edge and lift, so the two read as one control.
    final glassColor =
        theme.extension<CupolaThemeColors>()?.glassSurface ??
        colorScheme.surfaceContainer.withValues(alpha: isDark ? 0.72 : 0.55);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : colorScheme.outline.withValues(alpha: 0.85);
    final itemWidth = _itemWidthOf(context, destinations);
    final itemHeight = _itemHeightOf(context);
    final lit = selectedIndex >= 0 && selectedIndex < destinations.length;

    // Lit enamel, as the bar's: a sheen of the room in front at its top and
    // its pill tinted by the same light ([RoomSheen]).
    return RoomSheen(
      builder: (context, sheen, pill) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.full),
          boxShadow: AppElevation.glass(colorScheme),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.full),
          child: Container(
            key: const ValueKey('floating-nav-rail-surface'),
            padding: const EdgeInsets.all(_inset),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  sheen.withValues(alpha: glassColor.a),
                  glassColor,
                ],
                stops: const [0, 0.7],
              ),
              borderRadius: BorderRadius.circular(AppRadius.full),
              border: Border.all(color: borderColor, width: _edge),
            ),
            child: SizedBox(
              width: itemWidth,
              height: itemHeight * destinations.length,
              child: Stack(
                children: [
                  // The one lit shape, sliding to the section the person is on:
                  // the room's strong fill tinted by the room in front, no edge.
                  if (lit)
                    AnimatedPositioned(
                      duration: AppAnimation.durationSm,
                      curve: AppAnimation.emphasizedCurve,
                      left: 0,
                      top: itemHeight * selectedIndex,
                      width: itemWidth,
                      height: itemHeight,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          key: const ValueKey('floating-nav-rail-indicator'),
                          decoration: BoxDecoration(
                            color: pill,
                            borderRadius: BorderRadius.circular(_item / 2),
                          ),
                        ),
                      ),
                    ),
                  Column(
                    children: [
                      for (var index = 0; index < destinations.length; index++)
                        SizedBox(
                          width: itemWidth,
                          height: itemHeight,
                          child: _RailItem(
                            destination: destinations[index],
                            lit: index == selectedIndex,
                            index: index,
                            count: destinations.length,
                            onTap: () => onDestinationSelected(index),
                          ),
                        ),
                    ],
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

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.destination,
    required this.lit,
    required this.index,
    required this.count,
    required this.onTap,
  });

  final FloatingNavDestination destination;
  final bool lit;

  /// Zero-based place in the rail, announced as "Tab 2 of 4", as the bar's.
  final int index;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Monochrome, as the bar: the lit section in the primary ink, the rest in
    // the secondary.
    final ink = lit ? colorScheme.onSurface : colorScheme.onSurfaceVariant;
    final indexLabel = MaterialLocalizations.of(
      context,
    ).tabLabel(tabIndex: index + 1, tabCount: count);

    return Semantics(
      key: ValueKey(
        'floating-nav-rail-item-${destination.label.toLowerCase()}',
      ),
      button: true,
      container: true,
      excludeSemantics: true,
      label: destination.badgeSemanticLabel == null
          ? '${destination.label}\n$indexLabel'
          : '${destination.label}, ${destination.badgeSemanticLabel}'
                '\n$indexLabel',
      selected: lit,
      enabled: true,
      onTap: onTap,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            NavBadgedIcon(
              count: destination.badgeCount,
              label: destination.badgeLabel,
              child: AnimatedSwitcher(
                duration: AppAnimation.durationSm,
                child: Icon(
                  lit ? destination.selectedIcon : destination.icon,
                  key: ValueKey(lit),
                  color: ink,
                  size: FloatingNavRail._iconSize,
                ),
              ),
            ),
            const SizedBox(height: FloatingNavRail._labelGap),
            Text(
              destination.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textScaler: FloatingNavRail._scalerOf(context),
              style: FloatingNavRail._labelStyle(
                context,
                lit: lit,
              ).copyWith(color: ink),
            ),
          ],
        ),
      ),
    );
  }
}
