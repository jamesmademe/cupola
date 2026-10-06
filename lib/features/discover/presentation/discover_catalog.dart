import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_gradients.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/content_card.dart';
import 'package:cupola/core/widgets/media_poster_card.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';
import 'package:cupola/features/discover/domain/models/seerr_genre.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/discover/presentation/widgets/discover_carousel.dart';
import 'package:cupola/features/discover/presentation/widgets/discover_region_chip.dart';
import 'package:cupola/features/discover/presentation/widgets/seerr_decisions_section.dart';
import 'package:cupola/features/media/presentation/open_media.dart';

/// Seerr's catalogue as rails: what the Discover tab shows at rest, before
/// anything is typed into its field. The tab decides whether Seerr is there to
/// ask; this draws the rails once it is.
class DiscoverCatalog extends ConsumerWidget {
  const DiscoverCatalog({super.key, this.bottomPadding = 0});

  /// The room the floating bar takes at the foot of the list.
  final double bottomPadding;

  /// How many genre rows to render on the catalog.
  static const _genreRowLimit = 8;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () async => invalidate(ref),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          top: AppSpacing.sm,
          bottom: AppSpacing.xl + bottomPadding,
        ),
        children: [
          // Decisions first, rails after: what is waiting on an approval is a
          // reason to open the catalogue that a trending rail is not. The
          // section draws nothing at all when nothing is waiting.
          const SeerrDecisionsSection(),
          // The readout that labels the rails below it — and not the decisions
          // above it, which no region touches: a label with a door, never a
          // filter.
          const Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.xs,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: DiscoverRegionChip(),
            ),
          ),
          const _DiscoverFeatured(),
          DiscoverCarousel(
            title: 'Trending',
            sectionId: 'trending',
            items: ref.watch(discoverTrendingProvider),
            onRetry: () => ref.invalidate(discoverTrendingProvider),
            onSeeAll: () => context.push(ServiceRoutes.discoverTrendingAll),
          ),
          DiscoverCarousel(
            title: 'Popular movies',
            sectionId: 'movies',
            items: ref.watch(discoverMoviesProvider),
            forcedMediaType: 'movie',
            onRetry: () => ref.invalidate(discoverMoviesProvider),
            onSeeAll: () => context.push(ServiceRoutes.discoverMoviesAll),
          ),
          DiscoverCarousel(
            title: 'Popular series',
            sectionId: 'tv',
            items: ref.watch(discoverTVProvider),
            forcedMediaType: 'tv',
            onRetry: () => ref.invalidate(discoverTVProvider),
            onSeeAll: () => context.push(ServiceRoutes.discoverTvAll),
          ),
          DiscoverCarousel(
            title: 'Upcoming movies',
            sectionId: 'upcoming_movies',
            items: ref.watch(discoverUpcomingMoviesProvider),
            forcedMediaType: 'movie',
            onRetry: () => ref.invalidate(discoverUpcomingMoviesProvider),
          ),
          DiscoverCarousel(
            title: 'Top rated movies',
            sectionId: 'top_rated',
            items: ref.watch(discoverTopRatedMoviesProvider),
            forcedMediaType: 'movie',
            onRetry: () => ref.invalidate(discoverTopRatedMoviesProvider),
          ),
          DiscoverCarousel(
            title: 'Upcoming series',
            sectionId: 'upcoming_tv',
            items: ref.watch(discoverUpcomingTvProvider),
            forcedMediaType: 'tv',
            onRetry: () => ref.invalidate(discoverUpcomingTvProvider),
          ),
          const _GenreRows(limit: _genreRowLimit),
        ],
      ),
    );
  }

  /// Asks Seerr for every rail again, the genre rows included.
  static void invalidate(WidgetRef ref) {
    ref.invalidate(discoverTrendingProvider);
    ref.invalidate(discoverMoviesProvider);
    ref.invalidate(discoverTVProvider);
    ref.invalidate(discoverUpcomingMoviesProvider);
    ref.invalidate(discoverUpcomingTvProvider);
    ref.invalidate(discoverTopRatedMoviesProvider);
    ref.invalidate(movieGenresProvider);
    ref.invalidate(discoverByGenreProvider);
    ref.invalidate(requestsProvider);
  }
}

/// Genre rows built from the available movie genres.
class _GenreRows extends ConsumerWidget {
  final int limit;

  const _GenreRows({required this.limit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final genresAsync = ref.watch(movieGenresProvider);
    return genresAsync.when(
      data: (genres) {
        final visible = genres.take(limit).toList(growable: false);
        return Column(
          children: [
            for (final genre in visible)
              _GenreCarousel(genre: genre, mediaType: 'movie'),
          ],
        );
      },
      // The genre rows are rails too: a list Seerr could not give says so,
      // once, under one header, rather than taking every genre row off the
      // page without a word.
      error: (error, _) => DiscoverCarousel(
        title: 'By genre',
        sectionId: 'genres',
        items: AsyncValue<List<MediaPreview>>.error(error, StackTrace.empty),
        onRetry: () => ref.invalidate(movieGenresProvider),
      ),
      loading: () => const SizedBox.shrink(),
    );
  }
}

class _GenreCarousel extends ConsumerWidget {
  final SeerrGenre genre;
  final String mediaType;

  const _GenreCarousel({required this.genre, required this.mediaType});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (mediaType: mediaType, genreId: genre.id);
    return DiscoverCarousel(
      title: genre.name,
      sectionId: 'genre_${genre.id}',
      items: ref.watch(discoverByGenreProvider(key)),
      forcedMediaType: mediaType,
      onRetry: () => ref.invalidate(discoverByGenreProvider(key)),
      onSeeAll: () => context.push(
        ServiceRoutes.discoverGenre(
          mediaType: mediaType,
          genreId: genre.id,
          title: genre.name,
        ),
      ),
    );
  }
}

/// Cinematic featured banner built from the first trending item.
class _DiscoverFeatured extends ConsumerWidget {
  const _DiscoverFeatured();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trending = ref.watch(discoverTrendingProvider);
    return trending.maybeWhen(
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        return _FeaturedBanner(item: items.first);
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _FeaturedBanner extends StatelessWidget {
  final MediaPreview item;

  const _FeaturedBanner({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final imageUrl = ImageUtils.buildTmdbPosterUrl(item.posterPath);
    final heroTag = 'discover_featured_${item.id}';
    final year = item.year;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      child: PressableScale(
        onTap: () => context.openSeerrTitle(
          mediaType: item.mediaType,
          id: item.id,
          heroTag: heroTag,
          posterUrl: imageUrl,
        ),
        child: ClipRRect(
          borderRadius: AppRadius.borderRadiusLg,
          child: SizedBox(
            height: 200,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Poster fill as the textured backdrop.
                if (imageUrl.isNotEmpty)
                  ContentCard(imageUrl: imageUrl)
                else
                  ColoredBox(color: colorScheme.surfaceContainerHigh),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: AppGradients.heroScrim(colorScheme.surface),
                  ),
                ),
                Positioned(
                  left: AppSpacing.lg,
                  right: AppSpacing.lg,
                  bottom: AppSpacing.lg,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      SizedBox(
                        width: 74,
                        height: 111,
                        child: Hero(
                          tag: heroTag,
                          transitionOnUserGestures:
                              MediaPosterCard.flightOnUserGestures,
                          child: ContentCard(
                            imageUrl: imageUrl,
                            paneTag: heroTag,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Featured',
                              semanticsLabel: 'Featured',
                              style: AppTheme.chrome(
                                context,
                                color: colorScheme.primary,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              item.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: colorScheme.onSurface,
                                height: 1.1,
                              ),
                            ),
                            if (year.isNotEmpty) ...[
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                year,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
