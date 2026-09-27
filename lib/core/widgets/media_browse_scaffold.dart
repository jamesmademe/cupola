import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: implementation_imports
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_breakpoints.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/providers/navigation_refresh_provider.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/core/widgets/ambient_scaffold.dart';
import 'package:cupola/core/widgets/async_value_widget.dart';
import 'package:cupola/core/widgets/content_card.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/widgets/glass_app_bar.dart';
import 'package:cupola/core/widgets/media_grid.dart';
import 'package:cupola/core/widgets/media_poster_card.dart';
import 'package:cupola/core/widgets/search_bar_header.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

typedef SettingsSelector = (String, String) Function(SettingsModel settings);
typedef MediaBrowseItemTap<T> =
    void Function(BuildContext context, T item, String heroTag);
typedef MediaBrowseTextExtractor<T> = String Function(T item);
typedef MediaBrowseRefreshCallback = void Function(WidgetRef ref);

enum MediaBrowseFilter {
  all,
  available,
  missing,
  inQueue,

  /// On disk, but not at the quality the profile asks for. Its own chip rather
  /// than a shade of Missing: the file is there, so nothing is absent — what is
  /// outstanding is an upgrade, and the operator who wants one is not the
  /// operator hunting a gap.
  cutoffUnmet,

  /// Tracked by the service but not watched by it. Orthogonal to every other
  /// chip, and the only one that says nothing about the file.
  unmonitored,
}

/// Which library chip a resolved status belongs under.
///
/// Three buckets rather than two predicates, and that is the whole point: a pair
/// of independent predicates is how [MediaAvailability.unknown] and
/// [MediaAvailability.deleted] came to match *neither* Available nor Missing, so
/// a freshly added Sonarr series — `sonarrSeriesAvailability` returns `unknown`
/// whenever the server omits `statistics` — was visible under `All` and under
/// nothing else. A bucket is exhaustive over [MediaAvailability] by
/// construction, so a state added later cannot silently fall out of the library.
enum MediaBrowseBucket {
  /// Something is on disk: Available, Upgrade available, Partial.
  onDisk,

  /// Something the user can act on is not on disk.
  gap,

  /// Not out yet — the one state that deliberately answers to no chip but
  /// `All`, because an unreleased title is not a gap anyone can close.
  unreleased,
}

/// The bucket for [status], exhaustively.
///
/// A null status means the screen supplied no extractor, or the feature could
/// not resolve one: it lands in [MediaBrowseBucket.gap], which is what the
/// pre-refactor `_browseStatusFor` did with its terminal `_ => missing` case.
MediaBrowseBucket mediaBrowseBucketOf(MediaStatusInfo? status) {
  if (status == null) return MediaBrowseBucket.gap;

  return switch (status.availability) {
    MediaAvailability.available ||
    MediaAvailability.upgradable ||
    // Partial counts as on disk: part of it genuinely is, and the page shows
    // the count. It is deliberately not also a gap — a title cannot answer to
    // two chips or the two lists stop being a partition.
    MediaAvailability.partial => MediaBrowseBucket.onDisk,
    MediaAvailability.missing ||
    // Not tracked, gone from the service, or never reported: nothing is on
    // disk, so the operator finds it where they look for what is not there.
    MediaAvailability.notTracked ||
    MediaAvailability.deleted ||
    MediaAvailability.unknown => MediaBrowseBucket.gap,
    MediaAvailability.unavailable => MediaBrowseBucket.unreleased,
  };
}

/// Whether an item with [status] is shown under [filter].
///
/// Pure and top-level so the partition can be asserted rung by rung instead of
/// only through a pumped scaffold.
///
/// [belowCutoff] is the one fact the status cannot carry: whether *this* item
/// is in the service's own `wanted/cutoff` set. It arrives as a plain bool so
/// this function stays a function of its arguments — the caller owns the id
/// set and the lookup, and a screen with no cutoff source passes `false` and
/// does not offer the chip at all.
bool mediaBrowseFilterMatches(
  MediaBrowseFilter filter,
  MediaStatusInfo? status, {
  bool belowCutoff = false,
}) {
  return switch (filter) {
    MediaBrowseFilter.all => true,
    MediaBrowseFilter.available =>
      mediaBrowseBucketOf(status) == MediaBrowseBucket.onDisk,
    MediaBrowseFilter.missing =>
      mediaBrowseBucketOf(status) == MediaBrowseBucket.gap,
    // Orthogonal to the buckets on purpose: what is moving is a different
    // question from what is on disk, and a downloading title belongs in both
    // In queue and Missing.
    MediaBrowseFilter.inQueue => status?.isInPipeline ?? false,
    // Also orthogonal: a below-cutoff file is on disk, so it answers to
    // Available too. Neither of these two may join the bucket partition or the
    // two exhaustive lists stop being lists.
    MediaBrowseFilter.cutoffUnmet => belowCutoff,
    MediaBrowseFilter.unmonitored => status?.unmonitored ?? false,
  };
}

/// What the browse wall draws an item as.
///
/// Not a style flag: a poster and an artist portrait are different claims. A
/// 2:3 crop of a band photograph is a worse lie than a circle — it invents a
/// poster that does not exist and crops a face to do it — so Lidarr's wall is
/// circular and says so here rather than tuning a radius at the call site.
enum MediaBrowseTileShape {
  /// The 2:3 poster, with the status dot painted over its lower-left corner.
  poster,

  /// The circular portrait, centred, with the status carried by the caption
  /// instead of a dot: a circle has no corner to put one in, and `LidarrArtists`
  /// draws the completeness in words (`6 albums · complete`).
  circle,
}

/// One order the browse wall can be read in.
///
/// A sort is a label, a comparator and a claim about headings — not an enum the
/// scaffold switches on, because the scaffold is generic over `T` and cannot
/// read a release date or a file size. Each service declares the orders its own
/// model can actually answer, which is also why there is no dead `Size` entry on
/// a screen whose model has no size.
@immutable
class MediaBrowseSort<T> {
  /// What the control reads after `Sort · `.
  final String label;

  final Comparator<T> compare;

  /// Whether the A–Z letter headings belong over this order.
  ///
  /// They belong over exactly one: an alphabetical wall is what a letter
  /// heading describes. Over a date-added order the same headings are a lie
  /// told once per section — `LidarrArtists` says so in the board itself
  /// ("letter headings appear only in Name A–Z sort") and `RadarrLibrary`,
  /// sorted by date added, draws none.
  final bool lettered;

  const MediaBrowseSort({
    required this.label,
    required this.compare,
    this.lettered = false,
  });

  /// Newest first, and anything the service did not date goes last.
  ///
  /// The arrs hand `added` back as an ISO string. Parsing it rather than
  /// comparing the strings is not pedantry: a server that answers a local
  /// offset sorts wrongly under a string compare, and a row the server never
  /// dated sorts *first* under one — the loudest position in the list for the
  /// item we know least about.
  factory MediaBrowseSort.dateAdded(String? Function(T item) addedOf) {
    return MediaBrowseSort<T>(
      label: 'Date added',
      compare: (left, right) {
        final leftAt = DateTime.tryParse(addedOf(left) ?? '');
        final rightAt = DateTime.tryParse(addedOf(right) ?? '');
        if (leftAt == null && rightAt == null) return 0;
        if (leftAt == null) return 1;
        if (rightAt == null) return -1;
        return rightAt.compareTo(leftAt);
      },
    );
  }

  /// Largest first. A zero is an honest answer here — nothing on disk — so it
  /// sorts to the bottom rather than being held out.
  factory MediaBrowseSort.size(int Function(T item) bytesOf) {
    return MediaBrowseSort<T>(
      label: 'Size',
      compare: (left, right) => bytesOf(right).compareTo(bytesOf(left)),
    );
  }

  /// Newest first; an unknown year (the arrs write 0) sorts last rather than
  /// claiming to be the oldest title in the library.
  factory MediaBrowseSort.year(int Function(T item) yearOf) {
    return MediaBrowseSort<T>(
      label: 'Year',
      compare: (left, right) {
        final leftYear = yearOf(left);
        final rightYear = yearOf(right);
        if (leftYear == 0 && rightYear == 0) return 0;
        if (leftYear == 0) return 1;
        if (rightYear == 0) return -1;
        return rightYear.compareTo(leftYear);
      },
    );
  }
}

/// The fewest columns the browse wall drops to, matching the three the phone
/// boards draw. Below this the floor stops being the binding constraint: two
/// posters across a 390pt phone would be enormous, not better.
const int _minBrowseColumns = 3;

/// A sort key whose first character is a Latin letter, and therefore gets its
/// own section heading rather than landing under `#`.
///
/// Top level because the section pass runs it once per library item: built
/// inline, the pattern was recompiled for every row on every rebuild.
final RegExp _sectionLetter = RegExp(r'^[A-Z]$');

/// Shared scaffold for media library browse screens.
///
/// Provides the shared AppBar, search bar, navigation refresh listener,
/// library refresh flow, and search results layout used by the Movies, Series,
/// and Music screens.
///
class MediaBrowseScaffold<T> extends ConsumerStatefulWidget {
  final String title;
  final String searchHint;
  final String activityRoute;
  final NavigationSection navigationSection;
  final String serviceName;
  final Color? accentColor;
  final String heroTagPrefix;
  final String searchHeroTagPrefix;
  final FutureProvider<List<T>> libraryProvider;
  final StateProvider<String> searchQueryProvider;
  final FutureProvider<List<T>?> searchResultsProvider;
  final MediaBrowseTextExtractor<T> titleExtractor;
  final MediaBrowseTextExtractor<T> subtitleExtractor;
  final MediaBrowseTextExtractor<T>? sortTitleExtractor;
  final List<dynamic>? Function(T item) imagesExtractor;
  final int Function(T item) idExtractor;
  final StatusExtractor<T>? statusExtractor;
  final MediaBrowseRefreshCallback? onRefresh;
  final SettingsSelector settingsSelector;
  final MediaBrowseItemTap<T> onItemTap;
  final List<String>? coverTypes;
  final bool showAppBar;
  final double topPadding;

  /// Optional KPI peek rail shown under the search bar (hidden while searching).
  final Widget? kpiPeek;

  /// Orders this service can offer beyond the built-in Title A–Z, which is
  /// always first and always the default.
  final List<MediaBrowseSort<T>> sorts;

  /// What a tile is drawn as — see [MediaBrowseTileShape].
  final MediaBrowseTileShape tileShape;

  /// The ids the service reported under `wanted/cutoff`, or null when this
  /// screen has no cutoff source.
  ///
  /// Null and empty are different answers and the chip strip treats them so: an
  /// empty set means the service answered "none below cutoff" and the chip is
  /// offered reading zero, while null means nothing was asked and the chip is
  /// not drawn at all. A chip that cannot be told apart from an unasked
  /// question is a claim the screen cannot honour.
  final Set<int>? cutoffUnmetIds;

  const MediaBrowseScaffold({
    super.key,
    required this.title,
    required this.searchHint,
    required this.activityRoute,
    required this.navigationSection,
    required this.serviceName,
    this.accentColor,
    required this.heroTagPrefix,
    required this.searchHeroTagPrefix,
    required this.libraryProvider,
    required this.searchQueryProvider,
    required this.searchResultsProvider,
    required this.titleExtractor,
    required this.subtitleExtractor,
    this.sortTitleExtractor,
    required this.imagesExtractor,
    required this.idExtractor,
    this.statusExtractor,
    this.onRefresh,
    required this.settingsSelector,
    required this.onItemTap,
    this.coverTypes,
    this.showAppBar = true,
    this.topPadding = 0,
    this.kpiPeek,
    this.sorts = const [],
    this.cutoffUnmetIds,
    this.tileShape = MediaBrowseTileShape.poster,
  });

  @override
  ConsumerState<MediaBrowseScaffold<T>> createState() =>
      _MediaBrowseScaffoldState<T>();
}

class _MediaBrowseScaffoldState<T>
    extends ConsumerState<MediaBrowseScaffold<T>> {
  MediaBrowseFilter _selectedFilter = MediaBrowseFilter.all;

  /// Index into [_sortOptions]. Zero — Title A–Z — is the default order on
  /// every service, which is also the only order the wall had before.
  int _sortIndex = 0;

  /// The library list the cached order was computed from, and that order.
  ///
  /// The comparator does not read [_selectedFilter], so the sort is invariant
  /// across a chip tap and across every other rebuild of this element — of
  /// which the soft keyboard alone produces one per frame. [FutureProvider]
  /// hands back the same `List` instance until it is invalidated, so identity
  /// is a sound key; the filter itself still runs on every build.
  ///
  /// It is *not* invariant across a sort change, so the chosen order is part of
  /// the key too — without it, picking a new sort would hand back the old one.
  List<T>? _sortedSource;
  List<T>? _sorted;
  int? _sortedUnder;

  @override
  void didUpdateWidget(MediaBrowseScaffold<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The comparator reads both extractors, so a rebuild that re-closes over
    // new ones has to re-sort even when the list itself is unchanged.
    if (!identical(widget.titleExtractor, oldWidget.titleExtractor) ||
        !identical(widget.sortTitleExtractor, oldWidget.sortTitleExtractor) ||
        !identical(widget.sorts, oldWidget.sorts)) {
      _sortedSource = null;
      _sorted = null;
    }
    // A service that offered five orders and now offers two must not stay
    // parked on an index that no longer exists.
    if (_sortIndex >= _sortOptions.length) {
      _sortIndex = 0;
    }
  }

  /// Title A–Z first, then whatever the service declared.
  ///
  /// The built-in order cannot be a const in [MediaBrowseScaffold.sorts]
  /// because it closes over this widget's own title extractors.
  List<MediaBrowseSort<T>> get _sortOptions => [
    MediaBrowseSort<T>(
      label: 'Title A–Z',
      lettered: true,
      compare: (left, right) {
        final bySortTitle = _sortKeyFor(left).compareTo(_sortKeyFor(right));
        if (bySortTitle != 0) {
          return bySortTitle;
        }
        return widget
            .titleExtractor(left)
            .toLowerCase()
            .compareTo(widget.titleExtractor(right).toLowerCase());
      },
    ),
    ...widget.sorts,
  ];

  /// The chips this screen can honestly offer.
  ///
  /// Cutoff unmet is conditional on a source — see
  /// [MediaBrowseScaffold.cutoffUnmetIds]. Unmonitored never is: `monitored`
  /// rides on every resolved status already, so the chip cannot be wrong.
  List<MediaBrowseFilter> get _filterOptions => [
    MediaBrowseFilter.all,
    MediaBrowseFilter.available,
    MediaBrowseFilter.missing,
    MediaBrowseFilter.inQueue,
    if (widget.cutoffUnmetIds != null) MediaBrowseFilter.cutoffUnmet,
    MediaBrowseFilter.unmonitored,
  ];

  @override
  Widget build(BuildContext context) {
    final isSearching = ref.watch(
      widget.searchQueryProvider.select((value) => value.isNotEmpty),
    );

    ref.listen<int>(navigationRefreshProvider(widget.navigationSection), (
      previous,
      next,
    ) {
      ref.read(widget.searchQueryProvider.notifier).state = '';
      ref.invalidate(widget.libraryProvider);
      widget.onRefresh?.call(ref);
      if (_selectedFilter != MediaBrowseFilter.all) {
        setState(() {
          _selectedFilter = MediaBrowseFilter.all;
        });
      }
    });

    return AmbientScaffold(
      accent: widget.accentColor,
      // The token, not a number tuned against it. This used to be 1160, argued
      // as "eight 130pt posters and their gaps" — an off-token well chosen to
      // make a gap-blind column calculation come out right. Both halves of that
      // are gone: `MediaGrid.columnsFor` now resolves the count from the
      // constraints it is actually handed and accounts for the gaps, so the
      // well is free to be the same width as every other main well in the app.
      // `AppBreakpoints.contentWell` is the widest the main well is allowed to
      // grow on any shell, and a browse grid is not an exception to it.
      contentWellWidth: AppBreakpoints.contentWell,
      appBar: widget.showAppBar
          ? GlassAppBar(
              leading: isSearching
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () {
                        ref.read(widget.searchQueryProvider.notifier).state =
                            '';
                      },
                      tooltip: 'Exit search',
                    )
                  : null,
              title: Text(widget.title),
              actions: [
                IconButton(
                  icon: const Icon(Icons.history),
                  onPressed: () => context.push(widget.activityRoute),
                  tooltip: 'Activity',
                ),
              ],
            )
          : null,
      // The header (search + KPI + filters) lives in the NestedScrollView
      // header slivers as non-pinned adapters, so it scrolls away with the
      // content instead of staying fixed above the list.
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          if (widget.topPadding > 0)
            SliverToBoxAdapter(
              child: SizedBox(
                height: widget.topPadding + MediaQuery.paddingOf(context).top,
              ),
            ),
          SliverToBoxAdapter(
            child: SearchBarHeader(
              hintText: widget.searchHint,
              accent: widget.accentColor,
              onQueryChanged: (query) {
                ref.read(widget.searchQueryProvider.notifier).state = query;
              },
            ),
          ),
          if (!isSearching && widget.kpiPeek != null)
            SliverToBoxAdapter(child: widget.kpiPeek!),
          if (!isSearching)
            SliverToBoxAdapter(
              child: _MediaBrowseFilterChips(
                filters: _filterOptions,
                selectedFilter: _selectedFilter,
                color:
                    widget.accentColor ?? Theme.of(context).colorScheme.primary,
                onSelected: (filter) {
                  setState(() {
                    _selectedFilter = filter;
                  });
                },
                sortLabel: _sortOptions[_sortIndex].label,
                sortOptions: [for (final sort in _sortOptions) sort.label],
                selectedSort: _sortIndex,
                onSortSelected: (index) {
                  setState(() {
                    _sortIndex = index;
                  });
                },
              ),
            ),
        ],
        body: isSearching
            ? _buildSearchResults(context)
            : _buildLibraryContent(context),
      ),
    );
  }

  Widget _buildLibraryContent(BuildContext context) {
    final libraryAsync = ref.watch(widget.libraryProvider);
    final (url, apiKey) = ref.watch(
      currentSettingsProvider.select(widget.settingsSelector),
    );

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(widget.libraryProvider);
        widget.onRefresh?.call(ref);
      },
      child: AsyncValueWidget<List<T>>(
        value: libraryAsync,
        serviceName: widget.serviceName,
        onRetry: () {
          ref.invalidate(widget.libraryProvider);
          widget.onRefresh?.call(ref);
        },
        data: (items) => _buildBrowseContent(
          context: context,
          items: items,
          baseUrl: url,
          apiKey: apiKey,
        ),
      ),
    );
  }

  Widget _buildSearchResults(BuildContext context) {
    final searchResultsAsync = ref.watch(widget.searchResultsProvider);
    final (url, apiKey) = ref.watch(
      currentSettingsProvider.select(widget.settingsSelector),
    );

    return searchResultsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(child: Text('Error: $error')),
      data: (results) {
        if (results == null || results.isEmpty) {
          return const Center(child: Text('No results found'));
        }

        return _buildGrid(
          context: context,
          items: results,
          baseUrl: url,
          apiKey: apiKey,
          heroTagPrefix: widget.searchHeroTagPrefix,
        );
      },
    );
  }

  Widget _buildBrowseContent({
    required BuildContext context,
    required List<T> items,
    required String baseUrl,
    required String apiKey,
  }) {
    final visibleItems = _filteredItems(items);

    if (visibleItems.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          top: AppSpacing.lg,
          bottom:
              AppSpacing.lg +
              FloatingNavBarMetrics.getScrollViewBottomPadding(context),
        ),
        children: const [
          SizedBox(height: 160),
          Center(child: Text('No items found')),
        ],
      );
    }

    final sections = _buildSections(visibleItems);
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.sm,
        bottom:
            AppSpacing.lg +
            FloatingNavBarMetrics.getScrollViewBottomPadding(context),
      ),
      itemCount: sections.length,
      itemBuilder: (context, sectionIndex) {
        final section = sections[sectionIndex];
        return Padding(
          key: ValueKey(
            'media-browse-section-${section.label.isEmpty ? 'flat' : section.label}',
          ),
          padding: EdgeInsets.only(
            bottom: sectionIndex == sections.length - 1
                ? AppSpacing.lg
                : AppSpacing.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (section.label.isNotEmpty) ...[
                Text(
                  section.label,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge!.weight(FontWeight.w600),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              LayoutBuilder(
                builder: (context, constraints) {
                  // One column math for the whole app, and the tiles fill the
                  // row they are given.
                  //
                  // This used to pin a 96pt tile — under the 130pt floor every
                  // other grid is held to — and then compute a spacing to
                  // distribute the leftover, only to `.clamp(0, gridGap)` that
                  // spacing away again. The slack it had just measured came
                  // back as a ragged right edge: at 390pt, three 96pt tiles
                  // and two 12pt gaps are 312 inside 358, so 46pt of dead
                  // space sat at the end of every row. The boards draw
                  // `repeat(N, minmax(0, 1fr))`: the count is resolved first,
                  // then the tiles take what is left.
                  final columns = MediaGrid.columnsFor(
                    constraints.maxWidth,
                    _minBrowseColumns,
                  );
                  final tileWidth = math.max(
                    1.0,
                    (constraints.maxWidth -
                            (AppSpacing.gridGap * (columns - 1))) /
                        columns,
                  );

                  return Wrap(
                    spacing: AppSpacing.gridGap,
                    runSpacing: AppSpacing.lg,
                    children: [
                      for (
                        var itemIndex = 0;
                        itemIndex < section.items.length;
                        itemIndex++
                      )
                        _BrowsePosterTile(
                          width: tileWidth,
                          shape: widget.tileShape,
                          title: widget.titleExtractor(
                            section.items[itemIndex],
                          ),
                          subtitle: widget.subtitleExtractor(
                            section.items[itemIndex],
                          ),
                          imageSource: ImageUtils.extractPosterUrl(
                            widget.imagesExtractor(section.items[itemIndex]),
                            baseUrl: baseUrl,
                            apiKey: apiKey,
                            coverTypes:
                                widget.coverTypes ?? const ['poster', 'cover'],
                          ),
                          status: widget.statusExtractor?.call(
                            section.items[itemIndex],
                          ),
                          heroTag:
                              '${widget.heroTagPrefix}_${widget.idExtractor(section.items[itemIndex])}_${section.startIndex + itemIndex}',
                          onTap: () => widget.onItemTap(
                            context,
                            section.items[itemIndex],
                            '${widget.heroTagPrefix}_${widget.idExtractor(section.items[itemIndex])}_${section.startIndex + itemIndex}',
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGrid({
    required BuildContext context,
    required List<T> items,
    required String baseUrl,
    required String apiKey,
    required String heroTagPrefix,
  }) {
    return MediaGrid<T>(
      items: items,
      imagesExtractor: widget.imagesExtractor,
      idExtractor: widget.idExtractor,
      statusExtractor: widget.statusExtractor,
      titleExtractor: widget.titleExtractor,
      baseUrl: baseUrl,
      apiKey: apiKey,
      heroTagPrefix: heroTagPrefix,
      onItemTap: (item, heroTag) {
        widget.onItemTap(context, item, heroTag);
      },
      coverTypes: widget.coverTypes ?? const ['poster', 'cover'],
    );
  }

  List<T> _filteredItems(List<T> items) {
    final cutoff = widget.cutoffUnmetIds;
    return _sortedItems(items)
        .where(
          (item) => mediaBrowseFilterMatches(
            _selectedFilter,
            widget.statusExtractor?.call(item),
            belowCutoff:
                cutoff != null && cutoff.contains(widget.idExtractor(item)),
          ),
        )
        .toList(growable: false);
  }

  /// [items] in display order, computed once per (library list, chosen order) —
  /// see [_sortedSource]. The result is never mutated afterwards.
  List<T> _sortedItems(List<T> items) {
    final cached = _sorted;
    if (cached != null &&
        identical(items, _sortedSource) &&
        _sortedUnder == _sortIndex) {
      return cached;
    }

    final sortedItems = [...items]..sort(_sortOptions[_sortIndex].compare);

    _sortedSource = items;
    _sorted = sortedItems;
    _sortedUnder = _sortIndex;
    return sortedItems;
  }

  List<_MediaBrowseSection<T>> _buildSections(List<T> items) {
    // One unlabelled run under any order but Title A–Z. The headings used to be
    // unconditional, so a date-added wall printed "A" over a section whose
    // first title happened to start with one.
    if (!_sortOptions[_sortIndex].lettered) {
      final section = _MediaBrowseSection<T>(label: '', startIndex: 0);
      section.items.addAll(items);
      return [section];
    }

    final sections = <_MediaBrowseSection<T>>[];
    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      final label = _sectionLabelFor(item);
      if (sections.isEmpty || sections.last.label != label) {
        sections.add(_MediaBrowseSection(label: label, startIndex: index));
      }
      sections.last.items.add(item);
    }
    return sections;
  }

  String _sortKeyFor(T item) {
    final sortTitle =
        (widget.sortTitleExtractor?.call(item) ?? widget.titleExtractor(item))
            .trim()
            .toLowerCase();
    return sortTitle;
  }

  String _sectionLabelFor(T item) {
    final sortKey = _sortKeyFor(item);
    if (sortKey.isEmpty) {
      return '#';
    }
    final firstCharacter = sortKey.characters.first.toUpperCase();
    return _sectionLetter.hasMatch(firstCharacter) ? firstCharacter : '#';
  }
}

class _MediaBrowseSection<T> {
  final String label;
  final int startIndex;
  final List<T> items;

  _MediaBrowseSection({required this.label, required this.startIndex})
    : items = <T>[];
}

class _MediaBrowseFilterChips extends StatelessWidget {
  final List<MediaBrowseFilter> filters;
  final MediaBrowseFilter selectedFilter;
  final Color color;
  final ValueChanged<MediaBrowseFilter> onSelected;
  final String sortLabel;
  final List<String> sortOptions;
  final int selectedSort;
  final ValueChanged<int> onSortSelected;

  const _MediaBrowseFilterChips({
    required this.filters,
    required this.selectedFilter,
    required this.color,
    required this.onSelected,
    required this.sortLabel,
    required this.sortOptions,
    required this.selectedSort,
    required this.onSortSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      // The chips scroll; the sort control does not. It is the one instrument
      // on this strip that has to stay reachable no matter how many chips a
      // service declares, and a control that scrolls off the end of a strip it
      // does not belong to is a control nobody finds.
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final filter in filters)
                    _MediaBrowseFilterChip(
                      label: switch (filter) {
                        MediaBrowseFilter.all => 'All',
                        MediaBrowseFilter.available => 'Available',
                        MediaBrowseFilter.missing => 'Missing',
                        MediaBrowseFilter.inQueue => 'In queue',
                        MediaBrowseFilter.cutoffUnmet => 'Cutoff unmet',
                        MediaBrowseFilter.unmonitored => 'Unmonitored',
                      },
                      color: color,
                      selected: selectedFilter == filter,
                      onTap: () => onSelected(filter),
                    ),
                ],
              ),
            ),
          ),
          if (sortOptions.length > 1)
            _MediaBrowseSortControl(
              label: sortLabel,
              options: sortOptions,
              selected: selectedSort,
              onSelected: onSortSelected,
            ),
        ],
      ),
    );
  }
}

/// `Sort · <label>`, opening the orders this service declared.
///
/// One order is not a choice, so the control is only built when there are two —
/// a menu whose every opening shows the same single item is a control that
/// cannot fail and cannot help either.
class _MediaBrowseSortControl extends StatelessWidget {
  final String label;
  final List<String> options;
  final int selected;
  final ValueChanged<int> onSelected;

  const _MediaBrowseSortControl({
    required this.label,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return PopupMenuButton<int>(
      tooltip: 'Change sort order',
      initialValue: selected,
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (var index = 0; index < options.length; index++)
          PopupMenuItem<int>(value: index, child: Text(options[index])),
      ],
      // The hint rides on the child, never on the button: a button is a
      // semantic boundary and an annotation wrapped around one is dropped.
      child: Semantics(
        hint: 'Sorted by $label',
        child: Container(
          // 44, and no `VisualDensity.compact` anywhere near it — compact
          // silently overrides a declared minimum and lands the real target at
          // 40.
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.swap_vert_rounded,
                size: 18,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                label,
                style: AppTheme.chrome(
                  context,
                  weight: FontWeight.w600,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MediaBrowseFilterChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _MediaBrowseFilterChip({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      // `AppRadius.pill`, not a twice-repeated literal 20. The season selector in
      // `media_child_list.dart` was deliberately unified onto this chip's
      // vocabulary, so the two were pixel-identical by coincidence rather than by
      // construction — a change to the token would have silently split them.
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        onTap: onTap,
        child: ExcludeSemantics(
          child: InkWell(
            onTap: onTap,
            borderRadius: AppRadius.borderRadiusPill,
            child: Container(
              decoration: BoxDecoration(
                color: selected ? color : color.withValues(alpha: 0.12),
                borderRadius: AppRadius.borderRadiusPill,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelMedium!
                    .weight(FontWeight.w600)
                    .copyWith(
                      // Unselected, the accent is a label on its own 12% wash,
                      // so it is walked against that composite — raw, the
                      // amber accents measured under 2:1 on the light page.
                      color: selected
                          ? ServiceTheme.foregroundOn(color)
                          : ServiceTheme.onTint(
                              color,
                              surface: Theme.of(context).colorScheme.surface,
                              tintAlpha: 0.12,
                            ),
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BrowsePosterTile extends StatelessWidget {
  /// Resolved by the row, not by the tile: the column count is decided against
  /// [MediaGrid.tileWidthFloor] first and the tiles then fill what is left, so
  /// a tile never has an opinion about how wide it is.
  final double width;

  final MediaBrowseTileShape shape;

  final String title;
  final String subtitle;
  final ImageSource imageSource;
  final MediaStatusInfo? status;
  final String heroTag;
  final VoidCallback onTap;

  const _BrowsePosterTile({
    required this.width,
    required this.shape,
    required this.title,
    required this.subtitle,
    required this.imageSource,
    required this.status,
    required this.heroTag,
    required this.onTap,
  });

  bool get isCircle => shape == MediaBrowseTileShape.circle;

  /// The portrait or the poster, sized from the width the row resolved.
  Widget _artwork(BuildContext context) {
    if (isCircle) {
      // Square, so the circle is a circle at any column count, and
      // `MediaPosterCard.circular` brings its own Hero — the rectangular path
      // has to supply one because `ContentCard` does not.
      //
      // No status dot: a circle has no corner to hold one without overlapping
      // the face, and the caption carries the completeness in words instead.
      return AspectRatio(
        aspectRatio: 1,
        child: MediaPosterCard.circular(
          heroTag: heroTag,
          imageUrl: imageSource.url,
          imageHeaders: imageSource.headers,
          fallbackIcon: Icons.person_outline,
        ),
      );
    }

    // 2:3 of whatever width the row resolved, rather than a 96×138 pair that
    // only held at one column count.
    return AspectRatio(
      aspectRatio: 2 / 3,
      child: Stack(
        children: [
          Positioned.fill(
            child: Hero(
              tag: heroTag,
              transitionOnUserGestures: MediaPosterCard.flightOnUserGestures,
              child: ContentCard(
                imageUrl: imageSource.url,
                httpHeaders: imageSource.headers,
              ),
            ),
          ),
          if (status != null)
            Positioned(
              left: 6,
              bottom: 6,
              // Redundant against the parent's `excludeSemantics`, but it keeps
              // the invariant local: the tile speaks the status, the dot does
              // not.
              child: StatusBadge(
                info: status!,
                iconOnly: true,
                excludeFromSemantics: true,
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // The status is painted inside the excluded subtree — or, on the circular
    // shape, not painted at all — so it has to be spoken here or it is lost
    // entirely.
    final spokenValue = joinDisplayParts([
      subtitle,
      status?.semanticLabel,
    ], separator: ', ');

    return SizedBox(
      width: width,
      // Labelled as one button: the visible title is truncated to a single line,
      // so a screen reader would otherwise announce a clipped name.
      child: Semantics(
        button: true,
        container: true,
        excludeSemantics: true,
        label: title,
        value: spokenValue.isEmpty ? null : spokenValue,
        onTap: onTap,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.borderRadiusMd,
          child: Column(
            crossAxisAlignment: isCircle
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              _artwork(context),
              const SizedBox(height: AppSpacing.xs),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: isCircle ? TextAlign.center : TextAlign.start,
                style: Theme.of(context).textTheme.labelSmall!
                    .weight(FontWeight.w600)
                    .copyWith(color: colorScheme.onSurface),
              ),
              if (subtitle.isNotEmpty)
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: isCircle ? TextAlign.center : TextAlign.start,
                  // Was fontSize 10, below the 11pt floor; the subtitle keeps
                  // its dimmer tone to stay a step under the title.
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
