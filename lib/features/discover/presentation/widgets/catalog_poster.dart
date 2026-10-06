import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/core/text_scale.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/core/utils/unit_space.dart';
import 'package:cupola/core/widgets/content_card.dart';
import 'package:cupola/core/widgets/media_poster_card.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/discover/domain/seerr_status.dart';
import 'package:cupola/features/discover/presentation/discover_details_provider.dart';
import 'package:cupola/features/media/presentation/open_media.dart';

/// One title of Seerr's catalogue as a tile: the poster with what Seerr holds
/// of it in the corner, the title under it, and TMDB's score.
///
/// The state comes from the catalogue's own answer (`mediaInfo`), in the
/// words of whoever reads it (`seerrCatalogStatus`): nothing at all for a
/// title Seerr holds no record of. The tile speaks one sentence, the title
/// with its state and score, and silences its parts.
class CatalogPoster extends ConsumerWidget {
  const CatalogPoster({
    super.key,
    required this.item,
    required this.heroTag,
    required this.width,
    this.mediaType,
  });

  final MediaPreview item;
  final String heroTag;

  /// The tile's width; the poster is 2:3 inside it.
  final double width;

  /// The kind the row is about, when the row fixes it (a movie rail); else
  /// the item's own.
  final String? mediaType;

  /// Two lines of title and one of score, at the reading size the user chose
  /// up to the compact tile's ceiling (`TextScaleMetrics.clampedScalerOf`):
  /// past it the words ellipsise rather than break inside a word.
  static double heightFor(BuildContext context, double width) {
    final theme = Theme.of(context).textTheme;
    final scaler = TextScaleMetrics.clampedScalerOf(context);
    double line(TextStyle? style) =>
        scaler.scale(style?.fontSize ?? 14) * (style?.height ?? 1.3);
    return width * 3 / 2 +
        AppSpacing.sm +
        2 * line(_titleStyle(theme)) +
        line(_scoreStyle(theme));
  }

  static TextStyle? _titleStyle(TextTheme theme) =>
      theme.bodyMedium?.weight(FontWeight.w600);

  static TextStyle? _scoreStyle(TextTheme theme) => theme.bodySmall;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final imageUrl = ImageUtils.buildTmdbPosterUrl(item.posterPath);
    final status = seerrCatalogStatus(
      item.mediaInfo,
      numbering: ref.watch(seerrNumberingProvider).value,
      audience: ref.watch(audienceProvider),
    );
    final vote = item.voteAverage;
    // TMDB's zero is a title nobody has rated, not a score of nothing.
    final score = vote == null || vote <= 0
        ? null
        : 'TMDB$unitSpace${vote.toStringAsFixed(1)}';

    return SizedBox(
      width: width,
      child: PressableScale(
        onTap: () => context.openSeerrTitle(
          mediaType: mediaType ?? item.mediaType,
          id: item.id,
          heroTag: heroTag,
          posterUrl: imageUrl,
        ),
        semanticLabel: item.title,
        semanticValue: status == null && score == null
            ? null
            : [?status?.semanticLabel, ?score].join(', '),
        excludeChildSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: width,
              height: width * 3 / 2,
              child: Hero(
                tag: heroTag,
                transitionOnUserGestures: MediaPosterCard.flightOnUserGestures,
                child: ContentCard(
                  imageUrl: imageUrl,
                  paneTag: heroTag,
                  badge: status == null
                      ? null
                      : StatusBadge(
                          info: status,
                          compact: true,
                          excludeFromSemantics: true,
                        ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            // The words lay out on the same clamp the tile grew by.
            MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaleMetrics.clampedScalerOf(context)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: _titleStyle(
                      theme.textTheme,
                    )?.copyWith(color: theme.colorScheme.onSurface),
                  ),
                  if (score != null)
                    Text(
                      score,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _scoreStyle(
                        theme.textTheme,
                      )?.copyWith(color: CupolaThemeColors.of(context).dimText),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
