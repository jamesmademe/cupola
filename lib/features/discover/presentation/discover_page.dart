import 'dart:async';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_breakpoints.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/providers/navigation_refresh_provider.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/utils/unit_space.dart';
import 'package:cupola/core/widgets/ambient_scaffold.dart';
import 'package:cupola/core/widgets/brief_failure_line.dart';
import 'package:cupola/core/widgets/failure_remedy.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/widgets/glass_app_bar.dart';
import 'package:cupola/core/widgets/not_configured_placeholder.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';
import 'package:cupola/core/widgets/search_bar_header.dart';
import 'package:cupola/core/widgets/shimmer_placeholder.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/discover/domain/seerr_numbering.dart';
import 'package:cupola/features/discover/domain/seerr_status.dart';
import 'package:cupola/features/discover/presentation/discover_atrium.dart';
import 'package:cupola/features/discover/presentation/discover_calendar_band.dart';
import 'package:cupola/features/discover/presentation/discover_details_provider.dart';
import 'package:cupola/features/discover/presentation/discover_room_light.dart';
import 'package:cupola/features/discover/presentation/widgets/discover_region_chip.dart';
import 'package:cupola/features/discover/presentation/widgets/search_row.dart';
import 'package:cupola/features/discover/presentation/widgets/seerr_not_set_up.dart';
import 'package:cupola/features/media/presentation/media_add_sheet.dart';
import 'package:cupola/features/media/presentation/open_media.dart';
import 'package:cupola/features/music/presentation/music_search_provider.dart';
import 'package:cupola/features/search/domain/global_search_result.dart';
import 'package:cupola/features/search/domain/search_sections.dart';
import 'package:cupola/features/search/presentation/global_search_provider.dart';
import 'package:cupola/features/search/presentation/recent_searches_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The Discover tab: at rest it browses Seerr's catalogue (the atrium);
/// focused and empty, it offers the recent searches; typing, it searches
/// everywhere and lays the answer out by kind: On your server,
/// Movies, Series, People, then Lidarr's own search for the word.
class DiscoverPage extends ConsumerStatefulWidget {
  const DiscoverPage({super.key});

  @override
  ConsumerState<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends ConsumerState<DiscoverPage> {
  final _focus = FocusNode(debugLabel: 'discover search');

  /// The field's place in the tree, wherever it is drawn. At rest it heads
  /// the atrium and scrolls with it; in use, it takes the title's place at
  /// the top. The key carries the one field from the first place to the
  /// second with its focus and its keyboard, and a screen reader stays on it.
  final _fieldKey = GlobalKey(debugLabel: 'discover field');

  /// How long a query has to stay put, with answers, before it is a recent
  /// search: the time it takes to stop typing and start reading. Recorded at
  /// once, every prefix the debounce let through ("dun", then "dune") would
  /// be a search of its own.
  static const recentAfter = Duration(seconds: 2);
  Timer? _recentTimer;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  @override
  void dispose() {
    _recentTimer?.cancel();
    _focus.removeListener(_onFocus);
    _focus.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (mounted) setState(() {});
  }

  /// Puts [query] in the field and runs it, as a recent search does.
  void _run(String query) {
    ref.read(globalSearchQueryProvider.notifier).state = query;
    ref.read(globalSearchFieldVersionProvider.notifier).state++;
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(globalSearchQueryProvider);
    final fieldVersion = ref.watch(globalSearchFieldVersionProvider);
    final bottomPadding = FloatingNavBarMetrics.getScrollViewBottomPadding(
      context,
    );

    // The tab again, at the top: a clean field and the keyboard put away.
    ref.listen<int>(navigationRefreshProvider(NavigationSection.discover), (
      previous,
      next,
    ) {
      ref.read(globalSearchQueryProvider.notifier).state = '';
      ref.read(globalSearchFieldVersionProvider.notifier).state++;
      _focus.unfocus();
    });

    // ⌘R's own channel: run this query again, rather than throw it away.
    ref.listen<int>(globalSearchRerunProvider, (previous, next) {
      rerunGlobalSearch(ref);
    });

    // A query that found something, and that the person stayed on, is a
    // recent search.
    ref.listen<List<GlobalSearchServiceResults>>(globalSearchLanesProvider, (
      previous,
      next,
    ) {
      final q = ref.read(globalSearchQueryProvider).trim();
      if (q.isEmpty || !next.any((lane) => lane.results.isNotEmpty)) return;
      _recentTimer?.cancel();
      _recentTimer = Timer(recentAfter, () {
        if (!mounted) return;
        if (ref.read(globalSearchQueryProvider).trim() != q) return;
        ref.read(recentSearchesProvider.notifier).add(q);
      });
    });

    final searching = query.trim().isNotEmpty;
    final engaged = searching || _focus.hasFocus;
    final seerr = watchSeerrConfigured(ref);
    final requester = ref.watch(audienceProvider) == Audience.requester;

    // People come from Seerr: without it the field finds titles alone.
    final hint = seerr || requester
        ? 'Movies, series, people'
        : 'Movies and series';
    final field = KeyedSubtree(
      key: _fieldKey,
      child: SearchBarHeader(
        key: ValueKey(fieldVersion),
        initialQuery: query,
        focusNode: _focus,
        hintText: hint,
        onQueryChanged: (value) {
          ref.read(globalSearchQueryProvider.notifier).state = value;
        },
        onCancel: () {},
      ),
    );

    // At rest, as drawn: the tab's title in the tab-root role, its region
    // beside it, the field under them, all scrolled away with the doors.
    final head = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DiscoverTitle(region: seerr),
        field,
      ],
    );

    final Widget body;
    if (searching) {
      body = _Results(query: query.trim(), bottomPadding: bottomPadding);
    } else if (engaged) {
      body = _Recents(onPick: _run, bottomPadding: bottomPadding);
    } else if (seerr) {
      body = DiscoverAtrium(head: head, bottomPadding: bottomPadding);
    } else if (ref
        .watch(currentSettingsProvider)
        .hasServiceConnection(ServiceKey.seerr)) {
      // A Seerr whose session ended: that, and the way back.
      body = Column(
        children: [
          head,
          Expanded(
            child: NotConfiguredPlaceholder.forService(ServiceKey.seerr),
          ),
        ],
      );
    } else {
      body = Column(
        children: [
          head,
          Expanded(child: _WithoutSeerr(bottomPadding: bottomPadding)),
        ],
      );
    }

    // The room takes the most coloured light of the band's next thing and
    // Trending's first titles.
    final light = ref.watch(discoverRoomLightProvider);
    return AmbientScaffold(
      accent: light?.light,
      art: light?.art,
      accentDuration: AppAnimation.light,
      // The tab's well on a desktop window is measured on the catalogue's
      // columns: at 1140 the atrium's grids and the catalogue page they open
      // hold seven posters at 148, the library's grid at the same window. The
      // answers to a search are rows, and take the reading well inside it
      // (`_rowsPadding`).
      contentWellWidth: AppBreakpoints.contentWell,
      body: Stack(
        children: [
          if (engaged)
            // Engaged, the field takes the title's place, as drawn, and with
            // its Cancel takes the column its answers read in.
            Column(
              children: [
                SizedBox(height: MediaQuery.paddingOf(context).top),
                LayoutBuilder(
                  builder: (context, box) => Padding(
                    padding: EdgeInsets.only(right: _rowsInset(box.maxWidth)),
                    child: field,
                  ),
                ),
                Expanded(child: body),
              ],
            )
          else
            body,
          // The doors pass under the clock, as every tab root's content does.
          const Positioned(top: 0, left: 0, right: 0, child: StatusBarScrim()),
        ],
      ),
    );
  }
}

/// `Discover`, said once in the tab-root role, as Activity and the Stack say
/// theirs, and Seerr's region beside it when there is a Seerr to read it.
class _DiscoverTitle extends StatelessWidget {
  const _DiscoverTitle({required this.region});

  final bool region;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        MediaQuery.paddingOf(context).top + AppSpacing.sm,
        AppSpacing.gutter,
        AppSpacing.s,
      ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                'Discover',
                style: AppType.screen.copyWith(color: room.ink),
              ),
            ),
          ),
          if (region) const DiscoverRegionChip(),
        ],
      ),
    );
  }
}

/// The recent searches, while the field is focused and empty.
class _Recents extends ConsumerWidget {
  const _Recents({required this.onPick, required this.bottomPadding});

  final ValueChanged<String> onPick;
  final double bottomPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recents = ref.watch(recentSearchesProvider);
    if (recents.isEmpty) return const SizedBox.shrink();
    final room = CupolaRoom.of(context);
    final notifier = ref.read(recentSearchesProvider.notifier);
    // Part of the field, for a click: a mouse press anywhere else takes the
    // field's focus, and with it these rows, before the press lands on one.
    return TextFieldTapRegion(
      child: LayoutBuilder(
        builder: (context, box) => ListView(
          padding: _rowsPadding(box.maxWidth, bottom: bottomPadding),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            Row(
              children: [
                Expanded(child: _Heading('Recent searches', top: 0)),
                TextButton(
                  onPressed: notifier.clear,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(44, 44),
                    visualDensity: VisualDensity.standard,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                    ),
                    foregroundColor: room.inkSecondary,
                    textStyle: AppType.label,
                  ),
                  child: const Text('Clear'),
                ),
              ],
            ),
            for (var i = 0; i < recents.length; i++)
              DecoratedBox(
                decoration: BoxDecoration(
                  border: i == 0
                      ? null
                      : Border(top: BorderSide(color: room.hair)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: PressableScale(
                        onTap: () => onPick(recents[i]),
                        semanticLabel: recents[i],
                        excludeChildSemantics: true,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 50),
                          child: Row(
                            children: [
                              Icon(
                                Icons.history_rounded,
                                size: 20,
                                color: room.inkSecondary,
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: Text(
                                  recents[i],
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppType.body.copyWith(color: room.ink),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => notifier.remove(recents[i]),
                      tooltip: 'Remove ${recents[i]} from recent searches',
                      icon: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: room.inkSecondary,
                      ),
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

/// A list of rows at the head of the tab, never wider than a page of one
/// column ([AppBreakpoints.readingWell]): a title's row and its add, a
/// recent search and its remove, are read across, and stretched over a
/// tablet on its side the control stops belonging to its row. The list still
/// scrolls the whole width, and on a phone this is the gutter alone.
EdgeInsets _rowsPadding(double width, {required double bottom}) =>
    EdgeInsets.fromLTRB(
      AppSpacing.lg,
      0,
      AppSpacing.lg + _rowsInset(width),
      bottom,
    );

/// How much of [width] lies right of the rows' column, past its gutter.
double _rowsInset(double width) =>
    math.max(0, width - 2 * AppSpacing.lg - AppBreakpoints.readingWell);

/// A section's name, in the secondary ink.
class _Heading extends StatelessWidget {
  const _Heading(this.text, {this.top = AppSpacing.md});

  final String text;
  final double top;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(top: top, bottom: AppSpacing.xxs),
    child: Semantics(
      header: true,
      child: Text(
        text,
        style: AppType.label.copyWith(
          color: CupolaRoom.of(context).inkSecondary,
        ),
      ),
    ),
  );
}

/// What a search found, by kind.
class _Results extends ConsumerWidget {
  const _Results({required this.query, required this.bottomPadding});

  final String query;
  final double bottomPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lanes = ref.watch(globalSearchLanesProvider);
    final requester = ref.watch(audienceProvider) == Audience.requester;
    final sections = searchSections(
      lanes,
      numbering: ref.watch(seerrNumberingProvider).value,
    );
    final room = CupolaRoom.of(context);
    final dim = room.inkSecondary;
    final lidarr =
        !requester &&
        ref.watch(
          currentSettingsProvider.select(
            (settings) => settings.isServiceConfigured(ServiceKey.lidarr),
          ),
        );

    final people = <Widget>[
      if (sections.people.isNotEmpty || sections.peopleAsked) ...[
        const _Heading('People'),
        if (sections.people.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.s),
            child: Text(
              'No one called “$query”',
              style: AppType.meta.copyWith(color: dim),
            ),
          ),
        for (final person in sections.people)
          SearchRow.person(
            name: person.title,
            line: person.knownFor.isEmpty
                ? ''
                : 'Known for ${person.knownFor.take(2).join(', ')}',
            face: person.imageUrl,
            onTap: () => context.pushMounted(person.route),
            selected: context.paneShowsPerson(person.id),
          ),
      ],
    ];

    final children = <Widget>[
      // What is missing first: it qualifies everything under it.
      for (final lane in sections.silent) _SilentSource(lane: lane),
      if (sections.isEmpty && sections.searching)
        const _Searching()
      else if (sections.isEmpty) ...[
        if (sections.silent.length < lanes.length) _Nothing(query: query),
      ] else ...[
        if (sections.onServer.isNotEmpty) ...[
          const _Heading('On your server', top: AppSpacing.xs),
          for (final title in sections.onServer) _TitleRow(title: title),
        ],
        // A word that names someone leads with them; else the titles do.
        if (sections.peopleFirst) ...people,
        if (sections.movies.isNotEmpty) ...[
          const _Heading('Movies'),
          for (final title in sections.movies) _TitleRow(title: title),
        ],
        if (sections.series.isNotEmpty) ...[
          const _Heading('Series'),
          for (final title in sections.series) _TitleRow(title: title),
        ],
        if (!sections.peopleFirst) ...people,
        if (sections.searching) const _Searching(rows: 1),
      ],
      if (lidarr && sections.settled) _LidarrLink(query: query),
    ];

    return LayoutBuilder(
      builder: (context, box) => ListView(
        padding: _rowsPadding(
          box.maxWidth,
          bottom: AppSpacing.xl + bottomPadding,
        ),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: children,
      ),
    );
  }
}

/// One title of the answer: what it is, where it stands, and the plus where
/// the operator may add it.
class _TitleRow extends ConsumerWidget {
  const _TitleRow({required this.title});

  final SearchTitle title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    final audience = ref.watch(audienceProvider);
    final status = _statusOf(
      title,
      numbering: ref.watch(seerrNumberingProvider).value,
      audience: audience,
    );
    final connections = title.addable && audience == Audience.operator
        ? settings.configuredInstancesOf(title.arr)
        : const [];
    final where = connections.length == 1
        ? settings.connectionTitle(connections.single.id, title.arr)
        : title.arr.title;
    final score = title.score;
    final meta = [
      title.isMovie ? 'Movie' : 'Series',
      if (title.year != null) '${title.year}',
      if (score != null) 'TMDB$unitSpace${score.toStringAsFixed(1)}',
    ].join(dotSeparator);

    return SearchRow.title(
      title: title.title,
      meta: meta,
      status: status,
      poster: title.imageUrl,
      posterHeaders: title.imageHeaders,
      heroTag: title.canFlyPoster ? title.heroTag : null,
      onTap: () => context.pushMounted(title.route, extra: title.routeExtra),
      selected: title.key != null && context.paneShows(title.key!),
      action: connections.isEmpty
          ? null
          : SearchRowAdd(
              label: 'Add ${title.title} to $where',
              onTap: () => _add(context, ref),
            ),
    );
  }

  /// The add sheet the title's page opens; then its arr is asked again, so
  /// the row moves to On your server on the arr's word, not on a guess.
  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final settings = ref.read(currentSettingsProvider);
    String name(ServiceInstance connection) =>
        settings.connectionTitle(connection.id, connection.service);
    final added = await showMediaAddSheet(
      context,
      arr: title.arr,
      connections: settings.configuredInstancesOf(title.arr),
      name: name,
      title: title.title,
      tmdbId: title.key?.tmdbId,
      tvdbId: title.key?.tvdbId,
      year: title.year?.toString(),
    );
    if (added == null || !context.mounted) return;
    SnackBarHelper.success(context, 'Added to ${name(added)}');
    for (final leg in ref.read(globalSearchLegsProvider)) {
      if (leg.instance.service == title.arr) {
        ref.invalidate(globalSearchLegProvider(leg));
      }
    }
  }
}

/// Where a title stands, in the words of whoever reads it: on a media server
/// it is there; else what Seerr says (requested, processing, there in part);
/// else which arr's library holds it.
({String label, StatusTone tone})? _statusOf(
  SearchTitle title, {
  required SeerrNumbering? numbering,
  required Audience audience,
}) {
  if (title.servers.isNotEmpty) {
    return (
      label: 'On ${title.servers.join(' and ')}',
      tone: StatusTone.success,
    );
  }
  final seerr = seerrCatalogStatus(
    title.seerrInfo,
    numbering: numbering,
    audience: audience,
  );
  if (seerr != null) return (label: seerr.label, tone: seerr.tone);
  if (title.libraries.isNotEmpty) {
    return (label: 'In ${title.libraries.first}', tone: StatusTone.neutral);
  }
  return null;
}

/// A source that stopped short of an answer: what is missing and why, once,
/// with the remedy its cause names and Retry where asking again can help.
/// The requester reads one line, never the cause.
class _SilentSource extends ConsumerWidget {
  const _SilentSource({required this.lane});

  final GlobalSearchServiceResults lane;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gate = ref.watch(roleGateOfProvider(lane.instanceId));
    void retry() => ref.invalidate(globalSearchLegProvider(lane.leg));
    if (!gate.namesService(lane.service)) {
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: BriefFailureLine.line(
          error: lane.reason == null ? null : ClassifiedFailure(lane.reason!),
          onRetry: retry,
          service: lane.service,
          instanceId: lane.instanceId,
        ),
      );
    }
    final colorScheme = Theme.of(context).colorScheme;
    final tone = statusToneColor(colorScheme, lane.state.tone);
    final remedy = lane.reason == null
        ? null
        : FailureRemedy.forReason(
            lane.service,
            lane.reason!,
            instanceId: lane.instanceId,
            gateway: lane.gateway,
          );
    final verbs = failureLineVerbs(
      context,
      remedy: remedy,
      fault: lane.state.tone == StatusTone.warning,
      onRetry: retry,
      subject: lane.titleFor(gate),
    );
    final sentence = Row(
      children: [
        Icon(_glyph, size: 18, color: tone),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            lane.faultSentence,
            style: AppType.meta.copyWith(
              color: CupolaRoom.of(context).inkSecondary,
            ),
          ),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      // A lone Retry sits beside the sentence; a remedy is a phrase, and
      // takes the line under it, at the trailing edge.
      child: verbs.length == 1 && remedy == null
          ? Row(
              children: [
                Expanded(child: sentence),
                const SizedBox(width: AppSpacing.sm),
                verbs.single,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: sentence,
                ),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: AppSpacing.xs,
                  children: verbs,
                ),
              ],
            ),
    );
  }

  /// The glyph the settings rows use for the same reason.
  IconData get _glyph => switch (lane.state) {
    SearchLaneState.timedOut => Icons.timer_off_rounded,
    SearchLaneState.unreachable => Icons.cloud_off_rounded,
    _ => failureIcon(lane.reason ?? ServiceFailureReason.unknown),
  };
}

/// Rows still on their way: plates at a row's size.
class _Searching extends StatelessWidget {
  const _Searching({this.rows = 3});

  final int rows;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Searching',
    child: Column(
      children: [
        for (var i = 0; i < rows; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Row(
              children: [
                ShimmerPlaceholder(
                  width: 44,
                  height: 66,
                  borderRadius: BorderRadius.circular(AppRadius.thumb),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ShimmerPlaceholder(
                        height: 14,
                        width: 160,
                        borderRadius: AppRadius.borderRadiusXs,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      ShimmerPlaceholder(
                        height: 12,
                        width: 100,
                        borderRadius: AppRadius.borderRadiusXs,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

/// Nothing anywhere, once every source has answered.
class _Nothing extends StatelessWidget {
  const _Nothing({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: Column(
        children: [
          Text(
            'Nothing called “$query”',
            textAlign: TextAlign.center,
            style: AppType.section.copyWith(color: room.ink),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'No movie, series or person by that name. A release name is '
            'often not the title: try the name of the series.',
            textAlign: TextAlign.center,
            style: AppType.meta.copyWith(color: room.inkSecondary),
          ),
        ],
      ),
    );
  }
}

/// Lidarr's own search for the word: music is not in the catalogue.
class _LidarrLink extends ConsumerWidget {
  const _LidarrLink({required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = CupolaRoom.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: PressableScale(
        onTap: () {
          ref.read(musicSearchQueryProvider.notifier).state = query;
          context.go(ServiceRoutes.lidarrLibrary);
        },
        semanticLabel: 'Search Lidarr for $query',
        semanticHint: 'Music is not in the movie and series catalog',
        excludeChildSemantics: true,
        child: Container(
          constraints: const BoxConstraints(minHeight: 60),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: room.fillQuiet,
            borderRadius: BorderRadius.circular(AppRadius.door),
            border: Border.all(color: room.hair),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: room.fillQuiet,
                  borderRadius: AppRadius.borderRadiusMd,
                  border: Border.all(color: room.hair),
                ),
                child: Icon(ServiceKey.lidarr.icon, size: 19, color: room.ink),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Search Lidarr for “$query”',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.row.copyWith(color: room.ink),
                    ),
                    Text(
                      'Artists and albums aren’t in the movie catalog',
                      style: AppType.meta.copyWith(color: room.inkSecondary),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: room.inkSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

/// At rest with no Seerr: the catalogue's place, and what the field can
/// still reach. With nothing searchable set up, one way in.
class _WithoutSeerr extends ConsumerWidget {
  const _WithoutSeerr({required this.bottomPadding});

  final double bottomPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    final room = CupolaRoom.of(context);
    if (ref.watch(audienceProvider) == Audience.requester) {
      return NotConfiguredPlaceholder.forService(ServiceKey.seerr);
    }
    final searchable = globalSearchServices
        .where(settings.isServiceConfigured)
        .toList(growable: false);

    if (searchable.isEmpty) {
      final notSetUp = globalSearchServices
          .where((service) => !settings.hasServiceConnection(service))
          .toList(growable: false);
      return ListView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.xxl,
          AppSpacing.xl,
          bottomPadding,
        ),
        children: [
          Icon(Icons.link_off_rounded, size: 48, color: room.inkSecondary),
          const SizedBox(height: AppSpacing.md),
          Text(
            'No searchable service is set up',
            textAlign: TextAlign.center,
            style: AppType.row.copyWith(color: room.ink),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            // "or": any one of them is enough to search from here.
            '${Lexicon.setUp(_serviceList(notSetUp, conjunction: 'or'))} '
            'to search your libraries from here.',
            textAlign: TextAlign.center,
            style: AppType.meta.copyWith(color: room.inkSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          Center(
            child: FilledButton(
              // `go`: Connections lives in the Settings branch.
              onPressed: () => context.go(ServiceRoutes.settingsConnections),
              child: const Text('Set up a service'),
            ),
          ),
        ],
      );
    }

    return ListView(
      // No side padding: the band carries its own margins, as in the atrium.
      padding: EdgeInsets.only(top: AppSpacing.sm, bottom: bottomPadding),
      children: [
        // The calendar comes from the arrs, and needs no Seerr.
        const DiscoverCalendarBand(),
        // A paragraph: never a line longer than a page of one column.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          alignment: AlignmentDirectional.topStart,
          child: Container(
            // The whole width up to the measure, whatever the words take.
            width: double.infinity,
            constraints: const BoxConstraints(
              maxWidth: AppBreakpoints.readingWell,
            ),
            padding: const EdgeInsets.all(AppSpacing.xl),
            decoration: BoxDecoration(
              color: room.slab,
              borderRadius: BorderRadius.circular(AppRadius.group),
              border: Border.all(color: room.hair),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'The catalog comes from Seerr',
                  style: AppType.section.copyWith(color: room.ink),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Set up Seerr to browse movies and series by genre, network '
                  'and studio, and see what is coming. The field above '
                  'searches ${_serviceList(searchable)}.',
                  style: AppType.meta.copyWith(color: room.inkSecondary),
                ),
                const SizedBox(height: AppSpacing.lg),
                FilledButton(
                  onPressed: () =>
                      context.push(ServiceRoutes.setUp(ServiceKey.seerr)),
                  child: Text(Lexicon.setUp(ServiceKey.seerr.title)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// "Radarr", "Radarr and Sonarr", "Radarr, Sonarr and Plex"; with
/// [conjunction] `or`, a list where any one will do.
String _serviceList(List<ServiceKey> services, {String conjunction = 'and'}) {
  final titles = services.map((s) => s.title).toList(growable: false);
  if (titles.length == 1) return titles.single;
  return '${titles.sublist(0, titles.length - 1).join(', ')} $conjunction '
      '${titles.last}';
}
