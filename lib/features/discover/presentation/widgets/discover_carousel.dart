import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/core/widgets/app_skeleton.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/widgets/fault_note.dart';
import 'package:cupola/core/widgets/inline_error_retry.dart';
import 'package:cupola/core/widgets/section_header.dart';
import 'package:cupola/core/widgets/staggered_entrance.dart';
import 'package:cupola/features/discover/presentation/widgets/catalog_poster.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/service_not_configured.dart';

/// A single premium discover row: a section header + horizontal poster
/// carousel. Collapses to nothing when Seerr answered with nothing (an empty
/// genre simply does not render).
///
/// A row whose source **failed** is not a row with nothing in it. It used to
/// collapse the same way: Seerr's reads turned every failure into `[]`, so a
/// dark Seerr quietly took its rails off the page and the page looked like a
/// short catalogue. It now keeps its header and says what happened, in the
/// classified words, with Retry: "Seerr did not answer" only when nothing did.
///
/// **A row that has its posters keeps them.** Asked again (a lens that moved,
/// a connection that changed), it does not drop back to its skeleton, and when
/// that read fails it does not swap them for a line: what it had is what the
/// person last saw, and a page that wants the failure said says it once for
/// all its rows (the requester's Home above everything, the atrium from its
/// Trending canary). A row with no posters and a failed read says it itself,
/// as above. A Home's last drawing of a shelf is handed in as the posters it
/// has (`homeShelfOf`), and is kept the same way.
class DiscoverCarousel extends StatelessWidget {
  final String title;

  /// Unique id used for Hero tags in this row (e.g. 'trending', 'genre_28').
  final String sectionId;

  final AsyncValue<List<MediaPreview>> items;

  /// Forces the media type for detail navigation (movie rows vs tv rows).
  final String? forcedMediaType;

  final VoidCallback? onSeeAll;

  /// Asks for this row again after it failed. Without one, a failure is
  /// said with no Retry beside it: a Retry with nothing behind it would be a
  /// control that fails.
  final VoidCallback? onRetry;

  /// A line under the title: where the row comes from, how it is ordered.
  final String? subtitle;

  /// The line under a title in place of TMDB's score (`Out 14 Oct`), or
  /// null to keep the score.
  final String? Function(MediaPreview item)? metaOf;

  static const double _posterWidth = 104;
  static const double _posterHeight = 156;

  /// How far the heading and the first poster stand from the row's edges.
  ///
  /// The row spans the page so its posters scroll to the page's edge, and the
  /// page's own margin goes here, so the first poster stands on the line of
  /// the column above it: a row cut off at the column's edge on a wide page
  /// reads as broken, with nothing beside the cut.
  final double inset;

  const DiscoverCarousel({
    super.key,
    required this.title,
    required this.sectionId,
    required this.items,
    this.forcedMediaType,
    this.onSeeAll,
    this.onRetry,
    this.subtitle,
    this.metaOf,
    this.inset = AppSpacing.lg,
  });

  @override
  Widget build(BuildContext context) {
    // While loading, show a header + skeleton rail so layout doesn't jump;
    // once there are posters, a reload or a failed read leaves them be.
    return items.when(
      skipLoadingOnReload: true,
      skipError: true,
      loading: () => _shell(
        child: AppSkeleton.posterRow(height: _posterHeight, inset: inset),
      ),
      error: (error, _) {
        // A Seerr nobody set up is the page's to say, once, not every row's.
        // Matched on the type the app throws for it, as `AsyncValueWidget` does.
        if (error is ServiceNotConfigured) {
          return const SizedBox.shrink();
        }
        final message =
            '${describeFailureOf(ServiceKey.seerr, error).headline}, '
            'so this row is missing.';
        final retry = onRetry;
        return _shell(
          // On the heading's line: the retry line keeps a margin of its own.
          child: retry != null
              ? Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: inset - AppSpacing.lg,
                  ),
                  child: InlineErrorRetry(
                    message: message,
                    error: error,
                    service: ServiceKey.seerr,
                    onRetry: retry,
                  ),
                )
              : Padding(
                  padding: EdgeInsets.symmetric(horizontal: inset),
                  child: failureDidNotAnswer(classifyConnectionFailure(error))
                      ? FaultNote.unreachable(message: message)
                      : FaultNote.fault(message: message),
                ),
          // The skeleton's height is the rail's; the line is not a rail, and
          // the page should not hold a poster-sized gap under it.
          compact: true,
        );
      },
      data: (list) {
        if (list.isEmpty) return const SizedBox.shrink();
        return _shell(
          child: SizedBox(
            height: CatalogPoster.heightFor(context, _posterWidth),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: inset),
              itemCount: list.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(width: AppSpacing.carouselGap),
              itemBuilder: (context, index) =>
                  _tile(context, list[index], index),
            ),
          ),
        );
      },
    );
  }

  Widget _shell({required Widget child, bool compact = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The heading pads itself by the default margin.
        Padding(
          padding: EdgeInsets.symmetric(horizontal: inset - AppSpacing.lg),
          child: SectionHeader(
            title: title,
            subtitle: subtitle,
            // Nothing to see all of when the row failed.
            showChevron: onSeeAll != null && !compact,
            onTap: compact ? null : onSeeAll,
          ),
        ),
        SizedBox(height: compact ? 0 : AppSpacing.md),
        child,
        SizedBox(height: compact ? AppSpacing.md : AppSpacing.xl),
      ],
    );
  }

  Widget _tile(BuildContext context, MediaPreview item, int index) {
    return StaggeredEntrance(
      index: index,
      child: CatalogPoster(
        item: item,
        heroTag: 'discover_${sectionId}_${item.id}',
        width: _posterWidth,
        mediaType: forcedMediaType,
        meta: metaOf?.call(item),
      ),
    );
  }
}
