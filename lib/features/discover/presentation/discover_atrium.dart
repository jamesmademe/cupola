import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_breakpoints.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/core/text_scale.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/ambient_scaffold.dart';
import 'package:cupola/core/widgets/app_skeleton.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/widgets/glass_app_bar.dart';
import 'package:cupola/core/widgets/inline_error_retry.dart';
import 'package:cupola/core/widgets/media_grid.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';
import 'package:cupola/core/widgets/selection_pills.dart';
import 'package:cupola/features/discover/domain/catalog_curation.dart';
import 'package:cupola/features/discover/domain/catalog_query.dart';
import 'package:cupola/features/discover/domain/discover_index.dart';
import 'package:cupola/features/discover/domain/models/seerr_genre.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/presentation/catalog_providers.dart';
import 'package:cupola/features/discover/presentation/discover_calendar_band.dart';
import 'package:cupola/features/discover/presentation/discover_details_provider.dart';
import 'package:cupola/features/discover/presentation/library_calendar_provider.dart';
import 'package:cupola/features/discover/presentation/library_shelves_provider.dart';
import 'package:cupola/features/discover/presentation/widgets/catalog_poster.dart';
import 'package:cupola/features/discover/presentation/widgets/collection_tally.dart';
import 'package:cupola/features/discover/presentation/widgets/discover_carousel.dart';
import 'package:cupola/features/discover/presentation/widgets/discover_door.dart';
import 'package:cupola/features/discover/presentation/widgets/search_row.dart';
import 'package:cupola/features/media/presentation/open_media.dart';
import 'package:cupola/features/movies/presentation/movies_provider.dart';
import 'package:cupola/features/series/presentation/series_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Seerr's catalogue at rest: what the Discover tab shows before anything is
/// typed into its field. The tab decides whether Seerr is there to ask; this
/// draws the atrium once it is.
///
/// From the top: the calendar's band, six doors (Trending, Genres, Networks,
/// Studios, People, Decades), the quiet links to Moods and Languages, then
/// the shelves, each only where it has titles. A door opens its index in
/// place, under a row that switches between the indexes and leads back.
///
/// Trending is the canary. When it fails, Seerr did not give the atrium
/// anything, and the atrium says so once, in the classified words, instead of
/// a failure under every door and shelf.
class DiscoverAtrium extends ConsumerStatefulWidget {
  const DiscoverAtrium({super.key, this.head, this.bottomPadding = 0});

  /// The tab's title and its field, scrolled away with the doors under them
  /// as drawn; null where the page draws its own head.
  final Widget? head;

  /// The room the floating bar takes at the foot of the list.
  final double bottomPadding;

  /// Asks Seerr, and the arrs the calendar's band reads, for everything on
  /// the atrium again.
  static void invalidate(WidgetRef ref) {
    ref.invalidate(atriumTrendingProvider);
    ref.invalidate(bestMissingProvider);
    ref.invalidate(comingSoonProvider);
    ref.invalidate(catalogGenresProvider);
    ref.invalidate(trendingPeopleProvider);
    ref.invalidate(atriumFacesProvider);
    ref.invalidate(seerrNumberingProvider);
    ref.invalidate(completeTheCollectionProvider);
    ref.invalidate(becauseYouWatchedProvider);
    ref.invalidate(calendarDayProvider);
    ref.invalidate(calendarSourceProvider);
  }

  @override
  ConsumerState<DiscoverAtrium> createState() => _DiscoverAtriumState();
}

class _DiscoverAtriumState extends ConsumerState<DiscoverAtrium> {
  @override
  Widget build(BuildContext context) {
    final trending = ref.watch(atriumTrendingProvider);
    final failed = trending.hasError && !trending.isLoading;

    final List<Widget> children;
    if (failed) {
      // The calendar comes from the arrs: Seerr's silence leaves it be.
      children = [
        const DiscoverCalendarBand(),
        _SeerrSilent(error: trending.error!),
      ];
    } else {
      children = [
        const DiscoverCalendarBand(),
        const _Doors(),
        const _QuietLinks(),
        const SizedBox(height: AppSpacing.xl),
        const _CompleteTheCollection(),
        const _BecauseYouWatched(),
        DiscoverCarousel(
          title: 'The best you’re missing',
          sectionId: 'best_missing',
          items: ref.watch(bestMissingProvider),
          onRetry: () => ref.invalidate(bestMissingProvider),
        ),
        DiscoverCarousel(
          title: 'Trending this week',
          sectionId: 'trending',
          items: trending,
          onRetry: () => ref.invalidate(atriumTrendingProvider),
          onSeeAll: () =>
              context.push(ServiceRoutes.discoverIndex(DiscoverIndex.trending)),
        ),
        DiscoverCarousel(
          title: 'Coming soon',
          sectionId: 'coming_soon',
          items: ref.watch(comingSoonProvider),
          onRetry: () => ref.invalidate(comingSoonProvider),
          onSeeAll: () => context.push(
            ServiceRoutes.discoverCatalog(
              const CatalogQuery.upcoming(CatalogKind.movie),
            ),
          ),
        ),
      ];
    }

    // The route's primary list: the tab tapped again brings it back to the
    // top (`ShellScreen`).
    return RefreshIndicator(
      onRefresh: () async => DiscoverAtrium.invalidate(ref),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(bottom: widget.bottomPadding),
        children: [
          ?widget.head,
          const SizedBox(height: AppSpacing.sm),
          ...children,
        ],
      ),
    );
  }
}

/// The collection the operator is part way through, the nearest to whole:
/// the strip of its movies and where each stands, one tap from its page.
/// Drawn only once it has one to show.
class _CompleteTheCollection extends ConsumerWidget {
  const _CompleteTheCollection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(mayCompleteCollectionsProvider)) {
      return const SizedBox.shrink();
    }
    final invitation = ref.watch(completeTheCollectionProvider).value;
    if (invitation == null) return const SizedBox.shrink();
    final (:detail, :shelf) = invitation;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      child: CollectionTally.invitation(
        shelf: shelf,
        name: detail.name,
        onTap: () => context.openCollection(detail.id),
      ),
    );
  }
}

/// TMDB's recommendations for what the household finished last on its media
/// server. Drawn only once there is something to recommend from.
class _BecauseYouWatched extends ConsumerWidget {
  const _BecauseYouWatched();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(hasWatchHistoryProvider)) return const SizedBox.shrink();
    final shelf = ref.watch(becauseYouWatchedProvider).value;
    if (shelf == null) return const SizedBox.shrink();
    return DiscoverCarousel(
      title: 'Because you watched ${shelf.watched}',
      sectionId: 'because_you_watched',
      items: AsyncData(shelf.items),
    );
  }
}

/// Seerr gave the atrium nothing: one line under the field, with the remedy
/// its cause names, and none of Seerr's doors or shelves under it.
class _SeerrSilent extends ConsumerWidget {
  const _SeerrSilent({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: InlineErrorRetry(
        message:
            '${describeFailureOf(ServiceKey.seerr, error).headline}, '
            'so the catalog is missing.',
        error: error,
        service: ServiceKey.seerr,
        onRetry: () => DiscoverAtrium.invalidate(ref),
      ),
    );
  }
}

/// [children] in rows, each row as tall as its taller tile: index tiles grow
/// with their words, so a fixed grid extent would clip them.
///
/// [columns] answers how many to a row for the width the tiles share; by
/// default an index's tiles, which add a column wherever another fits at
/// [_indexTileFloor].
class _TileRows extends StatelessWidget {
  const _TileRows({required this.children, this.columns = _indexColumns});

  final List<Widget> children;
  final int Function(BuildContext context, double width) columns;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: LayoutBuilder(
        builder: (context, box) {
          final count = columns(context, box.maxWidth);
          return Column(
            children: [
              for (var start = 0; start < children.length; start += count)
                Padding(
                  padding: EdgeInsets.only(top: start == 0 ? 0 : AppSpacing.sm),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = start; i < start + count; i++) ...[
                          if (i > start) const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: i < children.length
                                ? children[i]
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// The narrowest an index's tile is drawn: two to a row on the narrowest
/// phone (360pt), whose tiles come to 160. A wider window adds a column
/// wherever another fits at that width, never a wider tile than it needs:
/// two on every phone and in a tablet's list beside a title, six across a
/// tablet on its side and in a desktop window's well.
const double _indexTileFloor = 160;

int _indexColumns(BuildContext context, double width) {
  final fits = ((width + AppSpacing.sm) / (_indexTileFloor + AppSpacing.sm))
      .floor();
  return fits > 2 ? fits : 2;
}

/// The narrowest a door of the lobby is drawn: three to a row on the
/// narrowest phone (360pt) come to 104. Six fit on one row once each of them
/// is that wide (664pt between the gutters), which no phone and no tablet's
/// list beside a title reaches, and every tablet and desktop window does.
const double _doorFloor = 104;

int _doorColumns(BuildContext context, double width) {
  final row = width >= 6 * _doorFloor + 5 * AppSpacing.sm;
  // Two once the words are large, where three narrow doors would cut every
  // name short; three across a wide window, where two would stretch a door
  // past anything it holds.
  final large =
      TextScaleMetrics.clampedScalerOf(context).scale(1) >
      DiscoverDoor.largeTextScale;
  return switch ((row, large)) {
    (true, false) => 6,
    (true, true) || (false, false) => 3,
    (false, true) => 2,
  };
}

String? _poster(MediaPreview? item, {String size = 'w154'}) {
  final path = item?.posterPath;
  if (path == null || path.isEmpty) return null;
  return ImageUtils.buildTmdbPosterUrl(path, size: size);
}

/// The six doors.
class _Doors extends ConsumerWidget {
  const _Doors();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trending = ref.watch(atriumTrendingProvider).value ?? const [];
    final best = ref.watch(bestMissingProvider).value ?? const [];
    final genres = ref.watch(catalogGenresProvider(CatalogKind.movie)).value;
    final networks = _libraryNetworks(ref);
    final studios = _libraryStudios(ref);
    final faces = ref.watch(atriumFacesProvider).value ?? const <String>[];
    MediaPreview? at(List<MediaPreview> list, int i) =>
        i < list.length ? list[i] : null;
    void open(DiscoverIndex index) =>
        context.push(ServiceRoutes.discoverIndex(index));

    // Three to a row on a phone, all six on one row once the window is wide
    // enough (`_doorColumns`).
    return Semantics(
      container: true,
      label: 'Browse by',
      child: _TileRows(
        columns: _doorColumns,
        children: [
          DiscoverDoor.lobby(
            title: 'Trending',
            subtitle: 'This week',
            lightUrl: _poster(at(trending, 0), size: 'w92'),
            posterUrls: [?_poster(at(trending, 1)), ?_poster(at(trending, 2))],
            onTap: () => open(DiscoverIndex.trending),
          ),
          DiscoverDoor.lobby(
            title: 'Genres',
            // How many there are, once Seerr said: a complete list, so a
            // count of it is a fact.
            subtitle: genres == null ? 'Movies, series' : '${genres.length}',
            // Words, like the networks and the studios: a genre's backdrop
            // blurred to a door is a grey nobody can tell from a door still
            // loading.
            names: [
              for (final genre in doorGenresFirst(genres ?? const []).take(3))
                genre.name,
            ],
            onTap: () => open(DiscoverIndex.genres),
          ),
          DiscoverDoor.lobby(
            title: 'Networks',
            subtitle: 'Series',
            names: [for (final entry in networks.take(3)) entry.name],
            onTap: () => open(DiscoverIndex.networks),
          ),
          DiscoverDoor.lobby(
            title: 'Studios',
            subtitle: 'Movies',
            names: [for (final entry in studios.take(3)) entry.name],
            onTap: () => open(DiscoverIndex.studios),
          ),
          DiscoverDoor.lobby(
            title: 'People',
            subtitle: 'Directors, cast',
            lightUrl: _poster(at(trending, 3), size: 'w92'),
            // Faces, as Trending and Decades lean posters: the light alone
            // left the one door with nothing in it.
            faceUrls: [
              for (final path in faces)
                ImageUtils.buildTmdbPosterUrl(path, size: 'w185'),
            ],
            onTap: () => open(DiscoverIndex.people),
          ),
          DiscoverDoor.lobby(
            title: 'Decades',
            subtitle: '1920s to now',
            lightUrl: _poster(at(best, 0), size: 'w92'),
            posterUrls: [?_poster(at(best, 1)), ?_poster(at(best, 2))],
            onTap: () => open(DiscoverIndex.decades),
          ),
        ],
      ),
    );
  }
}

/// The networks, those the operator's series come from first.
///
/// Read from Sonarr only when it is set up and the reader is the operator
/// (a requester has no Sonarr to ask), and only from a library another
/// screen already loaded: the order settles once it arrives, and nothing
/// waits for it or asks for it.
List<CatalogEntity> _libraryNetworks(WidgetRef ref) {
  final settings = ref.watch(currentSettingsProvider);
  if (ref.watch(audienceProvider) != Audience.operator ||
      !settings.isServiceConfigured(ServiceKey.sonarr)) {
    return curatedNetworks;
  }
  // Only a library something else already asked for: the atrium never
  // starts a read of the whole of Sonarr to order four names.
  final series = ref.exists(seriesProvider)
      ? ref.watch(seriesProvider).value ?? const []
      : const [];
  return libraryFirst(curatedNetworks, [
    for (final show in series) ?show.network,
  ]);
}

/// The studios, those the operator's movies come from first; see
/// [_libraryNetworks].
List<CatalogEntity> _libraryStudios(WidgetRef ref) {
  final settings = ref.watch(currentSettingsProvider);
  if (ref.watch(audienceProvider) != Audience.operator ||
      !settings.isServiceConfigured(ServiceKey.radarr)) {
    return curatedStudios;
  }
  final movies = ref.exists(moviesProvider)
      ? ref.watch(moviesProvider).value ?? const []
      : const [];
  return libraryFirst(curatedStudios, [
    for (final movie in movies) ?movie.studio,
  ]);
}

/// "Moods ›  Languages ›": the two indexes with no door of their own.
class _QuietLinks extends ConsumerWidget {
  const _QuietLinks();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget link(DiscoverIndex index) => _QuietLink(
      label: index.label,
      onTap: () => context.push(ServiceRoutes.discoverIndex(index)),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        0,
      ),
      // A wrap rather than a row: at a large reading size the two links do
      // not fit one phone's line, and the second goes under the first.
      child: Wrap(
        spacing: AppSpacing.xl,
        children: [link(DiscoverIndex.moods), link(DiscoverIndex.languages)],
      ),
    );
  }
}

class _QuietLink extends StatelessWidget {
  const _QuietLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = CupolaRoom.of(context).inkSecondary;
    return PressableScale(
      onTap: onTap,
      semanticLabel: label,
      excludeChildSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: AppType.label.copyWith(color: color)),
            const SizedBox(width: AppSpacing.xxs),
            Icon(Icons.chevron_right_rounded, size: 18, color: color),
          ],
        ),
      ),
    );
  }
}

/// An index of the atrium, on a page of its own: opened from a door of the
/// lobby with the platform's push, and closed with its back and its swipe.
///
/// The row of pills switches between the indexes in place, in a fixed order:
/// the open one is lit and brought into view, never moved to the head of the
/// row (a pill that jumped to the front read as the row reshuffling, 11/10).
/// The page's title follows the pill.
class DiscoverIndexPage extends ConsumerStatefulWidget {
  const DiscoverIndexPage({super.key, required this.index});

  /// The index the page opens on.
  final DiscoverIndex index;

  @override
  ConsumerState<DiscoverIndexPage> createState() => _DiscoverIndexPageState();
}

class _DiscoverIndexPageState extends ConsumerState<DiscoverIndexPage> {
  late DiscoverIndex _open = widget.index;

  void _switch(DiscoverIndex index) {
    if (index == _open) return;
    setState(() => _open = index);
    // A new index starts at its top.
    final list = PrimaryScrollController.maybeOf(context);
    if (list != null && list.hasClients) list.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    return AmbientScaffold(
      contentWellWidth: AppBreakpoints.contentWell,
      appBar: GlassAppBar(title: Text(_open.label)),
      body: RefreshIndicator(
        onRefresh: () async => DiscoverAtrium.invalidate(ref),
        child: ListView(
          primary: true,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(
            top: AppSpacing.sm,
            bottom: FloatingNavBarMetrics.getScrollViewBottomPadding(context),
          ),
          children: [
            SelectionPills<DiscoverIndex>(
              values: DiscoverIndex.values,
              selected: _open,
              labelBuilder: (index) => index.label,
              onSelected: _switch,
            ),
            _IndexBody(index: _open),
          ],
        ),
      ),
    );
  }
}

/// What an open index lists.
class _IndexBody extends ConsumerWidget {
  const _IndexBody({required this.index});

  final DiscoverIndex index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (index) {
      DiscoverIndex.trending => const _TrendingIndex(),
      DiscoverIndex.genres => const _GenresIndex(),
      DiscoverIndex.networks => _EntityIndex(
        lead: 'Series by where they first aired',
        entries: _libraryNetworks(ref),
        query: (entry) => CatalogQuery.network(entry.id, entry.name),
      ),
      DiscoverIndex.studios => _EntityIndex(
        lead: 'Movies by the studio that made them',
        entries: _libraryStudios(ref),
        query: (entry) => CatalogQuery.studio(entry.id, entry.name),
      ),
      DiscoverIndex.people => const _PeopleIndex(),
      DiscoverIndex.decades => _PlainIndex(
        lead: 'Movies and series by the decade they came out',
        tiles: [
          for (final start in catalogDecades(today: DateTime.now()))
            (
              title: decadeLabel(start),
              query: CatalogQuery.decade(CatalogKind.movie, start),
            ),
        ],
      ),
      DiscoverIndex.moods => _PlainIndex(
        lead: 'Movies and series by what they are about',
        tiles: [
          for (final mood in curatedMoods)
            (
              title: mood.name,
              query: CatalogQuery.keyword(
                CatalogKind.movie,
                mood.id,
                mood.name,
              ),
            ),
        ],
      ),
      DiscoverIndex.languages => _PlainIndex(
        lead: 'Movies and series by the language they were made in',
        tiles: [
          for (final language in curatedLanguages)
            (
              title: language.name,
              query: CatalogQuery.language(
                CatalogKind.movie,
                language.code,
                language.name,
              ),
            ),
        ],
      ),
    };
  }
}

/// The line that says what an index lists.
class _Lead extends StatelessWidget {
  const _Lead(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: CupolaThemeColors.of(context).dimText,
        ),
      ),
    );
  }
}

/// Plain tiles, each opening a catalogue page.
class _PlainIndex extends StatelessWidget {
  const _PlainIndex({required this.lead, required this.tiles});

  final String lead;
  final List<({String title, CatalogQuery query})> tiles;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Lead(lead),
        _TileRows(
          children: [
            for (final tile in tiles)
              DiscoverDoor.index(
                title: tile.title,
                onTap: () =>
                    context.push(ServiceRoutes.discoverCatalog(tile.query)),
              ),
          ],
        ),
      ],
    );
  }
}

/// Networks or studios, the library's first.
class _EntityIndex extends StatelessWidget {
  const _EntityIndex({
    required this.lead,
    required this.entries,
    required this.query,
  });

  final String lead;
  final List<CatalogEntity> entries;
  final CatalogQuery Function(CatalogEntity entry) query;

  @override
  Widget build(BuildContext context) {
    return _PlainIndex(
      lead: lead,
      tiles: [
        for (final entry in entries) (title: entry.name, query: query(entry)),
      ],
    );
  }
}

/// The genres of the kind chosen, each lit by one of its backdrops.
class _GenresIndex extends ConsumerStatefulWidget {
  const _GenresIndex();

  @override
  ConsumerState<_GenresIndex> createState() => _GenresIndexState();
}

class _GenresIndexState extends ConsumerState<_GenresIndex> {
  CatalogKind _kind = CatalogKind.movie;

  @override
  Widget build(BuildContext context) {
    final genres = ref.watch(catalogGenresProvider(_kind));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.md),
        SelectionPills<CatalogKind>(
          values: CatalogKind.values,
          selected: _kind,
          labelBuilder: (kind) => kind.label,
          onSelected: (kind) => setState(() => _kind = kind),
        ),
        const SizedBox(height: AppSpacing.sm),
        genres.when(
          loading: () => const _TilesLoading(),
          error: (error, _) => _IndexFailure(
            error: error,
            what: 'the genres',
            onRetry: () => ref.invalidate(catalogGenresProvider(_kind)),
          ),
          data: (list) {
            final lights = _distinctLights(list);
            return _TileRows(
              children: [
                for (final genre in list)
                  DiscoverDoor.index(
                    title: genre.name,
                    lightUrl: lights[genre.id] == null
                        ? null
                        : ImageUtils.buildTmdbPosterUrl(
                            lights[genre.id],
                            size: 'w300',
                          ),
                    onTap: () => context.push(
                      ServiceRoutes.discoverCatalog(
                        CatalogQuery.genre(_kind, genre.id, genre.name),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Each genre's light: its first backdrop no genre before it took. A popular
/// title is in several genres, and Action beside Adventure lit by the same
/// picture reads as one tile drawn twice.
Map<int, String?> _distinctLights(List<SeerrGenre> genres) {
  final taken = <String>{};
  return {
    for (final genre in genres)
      genre.id:
          genre.backdrops.where(taken.add).firstOrNull ??
          genre.backdrops.firstOrNull,
  };
}

/// Trending today or this week: the first page as a grid, and the rest on a
/// catalogue page.
class _TrendingIndex extends ConsumerStatefulWidget {
  const _TrendingIndex();

  @override
  ConsumerState<_TrendingIndex> createState() => _TrendingIndexState();
}

class _TrendingIndexState extends ConsumerState<_TrendingIndex> {
  TrendingWindow _window = TrendingWindow.week;

  @override
  Widget build(BuildContext context) {
    final query = CatalogQuery.trending(window: _window);
    // This week's first page is the shelf's own read; today's is its own.
    final items = _window == TrendingWindow.week
        ? ref.watch(atriumTrendingProvider)
        : ref.watch(_trendingTodayProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.md),
        SelectionPills<TrendingWindow>(
          values: TrendingWindow.values,
          selected: _window,
          labelBuilder: (window) => window.label,
          onSelected: (window) => setState(() => _window = window),
        ),
        const SizedBox(height: AppSpacing.sm),
        items.when(
          loading: () => const _TilesLoading(),
          error: (error, _) => _IndexFailure(
            error: error,
            what: 'the trending titles',
            onRetry: () => ref.invalidate(_trendingTodayProvider),
          ),
          data: (list) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PosterGrid(items: list, sectionId: 'trending_${_window.param}'),
              _MoreLink(
                label: 'More of what is trending',
                onTap: () => context.push(ServiceRoutes.discoverCatalog(query)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

final _trendingTodayProvider = FutureProvider.autoDispose<List<MediaPreview>>(
  (ref) async =>
      (await ref
              .watch(seerrServiceProvider)
              .getCatalogPage(
                const CatalogQuery.trending(window: TrendingWindow.day),
              ))
          .items,
  retry: noProviderRetry,
);

/// [items] in the poster grid every grid of the app uses.
class _PosterGrid extends StatelessWidget {
  const _PosterGrid({required this.items, required this.sectionId});

  final List<MediaPreview> items;
  final String sectionId;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final inner = constraints.maxWidth - 2 * AppSpacing.lg;
        final columns = MediaGrid.columnsFor(inner, 3);
        final tileWidth =
            (inner - (columns - 1) * AppSpacing.gridGap) / columns;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Wrap(
            spacing: AppSpacing.gridGap,
            runSpacing: AppSpacing.lg,
            children: [
              for (final item in items)
                CatalogPoster(
                  item: item,
                  heroTag: 'discover_${sectionId}_${item.id}',
                  width: tileWidth,
                ),
            ],
          ),
        );
      },
    );
  }
}

/// "More of …›" at the foot of an index.
class _MoreLink extends StatelessWidget {
  const _MoreLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        0,
      ),
      child: _QuietLink(label: label, onTap: onTap),
    );
  }
}

/// The people behind this week's trending titles.
class _PeopleIndex extends ConsumerWidget {
  const _PeopleIndex();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final people = ref.watch(trendingPeopleProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Lead('Who is behind this week’s trending titles'),
        people.when(
          loading: () => const _TilesLoading(),
          error: (error, _) => _IndexFailure(
            error: error,
            what: 'the people',
            onRetry: () => ref.invalidate(trendingPeopleProvider),
          ),
          data: (list) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            // Rows read across, a face to its name: never wider than a page
            // of one column, and at the head of a wider window, under the
            // line that says what they are.
            child: Align(
              alignment: AlignmentDirectional.topStart,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppBreakpoints.readingWell,
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: CupolaRoom.of(context).slab,
                      borderRadius: BorderRadius.circular(AppRadius.group),
                      border: Border.all(color: CupolaRoom.of(context).hair),
                    ),
                    child: Column(
                      children: [
                        for (var i = 0; i < list.length; i++) ...[
                          if (i > 0)
                            Divider(
                              height: 1,
                              indent: AppSpacing.lg,
                              endIndent: AppSpacing.lg,
                              color: CupolaRoom.of(context).hair,
                            ),
                          _PersonRow(person: list[i]),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.person});

  final CatalogPerson person;

  @override
  Widget build(BuildContext context) {
    final photo = person.profilePath == null
        ? null
        : ImageUtils.buildTmdbPosterUrl(person.profilePath, size: 'w185');
    return SearchRow.person(
      name: person.name,
      line: '${person.role}\u00A0· ${person.title}',
      face: photo ?? '',
      onTap: () => context.openPerson(person.id, posterUrl: photo),
      selected: context.paneShowsPerson(person.id),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
    );
  }
}

/// A skeleton the height of a few tiles while an index loads.
class _TilesLoading extends StatelessWidget {
  const _TilesLoading();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: AppSkeleton.posterRow(height: 156),
    );
  }
}

/// An index Seerr did not give, in the classified words.
class _IndexFailure extends StatelessWidget {
  const _IndexFailure({
    required this.error,
    required this.what,
    required this.onRetry,
  });

  final Object error;
  final String what;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: InlineErrorRetry(
        message:
            '${describeFailureOf(ServiceKey.seerr, error).headline}, '
            'so $what are missing.',
        error: error,
        service: ServiceKey.seerr,
        onRetry: onRetry,
      ),
    );
  }
}
