import 'package:flutter/material.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/core/widgets/app_empty_state.dart';
import 'package:cupola/core/widgets/content_card.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/widgets/media_poster_card.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';
import 'package:cupola/core/widgets/staggered_entrance.dart';
import 'package:cupola/core/widgets/status_badge.dart';

/// Callback signature for when a media item is tapped.
typedef OnMediaItemTap<T> = void Function(T item, String heroTag);

/// Callback signature for extracting a resolved status from a media item.
///
/// The caller resolves the status — including the download queue — so the grid
/// and the item's detail page cannot show different badges for the same item.
typedef StatusExtractor<T> = MediaStatusInfo? Function(T item);

/// A reusable grid widget for displaying media items (movies, series, music).
///
/// This widget provides a consistent 3-column grid layout with poster images,
/// status badges, and Hero transition support. Following Material Design 3.
class MediaGrid<T> extends StatelessWidget {
  /// The list of media items to display.
  final List<T> items;

  /// Extracts the images list from an item for poster URL resolution.
  final List<dynamic>? Function(T item) imagesExtractor;

  /// Extracts a unique ID from an item for Hero tags.
  final int Function(T item) idExtractor;

  /// Optional: Extracts status info for badge display.
  final StatusExtractor<T>? statusExtractor;

  /// Optional: Extracts the item's title, used as the accessible name.
  ///
  /// Without it each cell is an unlabelled poster image and a screen reader has
  /// nothing to announce.
  final String Function(T item)? titleExtractor;

  /// Base URL for authenticated image URLs.
  final String baseUrl;

  /// API key for authenticated image URLs.
  final String apiKey;

  /// Prefix for Hero tags (e.g., 'movie', 'series', 'artist').
  final String heroTagPrefix;

  /// Callback when an item is tapped.
  final OnMediaItemTap<T>? onItemTap;

  /// Cover types to search for in images.
  final List<String> coverTypes;

  /// Scroll physics. Use AlwaysScrollableScrollPhysics for RefreshIndicator.
  final ScrollPhysics? physics;

  /// Minimum number of columns; more are used when the window is wide enough.
  ///
  /// This is a floor rather than a fixed count so an iPad or a resized macOS
  /// window fills with more posters instead of stretching three of them to
  /// several hundred points each.
  final int crossAxisCount;

  const MediaGrid({
    super.key,
    required this.items,
    required this.imagesExtractor,
    required this.idExtractor,
    this.statusExtractor,
    this.titleExtractor,
    required this.baseUrl,
    required this.apiKey,
    required this.heroTagPrefix,
    this.onItemTap,
    this.coverTypes = const ['poster', 'cover'],
    this.physics,
    this.crossAxisCount = 3,
  });

  /// The floor a poster is built on: below this width the artwork stops being
  /// readable as artwork and the title under it stops fitting. Chosen so a
  /// 390pt-wide phone keeps exactly three columns.
  ///
  /// The measurement this number exists to forbid: a 640pt well asked for the
  /// most columns it could fit answers **five at 118pt**, under the floor —
  /// where the same well, held to the floor, answers **four at 151pt**. Every
  /// grid in the app resolves its count through [columnsFor] for that reason;
  /// a delegate that rounds the count *up* from a maximum extent reproduces
  /// the 5-at-118 failure exactly, which is why none of them uses one.
  static const double tileWidthFloor = 130.0;

  /// Columns that fit [availableWidth] at or above [tileWidthFloor], never
  /// fewer than [minColumns].
  ///
  /// ## The column floor rule: fewer tiles, never smaller ones
  ///
  /// A narrower frame drops a column. It does **not** shrink the tiles to keep
  /// the count, which is the failure this arithmetic exists to prevent — a
  /// 640pt well drawn with five columns gives 118pt posters, under a floor the
  /// tile's own layout is built on, where the same well at four gives 151.
  ///
  /// [gap] is why the old form was wrong twice over. It divided by the tile
  /// width alone and ignored the spacing between columns entirely, so it
  /// answered with a count whose tiles could not actually be that wide: `n`
  /// columns carry `n - 1` gaps, and the real tile width is
  /// `(available - (n - 1) * gap) / n`. Solving that for the floor gives the
  /// expression below, which is the *only* arrangement where every tile clears
  /// [tileWidthFloor].
  ///
  /// [minColumns] stays a floor on the count for the phone, where two enormous
  /// posters would be a worse answer than three correct ones.
  static int columnsFor(
    double availableWidth,
    int minColumns, {
    double gap = AppSpacing.gridGap,
  }) {
    final fits = ((availableWidth + gap) / (tileWidthFloor + gap)).floor();
    return fits > minColumns ? fits : minColumns;
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const AppEmptyState(
        icon: Icons.movie_filter_outlined,
        title: 'No items found',
      );
    }

    // The grid's own constraints, not the window's. `MediaQuery.sizeOf` is the
    // whole window, and on a desktop shell the grid is nothing like the whole
    // window: a 1920pt frame with the 232pt rail and a 400pt inspector open
    // leaves this widget about 500pt, and measuring the window answered
    // fourteen columns of 24pt posters. The same thing happens, less
    // spectacularly, inside the content well on every wide layout.
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = columnsFor(
          constraints.maxWidth - (AppSpacing.lg * 2),
          crossAxisCount,
        );
        return _grid(context, columns);
      },
    );
  }

  Widget _grid(BuildContext context, int columns) {
    return GridView.builder(
      physics: physics ?? const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.lg,
        bottom:
            AppSpacing.lg +
            FloatingNavBarMetrics.getScrollViewBottomPadding(context),
      ),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        childAspectRatio: 2 / 3,
        crossAxisSpacing: AppSpacing.gridGap,
        mainAxisSpacing: AppSpacing.gridGap,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final images = imagesExtractor(item);
        final itemId = idExtractor(item);

        final imageSource = ImageUtils.extractPosterUrl(
          images,
          baseUrl: baseUrl,
          apiKey: apiKey,
          coverTypes: coverTypes,
        );

        // Include index to ensure uniqueness for search results where id may be 0
        final heroTag = '${heroTagPrefix}_${itemId}_$index';

        // Extract status for badge
        Widget? badge;
        final statusInfo = statusExtractor?.call(item);
        final title = titleExtractor?.call(item);
        if (statusInfo != null) {
          badge = StatusBadge(
            info: statusInfo,
            compact: true,
            // With a title the cell publishes one node and drops the child
            // subtree, so the badge's own node would be discarded anyway and
            // the status rides on `semanticValue` instead. Without a title
            // there is nothing to exclude, so the badge speaks for itself.
            excludeFromSemantics: title != null,
          );
        }

        return StaggeredEntrance(
          index: index,
          wrapCount: columns * 4,
          child: PressableScale(
            onTap: onItemTap != null ? () => onItemTap!(item, heroTag) : null,
            semanticLabel: title,
            // Only alongside a label: a node carrying a value and no name
            // announces "Downloading" with nothing to attach it to.
            semanticValue: title == null ? null : statusInfo?.semanticLabel,
            excludeChildSemantics: title != null,
            child: Hero(
              tag: heroTag,
              transitionOnUserGestures: MediaPosterCard.flightOnUserGestures,
              child: ContentCard(
                imageUrl: imageSource.url,
                httpHeaders: imageSource.headers,
                badge: badge,
              ),
            ),
          ),
        );
      },
    );
  }
}
