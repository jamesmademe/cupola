import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';

import 'package:cupola/core/app_breakpoints.dart';
import 'package:cupola/core/app_gradients.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/app_bottom_sheet.dart';
import 'package:cupola/core/widgets/app_error_state.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/widgets/glass_app_bar.dart';
import 'package:cupola/core/widgets/media_grid.dart';
import 'package:cupola/core/widgets/not_configured_placeholder.dart';
import 'package:cupola/core/widgets/selection_pills.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/domain/catalog_curation.dart';
import 'package:cupola/features/discover/domain/catalog_query.dart';
import 'package:cupola/features/discover/domain/seerr_status.dart';
import 'package:cupola/features/discover/presentation/catalog_providers.dart';
import 'package:cupola/features/discover/presentation/discover_details_provider.dart';
import 'package:cupola/features/discover/presentation/widgets/catalog_poster.dart';
import 'package:cupola/features/discover/presentation/widgets/seerr_not_set_up.dart';
import 'package:cupola/features/media/presentation/media_parts.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// One catalogue page: a genre, a network, a studio, a mood, a language, a
/// decade, trending, what is coming, or the whole of one kind. Every door of
/// the atrium and every "See all" lands here.
///
/// The name, "From the Seerr catalogue", the controls that exist for this
/// base (Movies or Series where both halves do, the order, the filters,
/// "Hide what I have"), then the posters, a page at a time as the list
/// scrolls, and at the foot how many titles the list holds, as a floor when
/// Seerr's figure is capped (`catalogCountPhrase`).
class CatalogPage extends ConsumerStatefulWidget {
  const CatalogPage({super.key, required this.query});

  final CatalogQuery query;

  @override
  ConsumerState<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends ConsumerState<CatalogPage> {
  /// TMDB serves five hundred pages and refuses the five hundred and first,
  /// whatever total Seerr reports beside them.
  static const _lastPage = 500;

  /// With "Hide what I have" on, a fetch reads up to this many pages to find
  /// enough titles the server does not hold.
  static const _hiddenReads = 3;

  /// The titles a fetch with the switch on tries to bring back.
  static const _hiddenFill = 12;

  late CatalogQuery _query = widget.query;

  /// The next Seerr page to read, what Seerr said of the whole, and which
  /// question those belong to: a fetch for a query the user has moved on
  /// from leaves them alone.
  int _nextPage = 1;
  int? _totalPages;
  int? _totalResults;
  int _generation = 0;

  late final _paging = PagingController<int, MediaPreview>(
    getNextPageKey: (state) {
      final total = _totalPages;
      if (_nextPage > _lastPage || (total != null && _nextPage > total)) {
        return null;
      }
      return (state.keys?.lastOrNull ?? 0) + 1;
    },
    fetchPage: _fetch,
  );

  Future<List<MediaPreview>> _fetch(int _) async {
    final generation = _generation;
    final query = _query;
    final hide = ref.read(catalogHideOwnedProvider);
    final service = ref.read(seerrServiceProvider);
    final numbering = hide
        ? await ref.read(seerrNumberingProvider.future).catchError((_) => null)
        : null;
    final kept = <MediaPreview>[];
    for (var read = 0; read < (hide ? _hiddenReads : 1); read++) {
      final page = await service.getCatalogPage(query, page: _nextPage);
      if (generation != _generation) return const [];
      _nextPage++;
      _totalPages = page.totalPages;
      _totalResults = page.totalResults;
      kept.addAll(
        hide
            ? page.items.where(
                (item) => !seerrHolds(item.mediaInfo, numbering: numbering),
              )
            : page.items,
      );
      if (kept.length >= _hiddenFill ||
          _nextPage > math.min(page.totalPages, _lastPage)) {
        break;
      }
    }
    if (mounted) setState(() {});
    return kept;
  }

  void _ask(CatalogQuery query) {
    setState(() {
      _query = query;
      _generation++;
      _nextPage = 1;
      _totalPages = null;
      _totalResults = null;
    });
    _paging.refresh();
  }

  void _restart() => _ask(_query);

  @override
  void dispose() {
    _paging.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    // Before the pager asks for its first page: with no Seerr that page can
    // only fail, under a Retry that asks nobody.
    if (!watchSeerrConfigured(ref)) {
      return Scaffold(
        backgroundColor: room.ground,
        appBar: AppBar(title: Text(_title(ref))),
        body: NotConfiguredPlaceholder.forService(ServiceKey.seerr),
      );
    }
    ref.listen(catalogHideOwnedProvider, (previous, next) {
      if (previous != next) _restart();
    });
    // Kept alive for the fetches, which read Seerr's numbering to know which
    // titles the server holds.
    ref.watch(seerrNumberingProvider);

    final top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: room.ground,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppGradients.ambientBackground(scheme),
        ),
        child: Stack(
          children: [
            LayoutBuilder(
              builder: (context, box) => _scroll(context, box, top),
            ),
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: StatusBarScrim(),
            ),
          ],
        ),
      ),
    );
  }

  /// The page's name: the query's, or, for a genre reached by its id alone,
  /// the one Seerr's genre list gives that id.
  String _title(WidgetRef ref) {
    final title = _query.title;
    if (title.isNotEmpty) return title;
    if (_query.base == CatalogBase.genre) {
      final genres = ref.watch(catalogGenresProvider(_query.kind)).value;
      final name = genres
          ?.where((genre) => genre.id == _query.id)
          .firstOrNull
          ?.name;
      return name ?? 'Genre';
    }
    return '';
  }

  Widget _scroll(BuildContext context, BoxConstraints box, double top) {
    // On a desktop window the page stands in a well measured on its
    // columns: at 1140, seven posters at 148, the library's grid at the same
    // window (`MediaBrowseScaffold`), so a title is one size in both. The
    // scroll view keeps the window's width, so the wheel turns it anywhere
    // over the page; the gradient and the clock's scrim stay full-bleed.
    final well = AppBreakpoints.isDesktopShell(context)
        ? math.min(box.maxWidth, AppBreakpoints.contentWell)
        : box.maxWidth;
    final side = (box.maxWidth - well) / 2;
    final gutter = side + AppSpacing.lg;
    final inner = well - 2 * AppSpacing.lg;
    final columns = MediaGrid.columnsFor(inner, 3);
    final tileWidth = (inner - (columns - 1) * AppSpacing.gridGap) / columns;
    final bottom = math.max(
      AppSpacing.xxxl,
      FloatingNavBarMetrics.getScrollViewBottomPadding(context),
    );
    final count = catalogCountPhrase(_totalResults);

    return RefreshIndicator(
      edgeOffset: top,
      onRefresh: () async => _restart(),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              gutter,
              top + AppSpacing.md,
              gutter,
              0,
            ),
            sliver: SliverToBoxAdapter(child: _Head(title: _title(ref))),
          ),
          // The controls carry the gutter themselves: the pills scroll to
          // the well's edges.
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: side),
            sliver: SliverToBoxAdapter(
              child: _Controls(query: _query, onChanged: _ask),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(gutter, AppSpacing.md, gutter, 0),
            sliver: PagingListener<int, MediaPreview>(
              controller: _paging,
              builder: (context, state, fetchNextPage) =>
                  PagedSliverGrid<int, MediaPreview>(
                    state: state,
                    fetchNextPage: fetchNextPage,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisExtent: CatalogPoster.heightFor(
                        context,
                        tileWidth,
                      ),
                      crossAxisSpacing: AppSpacing.gridGap,
                      mainAxisSpacing: AppSpacing.lg,
                    ),
                    builderDelegate: PagedChildBuilderDelegate<MediaPreview>(
                      // A first page Seerr did not give is a failure in its
                      // own words, never the "nothing here" of a list that
                      // answered empty.
                      firstPageErrorIndicatorBuilder: (_) => AppErrorState(
                        error:
                            state.error ??
                            const ClassifiedFailure(
                              ServiceFailureReason.unknown,
                            ),
                        serviceName: ServiceKey.seerr.title,
                        service: ServiceKey.seerr,
                        onRetry: _restart,
                      ),
                      noItemsFoundIndicatorBuilder: (_) =>
                          _Nothing(hidden: ref.read(catalogHideOwnedProvider)),
                      itemBuilder: (context, item, index) => CatalogPoster(
                        item: item,
                        heroTag: 'catalog_${item.mediaType}_${item.id}_$index',
                        width: tileWidth,
                      ),
                    ),
                  ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(gutter, AppSpacing.lg, gutter, bottom),
            sliver: SliverToBoxAdapter(
              child: Text(
                // The trending list's figure is TMDB's cap, not a count.
                [
                  'Scores from TMDB',
                  if (count != null && _query.base != CatalogBase.trending)
                    count,
                ].join(' · '),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: CupolaThemeColors.of(context).dimText,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The way back, the name and where the titles come from. The requester
/// reads no service's name: the catalogue is the catalogue.
class _Head extends ConsumerWidget {
  const _Head({required this.title});

  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requester = ref.watch(audienceProvider) == Audience.requester;
    final room = CupolaRoom.of(context);
    final stacked = mediaStacked(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const MediaBackPlate(),
        const SizedBox(height: AppSpacing.md),
        Semantics(
          header: true,
          child: Text(
            title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: (stacked ? AppType.room : AppType.screen).copyWith(
              color: room.ink,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          requester ? 'From the catalog' : 'From the Seerr catalog',
          style: AppType.label
              .weight(FontWeight.w400)
              .copyWith(color: room.inkSecondary),
        ),
      ],
    );
  }
}

/// The controls this base has: the two halves, the order and filters, and
/// "Hide what I have". A base Seerr takes no filters on (trending, coming
/// soon) shows only what it has.
class _Controls extends ConsumerWidget {
  const _Controls({required this.query, required this.onChanged});

  final CatalogQuery query;
  final ValueChanged<CatalogQuery> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hide = ref.watch(catalogHideOwnedProvider);
    final pills = <Widget>[
      if (query.filters)
        SelectionPill(
          label: query.sort.label,
          selected: false,
          trailing: Icons.expand_more_rounded,
          onTap: () => _pickSort(context),
        ),
      if (query.base == CatalogBase.trending)
        for (final window in TrendingWindow.values)
          SelectionPill(
            label: window.label,
            selected: query.window == window,
            onTap: () => onChanged(query.withWindow(window)),
          ),
      if (query.offersDecade)
        SelectionPill(
          label: query.decadeFilter == null
              ? 'Decade'
              : decadeLabel(query.decadeFilter!),
          selected: query.decadeFilter != null,
          trailing: Icons.expand_more_rounded,
          onTap: () => _pickDecade(context),
        ),
      if (query.filters)
        SelectionPill(
          label: 'Rating 7+ · $catalogVoteFloor+ votes',
          selected: query.rated,
          onTap: () => onChanged(query.withRated(!query.rated)),
        ),
      if (query.offersShort)
        SelectionPill(
          label: 'Under 100\u00A0min',
          selected: query.short,
          onTap: () => onChanged(query.withShort(!query.short)),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.md),
        if (query.kinds.isNotEmpty)
          SelectionPills<CatalogKind>(
            values: query.kinds,
            selected: query.kind,
            labelBuilder: (kind) => kind.label,
            onSelected: (kind) => onChanged(query.withKind(kind)),
          ),
        if (pills.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: SelectionPills.gutter,
            child: Row(
              children: [
                for (final pill in pills)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: pill,
                  ),
              ],
            ),
          ),
        _HideOwned(
          value: hide,
          onChanged: ref.read(catalogHideOwnedProvider.notifier).set,
        ),
      ],
    );
  }

  Future<void> _pickSort(BuildContext context) async {
    final sort = await AppBottomSheet.show<CatalogSort>(
      context: context,
      title: 'Order',
      builder: (sheet) => SelectionPills<CatalogSort>.wrap(
        values: CatalogSort.values,
        selected: query.sort,
        labelBuilder: (sort) => sort.label,
        onSelected: (sort) => Navigator.of(sheet).pop(sort),
      ),
    );
    if (sort != null && sort != query.sort) onChanged(query.withSort(sort));
  }

  Future<void> _pickDecade(BuildContext context) async {
    // Zero stands for "any decade" in the sheet, which a pill value cannot
    // leave empty.
    final start = await AppBottomSheet.show<int>(
      context: context,
      title: 'Decade',
      builder: (sheet) => SelectionPills<int>.wrap(
        values: [
          0,
          ...catalogDecades(today: DateTime.now()),
        ],
        selected: query.decadeFilter ?? 0,
        labelBuilder: (start) => start == 0 ? 'Any' : decadeLabel(start),
        onSelected: (start) => Navigator.of(sheet).pop(start),
      ),
    );
    if (start == null) return;
    final next = start == 0 ? null : start;
    if (next != query.decadeFilter) onChanged(query.withDecade(next));
  }
}

/// "Hide what I have": one switch for the whole catalogue.
///
/// The row is a phone's at most ([AppBreakpoints.splitList]), at the head of
/// a wider page: across a tablet or a desktop window the switch would sit a
/// thousand points from the words that say what it does.
class _HideOwned extends StatelessWidget {
  const _HideOwned({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppBreakpoints.splitList),
        child: _row(room),
      ),
    );
  }

  Widget _row(CupolaRoom room) {
    return MergeSemantics(
      child: InkWell(
        onTap: () => onChanged(!value),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Hide what I have',
                    style: AppType.row
                        .weight(FontWeight.w500)
                        .copyWith(color: room.ink),
                  ),
                ),
                Switch(value: value, onChanged: onChanged),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A page with no titles to show.
class _Nothing extends StatelessWidget {
  const _Nothing({required this.hidden});

  final bool hidden;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
      child: Text(
        // With the switch on, an empty page can be one the server holds
        // whole, which is not a catalogue with nothing in it.
        hidden
            ? 'You have every title here. Turn off Hide what I have to see '
                  'them.'
            : 'Seerr has no titles here.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: CupolaThemeColors.of(context).dimText,
        ),
      ),
    );
  }
}

/// The page a catalogue route resolves to from its path alone: the base
/// from the path, the kind and id from its parameters, the name from the
/// curated lists or the `title` the link carried. Null for parameters this
/// app cannot read, which the router sends back to the atrium.
CatalogQuery? catalogQueryFor(
  CatalogBase base,
  Map<String, String> path,
  Map<String, String> query,
) {
  final kind = CatalogKind.parse(path['kind']);
  final id = int.tryParse(path['id'] ?? '');
  final title = query['title']?.trim();
  final name = title == null || title.isEmpty ? null : title;
  switch (base) {
    case CatalogBase.all:
      return kind == null ? null : CatalogQuery.all(kind);
    case CatalogBase.trending:
      return CatalogQuery.trending(
        window: query['window'] == TrendingWindow.day.param
            ? TrendingWindow.day
            : TrendingWindow.week,
      );
    case CatalogBase.upcoming:
      return kind == null ? null : CatalogQuery.upcoming(kind);
    case CatalogBase.genre:
      // The name is optional: the page finds it in Seerr's genre list.
      if (kind == null || id == null) return null;
      return CatalogQuery.genre(kind, id, name ?? '');
    case CatalogBase.network:
      if (id == null) return null;
      return CatalogQuery.network(
        id,
        curatedById(curatedNetworks, id)?.name ?? name ?? 'Network',
      );
    case CatalogBase.studio:
      if (id == null) return null;
      return CatalogQuery.studio(
        id,
        curatedById(curatedStudios, id)?.name ?? name ?? 'Studio',
      );
    case CatalogBase.keyword:
      if (kind == null || id == null) return null;
      return CatalogQuery.keyword(
        kind,
        id,
        curatedById(curatedMoods, id)?.name ?? name ?? 'Mood',
      );
    case CatalogBase.language:
      final code = path['code'];
      if (kind == null || code == null || code.isEmpty) return null;
      return CatalogQuery.language(
        kind,
        code,
        curatedLanguage(code)?.name ?? name ?? code.toUpperCase(),
      );
    case CatalogBase.decade:
      final start = int.tryParse(path['start'] ?? '');
      if (kind == null || start == null || start % 10 != 0 || start < 1870) {
        return null;
      }
      return CatalogQuery.decade(kind, start);
  }
}
