import 'package:flutter/material.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';

class MediaInfoCard extends StatelessWidget {
  final List<MediaInfoGroup> groups;

  /// Fields the page can write, each on its own full-width row above the grid.
  ///
  /// Rows rather than grid cells, and that is decision 25 rather than a layout
  /// preference: **a detail edits in place**, with a select on its own row on a
  /// window and a 44pt target opening one sheet per field on a phone. A cell in
  /// a two-column grid is neither — it is half a column wide, and its label is
  /// drawn by the grid rather than by the control, so the button would be
  /// announced by its value alone with the field name floating beside it as an
  /// unrelated fragment.
  ///
  /// Editable first, read-only under it: what you can change is worth more than
  /// what you can only read, and a control buried under eight facts is a control
  /// nobody finds.
  final List<Widget> rows;

  const MediaInfoCard({
    super.key,
    required this.groups,
    this.rows = const <Widget>[],
  });

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty && rows.isEmpty) {
      return const SizedBox.shrink();
    }

    final grid = _InfoGrid(
      cells: groups
          .map((group) => _InfoGridCell(label: group.title, child: group.child))
          .toList(growable: false),
    );

    if (rows.isEmpty) return grid;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.sm),
          rows[i],
        ],
        if (groups.isNotEmpty) ...[const SizedBox(height: AppSpacing.md), grid],
      ],
    );
  }
}

class MediaInfoGroup {
  final String title;
  final Widget child;

  const MediaInfoGroup({required this.title, required this.child});
}

class MediaFactsList extends StatelessWidget {
  final List<MediaFact> facts;

  const MediaFactsList({super.key, required this.facts});

  @override
  Widget build(BuildContext context) {
    if (facts.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return _InfoGrid(
      cells: facts
          .map(
            (fact) => _InfoGridCell(
              label: fact.label,
              child: Text(
                fact.value,
                // Facts are runtimes, sizes, bitrates and years as often as
                // words, and they stack in a two-column grid.
                style: theme.textTheme.bodySmall!
                    .weight(FontWeight.w600)
                    .tabular
                    .copyWith(color: colorScheme.onSurface, height: 1.3),
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _InfoGrid extends StatelessWidget {
  final List<_InfoGridCell> cells;

  const _InfoGrid({required this.cells});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useSingleColumn = constraints.maxWidth < 320;

        if (useSingleColumn) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < cells.length; i++) ...[
                if (i > 0) const SizedBox(height: AppSpacing.md),
                cells[i],
              ],
            ],
          );
        }

        // Pair cells into two-column rows so the columns stay aligned and share
        // a top baseline regardless of individual cell height. The previous
        // Wrap-of-fixed-width layout could wrap raggedly at sub-pixel widths,
        // producing the broken table that was reported.
        final rows = <Widget>[];
        for (var i = 0; i < cells.length; i += 2) {
          final right = i + 1 < cells.length ? cells[i + 1] : null;
          rows.add(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: cells[i]),
                const SizedBox(width: AppSpacing.lg),
                Expanded(child: right ?? const SizedBox.shrink()),
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.sm),
              rows[i],
            ],
          ],
        );
      },
    );
  }
}

class _InfoGridCell extends StatelessWidget {
  final String label;
  final Widget child;

  const _InfoGridCell({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          // One label per grid cell, repeated down the card: a plain dense
          // metadata label, not a region kicker, so it keeps the role's own
          // derived tracking rather than an authored overline.
          style: theme.textTheme.labelSmall!
              .weight(FontWeight.w700)
              .copyWith(color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 2),
        DefaultTextStyle.merge(
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall!
              .weight(FontWeight.w600)
              .copyWith(color: colorScheme.onSurface, height: 1.3),
          child: child,
        ),
      ],
    );
  }
}

class MediaFact {
  final String label;
  final String value;

  const MediaFact(this.label, this.value);
}
