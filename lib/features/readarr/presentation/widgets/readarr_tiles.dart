import 'package:flutter/material.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/utils/unit_space.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/activity/domain/global_activity_status.dart';
import 'package:cupola/features/readarr/domain/models/readarr_models.dart';

/// Visual style (icon + colour + label) for a Readarr history event type.
///
/// **A reader of the shared \*arr table, not a third derivation of it.** This
/// function used to hold its own `switch`, and its default arm was
/// `eventType.toUpperCase()`: so `bookFileRenamed`, an event the shared table
/// has named all along, read "BOOKFILERENAMED" on the History tab while the
/// Readarr Overview, resolving the same record through
/// `historyEventDisplay`, read "Renamed". It also disagreed on `grabbed`,
/// which it toned blue while the table calls it neutral: a grab is the system
/// doing its job, on a list that is mostly grabs.
///
/// Only the *shape* is this file's: a badge string and an [IconData]. The label, the tone and the picture all come from the table.
({IconData icon, Color color, String label}) readarrEventStyle(
  String eventType,
  ColorScheme colorScheme,
) {
  final (label, tone) = historyEventDisplay(eventType);
  return (
    icon: _glyphIcon(historyEventGlyph(eventType)),
    // Walked, never the raw palette constant: on paper `AppColors.info`
    // measures 3.34:1 and `AppColors.success` 2.07:1, so a grab and an import
    // (the two events this list shows most) were the only ones in it that
    // could not be read in daylight.
    color: statusToneColor(colorScheme, tone),
    // The table's own sentence-case wording, unchanged. The badge used to
    // uppercase it, which made a dense label repeated on every row into a
    // second uppercase voice beside the eyebrow. An event the table has not
    // classified arrives humanised ("Author renamed").
    label: label,
  );
}

/// The picture for a [StatusGlyph], in this tile's own icon set.
///
/// Deliberately a local table rather than a reach into `status_badge.dart`:
/// that one is sized and weighted for a badge, these are the 16pt outline
/// icons this row's accent square has always drawn. The *choice* of glyph is
/// shared; the drawing of it is not.
IconData _glyphIcon(StatusGlyph? glyph) {
  return switch (glyph) {
    StatusGlyph.grabbed => Icons.download_rounded,
    StatusGlyph.imported => Icons.check_circle_rounded,
    StatusGlyph.failed => Icons.file_download_off_rounded,
    StatusGlyph.ignored => Icons.do_not_disturb_on_rounded,
    StatusGlyph.deleted => Icons.delete_outline_rounded,
    StatusGlyph.renamed => Icons.drive_file_rename_outline_rounded,
    StatusGlyph.blocked => Icons.block_rounded,
    // A retag, or an event nobody has classified. The generic history mark is
    // the honest picture for "something happened that has no shape".
    null => Icons.history_rounded,
  };
}

/// A bordered list row for a Readarr history event.
class ReadarrHistoryTile extends StatelessWidget {
  const ReadarrHistoryTile({super.key, required this.item});

  final ReadarrHistoryItem item;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final event = readarrEventStyle(item.eventType, colorScheme);
    final title = item.sourceTitle?.trim().isNotEmpty == true
        ? item.sourceTitle!
        : (item.authorName ?? 'Readarr activity');
    final subtitleParts = <String>[
      if (item.authorName != null && item.authorName!.isNotEmpty)
        item.authorName!,
      if (item.date != null) _relativeTime(item.date!),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      child: Material(
        color: colorScheme.surface,
        borderRadius: AppRadius.borderRadiusMd,
        child: Container(
          // The card padding of the Activity history rows, the app's other
          // bordered history card.
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            border: Border.all(color: colorScheme.outlineVariant),
            borderRadius: AppRadius.borderRadiusMd,
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: event.color.withValues(alpha: 0.12),
                  borderRadius: AppRadius.borderRadiusSm,
                ),
                alignment: Alignment.center,
                child: Icon(event.icon, size: 16, color: event.color),
              ),
              const SizedBox(width: AppSpacing.row),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(
                        context,
                      ).textTheme.titleSmall!.weight(FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitleParts.isNotEmpty)
                      Text(
                        subtitleParts.join(dotSeparator),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s,
                  vertical: AppSpacing.xxs,
                ),
                decoration: BoxDecoration(
                  color: event.color.withValues(alpha: 0.12),
                  borderRadius: AppRadius.borderRadiusSm,
                ),
                child: Text(
                  event.label,
                  style: Theme.of(context).textTheme.labelSmall!
                      .weight(FontWeight.w600)
                      .copyWith(color: event.color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _relativeTime(DateTime date) {
  final diff = DateTime.now().difference(date);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${withUnit(diff.inMinutes, 'min')} ago';
  if (diff.inHours < 24) return '${withUnit(diff.inHours, 'h')} ago';
  if (diff.inDays < 30) {
    return '${diff.inDays} ${diff.inDays == 1 ? 'day' : 'days'} ago';
  }
  final months = (diff.inDays / 30).floor();
  return '$months ${months == 1 ? 'month' : 'months'} ago';
}
