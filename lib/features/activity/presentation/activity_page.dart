import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_breakpoints.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/lifecycle/page_activity.dart';
import 'package:cupola/core/lifecycle/refresh_on_return.dart';
import 'package:cupola/core/providers/navigation_refresh_provider.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/ambient_scaffold.dart';
import 'package:cupola/core/widgets/brief_failure_line.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/widgets/glass_app_bar.dart';
import 'package:cupola/core/widgets/page_tabs.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/activity/data/acted_faults.dart';
import 'package:cupola/features/activity/data/activity_live.dart';
import 'package:cupola/features/activity/domain/activity_history.dart';
import 'package:cupola/features/activity/domain/activity_readout.dart';
import 'package:cupola/features/activity/domain/activity_download.dart';
import 'package:cupola/features/activity/domain/activity_tab.dart';
import 'package:cupola/features/activity/domain/everyones_requests.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_download_row.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_history_row.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_section.dart';
import 'package:cupola/features/activity/presentation/widgets/decision_fault_card.dart';
import 'package:cupola/features/activity/presentation/widgets/requests_list.dart';
import 'package:cupola/features/activity/presentation/widgets/stuck_download_card.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/home/data/answered_requests.dart';
import 'package:cupola/features/home/domain/downloads.dart';
import 'package:cupola/features/home/domain/home_module.dart';
import 'package:cupola/features/home/presentation/widgets/home_module_parts.dart';
import 'package:cupola/features/home/presentation/widgets/home_well.dart';
import 'package:cupola/features/home/presentation/widgets/now_playing_module.dart';
import 'package:cupola/features/import/presentation/import_service_picker_sheet.dart';
import 'package:cupola/features/release_search/presentation/release_searches_body.dart';
import 'package:cupola/features/requests/domain/my_requests.dart';
import 'package:cupola/features/requests/presentation/my_request_actions.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/services/presentation/dashboard_retry.dart';
import 'package:cupola/features/services/presentation/dashboard_sections.dart'
    show DecisionRow;
import 'package:cupola/features/services/presentation/nothing_set_up.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/presentation/stream_activity_provider.dart';

/// The services Activity reads: the queues, the clients, the requests and
/// the media servers. With none of them set up the page has nothing to say
/// and says how to begin.
const _activityServices = [
  ServiceKey.radarr,
  ServiceKey.sonarr,
  ServiceKey.lidarr,
  ServiceKey.readarr,
  ServiceKey.qbittorrent,
  ServiceKey.transmission,
  ServiceKey.sabnzbd,
  ServiceKey.nzbget,
  ServiceKey.seerr,
  ServiceKey.jellyfin,
  ServiceKey.plex,
];

/// The arrs whose History tab the page's foot leads to.
const _historyServices = [
  ServiceKey.sonarr,
  ServiceKey.radarr,
  ServiceKey.lidarr,
  ServiceKey.readarr,
];

/// How many downloads All draws before the way to Downloads.
const _allDownloadsLimit = 5;

/// How many waiting downloads All draws before the way to Downloads.
const _allUpNextLimit = 3;

/// How many of today's imports All draws before the way to History.
const _allFinishedLimit = 5;

/// Activity: what is moving, what is stuck, who asked and who is watching.
///
/// One page with four views, each at its own address ([ActivityTab]): All,
/// Downloads, Requests and History. A view is a choice, never a filter on
/// top of another. The page has no app bar: its name, the line under it and
/// the views scroll with it, as the Home's day does.
class ActivityPage extends ConsumerWidget {
  const ActivityPage({super.key, required this.tab, this.requestsOf});

  /// The view the address names.
  final ActivityTab tab;

  /// The Seerr connection the Requests view reads (`?i=`), or null for
  /// every one.
  final String? requestsOf;

  /// How stale the page may be before returning to it earns a refetch: the
  /// Home's two minutes, for the same reads.
  static const staleAfter = Duration(minutes: 2);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<int>(
      navigationRefreshProvider(NavigationSection.activity),
      (_, _) => invalidateActivity(ref, tab),
    );
    ref.watchWhileLive(context, activityLivePollProvider(tab));

    final bottomPadding = FloatingNavBarMetrics.getScrollViewBottomPadding(
      context,
    );
    final settings = ref.watch(currentSettingsProvider);
    final nothingSetUp = !_activityServices.any(settings.isServiceConfigured);

    return RefreshOnReturn(
      id: 'activity',
      maxAge: staleAfter,
      onStale: () => ref.triggerNavigationRefresh(NavigationSection.activity),
      child: AmbientScaffold(
        body: nothingSetUp
            ? NothingSetUpView(bottomPadding: bottomPadding)
            : Stack(
                children: [
                  RefreshIndicator(
                    onRefresh: () => refreshActivity(ref, tab),
                    child: LayoutBuilder(
                      builder: (context, box) => HomeWell(
                        inset: AppBreakpoints.wellInset(box.maxWidth),
                        child: Builder(
                          builder: (context) {
                            Widget column(Widget child) =>
                                HomeWell.column(context, child);
                            return ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: EdgeInsets.only(bottom: bottomPadding),
                              children: [
                                column(const _ActivityHeader()),
                                column(
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      AppSpacing.gutter,
                                      AppSpacing.md,
                                      AppSpacing.gutter,
                                      0,
                                    ),
                                    child: PageTabs<ActivityTab>(
                                      values: ActivityTab.values,
                                      selected: tab,
                                      labelBuilder: (tab) => tab.label,
                                      onSelected: (tab) =>
                                          context.go(tab.location),
                                    ),
                                  ),
                                ),
                                for (final section in _sectionsOf(tab))
                                  column(section),
                                const SizedBox(height: AppSpacing.lg),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
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

  List<Widget> _sectionsOf(ActivityTab tab) => switch (tab) {
    ActivityTab.all => const [
      _NeedsYouSection(),
      _EveryonesRequestsSection(),
      _WatchingNowSection(),
      _DownloadsSection(limit: _allDownloadsLimit),
      _UpNextSection(limit: _allUpNextLimit),
      _FinishedTodaySection(),
      _HistoryFoot(),
    ],
    ActivityTab.downloads => [
      ReleaseSearchesGroup(
        heading: (count) => _GroupHeading(
          title: 'Searching',
          meta: count == 1 ? '1 search' : '$count searches',
        ),
      ),
      const _DownloadsSection(),
      const _UpNextSection(),
    ],
    ActivityTab.requests => [_RequestsView(requestsOf)],
    ActivityTab.history => const [
      _HistoryDays(),
      _HistoryFoot(blocklist: true),
    ],
  };
}

/// The Requests view: the list of the Seerr connection the address names.
///
/// A link outlives the connection it names (a row opened, that Seerr deleted
/// in Settings, the link followed again): the list then reads the lens's, as
/// a link naming none does. Handed the dead id it would say Seerr is not set
/// up while one is.
class _RequestsView extends ConsumerWidget {
  const _RequestsView(this.instanceId);

  final String? instanceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final named = instanceId ?? '';
    final exists = ref.watch(
      currentSettingsProvider.select(
        (settings) => settings
            .configuredInstancesOf(ServiceKey.seerr)
            .any((instance) => instance.id == named),
      ),
    );
    final resolved = exists ? named : '';
    return RequestsList.embedded(key: ValueKey(resolved), instanceId: resolved);
  }
}

/// The page's name over what is moving: `4 moving · 40.4 MB/s · 1 stuck`,
/// or `Nothing moving` and when the last download finished; and the menu of
/// what the page can start.
class _ActivityHeader extends ConsumerWidget {
  const _ActivityHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = CupolaRoom.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        MediaQuery.paddingOf(context).top + AppSpacing.sm,
        AppSpacing.xs,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    'Activity',
                    style: AppType.screen.copyWith(color: room.ink),
                  ),
                ),
              ),
              const _ActivityMenu(),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(right: AppSpacing.md),
            child: _Readout(),
          ),
        ],
      ),
    );
  }
}

/// What the page can start that no row starts: a manual import of a
/// download no fault names.
class _ActivityMenu extends StatelessWidget {
  const _ActivityMenu();

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return PopupMenuButton<_MenuItem>(
      tooltip: 'More',
      icon: Icon(Icons.more_horiz_rounded, color: room.ink),
      onSelected: (item) => switch (item) {
        _MenuItem.manualImport => showImportServicePickerSheet(context),
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: _MenuItem.manualImport,
          child: Text('Manual import…'),
        ),
      ],
    );
  }
}

enum _MenuItem { manualImport }

/// The line under the title, from the queues the Home's Downloads reads, so
/// the two never disagree.
class _Readout extends ConsumerWidget {
  const _Readout();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    final read = ref.watch(servicesInFlightProvider);
    final data = read.value;
    final words = AppType.body.copyWith(color: room.inkSecondary);

    Widget line(Widget child) => ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Align(alignment: Alignment.centerLeft, child: child),
    );

    if (data == null) {
      if (!read.hasError) return line(const SizedBox.shrink());
      return line(
        BriefFailureLine.line(
          error: read.error!,
          service: ServiceKey.radarr,
          onRetry: () => ref.invalidate(servicesQueueProvider),
        ),
      );
    }

    final coverage = data.coverage;
    final stuck = data.faults
        .where((item) => isDownloadFault(item.fault))
        .length;
    final parts = activityReadoutParts(
      moving: data.movingCount,
      stuck: stuck,
      rateBytesPerSecond: data.rateBytesPerSecond,
      coverage: coverage,
    );
    final note = coverageNote(coverage);

    if (parts.isEmpty) {
      final last = lastDownloadFinished(
        lastImportOf(
          ref.watch(servicesArrivalsProvider).value?.entries ?? const [],
        ),
        now: ref.watch(arrivalsClockProvider)(),
      );
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(nothingMoving, style: AppType.body.copyWith(color: room.ink)),
            if (last != null) Text(last, style: words),
            if (note != null) ...[
              const SizedBox(height: AppSpacing.xs),
              HomeCoverageNote(note: note, coverage: coverage),
            ],
          ],
        ),
      );
    }

    final amber = statusToneColor(
      scheme,
      StatusTone.warning,
      surface: room.ground,
    );
    final figure = AppType.figureSmall;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            label: spokenActivityReadout(parts),
            excludeSemantics: true,
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xxs,
              children: [
                for (final (index, part) in parts.indexed) ...[
                  if (index > 0)
                    Text('·', style: words.copyWith(color: room.inkTertiary)),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: part.figure,
                          style: figure.copyWith(
                            color: part.stuck ? amber : room.ink,
                          ),
                        ),
                        TextSpan(
                          text: ' ${part.words}',
                          style: part.stuck
                              ? words
                                    .weight(FontWeight.w600)
                                    .copyWith(color: amber)
                              : words,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (note != null) ...[
            const SizedBox(height: AppSpacing.xs),
            HomeCoverageNote(note: note, coverage: coverage),
          ],
        ],
      ),
    );
  }
}

/// A section's name with no slab under it: the searches, whose cards are
/// slabs of their own.
class _GroupHeading extends StatelessWidget {
  const _GroupHeading({required this.title, required this.meta});

  final String title;
  final String meta;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.section,
        AppSpacing.gutter,
        AppSpacing.md,
      ),
      child: Semantics(
        header: true,
        label: '$title, $meta',
        excludeSemantics: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                title,
                style: AppType.section.copyWith(color: room.ink),
              ),
            ),
            Text(meta, style: AppType.meta.copyWith(color: room.inkSecondary)),
          ],
        ),
      ),
    );
  }
}

/// `3 faults · 2 requests`: what Needs you holds, each kind counted apart,
/// since a request is somebody waiting and not something broken.
String needsYouMeta({required int faults, required int requests}) => [
  if (faults > 0) faults == 1 ? '1 fault' : '$faults faults',
  if (requests > 0) requests == 1 ? '1 request' : '$requests requests',
].join(' · ');

/// `2 requests wait for your approval`.
String requestsWaitLine(int count) => count == 1
    ? '1 request waits for your approval'
    : '$count requests wait for your approval';

/// One card of Needs you: a fault's decision, or one stuck download of it,
/// since each stuck download has a way out of its own.
typedef _FaultEntry = ({
  String id,
  DashboardDecision? decision,
  String? downloadKey,
});

List<_FaultEntry> _faultEntries(Iterable<DashboardDecision> faults) => [
  for (final decision in faults)
    if (decision.kind == DecisionKind.stalledDownload &&
        decision.downloadKeys.isNotEmpty)
      for (final key in decision.downloadKeys)
        (id: 'download-$key', decision: null, downloadKey: key)
    else
      (id: decision.id, decision: decision, downloadKey: null),
];

/// Needs you: every fault on its card with its way out, then the requests
/// that wait for an answer. The same list the Home's banner counts.
class _NeedsYouSection extends ConsumerStatefulWidget {
  const _NeedsYouSection();

  @override
  ConsumerState<_NeedsYouSection> createState() => _NeedsYouSectionState();
}

class _NeedsYouSectionState extends ConsumerState<_NeedsYouSection> {
  /// The cards as last drawn, for a card acted on to keep its place.
  List<_FaultEntry> _shown = const [];

  @override
  Widget build(BuildContext context) {
    final decisions = ref.watch(dashboardDecisionsProvider);
    final answered = ref.watch(answeredRequestsProvider);
    final acted = ref.watch(actedFaultsProvider);
    final entries = _faultEntries(
      decisions.decisions.where((decision) => decision.isFault),
    );
    // A download acted on leaves the list as the queue is read again; its
    // note stays where its card was until Activity is read again.
    final present = {for (final entry in entries) entry.id};
    final cards = [...entries];
    for (final (index, entry) in _shown.indexed) {
      final key = entry.downloadKey;
      if (key != null &&
          acted.containsKey(key) &&
          !present.contains(entry.id)) {
        cards.insert(index.clamp(0, cards.length), entry);
      }
    }
    _shown = cards;
    final waiting = [
      for (final decision in decisions.decisions)
        if (decision.kind == DecisionKind.pendingRequest &&
            !answered.containsKey(decision.id))
          decision,
    ];
    final requests = [...waiting, for (final a in answered.values) ?a.decision];
    final coverage = decisions.coverage;
    if (cards.isEmpty && requests.isEmpty) {
      final note = coverage.failed.isEmpty ? null : coverageNote(coverage);
      if (note == null) return const SizedBox.shrink();
      return ActivitySection(
        title: 'Needs you',
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: HomeCoverageNote(note: note, coverage: coverage),
          ),
        ],
      );
    }
    final note = coverageNote(coverage);
    final scheme = Theme.of(context).colorScheme;
    final room = CupolaRoom.of(context);
    final blue = statusToneColor(scheme, StatusTone.info, surface: room.slab);
    final meta = needsYouMeta(faults: entries.length, requests: waiting.length);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ActivitySection(
          title: 'Needs you',
          meta: meta.isEmpty ? null : meta,
          children: [
            if (note != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.md),
                child: HomeCoverageNote(note: note, coverage: coverage),
              ),
            for (final (index, entry) in cards.indexed)
              if (entry.downloadKey case final key?)
                StuckDownloadCard(
                  key: ValueKey(entry.id),
                  downloadKey: key,
                  divided: index > 0,
                )
              else
                DecisionFaultCard(
                  key: ValueKey(entry.id),
                  decision: entry.decision!,
                  divided: index > 0,
                ),
            if (cards.isEmpty) ..._requestRows(requests, answered, blue),
          ],
        ),
        if (cards.isNotEmpty && requests.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              AppSpacing.md,
              AppSpacing.gutter,
              0,
            ),
            child: ActivitySlab(
              children: _requestRows(requests, answered, blue),
            ),
          ),
      ],
    );
  }

  List<Widget> _requestRows(
    List<DashboardDecision> requests,
    Map<String, AnsweredRequest> answered,
    Color blue,
  ) {
    final waiting = requests
        .where((decision) => !answered.containsKey(decision.id))
        .length;
    return [
      if (waiting > 0)
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.lg),
          child: Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(shape: BoxShape.circle, color: blue),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  requestsWaitLine(waiting),
                  style: AppType.label.copyWith(color: blue),
                ),
              ),
            ],
          ),
        ),
      for (final (index, decision) in requests.indexed)
        DecisionRow(
          key: ValueKey(decision.id),
          decision: decision,
          divided: index > 0,
          outcome: answered[decision.id]?.outcome,
        ),
    ];
  }
}

/// Everyone's requests: the latest that move or arrived, who asked them, and
/// the way to all of them.
class _EveryonesRequestsSection extends ConsumerWidget {
  const _EveryonesRequestsSection();

  static const _title = "Everyone's requests";

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(
      currentSettingsProvider.select(
        (settings) => settings.isServiceConfigured(ServiceKey.seerr),
      ),
    )) {
      return const SizedBox.shrink();
    }
    final read = ref.watch(requestsProvider);
    final list = read.value;
    if (list == null) {
      if (!read.hasError) return const SizedBox.shrink();
      return ActivitySection(
        title: _title,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: BriefFailureLine.line(
              error: read.error!,
              service: ServiceKey.seerr,
              onRetry: () =>
                  retryDashboardServices(ref, const [ServiceKey.seerr]),
            ),
          ),
        ],
      );
    }
    if (list.isEmpty) return const SizedBox.shrink();
    final now = ref.watch(arrivalsClockProvider)();
    final requests = myRequestsOf(list, now: now, stale: read.hasError);
    final rows = everyonesLatest(requests);
    // Seerr's own count when it gave one: a page that did not arrive left the
    // rows short of the household's requests, and their number is then a
    // floor, never the total. What is tallied over them (how many are being
    // fetched, how many were declined) is left unsaid rather than understated.
    final whole = holdsEveryRequest(list);
    final server = list is SeerrRequestList ? list.total : null;
    final total = server ?? list.length;
    final figure = server == null && !whole ? '$total+' : '$total';
    final summary = whole ? everyonesSummary(requests) : '';

    return ActivitySection(
      title: _title,
      meta: '$figure total',
      children: [
        for (final (index, mine) in rows.indexed)
          _EveryoneRow(
            key: ValueKey(mine.request.id),
            mine: mine,
            now: now,
            divided: index > 0,
          ),
        ActivitySlabLink(
          label: figure == '1' ? 'All requests' : 'All $figure requests',
          meta: summary.isEmpty ? null : summary,
          divided: rows.isNotEmpty,
          onTap: () => context.go(ActivityTab.requests.location),
        ),
      ],
    );
  }
}

/// One of the household's requests: the title, where it stands and when, and
/// who asked.
class _EveryoneRow extends StatelessWidget {
  const _EveryoneRow({
    super.key,
    required this.mine,
    required this.now,
    required this.divided,
  });

  final MyRequest mine;
  final DateTime now;
  final bool divided;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    final tone = statusToneColor(scheme, mine.stage.tone, surface: room.slab);
    final line = everyonesLine(mine, now);
    final who = mine.request.requestedBy?.displayName;
    final art = mine.art;
    return ActivityRowFrame(
      divided: divided,
      label: mine.title,
      value: [line, ?who].join(', '),
      onTap: () => openMyRequest(context, mine),
      art: HomeRowArt(
        posterUrl: art.url.isEmpty ? null : art.url,
        icon: ServiceKey.seerr.icon,
      ),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                mine.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppType.row.copyWith(color: room.ink),
              ),
            ),
            if (who != null && who.isNotEmpty) ...[
              const SizedBox(width: AppSpacing.sm),
              Text(who, style: AppType.meta.copyWith(color: room.inkSecondary)),
            ],
          ],
        ),
        Text(
          line,
          style: AppType.meta.weight(FontWeight.w600).copyWith(color: tone),
        ),
      ],
    );
  }
}

/// Who is watching, on every media server: the Home's rows.
class _WatchingNowSection extends ConsumerWidget {
  const _WatchingNowSection();

  static const _title = 'Watching now';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    if (!HomeModule.nowPlaying.services.any(settings.isServiceConfigured)) {
      return const SizedBox.shrink();
    }
    final sessions = ref.watch(streamActivityProvider).value;
    if (sessions == null || sessions.isEmpty) return const SizedBox.shrink();
    final servers = {for (final row in sessions) row.service.title}.join(' · ');
    return ActivitySection(
      title: _title,
      meta: servers,
      semanticLabel: [
        _title,
        sessions.length == 1 ? '1 playing' : '${sessions.length} playing',
      ].join(', '),
      children: [
        for (final (index, row) in sessions.indexed)
          NowPlayingRow(
            key: ValueKey('${row.instanceId}-${row.session.id}'),
            row: row,
            divided: index > 0,
          ),
      ],
    );
  }
}

/// Downloads: what is moving and what is stuck, as their queues order them,
/// the stuck ones last. On All at most [limit], with the way to the rest.
class _DownloadsSection extends ConsumerWidget {
  const _DownloadsSection({this.limit});

  final int? limit;

  static const _title = 'Downloads';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final read = ref.watch(servicesQueueProvider);
    final queue = read.value;
    if (queue == null) {
      if (!read.hasError) return const SizedBox.shrink();
      return ActivitySection(
        title: _title,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: BriefFailureLine.line(
              error: read.error!,
              service: ServiceKey.radarr,
              onRetry: () => ref.invalidate(servicesQueueProvider),
            ),
          ),
        ],
      );
    }
    final coverage = queue.coverage;
    final moving = [
      for (final item in queue.items)
        if (item.isMoving) item,
    ];
    final stuck = [
      for (final item in queue.items)
        if (isDownloadFault(item.fault)) item,
    ];
    if (moving.isEmpty && stuck.isEmpty) {
      // On All a quiet queue is the header's to say; Downloads says it in
      // its own place.
      if (limit != null) return const SizedBox.shrink();
      return const _NothingDownloading();
    }
    final cap = limit;
    final rows = cap == null
        ? [...moving, ...stuck]
        : downloadRowsOf(moving, stuck, limit: cap);
    final requests = ref.watch(_householdRequestsProvider);
    final total = moving.length + stuck.length;
    final meta = [
      if (moving.isNotEmpty) '${coveredFigure(moving.length, coverage)} moving',
      if (stuck.isNotEmpty) '${coveredFigure(stuck.length, coverage)} stuck',
    ].join(' · ');
    final now = ref.watch(stallClockProvider)();
    final note = coverageNote(coverage);

    return ActivitySection(
      title: _title,
      meta: meta,
      semanticLabel: [_title, spokenDownloadsSubtitle(meta)].join(', '),
      children: [
        if (note != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: HomeCoverageNote(note: note, coverage: coverage),
          ),
        for (final (index, item) in rows.indexed)
          ActivityDownloadRow(
            key: ValueKey('${item.service}-${item.instanceId}-${item.id}'),
            item: item,
            now: now,
            request: requestFor(item, requests),
            divided: index > 0,
          ),
        if (total > rows.length)
          ActivitySlabLink(
            label: 'All $total downloads',
            onTap: () => context.go(ActivityTab.downloads.location),
          ),
      ],
    );
  }
}

/// The household's requests the downloads are matched against: the lens
/// Seerr's list while one is set up, as last read; nothing otherwise.
final _householdRequestsProvider = Provider.autoDispose<List<SeerrRequest>>((
  ref,
) {
  final seerr = ref.watch(
    currentSettingsProvider.select(
      (settings) => settings.isServiceConfigured(ServiceKey.seerr),
    ),
  );
  if (!seerr) return const [];
  return ref.watch(requestsProvider).value ?? const [];
});

/// Up next: the downloads waiting their turn, in the order they will start,
/// with when where the client says. On All at most [limit].
class _UpNextSection extends ConsumerWidget {
  const _UpNextSection({this.limit});

  final int? limit;

  static const _title = 'Up next';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(servicesQueueProvider).value;
    if (queue == null) return const SizedBox.shrink();
    final queued = [
      for (final item in queue.items)
        if (item.isActive && item.queued) item,
    ];
    if (queued.isEmpty) return const SizedBox.shrink();
    final cap = limit;
    final rows = cap == null ? queued : queued.take(cap).toList();
    final count = coveredFigure(queued.length, queue.coverage);
    final meta = '$count queued';
    final now = ref.watch(stallClockProvider)();
    final requests = ref.watch(_householdRequestsProvider);
    return ActivitySection(
      title: _title,
      meta: meta,
      semanticLabel: [_title, spokenCountPhrase(meta)].join(', '),
      children: [
        for (final (index, item) in rows.indexed)
          ActivityDownloadRow.queued(
            key: ValueKey('${item.service}-${item.instanceId}-${item.id}'),
            item: item,
            now: now,
            request: requestFor(item, requests),
            divided: index > 0,
          ),
        if (queued.length > rows.length)
          ActivitySlabLink(
            label: 'All ${queued.length} queued',
            onTap: () => context.go(ActivityTab.downloads.location),
          ),
      ],
    );
  }
}

/// Downloads with nothing moving: the calm line, and when the last download
/// finished.
class _NothingDownloading extends ConsumerWidget {
  const _NothingDownloading();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = CupolaRoom.of(context);
    final last = lastDownloadFinished(
      lastImportOf(
        ref.watch(servicesArrivalsProvider).value?.entries ?? const [],
      ),
      now: ref.watch(arrivalsClockProvider)(),
    );
    return ActivitySection(
      title: 'Downloads',
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Nothing is downloading',
                style: AppType.row.copyWith(color: room.ink),
              ),
              if (last != null)
                Text(
                  last,
                  style: AppType.meta.copyWith(color: room.inkSecondary),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Finished today: what the libraries imported since midnight, newest
/// first, with the file each became.
class _FinishedTodaySection extends ConsumerWidget {
  const _FinishedTodaySection();

  static const _title = 'Finished today';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final read = ref.watch(servicesArrivalsProvider).value;
    if (read == null) return const SizedBox.shrink();
    final now = ref.watch(arrivalsClockProvider)();
    final today = finishedTodayOf(read.entries, now: now);
    if (today.isEmpty) return const SizedBox.shrink();
    final shown = today.take(_allFinishedLimit).toList(growable: false);
    final count = coveredFigure(today.length, read.coverage);
    return ActivitySection(
      title: _title,
      meta: count,
      semanticLabel: '$_title, $count',
      children: [
        for (final (index, entry) in shown.indexed)
          ActivityHistoryRow(
            key: ValueKey('${entry.instanceId}-${entry.id}'),
            entry: entry,
            divided: index > 0,
          ),
        if (today.length > shown.length)
          ActivitySlabLink(
            label: 'All of today in History',
            onTap: () => context.go(ActivityTab.history.location),
          ),
      ],
    );
  }
}

/// The week History draws: what was imported and what failed, one list
/// over the coverage of both reads.
final _weekProvider = FutureProvider.autoDispose<ArrHistory>((ref) async {
  final reads = await Future.wait([
    ref.watch(servicesArrivalsProvider.future),
    ref.watch(servicesFailuresSinceProvider.future),
  ]);
  return (
    entries: [for (final read in reads) ...read.entries],
    coverage: SourceCoverage.merge(reads.map((read) => read.coverage)),
  );
});

/// History: the last seven days, a section a day, newest first.
class _HistoryDays extends ConsumerWidget {
  const _HistoryDays();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final read = ref.watch(_weekProvider);
    final value = read.value;
    final room = CupolaRoom.of(context);
    if (value == null) {
      if (!read.hasError) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          AppSpacing.section,
          AppSpacing.gutter,
          0,
        ),
        child: BriefFailureLine.line(
          error: read.error!,
          service: ServiceKey.radarr,
          onRetry: () {
            ref.invalidate(servicesArrivalsProvider);
            ref.invalidate(servicesFailuresSinceProvider);
          },
        ),
      );
    }
    final now = ref.watch(arrivalsClockProvider)();
    final days = activityDaysOf(
      value.entries,
      now: now,
      since: now.subtract(arrivalsWindow),
    );
    final note = coverageNote(value.coverage);
    if (days.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          AppSpacing.section,
          AppSpacing.gutter,
          0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (note != null)
              HomeCoverageNote(note: note, coverage: value.coverage),
            Text(
              'Nothing finished in the last seven days',
              style: AppType.row.copyWith(color: room.ink),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (note != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              AppSpacing.md,
              AppSpacing.gutter,
              0,
            ),
            child: HomeCoverageNote(note: note, coverage: value.coverage),
          ),
        for (final day in days)
          ActivitySection(
            key: ValueKey(day.day),
            title: day.label,
            meta: '${day.entries.length}',
            children: [
              for (final (index, entry) in day.entries.indexed)
                ActivityHistoryRow(
                  key: ValueKey('${entry.instanceId}-${entry.id}'),
                  entry: entry,
                  divided: index > 0,
                ),
            ],
          ),
      ],
    );
  }
}

/// The page's foot: older history stays with each arr, under its History
/// tab, one row each.
class _HistoryFoot extends ConsumerWidget {
  const _HistoryFoot({this.blocklist = false});

  /// Whether the foot ends with the arrs' blocklist, as History's does.
  final bool blocklist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    final services = _historyServices
        .where(settings.isServiceConfigured)
        .toList(growable: false);
    if (services.isEmpty) return const SizedBox.shrink();
    final room = CupolaRoom.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.section,
        AppSpacing.gutter,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Older history stays in each service, under its History tab.',
            style: AppType.meta.copyWith(color: room.inkSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          ActivitySlab(
            children: [
              for (final (index, service) in services.indexed)
                ActivitySlabLink(
                  label: '${service.title} history',
                  divided: index > 0,
                  onTap: () => context.go(
                    '${ServiceRoutes.forService(service)}/history',
                  ),
                ),
              if (blocklist)
                ActivitySlabLink(
                  label: 'Blocklist',
                  meta: 'Releases the arrs will not take again',
                  onTap: () => context.push(ServiceRoutes.activityBlocklist),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
