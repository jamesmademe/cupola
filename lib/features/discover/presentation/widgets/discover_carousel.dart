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

/// A single premium discover row: a section header + horizontal poster
/// carousel. Collapses to nothing when Seerr answered with nothing (an empty
/// genre simply does not render).
///
/// A row whose source **failed** is not a row with nothing in it. It used to
/// collapse the same way — Seerr's reads turned every failure into `[]` — so a
/// dark Seerr quietly took its rails off the page and the page looked like a
/// short catalogue. It now keeps its header and says what happened, in the
/// classified words, with Retry: "Seerr did not answer" only when nothing did.
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

  static const double _posterWidth = 104;
  static const double _posterHeight = 156;

  const DiscoverCarousel({
    super.key,
    required this.title,
    required this.sectionId,
    required this.items,
    this.forcedMediaType,
    this.onSeeAll,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    // While loading, show a header + skeleton rail so layout doesn't jump.
    return items.when(
      loading: () =>
          _shell(child: AppSkeleton.posterRow(height: _posterHeight)),
      error: (error, _) {
        // A Seerr nobody set up is the page's to say, once, not every row's.
        // Matched on the phrase the app throws for it; see `AsyncValueWidget`.
        if (error.toString().contains('not configured')) {
          return const SizedBox.shrink();
        }
        final message =
            '${describeFailureOf(ServiceKey.seerr, error).headline}, '
            'so this row is missing.';
        final retry = onRetry;
        return _shell(
          child: retry != null
              ? InlineErrorRetry(
                  message: message,
                  error: error,
                  service: ServiceKey.seerr,
                  onRetry: retry,
                )
              : failureDidNotAnswer(classifyConnectionFailure(error))
              ? FaultNote.unreachable(message: message)
              : FaultNote.fault(message: message),
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
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
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
        SectionHeader(
          title: title,
          // Nothing to see all of when the row failed.
          showChevron: onSeeAll != null && !compact,
          onTap: compact ? null : onSeeAll,
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
      ),
    );
  }
}
