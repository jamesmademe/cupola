import 'package:flutter/material.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';

/// A horizontally scrolling row of pills selecting one value along one axis.
///
/// This replaces two implementations of the same control that had drifted apart
/// inside a single feature: a `SegmentedButton` pinned in a fixed-height
/// `SliverPersistentHeader` on the per-service Activity screen, and a hand-rolled
/// chip on the global one. Between them they had three defects worth naming,
/// because each is a class of mistake rather than a one-off:
///
/// - The chip had **no semantics node at all** — no button role, no accessible
///   name, no selected state — while a service tile 150 lines away in the same
///   file did all three correctly. It also skipped [PressableScale], which is
///   where the press animation, the haptic, the Reduce Motion check and the
///   button role live together; hand-rolling a tap silently drops all four.
/// - The chip hard-coded `BorderRadius.circular(20)` twice instead of taking a
///   token.
/// - The segmented button lived in a 56pt box with `minExtent == maxExtent`, so
///   at an accessibility reading size its label outgrew the header and Flutter
///   painted its overflow stripe across the control. Nothing here has a fixed
///   height; the pill is sized by its label, with a minimum for the touch target.
///
/// The selected pill borrows the navigation bar's treatment — [AppRadius.pill],
/// the room's strong fill, the primary ink — rather than inventing a third
/// "this one is active" language for the app. It is the same on every screen:
/// the room is monochrome, so no service or section colours the pill. It is
/// deliberately **not** [AppRadius.full]: full radius means metadata in this
/// system, so an interactive pill at full radius would read as a label.
class SelectionPills<T> extends StatelessWidget {
  final List<T> values;
  final T selected;
  final String Function(T value) labelBuilder;
  final ValueChanged<T> onSelected;

  /// The inset inside the scrolling row.
  ///
  /// The default puts the first pill on the screen gutter while the row itself
  /// runs edge to edge, so a scrolled pill bleeds off the screen instead of
  /// clipping at the column — right for a host that spans the screen. A host
  /// that already sits on the gutter (a detail slot, a padded card) passes
  /// [SelectionPills.flush], or its pills land a second gutter in from the
  /// label and summary above and below them.
  final EdgeInsetsGeometry padding;

  /// The screen-gutter inset, for a row that spans the screen.
  static const EdgeInsetsGeometry gutter = EdgeInsets.fromLTRB(
    AppSpacing.lg,
    0,
    AppSpacing.lg,
    AppSpacing.sm,
  );

  /// No side inset, for a row whose host is already on the gutter.
  static const EdgeInsetsGeometry flush = EdgeInsets.only(
    bottom: AppSpacing.sm,
  );

  const SelectionPills({
    super.key,
    required this.values,
    required this.selected,
    required this.labelBuilder,
    required this.onSelected,
    this.padding = gutter,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      child: Row(
        children: [
          for (final value in values)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: _Pill(
                label: labelBuilder(value),
                selected: value == selected,
                onTap: () => onSelected(value),
              ),
            ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  /// The stricter of the two platform minimums (48dp Android, 44pt iOS), applied
  /// as a floor rather than a fixed height so the pill can still grow with the
  /// reading size.
  static const double _minTouchTarget = 48;

  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Pill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final room = CupolaRoom.of(context);

    // The nav pill: the room's strong fill under the primary ink. The edge
    // stays in both states so a pill does not grow a pixel when it is chosen.
    final background = selected
        ? room.fillStrong
        : colorScheme.surfaceContainer;
    final border = selected ? room.edge : colorScheme.outlineVariant;
    final labelColor = selected
        ? colorScheme.onSurface
        : colorScheme.onSurfaceVariant;

    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: label,
      onTap: onTap,
      child: ExcludeSemantics(
        child: PressableScale(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: _minTouchTarget),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: background,
              borderRadius: AppRadius.borderRadiusPill,
              border: Border.all(color: border),
            ),
            child: Text(
              label,
              maxLines: 1,
              style: theme.textTheme.labelMedium!
                  .weight(FontWeight.w600)
                  .copyWith(color: labelColor),
            ),
          ),
        ),
      ),
    );
  }
}
