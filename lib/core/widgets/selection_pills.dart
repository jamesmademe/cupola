import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/generated/design_tokens.g.dart';
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
  /// clipping at the column — right for a host that spans the screen.
  final EdgeInsetsGeometry padding;

  /// The screen-gutter inset, for a row that spans the screen.
  static const EdgeInsetsGeometry gutter = EdgeInsets.fromLTRB(
    AppSpacing.lg,
    0,
    AppSpacing.lg,
    AppSpacing.sm,
  );

  /// No side inset: [SelectionPills.wrap] sits on its host's gutter.
  static const EdgeInsetsGeometry _wrapPadding = EdgeInsets.only(
    bottom: AppSpacing.sm,
  );

  const SelectionPills({
    super.key,
    required this.values,
    required this.selected,
    required this.labelBuilder,
    required this.onSelected,
    this.padding = gutter,
  }) : _wraps = false;

  /// The pills on as many lines as they need, with no row to scroll.
  ///
  /// For a choice the user has to see whole: a setting with a handful of
  /// answers, where a pill scrolled off the edge is an answer that does not
  /// exist (the Access row's four, `Custom headers` cut to `Cust…` on a
  /// 390pt phone). A view switcher keeps the scrolling row, which is the one
  /// line a section can spare. Sits on its host's gutter, with no side inset.
  const SelectionPills.wrap({
    super.key,
    required this.values,
    required this.selected,
    required this.labelBuilder,
    required this.onSelected,
  }) : padding = _wrapPadding,
       _wraps = true;

  final bool _wraps;

  @override
  Widget build(BuildContext context) {
    if (_wraps) {
      return Padding(
        padding: padding,
        child: Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final value in values)
              // Sized by its label. The pill centres its label by filling
              // what it is given, which in a scrolling row (or a pinned
              // header that sets its height) is its own width; a wrap gives
              // it the whole line, so it is held to its label's width here.
              IntrinsicWidth(
                child: SelectionPill(
                  label: labelBuilder(value),
                  selected: value == selected,
                  onTap: () => onSelected(value),
                ),
              ),
          ],
        ),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      child: Row(
        children: [
          for (final value in values)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: _InView(
                selected: value == selected,
                child: SelectionPill(
                  label: labelBuilder(value),
                  selected: value == selected,
                  onTap: () => onSelected(value),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Keeps the chosen pill of a scrolling row in view, with the least scroll
/// that shows it whole: at once when the row first draws with it past the
/// edge, with the row's motion when it is chosen.
///
/// The row's order never changes for it. The atrium once moved the open index
/// to the head of its row so it could not sit off the edge, and a row that
/// reshuffled under the finger read as a different row (11/10).
class _InView extends StatefulWidget {
  const _InView({required this.selected, required this.child});

  final bool selected;
  final Widget child;

  @override
  State<_InView> createState() => _InViewState();
}

class _InViewState extends State<_InView> {
  @override
  void initState() {
    super.initState();
    if (widget.selected) _revealAfterLayout(animate: false);
  }

  @override
  void didUpdateWidget(_InView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected && !oldWidget.selected) {
      _revealAfterLayout(animate: true);
    }
  }

  void _revealAfterLayout({required bool animate}) =>
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(animate));

  void _reveal(bool animate) {
    if (!mounted) return;
    final pill = context.findRenderObject();
    final position = Scrollable.maybeOf(context)?.position;
    if (pill == null || position == null || !position.hasContentDimensions) {
      return;
    }
    final viewport = RenderAbstractViewport.maybeOf(pill);
    if (viewport == null) return;
    // The offsets that put the pill at the row's end and at its start: any
    // offset between the two shows it whole.
    final atEnd = viewport.getOffsetToReveal(pill, 1).offset;
    final atStart = viewport.getOffsetToReveal(pill, 0).offset;
    final target = position.pixels
        .clamp(atEnd, atStart)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if (target == position.pixels) return;
    if (animate && !MediaQuery.disableAnimationsOf(context)) {
      position.animateTo(
        target,
        duration: AppAnimation.durationMd,
        curve: AppAnimation.standardCurve,
      );
    } else {
      position.jumpTo(target);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// One pill of the row, on its own: a toggle (`Under 100 min`) or a pill
/// that opens a choice (`Popular`, with [trailing]'s chevron), in the same
/// drawing as the row's so the controls of one page speak one language.
class SelectionPill extends StatelessWidget {
  /// The finger's target, `size.touch` 44: the area grows, the drawing does
  /// not (brand book *Targets*). A floor, so it grows with the reading size.
  static const double _minTouchTarget = 44;

  /// The drawn pill, `size.chip` 36, centred in the target. It was drawn at
  /// the target's 48 itself.
  static const double _pillHeight = DesignTokens.sizeChip;

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// A glyph after the label: the chevron of a pill that opens a choice.
  final IconData? trailing;

  const SelectionPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.trailing,
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
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: _minTouchTarget),
            child: Center(
              heightFactor: 1,
              child: _pill(theme, background, border, labelColor),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pill(
    ThemeData theme,
    Color background,
    Color border,
    Color labelColor,
  ) => Container(
    constraints: const BoxConstraints(minHeight: _pillHeight),
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
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            style: theme.textTheme.labelMedium!
                .weight(FontWeight.w600)
                .copyWith(color: labelColor),
          ),
        ),
        if (trailing case final trailing?) ...[
          const SizedBox(width: AppSpacing.xxs),
          Icon(trailing, size: 18, color: labelColor),
        ],
      ],
    ),
  );
}
