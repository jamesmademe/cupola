import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/status_badge.dart';

/// A page's views, side by side in one track: one of them is the page.
///
/// The control at the head of a tab's root page whose views are whole pages
/// with their own addresses (Activity's All · Downloads · Requests ·
/// History). A choice inside a section keeps [SelectionPills]; this is the
/// page's own, so every view is on screen at once and none scrolls away.
///
/// A segment may carry a count after its label (`Need you 6`), in a tone when
/// the count is one ([countOf]): the Review of blocked imports jumps between
/// its two parts this way.
///
/// The views share the track equally. When a label no longer fits its share
/// (a long word, a large reading size) the track lays them two by two, so a
/// word is never cut and the target never shrinks.
class PageTabs<T> extends StatelessWidget {
  const PageTabs({
    super.key,
    required this.values,
    required this.selected,
    required this.labelBuilder,
    required this.onSelected,
    this.semanticLabel = 'Show',
    this.countOf,
  });

  final List<T> values;
  final T selected;
  final String Function(T value) labelBuilder;
  final ValueChanged<T> onSelected;

  /// What the group is, to a screen reader.
  final String semanticLabel;

  /// The count a segment carries after its label, and its tone, or null for
  /// none.
  final ({int count, StatusTone? tone})? Function(T value)? countOf;

  String _measured(T value) => switch (countOf?.call(value)) {
    final count? => '${labelBuilder(value)}  ${count.count}',
    null => labelBuilder(value),
  };

  /// Each segment's target at the default reading size: the track is this
  /// and its border.
  static const double height = 44;

  /// How far the thumb stands inside its segment's target, and so inside the
  /// track.
  static const double _inset = 2;

  /// The gap between two segments.
  static const double _gap = 2;

  /// The track's corner; the thumb's is the track's less its inset.
  static const double _radius = 14;

  /// A segment's label on each side, before it no longer fits its share.
  static const double _labelPadding = AppSpacing.xs;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final style = AppType.label;
    final scaler = MediaQuery.textScalerOf(context);
    return Semantics(
      container: true,
      label: semanticLabel,
      child: LayoutBuilder(
        builder: (context, box) {
          // The track's border, then each segment's own inset.
          final inner = box.maxWidth - 2;
          final share =
              (inner - (values.length - 1) * _gap) / values.length - 2 * _inset;
          var widest = 0.0;
          for (final value in values) {
            final painter = TextPainter(
              text: TextSpan(text: _measured(value), style: style),
              textScaler: scaler,
              textDirection: Directionality.of(context),
              maxLines: 1,
            )..layout();
            if (painter.width > widest) widest = painter.width;
            painter.dispose();
          }
          final columns =
              widest + 2 * _labelPadding <= share || values.length < 3
              ? values.length
              : 2;
          final rows = <List<T>>[
            for (var start = 0; start < values.length; start += columns)
              values.sublist(start, (start + columns).clamp(0, values.length)),
          ];
          return DecoratedBox(
            decoration: BoxDecoration(
              color: room.fillQuiet,
              borderRadius: BorderRadius.circular(_radius),
              border: Border.all(color: room.hair),
            ),
            child: Padding(
              padding: const EdgeInsets.all(1),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (index, row) in rows.indexed) ...[
                    if (index > 0) const SizedBox(height: _gap),
                    Row(
                      children: [
                        for (final (position, value) in row.indexed) ...[
                          if (position > 0) const SizedBox(width: _gap),
                          Expanded(
                            child: _Segment(
                              label: labelBuilder(value),
                              count: countOf?.call(value),
                              selected: value == selected,
                              style: style,
                              onTap: () => onSelected(value),
                            ),
                          ),
                        ],
                        // A short last row keeps its segments the width of
                        // the ones above.
                        for (var i = row.length; i < columns; i++) ...[
                          const SizedBox(width: _gap),
                          const Expanded(child: SizedBox.shrink()),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    this.count,
    required this.selected,
    required this.style,
    required this.onTap,
  });

  final String label;
  final ({int count, StatusTone? tone})? count;
  final bool selected;
  final TextStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final count = this.count;
    final countColor = count?.tone == null
        ? null
        : statusToneColor(
            scheme,
            count!.tone!,
            surface: selected ? scheme.primary : CupolaRoom.of(context).slab,
          );
    final room = CupolaRoom.of(context);
    final still = MediaQuery.disableAnimationsOf(context);
    final duration = still ? Duration.zero : AppAnimation.durationLg;
    const radius = BorderRadius.all(
      Radius.circular(PageTabs._radius - 1 - PageTabs._inset),
    );
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: count == null ? label : '$label, ${count.count}',
      onTap: selected ? null : onTap,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        // The whole segment is the target, 44 tall; the thumb is drawn
        // inside it.
        child: InkWell(
          onTap: selected
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  onTap();
                },
          borderRadius: BorderRadius.circular(PageTabs._radius - 1),
          child: Padding(
            padding: const EdgeInsets.all(PageTabs._inset),
            child: AnimatedContainer(
              duration: duration,
              curve: AppAnimation.standardCurve,
              constraints: const BoxConstraints(
                minHeight: PageTabs.height - 2 * PageTabs._inset,
              ),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(
                horizontal: PageTabs._labelPadding,
                vertical: AppSpacing.xxs,
              ),
              decoration: BoxDecoration(
                color: selected ? scheme.primary : Colors.transparent,
                borderRadius: radius,
              ),
              child: AnimatedDefaultTextStyle(
                duration: duration,
                curve: AppAnimation.standardCurve,
                style: style.copyWith(
                  color: selected ? scheme.onPrimary : room.inkSecondary,
                ),
                child: Text.rich(
                  TextSpan(
                    text: label,
                    children: [
                      if (count != null)
                        TextSpan(
                          text: '  ${count.count}',
                          style: TextStyle(
                            color: countColor,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.fade,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
