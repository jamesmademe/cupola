/// The dense child row ([MediaChildTile]) and the status word its facts line
/// carries ([mediaStatusWord]).
///
/// It replaces three implementations of the same row that had drifted apart.
/// Between them they had three defects worth naming, because each is a class of
/// mistake rather than a one-off:
///
/// - **State by colour alone.** Both episode and track rows drew a 7pt circle
///   filled `colorScheme.primary` or `colorScheme.outline` — the same eight
///   lines copied into two files, in files with *zero* `Semantics`. Nothing on
///   the page said what the fill meant, and a screen reader got nothing at all.
///   Here the state is a resolved [MediaStatusInfo]: the tile speaks
///   [MediaStatusInfo.semanticLabel] as its value, draws it through
///   [StatusBadge], and the caller is required to put a status *word* in [facts]
///   for anything that is not plainly available.
/// - **A second accent.** That `primary` indigo landed on a violet Sonarr page
///   and a pink Lidarr page. Every colour here is the resolved status tone,
///   through [StatusBadge].
/// - **Nothing to decide with.** A row was a number, a one-line truncated title
///   and — twenty-five times over — the same magnifier glyph. [facts] is the
///   slot that fixes that, and both text runs wrap to two lines instead of
///   eliding at the first accessibility step.
library;

import 'package:flutter/material.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/text_scale.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/percent_format.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/media_metadata_line.dart';
import 'package:cupola/core/widgets/status_badge.dart';

/// The status as a word for a child row's [MediaChildTile.facts] line, or null
/// when the row needs none.
///
/// A [StatusBadge] in a dense row is a tone-coloured dot or glyph and nothing
/// more, so its meaning reaches a screen reader (through the tile's spoken
/// value) but not a sighted low-vision user. A wall of twenty-five quiet green
/// dots is correct and wants no text; the exceptions have to carry some. So this
/// returns the pipeline state while something is in flight, the status label
/// while anything is outstanding, and null once the row is simply on disk.
String? mediaStatusWord(MediaStatusInfo? status) {
  if (status == null) return null;
  final pipeline = status.pipeline;
  if (pipeline != null) {
    final percent = status.progressPercent;
    return percent == null
        ? pipeline.label
        : '${pipeline.label} ${formatPercent(percent)}';
  }
  if (status.availability == MediaAvailability.available) return null;
  return status.label;
}

/// One dense row inside a `container -> children` region: an episode, a track,
/// an album.
///
/// [MediaChildTile.numbered] leads with a tabular ordinal column.
class MediaChildTile extends StatelessWidget {
  /// Base width of the ordinal column at the default reading size.
  ///
  /// Grown by the clamped reading scale rather than fixed, and applied as a
  /// *minimum* so a long ordinal widens the column instead of clipping in it.
  /// Tabular figures then give `E8` and `E9`, or `E10` and `E11`, one width.
  static const double _ordinalBaseWidth = 30;

  final String? ordinal;

  /// What [ordinal] is, in words. `E4` reads as "E four" otherwise.
  ///
  /// Pass an empty string to drop it from the spoken name entirely, for a row
  /// whose title already says what the ordinal is.
  final String? ordinalLabel;

  final String title;

  /// Decidable metadata: an air date, a duration, counts, and — per
  /// [mediaStatusWord] — the status in words whenever the row is not plainly
  /// available. A row without at least one of these is the arr-web-UI table
  /// this region exists to replace.
  final List<String> facts;

  /// The resolved status, from the feature's `domain/` layer.
  ///
  /// Nullable on purpose. Seerr models availability per *season* and not per
  /// episode, so a Seerr episode row genuinely has no status of its own and
  /// inventing one would be worse than omitting it.
  final MediaStatusInfo? status;

  final VoidCallback? onTap;

  /// A control — a search menu — that stays reachable: it is the one slot this
  /// row does not silence.
  final Widget? trailing;

  final String? semanticHint;

  const MediaChildTile.numbered({
    super.key,
    required this.ordinal,
    required this.title,
    this.ordinalLabel,
    this.facts = const <String>[],
    this.status,
    this.onTap,
    this.trailing,
    this.semanticHint,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final resolvedStatus = status;

    final spokenLabel = <String>[
      if (ordinalLabel != null) ordinalLabel! else ?ordinal,
      title,
      ...facts.map(spokenPercents),
    ].where((part) => part.trim().isNotEmpty).join(', ');

    return AppCard.filled(
      // A ~56pt row floods its own splash, and a flooded ripple reads as
      // selection rather than as a touch — the Ripple-Needs-Room Rule. So the
      // row dips instead.
      pressFeedback: AppCardPressFeedback.scale,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      onTap: onTap,
      semanticLabel: spokenLabel,
      semanticValue: resolvedStatus?.semanticLabel,
      semanticHint: semanticHint,
      child: Row(
        children: [
          if (ordinal != null) ...[
            ExcludeSemantics(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: TextScaleMetrics.clampedScalerOf(
                    context,
                  ).scale(_ordinalBaseWidth),
                ),
                child: Text(
                  ordinal!,
                  // A fixed-width column of ordinals: tabular figures are what
                  // keep 09 and 10 aligned down the list.
                  style: theme.textTheme.labelSmall!
                      .weight(FontWeight.w600)
                      .tabular
                      .copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          Expanded(
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    // Two lines, not one: "a one-line truncated title" was the
                    // observed defect, and the row has no fixed height to
                    // protect.
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium!.weight(FontWeight.w600),
                  ),
                  if (facts.isNotEmpty)
                    MediaMetadataLine(items: facts, maxLines: 2),
                ],
              ),
            ),
          ),
          if (resolvedStatus != null) ...[
            const SizedBox(width: AppSpacing.sm),
            StatusBadge(
              info: resolvedStatus,
              iconOnly: true,
              // The tile's own node already speaks the status as its value;
              // without this the row and the badge are two stops for one fact.
              excludeFromSemantics: true,
            ),
          ],
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.xs),
            trailing!,
          ],
        ],
      ),
    );
  }
}
