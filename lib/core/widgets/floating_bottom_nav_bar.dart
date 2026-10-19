import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_elevation.dart';
import 'package:cupola/core/app_breakpoints.dart';
import 'package:cupola/core/generated/design_tokens.g.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/front_room.dart';

/// A destination for the [FloatingBottomNavBar].
class FloatingNavDestination {
  /// The icon to display when this destination is not selected.
  final IconData icon;

  /// The icon to display when this destination is selected.
  final IconData selectedIcon;

  /// The desktop rail's glyph, where it differs from [icon]. Null elsewhere.
  final IconData? railIcon;

  /// The label for this destination.
  final String label;

  /// Count of things waiting on this destination, or zero for none.
  ///
  /// Painted in **ink**, never a status tone and never a colour of the
  /// section's own: a green or amber pill living in permanent chrome reads as
  /// stack health, and the chrome is monochrome: colour comes from the content
  /// and the five tones, nothing else. An ink disc with the on-ink numeral is
  /// the loudest thing the room can draw without a hue.
  final int badgeCount;

  /// Spoken alongside the label, because a number drawn on an icon is invisible
  /// to a screen reader.
  final String? badgeSemanticLabel;

  /// Actions a screen reader offers on this destination beside activating it.
  ///
  /// The accessible door to something the bar otherwise reaches only by a
  /// gesture: the shell hangs the Portal here, since a drag is exactly what a
  /// screen reader cannot perform. Null for none. Only the bar reads it: the
  /// rails have no gesture to stand in for.
  final Map<CustomSemanticsAction, VoidCallback>? customSemanticsActions;

  const FloatingNavDestination({
    required this.icon,
    required this.selectedIcon,
    this.railIcon,
    required this.label,
    this.badgeCount = 0,
    this.badgeSemanticLabel,
    this.customSemanticsActions,
  });

  /// What the badge prints: the count, or `9+` past nine.
  ///
  /// One rule for every surface that draws [badgeCount]: the phone's bar and
  /// the desktop rail, because both badges sit on a 20pt glyph, and a third
  /// digit is wider than the glyph it annotates.
  String get badgeLabel => badgeCount > 9 ? '9+' : '$badgeCount';
}

/// Constants for FloatingBottomNavBar dimensions.
///
/// Use [FloatingNavBarMetrics.getScrollViewBottomPadding] to calculate content
/// padding: the bar grows with the reading size, so a fixed constant would leave
/// the last row of a list under the bar at large text scales.
class FloatingNavBarMetrics {
  FloatingNavBarMetrics._();

  /// Height of the nav bar at the default reading size: `size.tabbar`.
  static const double barHeight = DesignTokens.sizeTabbar;

  /// Top padding above the nav bar.
  static const double topPadding = AppSpacing.sm; // 8dp

  /// Bottom padding below the nav bar (excluding safe area).
  static const double bottomPadding = AppSpacing.xs;

  /// Inset between the glass surface edge and the pill.
  static const double surfacePadding = 5.0;

  /// Total height at the default reading size, excluding safe area.
  ///
  /// Prefer [totalHeightFor], which accounts for the user's text scale.
  static const double totalHeight = barHeight + topPadding + bottomPadding;

  /// Upper bound applied to the user's text scale inside the bar.
  ///
  /// The nav bar is compact chrome sitting over content: letting its label grow
  /// without limit pushes the bar over half the screen, and ignoring the
  /// preference outright is hostile. Growing up to this factor keeps the label
  /// legible while the bar stays a bar: the same compromise the system tab bar
  /// makes.
  static const double maxTextScaleFactor = 1.3;

  /// The text scale actually used to lay the bar out.
  static TextScaler effectiveTextScaler(BuildContext context) =>
      _clamp(MediaQuery.textScalerOf(context));

  static TextScaler _clamp(TextScaler scaler) =>
      scaler.clamp(maxScaleFactor: maxTextScaleFactor);

  /// Height of the bar at the current reading size.
  ///
  /// Derived from what is inside it (a glyph over its name, with air above
  /// and below inside the pill), so a column can never overflow the surface.
  static double barHeightFor(BuildContext context) {
    final content = _NavBarItem.contentHeightFor(
      effectiveTextScaler(context),
      _NavBarItem.labelStyleOf(context),
    );
    final needed = content + (AppSpacing.xs + surfacePadding) * 2;
    return needed > barHeight ? needed : barHeight;
  }

  /// Total height at the current reading size, excluding safe area.
  static double totalHeightFor(BuildContext context) =>
      barHeightFor(context) + topPadding + bottomPadding;

  /// The bottom padding a page's scroll view needs to end above the bar,
  /// with [AppSpacing.lg] of air between its last row and the glass.
  ///
  /// The shell lays every page under the bar with `Scaffold(extendBody:
  /// true)`, and that Scaffold already hands its body the bar's height and the
  /// home indicator in `MediaQuery.padding.bottom`: the bar is in it once, and
  /// adding [totalHeightFor] again left every page a bar's height short of it
  /// (74pt, measured on a phone, 11/10). A page pushed over the shell has no
  /// bar, and the same reading gives it the home indicator alone.
  /// `test/core/widgets/bar_clearance_sweep_test.dart` reads the pages.
  static double getScrollViewBottomPadding(BuildContext context) {
    // No bar, no clearance. A desktop window navigates from the rail and the
    // deck, so reserving room at the foot of every scroll view would leave one
    // dead strip along the bottom of all 73 screens, and this one helper is
    // where all of them ask, which is why the answer belongs here rather than
    // in 50 build methods.
    if (AppBreakpoints.isDesktopShell(context)) return 0;

    // `paddingOf`, not `of`: this helper is called from ~50 `build` methods, and
    // an unscoped `MediaQuery.of` subscribes every one of them to *any*
    // MediaQueryData change, including `viewInsets`, which animates every frame
    // the soft keyboard opens or closes. The padding aspect changes only on a
    // real safe-area change (rotation, notch) and when the bar comes or goes.
    return MediaQuery.paddingOf(context).bottom + AppSpacing.lg;
  }
}

/// A custom floating bottom navigation bar with rounded corners and glass styling.
///
/// Features:
/// - Floating design with margins on all sides
/// - As wide as the page, a stadium, four columns of one width: each
///   destination its glyph over its name, the lit one a pill filling its
///   column, monochrome: the room's strong fill under the primary ink
/// - Elastic drag animation (rubber band effect)
/// - Glass surface: a semi-opaque tint, deliberately NOT a backdrop blur.
///   With `extendBody: true` every screen scrolls under this bar, so a
///   [BackdropFilter] here re-blurred the whole backdrop on every scroll
///   frame, measured on device at 15–25ms of raster per frame, half the
///   scroll budget gone. Same rule, same reason as [GlassAppBar].
///
/// Example usage:
/// ```dart
/// FloatingBottomNavBar(
///   selectedIndex: 0,
///   onDestinationSelected: (index) => print('Selected: $index'),
///   destinations: [
///     FloatingNavDestination(
///       icon: Icons.home_outlined,
///       selectedIcon: Icons.home_rounded,
///       label: 'Home',
///     ),
///   ],
/// )
/// ```
/// Contract through which the shell takes over the bar's VERTICAL drag (the
/// Portal trigger) while the bar keeps its horizontal rubber band to itself.
///
/// Lives here rather than in the shell feature so `core/widgets` never depends
/// on a feature: the bar knows this contract, never the Portal.
abstract class FloatingNavBarVerticalDragDelegate {
  /// Current lift to apply to the bar (pt, positive = raised).
  ValueListenable<double> get verticalLift;

  void onBarDragStart(double globalY);
  void onBarDragDelta(double dy);
  void onBarDragEnd(double velocityY);
}

class FloatingBottomNavBar extends StatefulWidget {
  /// The index of the currently selected destination.
  final int selectedIndex;

  /// Called when one of the destinations is selected.
  final ValueChanged<int> onDestinationSelected;

  /// The list of destinations to display.
  final List<FloatingNavDestination> destinations;

  /// When set, the vertical axis of the pan belongs to the delegate (the
  /// Portal) and the bar's own elastic runs horizontally only. With `null`
  /// the bar behaves exactly as it always has.
  final FloatingNavBarVerticalDragDelegate? verticalDragDelegate;

  const FloatingBottomNavBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    this.verticalDragDelegate,
  });

  @override
  State<FloatingBottomNavBar> createState() => _FloatingBottomNavBarState();
}

class _FloatingBottomNavBarState extends State<FloatingBottomNavBar>
    with SingleTickerProviderStateMixin {
  /// Current drag offset from original position.
  Offset _dragOffset = Offset.zero;

  /// Animation controller for spring-back animation.
  late AnimationController _springController;

  /// Animation for returning to original position.
  Animation<Offset>? _springAnimation;

  // === Elastic drag physics parameters ===

  /// Maximum allowed drag distance in any direction.
  static const double _maxDragDistance = 15.0;

  /// Base resistance factor (lower = more rigid).
  static const double _baseResistance = 0.15;

  /// Controls how quickly resistance increases with distance.
  static const double _resistanceFalloff = 30.0;

  @override
  void initState() {
    super.initState();
    _springController = AnimationController(
      vsync: this,
      duration: AppAnimation.durationXl,
    );
  }

  @override
  void dispose() {
    _springController.dispose();
    super.dispose();
  }

  /// Applies elastic resistance to drag delta.
  ///
  /// Resistance increases as offset grows, creating a "rubber band" feel.
  double _applyElasticResistance(double delta, double currentOffset) {
    // Resistance increases exponentially as we get further from origin
    final resistance =
        _baseResistance / (1 + (currentOffset.abs() / _resistanceFalloff));
    return delta * resistance;
  }

  void _onPanStart(DragStartDetails details) {
    widget.verticalDragDelegate?.onBarDragStart(details.globalPosition.dy);
  }

  void _onPanUpdate(DragUpdateDetails details) {
    // Stop any running spring animation
    if (_springController.isAnimating) {
      _springController.stop();
    }

    final delegate = widget.verticalDragDelegate;
    setState(() {
      // Apply elastic resistance; the vertical axis is the delegate's when one
      // is attached (the Portal's prelude replaces the aesthetic dy elastic).
      final dx = _applyElasticResistance(details.delta.dx, _dragOffset.dx);
      final dy = delegate == null
          ? _applyElasticResistance(details.delta.dy, _dragOffset.dy)
          : 0.0;

      _dragOffset += Offset(dx, dy);

      // Clamp to maximum drag distance
      _dragOffset = Offset(
        _dragOffset.dx.clamp(-_maxDragDistance, _maxDragDistance),
        _dragOffset.dy.clamp(-_maxDragDistance, _maxDragDistance),
      );
    });
    delegate?.onBarDragDelta(details.delta.dy);
  }

  void _onPanEnd(DragEndDetails details) {
    // Animate back to original position with elastic curve
    _springAnimation = Tween<Offset>(begin: _dragOffset, end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _springController, curve: Curves.elasticOut),
        );

    _springAnimation!.addListener(_onSpringAnimation);
    _springController.forward(from: 0).whenComplete(() {
      _springAnimation?.removeListener(_onSpringAnimation);
    });
    widget.verticalDragDelegate?.onBarDragEnd(
      details.velocity.pixelsPerSecond.dy,
    );
  }

  void _handleDestinationTap(int index) {
    // No haptic here: the shell fires one selection click for every tap, and it
    // is the only call site that covers both this bar and the wide-window rail.
    // Firing here as well buzzed twice on a tab change.
    widget.onDestinationSelected(index);
  }

  void _onSpringAnimation() {
    if (_springAnimation != null) {
      setState(() {
        _dragOffset = _springAnimation!.value;
      });
    }
  }

  /// The drag translate. With a vertical delegate attached the lift comes from
  /// it (a [ValueListenable], so only this transform rebuilds per frame);
  /// without one this is the original two-axis elastic offset.
  Widget _dragTransform({required Widget child}) {
    final delegate = widget.verticalDragDelegate;
    if (delegate == null) {
      return Transform.translate(
        key: const ValueKey('floating-nav-drag-transform'),
        offset: _dragOffset,
        child: child,
      );
    }
    return ValueListenableBuilder<double>(
      valueListenable: delegate.verticalLift,
      child: child,
      builder: (context, lift, inner) => Transform.translate(
        key: const ValueKey('floating-nav-drag-transform'),
        offset: Offset(_dragOffset.dx, _dragOffset.dy - lift),
        child: inner!,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    // Aspect-scoped for the same reason as
    // [FloatingNavBarMetrics.getScrollViewBottomPadding]: the bar is on screen
    // on every tab, so an unscoped subscription rebuilds it on every keyboard
    // frame.
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final barHeight = FloatingNavBarMetrics.barHeightFor(context);
    final isDark = colorScheme.brightness == Brightness.dark;
    final glassColor =
        theme.extension<CupolaThemeColors>()?.glassSurface ??
        colorScheme.surfaceContainer.withValues(alpha: isDark ? 0.72 : 0.55);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : colorScheme.outline.withValues(alpha: 0.85);
    final count = widget.destinations.length;
    final selected = widget.selectedIndex >= 0 && widget.selectedIndex < count
        ? widget.selectedIndex
        : null;

    return GestureDetector(
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      // Only where the bar is drawn: the content scrolls under the slot
      // (`extendBody`), so an opaque slot ate every tap in its margins.
      behavior: HitTestBehavior.deferToChild,
      child: Padding(
        // Outer padding to make it float
        padding: EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          bottom: bottomPadding + FloatingNavBarMetrics.bottomPadding,
          top: FloatingNavBarMetrics.topPadding,
        ),
        child: _dragTransform(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: AppRadius.borderRadiusFull,
              boxShadow: AppElevation.glass(colorScheme),
            ),
            child: ClipRRect(
              borderRadius: AppRadius.borderRadiusFull,
              // Lit enamel: a sheen of the room in front at its top, gone by
              // 70% of its height, and its pill tinted by the same light
              // ([RoomSheen]).
              child: RoomSheen(
                builder: (context, sheen, pill) => Container(
                  key: const ValueKey('floating-nav-surface'),
                  height: barHeight,
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
                    borderRadius: AppRadius.borderRadiusFull,
                    border: Border.all(color: borderColor),
                  ),
                  padding: const EdgeInsets.all(_barPadding),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // Four columns of one width: every destination says its
                      // name, and the lit one is the pill that fills its column.
                      final column = count == 0
                          ? 0.0
                          : constraints.maxWidth / count;
                      return Stack(
                        children: [
                          if (selected != null)
                            AnimatedPositioned(
                              duration: AppAnimation.durationSm,
                              curve: AppAnimation.emphasizedCurve,
                              left: column * selected,
                              top: 0,
                              width: column,
                              height: constraints.maxHeight,
                              child: IgnorePointer(
                                child: DecoratedBox(
                                  key: const ValueKey('floating-nav-indicator'),
                                  // The room's strong fill, tinted by the light
                                  // of the room in front, and no edge: the pill
                                  // says "you are here" and nothing about which
                                  // section "here" is.
                                  decoration: BoxDecoration(
                                    color: pill,
                                    borderRadius: AppRadius.borderRadiusFull,
                                  ),
                                ),
                              ),
                            ),
                          Row(
                            children: [
                              for (var index = 0; index < count; index++)
                                Expanded(
                                  child: _NavBarItem(
                                    destination: widget.destinations[index],
                                    isSelected: index == selected,
                                    index: index,
                                    destinationCount: count,
                                    onTap: () => _handleDestinationTap(index),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Between the glass's edge and the pill.
  static const double _barPadding = FloatingNavBarMetrics.surfacePadding;
}

class _NavBarItem extends StatelessWidget {
  /// The glyph, the rail's size: the two are one control on two devices.
  static const double iconSize = 20.0;

  /// Between the glyph and its name.
  static const double labelGap = AppSpacing.xxs;

  /// How far a count badge reaches past the icon's right edge.
  static const double badgeOverhang = 6.0;

  final FloatingNavDestination destination;
  final bool isSelected;

  /// Zero-based position in the bar, announced as "Tab 2 of 4".
  final int index;
  final int destinationCount;

  final VoidCallback onTap;

  const _NavBarItem({
    required this.destination,
    required this.isSelected,
    required this.index,
    required this.destinationCount,
    required this.onTap,
  });

  /// A destination's name: `labelMedium`, a step heavier where lit, as the
  /// rail's names.
  static TextStyle labelStyleOf(BuildContext context, {bool lit = true}) =>
      Theme.of(
        context,
      ).textTheme.labelMedium!.weight(lit ? FontWeight.w600 : FontWeight.w500);

  /// Height of the glyph over its name at the current reading size.
  static double contentHeightFor(TextScaler scaler, TextStyle labelStyle) =>
      iconSize +
      labelGap +
      scaler.scale(labelStyle.fontSize ?? 12) * (labelStyle.height ?? 1.0);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final scaler = FloatingNavBarMetrics.effectiveTextScaler(context);

    // Monochrome: the selected icon and label are the primary ink on the
    // strong fill, the rest the secondary ink. Both are the room's own inks,
    // spaced for the surfaces they sit on, so there is no hue to walk and
    // nothing a section could make fail in daylight.
    final itemColor = isSelected
        ? colorScheme.onSurface
        : colorScheme.onSurfaceVariant;

    // Rail parity: NavigationRail and NavigationBar both append this. '\n'
    // is the separator Flutter itself uses when merging labels, so the string
    // is byte-identical to Material's.
    final indexLabel = MaterialLocalizations.of(
      context,
    ).tabLabel(tabIndex: index + 1, tabCount: destinationCount);

    return Semantics(
      key: ValueKey('floating-nav-item-${destination.label.toLowerCase()}'),
      button: true,
      container: true,
      excludeSemantics: true,
      // The badge draws a number the screen reader cannot see, so the count
      // joins the spoken label rather than living only in the paint.
      label: destination.badgeSemanticLabel == null
          ? '${destination.label}\n$indexLabel'
          : '${destination.label}, ${destination.badgeSemanticLabel}\n$indexLabel',
      selected: isSelected,
      enabled: true,
      onTap: onTap,
      customSemanticsActions: destination.customSemanticsActions,
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
                  isSelected ? destination.selectedIcon : destination.icon,
                  key: ValueKey(isSelected),
                  color: itemColor,
                  size: iconSize,
                ),
              ),
            ),
            const SizedBox(height: labelGap),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
              child: Text(
                destination.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                // Clamped scaler: the bar was measured with it.
                textScaler: scaler,
                style: labelStyleOf(
                  context,
                  lit: isSelected,
                ).copyWith(color: itemColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A count on a navigation icon: the phone's bar and the tablet's rail
/// draw the same one.
///
/// Deliberately ink rather than a status tone; see
/// [FloatingNavDestination.badgeCount]. Excluded from semantics because the
/// destination already speaks the count in its label; a second node would read
/// the number twice.
class NavBadgedIcon extends StatelessWidget {
  const NavBadgedIcon({
    super.key,
    required this.count,
    required this.label,
    required this.child,
  });

  final int count;
  final String label;
  final Widget child;

  /// The badge's height at the default reading size.
  static const double _minSize = 15.0;
  static const double _collarWidth = 1.5;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return child;
    final colorScheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          child,
          Positioned(
            top: -4,
            right: -_NavBarItem.badgeOverhang,
            child: Container(
              key: const ValueKey('floating-nav-badge'),
              // A floor, not a height: the numeral grows with the bar's own
              // clamped reading size, and a fixed 15pt box clipped it to an
              // unreadable sliver at 2x.
              constraints: const BoxConstraints(
                minWidth: _minSize,
                minHeight: _minSize,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                // The ink disc: the primary ink, the fill of the ink button.
                color: colorScheme.primary,
                borderRadius: BorderRadius.circular(AppRadius.full),
                border: Border.all(
                  color: colorScheme.surface,
                  width: _collarWidth,
                ),
              ),
              child: Text(
                label,
                // The label's clamp, so the count grows with the reading size
                // exactly as far as the bar around it does, and no further.
                textScaler: FloatingNavBarMetrics.effectiveTextScaler(context),
                style: Theme.of(context).textTheme.labelSmall
                    ?.weight(FontWeight.w600)
                    .tabular
                    .copyWith(
                      // The on-ink numeral: the ink button's own label colour,
                      // spaced against the ink by the theme in both rooms.
                      color: colorScheme.onPrimary,
                      height: 1,
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
