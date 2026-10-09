import 'package:flutter/material.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';

/// One section of Activity: its name over a slab of rows.
///
/// The name sits on the page, above the slab, with what the section counts at
/// its end (`4 moving · 1 stuck`); when [onOpen] is given the count leads to
/// the section's own view, with a chevron. A section with nothing to say is
/// not drawn: the page decides that, never an empty slab.
class ActivitySection extends StatelessWidget {
  const ActivitySection({
    super.key,
    required this.title,
    required this.children,
    this.meta,
    this.onOpen,
    this.openHint,
    this.semanticLabel,
    this.slabPadding = const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
  });

  /// The section's name: `Downloads`, `Finished today`.
  final String title;

  /// What it counts, at the end of the name's line: `4 moving · 1 stuck`.
  final String? meta;

  /// Where the count leads.
  final VoidCallback? onOpen;

  /// Where [onOpen] leads, to a screen reader: `Opens Downloads`.
  final String? openHint;

  /// The heading as a screen reader says it, when the name and the count are
  /// not the whole sentence.
  final String? semanticLabel;

  final EdgeInsets slabPadding;

  /// The rows, on the slab.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final metaStyle = AppType.meta.copyWith(color: room.inkSecondary);
    final open = onOpen;
    final count = meta == null
        ? null
        : Text(
            meta!,
            style: open == null
                ? metaStyle
                : metaStyle.weight(FontWeight.w600).tabular,
          );
    final stacked = MediaQuery.textScalerOf(context).scale(10) >= 13;
    final titleText = Text(
      title,
      style: AppType.section.copyWith(color: room.ink),
    );
    final heading = Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.section,
        AppSpacing.gutter,
        AppSpacing.md,
      ),
      child: Semantics(
        header: true,
        label: semanticLabel ?? [title, ?meta].join(', '),
        button: open != null,
        hint: openHint,
        onTap: open,
        excludeSemantics: true,
        child: Flex(
          // At a large reading size the count goes under the name: beside
          // it, the name broke inside its words.
          direction: stacked ? Axis.vertical : Axis.horizontal,
          crossAxisAlignment: stacked
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            if (stacked) titleText else Expanded(child: titleText),
            if (count != null) ...[
              if (!stacked) const SizedBox(width: AppSpacing.md),
              if (open == null)
                count
              else
                InkWell(
                  onTap: open,
                  borderRadius: AppRadius.borderRadiusSm,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        count,
                        const SizedBox(width: AppSpacing.xxs),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 16,
                          color: room.inkSecondary,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
          child: ActivitySlab(padding: slabPadding, children: children),
        ),
      ],
    );
  }
}

/// The slab Activity's rows sit on.
class ActivitySlab extends StatelessWidget {
  const ActivitySlab({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
  });

  final List<Widget> children;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: room.slab,
        borderRadius: AppRadius.borderRadiusSlab,
        border: Border.all(color: room.hair),
      ),
      child: ClipRRect(
        borderRadius: AppRadius.borderRadiusSlab,
        child: Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }
}

/// A line of rows inside a slab that leads on: `All 48 requests` and what it
/// counts, with a chevron, over a hairline.
class ActivitySlabLink extends StatelessWidget {
  const ActivitySlabLink({
    super.key,
    required this.label,
    required this.onTap,
    this.meta,
    this.divided = true,
  });

  final String label;
  final String? meta;
  final VoidCallback onTap;

  /// Whether a hairline separates it from the rows above.
  final bool divided;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: divided ? Border(top: BorderSide(color: room.hair)) : null,
      ),
      child: Semantics(
        button: true,
        label: [label, ?meta].join(', '),
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: AppType.label.copyWith(color: room.inkSecondary),
                  ),
                ),
                if (meta case final meta?) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Flexible(
                    child: Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.meta.copyWith(color: room.inkTertiary),
                    ),
                  ),
                ],
                const SizedBox(width: AppSpacing.xxs),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: room.inkSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
