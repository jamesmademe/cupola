import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: implementation_imports
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_breakpoints.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/lifecycle/refresh_on_return.dart';
import 'package:cupola/core/lifecycle/page_activity.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/providers/navigation_refresh_provider.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/text_scale.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/ambient_scaffold.dart';
import 'package:cupola/core/widgets/app_empty_state.dart';
import 'package:cupola/core/widgets/app_error_state.dart';
import 'package:cupola/core/widgets/app_skeleton.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/widgets/glass_app_bar.dart';
import 'package:cupola/core/widgets/selection_pills.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/activity/domain/global_activity_status.dart'
    show needsManualImportClause, queueNeedsManualImport;
import 'package:cupola/features/activity/presentation/activity_provider.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_formatters.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_item_tiles.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/import/presentation/import_service_picker_sheet.dart';
import 'package:cupola/features/stream/presentation/widgets/stream_activity_section.dart';
import 'package:cupola/features/release_search/presentation/release_search_jobs_provider.dart';
import 'package:cupola/features/release_search/presentation/release_searches_body.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The three top-level activity buckets. Each bucket exposes a contextual
/// sub-segment bar so service-specific subsections (Queue/Requests,
/// History/Blocklist, Missing/Cutoff) remain reachable from the global view.
enum _ActivitySection {
  // Not a download arrow any more: the bucket carries both directions of the
  // box's traffic, bytes in and bytes out.
  now('Now', Icons.swap_vert_rounded),
  history('History', Icons.history_rounded),
  wanted('Wanted', Icons.manage_search_rounded);

  final String label;
  final IconData icon;

  const _ActivitySection(this.label, this.icon);
}

/// A contextual sub-segment within an [_ActivitySection], backed by one of the
/// granular providers in `activity_provider.dart`.
class _ActivitySub {
  final String label;

  /// Null on a paged or custom sub.
  final FutureProvider<ActivityFeed>? provider;

  /// The incremental provider behind a paged sub (History, Wanted).
  ///
  /// Null on one-shot and custom subs. A paged sub loads a window and then
  /// "load more"s, so its screen state carries cursors and flags the one-shot
  /// [FutureProvider] never needs.
  final NotifierProvider<PagedArrFeedNotifier, PagedArrFeedState>?
  pagedProvider;
  final String emptyMessage;

  /// A body that replaces the whole feed path, filter strip included.
  ///
  /// Live playback is the case this exists for. A session is not a queue record:
  /// it has a person, a device and a delivery method, and none of the queue
  /// affordances mean anything for it. Forcing it into [GlobalActivityItem] would
  /// need a new `ServiceType` member, which breaks 21 exhaustive switches here
  /// plus 6 on [GlobalActivityKind] — two of those with `_ =>` fallbacks that
  /// would mis-route the row silently rather than failing to compile.
  ///
  /// The service strip is skipped for these on purpose: it filters the four arr
  /// services, which is an axis a media-server session does not sit on.
  final Widget Function(double bottomPadding)? body;

  /// What a pull on a custom body refreshes.
  ///
  /// Null for a body that already owns the gesture — Streaming ships its own
  /// `RefreshIndicator` inside `StreamActivitySection`, and two nested
  /// indicators over one scrollable both answer the same overscroll. Null also
  /// for the feed path, which refreshes through the version bump instead.
  final void Function(WidgetRef ref)? onRefresh;

  const _ActivitySub(this.label, this.provider, this.emptyMessage)
    : pagedProvider = null,
      body = null,
      onRefresh = null;

  const _ActivitySub.paged(this.label, this.pagedProvider, this.emptyMessage)
    : provider = null,
      body = null,
      onRefresh = null;

  const _ActivitySub.custom({
    required this.label,
    required this.body,
    this.onRefresh,
  }) : provider = null,
       pagedProvider = null,
       emptyMessage = '';
}

/// Sub-segments per bucket. The first entry is the default selection.
///
/// A bucket with a single entry renders no pill row at all, which is why "Now"
/// has one. It used to offer `All / Queue / Requests`, and those collided with the
/// service strip directly beneath them: "Requests" selects Seerr's rows and
/// "Queue" selects the three \*arrs', which is precisely what picking a service
/// does. Two stacked rows filtering the same axis is what made the header read as
/// one confusing bank of controls rather than two orthogonal choices.
///
/// The pills that survive express a **record type** no service filter can reach:
/// a blocklist entry is not a history entry, and a missing item is not an unmet
/// cutoff. Those are real second axes; "which service" was not.
final Map<_ActivitySection, List<_ActivitySub>> _activitySubs = {
  _ActivitySection.now: [
    _ActivitySub(
      'Downloading',
      globalNowItemsProvider,
      'Nothing downloading right now',
    ),
    // The second record type this bucket was always waiting for. Its label was
    // 'All' only because a one-entry bucket renders no pill row — and "All" was
    // never true, since the bucket only ever held the ingress half.
    _ActivitySub.custom(label: 'Streaming', body: _streamActivityBody),
    // A background release search is live, and an expiring result is live too —
    // the gerund is what makes it a sibling of the two above rather than a
    // different kind of thing filed next to them.
    _ActivitySub.custom(
      label: _searchingSubLabel,
      body: _releaseSearchesBody,
      onRefresh: _refreshReleaseSearches,
    ),
  ],
  _ActivitySection.history: [
    // Paged: History can be thousands of rows, so it loads a window and
    // "load more"s like the web UI's history table.
    _ActivitySub.paged(
      'History',
      globalHistoryFeedProvider,
      'No recent history',
    ),
    _ActivitySub(
      'Blocklist',
      globalBlocklistItemsProvider,
      'Blocklist is empty',
    ),
  ],
  _ActivitySection.wanted: [
    _ActivitySub.paged('All', globalWantedFeedProvider, 'Nothing wanted'),
    _ActivitySub.paged('Missing', globalMissingFeedProvider, 'Nothing missing'),
    _ActivitySub.paged(
      // Sentence case, and the same string `resolveWantedStatus` stamps on the
      // rows behind it — the pill and the badge under it used to disagree about
      // the capital U.
      'Cutoff unmet',
      globalCutoffFeedProvider,
      'Cutoff met for everything',
    ),
  ],
};

final _activitySectionProvider = StateProvider<_ActivitySection>(
  (ref) => _ActivitySection.now,
);

/// Selected sub-segment index, remembered per bucket.
final _activitySubIndexProvider = StateProvider.family<int, _ActivitySection>(
  (ref, section) => 0,
);

/// Selected service filter; null means "all services".
/// Selects **Now › Searching** from outside this screen.
///
/// Exists for the notification tap: a finished background search says "tap to
/// pick one", and landing on whichever bucket the user last used — the sticky
/// selection this screen is otherwise right to keep — answers a different
/// question. The two providers behind the selection stay private; this is the
/// one sanctioned way to move it, so the sticky behaviour has a single exception
/// rather than a set of them.
///
/// Idempotent, and safe to call when the screen is not mounted: the state is
/// provider-held, so a later mount reads it as its starting position.
void selectActivitySearching(Ref ref) {
  const section = _ActivitySection.now;
  final index = _activitySubs[section]!.indexWhere(
    (sub) => sub.label == _searchingSubLabel,
  );
  if (index < 0) return;
  ref.read(_activitySectionProvider.notifier).state = section;
  ref.read(_activitySubIndexProvider(section).notifier).state = index;
}

/// The label the sub is found by, so the lookup above cannot drift from the
/// list below by a hard-coded index.
const _searchingSubLabel = 'Searching';

final _activityServiceFilterProvider = StateProvider<ServiceKey?>(
  (ref) => null,
);

/// Services whose group is collapsed in the grouped view.
///
/// With four services and twenty-odd rows each, reaching Radarr meant scrolling
/// past all of Seerr. Collapsing a group you are not working on is the cheapest
/// way to make the aggregate view navigable without giving up the aggregate.
final _collapsedServicesProvider = StateProvider<Set<ServiceKey>>((ref) => {});

/// Global cross-service activity (the Activity bottom-nav tab): one screen with
/// Now/History/Wanted buckets and a per-service filter, grouped by service.
///
/// The buckets are tabs rather than a `SegmentedButton`, for three reasons that
/// all pulled the same way. They gain **horizontal swipe**, the phone gesture the
/// screen had no equivalent of. They match the per-service Activity screen, which
/// was already a `TabBar` — the feature used to express one taxonomy through three
/// different controls (a segmented button, a pinned second segmented button, and a
/// hand-rolled chip row), and now expresses it through one. And moving the bucket
/// choice into the app bar returns a whole row of vertical space to the content:
/// on a phone the header was spending close to 200pt before the first row.
class GlobalActivityScreen extends ConsumerStatefulWidget {
  /// How stale the feed may be before returning to it earns a refetch.
  ///
  /// The Now bucket polls while it is on screen, so this only matters after
  /// an absence — and it is the same two minutes the services dashboard
  /// uses, because a queue and a control room go out of date together.
  static const staleAfter = Duration(minutes: 2);

  const GlobalActivityScreen({super.key});

  @override
  ConsumerState<GlobalActivityScreen> createState() =>
      _GlobalActivityScreenState();
}

class _GlobalActivityScreenState extends ConsumerState<GlobalActivityScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: _ActivitySection.values.length,
      // Seeded from the persisted section so coming back to the tab lands where
      // the user left it, which the `SegmentedButton` got for free from its
      // `StateProvider` and a fresh `TabController` would otherwise throw away.
      initialIndex: ref.read(_activitySectionProvider).index,
      vsync: this,
    );
    _tabs.addListener(_syncSection);
  }

  /// Mirrors the controller back onto the provider.
  ///
  /// Deliberately not guarded on `indexIsChanging`: the section drives the
  /// polling below, and waiting for the tab animation to settle before starting
  /// it would leave "Now" static for the length of the transition. The equality
  /// check is what keeps this idempotent while the animation ticks.
  void _syncSection() {
    final section = _ActivitySection.values[_tabs.index];
    if (ref.read(_activitySectionProvider) != section) {
      ref.read(_activitySectionProvider.notifier).state = section;
    }
  }

  @override
  void dispose() {
    _tabs.removeListener(_syncSection);
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(navigationRefreshProvider(NavigationSection.activity), (
      previous,
      next,
    ) {
      _invalidateRequests(ref);
      ref.read(activityRefreshVersionProvider.notifier).state++;
    });

    // A connection fix made in Settings changes the client underneath the
    // feed, but the feed itself is a cached aggregate and does not watch the
    // settings model. Without this edge, returning here keeps the old 403 or
    // timeout until the user discovers Retry. The same invalidation used by a
    // deliberate refresh makes the correction visible immediately.
    ref.listen(settingsProvider, (previous, next) {
      _invalidateRequests(ref);
      ref.read(activityRefreshVersionProvider.notifier).state++;
    });

    // The other direction of the mirror above: `_syncSection` pushes the
    // controller onto the provider, and until now nothing pushed the provider
    // onto the controller — so a selection made from outside this screen (see
    // [selectActivitySearching]) changed the body while the tab indicator stayed
    // where it was. Guarded on the index so the listener cannot fight the
    // gesture that is already animating.
    ref.listen<_ActivitySection>(_activitySectionProvider, (previous, next) {
      if (_tabs.index != next.index) _tabs.animateTo(next.index);
    });

    final section = ref.watch(_activitySectionProvider);

    // "Now" is the only bucket that claims to be live, so it is the only one
    // that polls — and it polls only while this page is the page on screen.
    //
    // Both halves are needed and neither replaces the other. The section check
    // stays because `TabBarView` keeps a visited child alive, so a watch inside
    // the Now tab would go on refetching three services after the user moved to
    // History. The visibility gate is the newer half: this screen itself is now
    // kept alive when its tab is switched away from, so being mounted no longer
    // means being read.
    if (section == _ActivitySection.now) {
      ref.watchWhileLive(context, activityNowPollingProvider);
    }

    return RefreshOnReturn(
      id: 'activity.feed',
      maxAge: GlobalActivityScreen.staleAfter,
      // The same refresh a re-tap performs, and silent: nobody pressed
      // anything.
      onStale: () => ref.triggerNavigationRefresh(NavigationSection.activity),
      child: AmbientScaffold(
        appBar: GlassAppBar(
          // The bar grew a second line, so the box grows with the reading size
          // (The Grown Box Rule). `kToolbarHeight` was sized for one line; at an
          // accessibility size the readout under the title would have met a
          // constant and painted the overflow stripe across the page's own
          // heading. The delta is zero at the default size, so nothing moves
          // for anyone who has not asked for larger text.
          toolbarHeight: TextScaleMetrics.boxHeight(
            context,
            base: kToolbarHeight,
            textHeight: _readoutLineHeight,
          ),
          title: const _ActivityTitle(),
          actions: [
            // A word, not a glyph. This is the page's one cross-cutting verb
            // and the only way into the import wizard that does not start from
            // a stuck row, and an icon-only button hid it behind a hover the
            // phone does not have — the tooltip was the only thing that named
            // it, and a tooltip is not a label.
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: OutlinedButton.icon(
                onPressed: () => showImportServicePickerSheet(context),
                icon: const Icon(Icons.download_for_offline_outlined, size: 18),
                label: const Text('Manual import'),
                style: OutlinedButton.styleFrom(
                  // 44, not the Material 36 default: the Components sheet's
                  // floor for a control a finger aims at.
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                ),
              ),
            ),
          ],
          // Text-only tabs. `Tab(icon:, text:)` stacks the two and doubles the bar's
          // height, which would hand back the vertical space this change exists to
          // recover — and "Now", "History" and "Wanted" are unambiguous words that
          // do not need a glyph to disambiguate them. The icons live on in the
          // per-bucket empty states, where they have room.
          bottom: TabBar(
            controller: _tabs,
            tabs: [for (final s in _ActivitySection.values) Tab(text: s.label)],
          ),
        ),
        body: TabBarView(
          controller: _tabs,
          children: [
            for (final s in _ActivitySection.values) _BucketBody(section: s),
          ],
        ),
      ),
    );
  }
}

/// One `labelSmall` line at the default reading size — what the app bar's
/// second line costs, and therefore what has to grow with the reading size.
const _readoutLineHeight = 14.0;

/// The page's name over what the queue is actually doing.
///
/// The readout is the reason this is two lines and not one: "Activity" alone
/// names the tab the user just tapped, which they already know, and the one
/// figure they came for — how much is in flight and how much of it is stuck —
/// was only reachable by counting rows.
///
/// Drawn for **Now** only, and deliberately. The History and Wanted boards draw
/// their own sub-lines (`4 blocklisted`, `63 wanted · 54 missing`). Their
/// totals now arrive with the page (`ActivityServiceResult.total`, which the
/// service strip reads), but a server that sends no `totalRecords` leaves only
/// "how many rows are loaded", which changes every time the user taps Show
/// more — and a number that moves while the data does not is worse than no
/// number.
class _ActivityTitle extends ConsumerWidget {
  const _ActivityTitle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final section = ref.watch(_activitySectionProvider);
    // `.value`, not `asData`: the 15 s poll puts this provider into
    // `AsyncLoading(isReloading:)` on every tick, and `asData` is null there —
    // the readout would blink out twice a minute. Same contract as the feed
    // body below.
    final feed = section == _ActivitySection.now
        ? ref.watch(globalNowItemsProvider).value
        : null;
    final readout = feed == null ? null : nowReadout(feed);

    final title = Text(
      'Activity',
      style: theme.appBarTheme.titleTextStyle ?? theme.textTheme.titleLarge,
    );
    if (readout == null) return title;

    return Semantics(
      container: true,
      header: true,
      label: 'Activity, ${readout.spoken}',
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            title,
            Text(
              readout.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "20 in the queue · 18 need a manual import · 2 stuck · 1 importing" — and
/// only the clauses that are true. A readout that prints "0 stuck" spends a
/// third of its width telling the user that nothing happened.
///
/// Faults before progress, and a blocked import is a fault. It used to be
/// counted with `importing` and `importPending`, so a queue of eighteen rows
/// each reading "Import blocked" in amber sat under "18 importing": the one
/// figure the user came for, stated as good news. It has its own clause now,
/// named by its remedy — the verb on the row — and it leads.
///
/// The figure covers the connections that answered and **names the ones that
/// did not**: `12 in the queue · 3 need a manual import · Sonarr Anime not
/// counted`. It used to count the survivors with no qualifier, so a Sonarr
/// that did not answer took its downloads out of the number without a word,
/// and when every \*arr failed the bar said "Nothing in the queue" over a page
/// that could not know. With nothing answering there is no figure at all, and
/// the bar says so with the em dash.
///
/// What to act on comes first and the reservation last, for the eye and the
/// ear alike. The qualifier used to sit straight after the count, and on a
/// phone the ellipsis took the manual-import clause, the one that asks for
/// something, to keep a note the health strip below says in full.
///
/// Null when no \*arr is set up, and the bar is the page's name alone. Every
/// clause here is about a queue, and with only Seerr configured there is no
/// queue to read: "Nothing in the queue" was a claim about something that
/// does not exist. The body already says which services are not set up.
@visibleForTesting
({String text, String spoken})? nowReadout(ActivityFeed feed) {
  if (feed.arrConnections.isEmpty) return null;
  if (feed.noArrAnswered) {
    return (
      text: '${Lexicon.noFigure} in the queue',
      spoken: 'queue count unavailable',
    );
  }
  final notCounted = feed.arrConnections
      .where((r) => r.failed)
      .toList(growable: false);

  final queued = feed.items
      .where((i) => i.kind == GlobalActivityKind.queue)
      .toList(growable: false);

  var needsImport = 0;
  var stalled = 0;
  var importing = 0;
  for (final item in queued) {
    final pipeline = item.status.pipeline;
    if (queueNeedsManualImport(
      pipeline: pipeline,
      hasWarning: item.status.hasWarning,
    )) {
      needsImport++;
      continue;
    }
    switch (pipeline) {
      case MediaPipeline.stalled:
        stalled++;
      case MediaPipeline.importing:
      case MediaPipeline.importPending:
        importing++;
      default:
        break;
    }
  }

  // The rows are a floor when a queue walk stopped short of the end — a full
  // page and no count, or out of pages — so the figure counted from them is
  // too: `200+ in the queue`, never `200`.
  final atLeast = feed.arrConnections.any(
    (r) => r.reached && (r.cutShort || r.incomplete),
  );
  String clauses(String queue) => [
    queue,
    if (needsImport > 0) needsManualImportClause(needsImport),
    if (stalled > 0) '$stalled ${StateWord.stuck.inline}',
    if (importing > 0) '$importing importing',
    if (notCounted.isNotEmpty) notCountedClause(notCounted),
  ].join(' · ');
  if (queued.isEmpty) {
    final text = clauses('Nothing in the queue');
    return (text: text, spoken: text);
  }
  return (
    text: clauses('${queued.length}${atLeast ? '+' : ''} in the queue'),
    spoken: clauses(
      '${atLeast ? 'at least ' : ''}${queued.length} in the queue',
    ),
  );
}

/// One bucket's contents: its record-type pills, the service strip, and the feed.
class _BucketBody extends ConsumerWidget {
  final _ActivitySection section;

  const _BucketBody({required this.section});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bottomPadding = FloatingNavBarMetrics.getScrollViewBottomPadding(
      context,
    );

    final subs = _activitySubs[section]!;
    final subIndex = ref
        .watch(_activitySubIndexProvider(section))
        .clamp(0, subs.length - 1);
    final sub = subs[subIndex];

    // Pull-to-refresh belongs to the TAB, never to a list inside it — so a
    // custom body that does not already own the gesture gets it here. Now ›
    // Searching had none at all: the branch returned above the
    // `RefreshIndicator` below, on the one section of the app that claims to be
    // live.
    //
    // The callback is the sub's own, not the feed's `refresh()`: bumping
    // `activityRefreshVersionProvider` re-reads the \*arr feeds and would leave
    // a search list spinning at a gesture that could not possibly change it.
    //
    // No `_RefreshingBar` on this path. A custom body carries no `refreshing`
    // flag, and a hairline that never lights is the same lie in the other
    // direction. Still returns before the feed's own watches: a session list
    // must not rebuild because the \*arr service filter moved.
    final customBody = sub.body;
    if (customBody != null) {
      final onRefresh = sub.onRefresh;
      final body = customBody(bottomPadding);
      return Column(
        children: [
          _SubPills(section: section, subs: subs, subIndex: subIndex),
          Expanded(
            child: onRefresh == null
                ? body
                : RefreshIndicator(
                    onRefresh: () async => onRefresh(ref),
                    child: body,
                  ),
          ),
        ],
      );
    }

    final pagedProvider = sub.pagedProvider;
    final pagedState = pagedProvider == null ? null : ref.watch(pagedProvider);
    final feedAsync = pagedProvider == null ? ref.watch(sub.provider!) : null;
    final filter = ref.watch(_activityServiceFilterProvider);
    final configuredServices = ref.watch(configuredActivityServicesProvider);

    void refresh() {
      _invalidateRequests(ref);
      ref.read(activityRefreshVersionProvider.notifier).state++;
    }

    // Keep the last good feed on screen while a refresh is in flight. `.when`
    // discarded it, so every pull-to-refresh and every poll tick blanked the
    // whole list to shimmer and then redrew it — turning a background update
    // into a full visual reset.
    //
    // `AsyncValue.value`, emphatically not `asData?.value`. In Riverpod 3 a
    // provider that re-runs because a watched dependency changed enters
    // `AsyncLoading` with `isReloading` set — and `asData` returns null in that
    // state. The 15s "Now" poll bumps `activityRefreshVersionProvider`, which
    // every feed provider watches, so `asData` was null on *every tick*: the
    // list was replaced by shimmer, the service strip's counts fell back to a
    // dash, and `isRefreshing` could never be true, which left `_RefreshingBar`
    // dead code. `.value` carries the previous data through a reload, which is
    // what the paragraph above always claimed to do.
    //
    // The paged subs keep the same contract through their own state: the
    // notifier's build re-runs on the refresh bump, returns the previous feed
    // with `refreshing` set, and swaps in the new first pages when they land.
    final feed = pagedState?.feed ?? feedAsync?.value;
    final isRefreshing =
        pagedState?.refreshing ?? (feedAsync!.isLoading && feed != null);

    return Column(
      children: [
        _SubPills(section: section, subs: subs, subIndex: subIndex),
        // Service selection, one tap, with the counts on it.
        //
        // This replaced an app-bar popup menu, which in turn replaced a row of
        // plain pills. The pills were the right *affordance* and the wrong
        // *form*: identical to the sub-segment row directly above them, so two
        // stacked rows filtered different axes and read as one bank. Burying
        // them in a menu fixed the confusion by removing the navigation — with
        // four services and twenty rows each, reaching Radarr meant scrolling
        // past all of Seerr. Instrument tiles are one tap again and cannot be
        // mistaken for the neutral text pills, because they carry an accent, an
        // icon, a number and a health state that the pills never had.
        if (configuredServices.length > 1)
          Padding(
            padding: EdgeInsets.only(top: subs.length > 1 ? 0 : AppSpacing.sm),
            child: _ServiceStrip(
              services: configuredServices,
              feed: feed,
              selected: filter,
              onSelected: (service) =>
                  ref.read(_activityServiceFilterProvider.notifier).state =
                      service,
            ),
          ),
        if (isRefreshing) const _RefreshingBar(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => refresh(),
            child: _FeedBody(
              feed: feed,
              hasError: pagedProvider == null ? feedAsync!.hasError : false,
              error: pagedProvider == null ? feedAsync!.error : null,
              section: section,
              emptyMessage: sub.emptyMessage,
              filter: filter,
              bottomPadding: bottomPadding,
              onRetry: refresh,
              hasMore: pagedState?.hasMore ?? false,
              loadingMore: pagedState?.loadingMore ?? false,
              loadMoreFailed: pagedState?.loadMoreFailed ?? false,
              onLoadMore: pagedProvider == null
                  ? () {}
                  : () => ref.read(pagedProvider.notifier).loadMore(),
            ),
          ),
        ),
      ],
    );
  }
}

/// The record-type pill row for a bucket.
///
/// Extracted because the Streaming sub renders a body of its own and still needs
/// this row above it — inline, the two paths would each carry a copy and could
/// drift. Renders nothing for a bucket with a single record type: a pill row with
/// one pill is a label pretending to be a control.
class _SubPills extends ConsumerWidget {
  const _SubPills({
    required this.section,
    required this.subs,
    required this.subIndex,
  });

  final _ActivitySection section;
  final List<_ActivitySub> subs;
  final int subIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (subs.length <= 1) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: SelectionPills<int>(
        values: [for (var index = 0; index < subs.length; index++) index],
        selected: subIndex,
        labelBuilder: (index) => subs[index].label,
        onSelected: (index) =>
            ref.read(_activitySubIndexProvider(section).notifier).state = index,
      ),
    );
  }
}

/// Top-level so `_activitySubs` can stay `const`.
Widget _streamActivityBody(double bottomPadding) =>
    StreamActivitySection(bottomPadding: bottomPadding);

Widget _releaseSearchesBody(double bottomPadding) =>
    ReleaseSearchesBody(bottomPadding: bottomPadding);

/// What a pull on Now › Searching actually refreshes.
///
/// Not a refetch: the jobs are in memory and the indexer searches behind them
/// are already running. What goes stale is each result's **grab window** — a
/// completed search's releases expire — and re-evaluating those is the only
/// honest thing a pull can do here. The 10 s tick inside the body does the
/// same thing on a timer; this is the user asking for it now.
void _refreshReleaseSearches(WidgetRef ref) {
  ref.read(releaseSearchJobsProvider.notifier).refreshWindows();
}

/// A hairline progress line while a refresh runs behind visible content.
///
/// The alternative — replacing the list with a skeleton — throws away what the
/// user is reading in order to tell them it is being updated.
class _RefreshingBar extends StatelessWidget {
  const _RefreshingBar();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 2,
      child: LinearProgressIndicator(
        minHeight: 2,
        backgroundColor: Colors.transparent,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

/// The services Activity reads, for its not-set-up state when the feed has
/// not said which of them are missing.
const _activitySources = [
  ServiceKey.radarr,
  ServiceKey.sonarr,
  ServiceKey.lidarr,
  ServiceKey.seerr,
];

/// Chooses between the four things a feed load can mean.
///
/// The distinction that did not exist before: "every service I asked said
/// nothing" and "no service answered me" are different facts, and only the first
/// one is an empty state.
class _FeedBody extends StatelessWidget {
  final ActivityFeed? feed;
  final bool hasError;
  final Object? error;
  final _ActivitySection section;
  final String emptyMessage;
  final ServiceKey? filter;
  final double bottomPadding;
  final VoidCallback onRetry;

  /// Whether another page of this bucket is available to load.
  ///
  /// False for the one-shot buckets (Now, Blocklist), which load everything at
  /// once; true for the paged ones while any pair has a full last page.
  final bool hasMore;

  /// A "load more" is in flight.
  final bool loadingMore;

  /// The last "load more" failed and the footer offers a retry.
  final bool loadMoreFailed;
  final VoidCallback onLoadMore;

  const _FeedBody({
    required this.feed,
    required this.hasError,
    required this.error,
    required this.section,
    required this.emptyMessage,
    required this.filter,
    required this.bottomPadding,
    required this.onRetry,
    required this.hasMore,
    required this.loadingMore,
    required this.loadMoreFailed,
    required this.onLoadMore,
  });

  @override
  Widget build(BuildContext context) {
    final feed = this.feed;

    // First load, nothing to show yet.
    if (feed == null) {
      if (hasError) {
        return _ScrollableState(
          bottomPadding: bottomPadding,
          child: AppErrorState(
            error: error ?? 'Activity could not be loaded.',
            onRetry: onRetry,
          ),
        );
      }
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        // The three sibling branches all reserved nav-bar clearance; this one
        // did not, so the last skeleton row sat under the floating bar.
        padding: EdgeInsets.only(top: AppSpacing.md, bottom: bottomPadding),
        children: [AppSkeleton.listRows(count: 6)],
      );
    }

    // None of Activity's sources is set up — the honest answer is "set one
    // up", not "nothing is downloading". Named, because a Jellyfin that is
    // set up is not one of them: "No services connected" was false there.
    if (!feed.hasConfiguredService) {
      final missing = {
        for (final result in feed.unconfigured) result.service,
      }.toList(growable: false);
      final sources = missing.isEmpty ? _activitySources : missing;
      return _ScrollableState(
        bottomPadding: bottomPadding,
        child: AppEmptyState(
          icon: Icons.settings_ethernet_rounded,
          title:
              '${Lexicon.names(sources.map((s) => s.title))} '
              '${sources.length == 1 ? 'is' : 'are'} not set up',
          message:
              'Activity lists what they download and what people ask for. '
              'Set one up and it shows up here.',
          // One `Set up X` per source, each to its own setup form.
          action: Wrap(
            alignment: WrapAlignment.center,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final (index, service) in sources.indexed)
                index == 0
                    ? FilledButton(
                        onPressed: () =>
                            context.go(ServiceRoutes.setUp(service)),
                        child: Text(Lexicon.setUp(service.title)),
                      )
                    : OutlinedButton(
                        onPressed: () =>
                            context.go(ServiceRoutes.setUp(service)),
                        child: Text(Lexicon.setUp(service.title)),
                      ),
            ],
          ),
        ),
      );
    }

    // Every configured service failed. "No items" here means "we have no idea",
    // so it must read as a failure with a retry — the branch that used to be
    // unreachable because each service's error was swallowed upstream.
    if (feed.allConfiguredFailed) {
      return _ScrollableState(
        bottomPadding: bottomPadding,
        child: AppErrorState(
          error:
              feed.firstError ?? 'None of your configured services responded.',
          onRetry: onRetry,
        ),
      );
    }

    return _ActivityData(
      feed: feed,
      section: section,
      emptyMessage: emptyMessage,
      filter: filter,
      bottomPadding: bottomPadding,
      onRetry: onRetry,
      hasMore: hasMore,
      loadingMore: loadingMore,
      loadMoreFailed: loadMoreFailed,
      onLoadMore: onLoadMore,
    );
  }
}

class _ActivityData extends ConsumerWidget {
  final ActivityFeed feed;
  final _ActivitySection section;
  final String emptyMessage;
  final ServiceKey? filter;
  final double bottomPadding;
  final VoidCallback onRetry;
  final bool hasMore;
  final bool loadingMore;
  final bool loadMoreFailed;
  final VoidCallback onLoadMore;

  const _ActivityData({
    required this.feed,
    required this.section,
    required this.emptyMessage,
    required this.filter,
    required this.bottomPadding,
    required this.onRetry,
    required this.hasMore,
    required this.loadingMore,
    required this.loadMoreFailed,
    required this.onLoadMore,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collapsed = ref.watch(_collapsedServicesProvider);
    final visible = filter == null
        ? feed.items
        : feed.items.where((i) => i.service == filter).toList(growable: false);

    // Shown only when a service did not answer. Always-on would put back the
    // permanent chrome row this pass just removed; the information only exists
    // when something is wrong, and the section-header counts already say who is
    // busy when everything is fine.
    final health = feed.isPartial
        ? _StackHealthStrip(feed: feed, onRetry: onRetry)
        : null;

    // What landed today, below the rows and inside the scroll. Only under the
    // Now table: on History it would be the same records twice, and on Wanted
    // it answers a question the section is not asking. Watching it starts the
    // history feed's first page, which is the cost the design signs up for by
    // drawing the band on this page at all.
    final trailing = <Widget>[
      if (section == _ActivitySection.now &&
          _FinishedTodayBand.visibleAt(context))
        const _FinishedTodayBand(),
    ];

    if (visible.isEmpty) {
      return _ScrollableState(
        bottomPadding: bottomPadding,
        header: health,
        footer: trailing.isEmpty ? null : trailing.first,
        child: AppEmptyState(
          icon: section.icon,
          // The title used to be the bucket name — "Now" as a heading, which
          // names the tab the user is already looking at instead of saying what
          // happened.
          title: emptyMessage,
          message: filter == null
              ? 'Anything your services report will appear here.'
              : 'Nothing from ${filter!.title} right now.',
        ),
      );
    }

    // The table's column header, on the sizes that draw a table. It rides
    // inside the list rather than above it so it scrolls away with the rows: a
    // pinned header is a promise about a sortable column, and nothing here
    // sorts.
    final leading = <Widget>[
      ?health,
      if (ActivityTableHeader.visibleAt(context)) const ActivityTableHeader(),
    ];

    // Flat list when a single service is selected.
    if (filter != null) {
      final footerVisible = hasMore || loadingMore || loadMoreFailed;
      final headerCount = leading.length;
      final tail = <Widget>[
        if (footerVisible)
          _FeedFooter(
            loadingMore: loadingMore,
            loadMoreFailed: loadMoreFailed,
            onLoadMore: onLoadMore,
          ),
        ...trailing,
      ];
      return ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(top: AppSpacing.md, bottom: bottomPadding),
        itemCount: visible.length + headerCount + tail.length,
        itemBuilder: (context, index) {
          if (index < headerCount) return leading[index];
          final itemIndex = index - headerCount;
          if (itemIndex >= visible.length) {
            return tail[itemIndex - visible.length];
          }
          return GlobalActivityItemTile(item: visible[itemIndex]);
        },
      );
    }

    // Otherwise group by service with an accented section header.
    final grouped = <ServiceKey, List<GlobalActivityItem>>{};
    for (final item in visible) {
      grouped.putIfAbsent(item.service, () => []).add(item);
    }
    final orderedServices = globalActivityServices
        .where(grouped.containsKey)
        .toList(growable: false);

    // One descriptor per row rather than a materialised `List<Widget>`.
    //
    // History and Wanted page 200 records per (kind, service) across three
    // services, so two taps of "Show more" put well over a thousand tiles in
    // this list — every one of them constructed up front and reconstructed on
    // each group collapse, service-filter change, pull-to-refresh and load more.
    // Order, widgets, padding and physics are unchanged; only the construction
    // became lazy, which is what the filtered path above already did.
    final rows = <Object>[
      ...leading,
      for (final service in orderedServices) ...[
        service,
        if (!collapsed.contains(service)) ...grouped[service]!,
      ],
      if (hasMore || loadingMore || loadMoreFailed) const _FooterRow(),
      ...trailing,
    ];

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.only(bottom: bottomPadding),
      itemCount: rows.length,
      itemBuilder: (context, index) => switch (rows[index]) {
        final ServiceKey service => _ServiceGroupHeader(
          service: service,
          // The tile's figure, so the header and the tile above it agree, with
          // the rows on screen beside it for when the servers named no total.
          count: activityCount(feed.results, service: service),
          shown: grouped[service]!.length,
          collapsed: collapsed.contains(service),
          onToggle: () {
            final next = {...collapsed};
            if (!next.remove(service)) next.add(service);
            ref.read(_collapsedServicesProvider.notifier).state = next;
          },
        ),
        final GlobalActivityItem item => GlobalActivityItemTile(item: item),
        _FooterRow() => _FeedFooter(
          loadingMore: loadingMore,
          loadMoreFailed: loadMoreFailed,
          onLoadMore: onLoadMore,
        ),
        final Widget widget => widget,
        _ => const SizedBox.shrink(),
      },
    );
  }
}

/// What landed today, under the Now table.
///
/// Not a port of the inspector pane's list, and not the same job: the pane is
/// an accelerator over one service, this is the record. It answers a question
/// the queue cannot — "did the thing I was watching an hour ago actually
/// arrive, and where did it go" — which is why every row carries a destination
/// and a clock rather than a relative age.
///
/// Desktop and the compact window only. The phone boards draw no such band, and
/// they are right to: on a 390pt column a destination path is a second ellipsis
/// under a title that already has one, and the phone's answer to "where did it
/// go" is the History section, one tap away.
///
/// The failed import is **amber**. It was red until the tone pass, which put it
/// in the same ink as a connection that did not answer — and a failed import is
/// a service answering and telling us it could not place a file.
class _FinishedTodayBand extends ConsumerWidget {
  const _FinishedTodayBand();

  /// Whether this width draws the band at all.
  static bool visibleAt(BuildContext context) =>
      AppBreakpoints.isDesktopShell(context);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(finishedTodayProvider);
    final items = today.rows;
    if (items.isEmpty) return const SizedBox.shrink();

    // The day's count, not the six rows drawn; and a floor (`12+`) when the
    // first page of history cannot prove it holds the whole day.
    final count = today.count;
    final noun = count == 1 && today.complete ? 'item' : 'items';

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Finished today · $count${today.complete ? '' : '+'} $noun',
                  semanticsLabel: today.complete
                      ? 'Finished today, $count $noun'
                      : 'Finished today, at least $count $noun',
                  style: AppTheme.chrome(
                    context,
                    color: CupolaThemeColors.of(context).dimText,
                  ),
                ),
              ),
              // The band is capped at six, so it is never the whole day — the
              // way out has to be on the band itself rather than left to the
              // user to find the History tab.
              TextButton(
                onPressed: () =>
                    ref.read(_activitySectionProvider.notifier).state =
                        _ActivitySection.history,
                child: const Text('Open history'),
              ),
            ],
          ),
          for (final item in items)
            _FinishedTodayRow(item: item, colorScheme: colorScheme),
        ],
      ),
    );
  }
}

class _FinishedTodayRow extends StatelessWidget {
  const _FinishedTodayRow({required this.item, required this.colorScheme});

  final GlobalActivityItem item;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final tone = statusToneColor(colorScheme, item.status.tone);
    final dim = CupolaThemeColors.of(context).dimText;
    // The two reads the annotation names and nothing in the app performed:
    // where the file landed, and — when it did not — what the service said.
    final destination = item.raw == null ? null : historyFilePath(item.raw!);
    final canImport = canManualImportFrom(item);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.chrome(
                    context,
                    size: 12,
                    weight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                // The destination, or the reason there is none. A failed import
                // has a `detail` after the resolver learned to read
                // `data.statusMessages`; a successful one has a path.
                if (item.detail != null || destination != null)
                  Text(
                    item.detail ?? 'imported to $destination',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.chrome(
                      context,
                      size: 11,
                      color: item.detail != null ? tone : dim,
                    ),
                  ),
              ],
            ),
          ),
          // The failed row's one way out. Blocklist is the other half the
          // annotation asks for and it is not offered here or anywhere else:
          // blocklisting a *history* record is `POST history/failed/{id}` and
          // no client method calls it.
          if (canImport)
            TextButton(
              onPressed: () => openManualImportFrom(context, item),
              child: const Text('Manual import'),
            ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            item.sortDate == null ? '' : formatTimeOnly(item.sortDate!),
            // Tabular so six clocks make a column rather than six ragged
            // strings — the only reason a time-only stamp beats a relative age
            // here.
            style: AppTheme.chrome(context, size: 11, color: dim).mono.tabular,
          ),
        ],
      ),
    );
  }
}

/// The footer's slot in [_ActivityData]'s row-descriptor list.
///
/// A marker rather than the widget itself, so the three "show more" faces are
/// still built lazily by the item builder alongside every other row.
class _FooterRow {
  const _FooterRow();
}

/// The row a paged bucket puts under its last record.
///
/// Three faces for the same slot: an idle "show more" button, a spinner while
/// the next pages are in flight, and a retry when that fetch failed — a failed
/// load more must not look like "everything is loaded".
class _FeedFooter extends StatelessWidget {
  final bool loadingMore;
  final bool loadMoreFailed;
  final VoidCallback onLoadMore;

  const _FeedFooter({
    required this.loadingMore,
    required this.loadMoreFailed,
    required this.onLoadMore,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (loadingMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
      );
    }

    if (loadMoreFailed) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'The next page did not arrive.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          TextButton(onPressed: onLoadMore, child: const Text('Retry')),
        ],
      );
    }

    return Center(
      child: TextButton.icon(
        onPressed: onLoadMore,
        icon: const Icon(Icons.expand_more_rounded, size: 18),
        label: const Text('Show more'),
      ),
    );
  }
}

/// A service group header you can fold away.
///
/// The aggregate view is only useful if you can get *past* the service you are
/// not looking at. The fold contract is
/// `expanded:` on the semantics node rather than an announcement, so the state is
/// discoverable on re-focus and works on TalkBack, and the chevron rotation is
/// the visual half only.
///
/// The figure is the server's total, the one the tile above prints. It used to
/// be the rows loaded under it, so History read "Sonarr 50" beneath a tile
/// that said 2369, and 100 after Show more. When no total was given it says
/// how many rows are on screen (`50 shown`) rather than passing them off as
/// the whole, and a connection that failed is named after the figure
/// (`12 · Sonarr Anime not counted`), since the figure leaves it out. A Seerr
/// that lost a page of its requests keeps its total and says how many rows
/// came (`120 · 70 shown`).
class _ServiceGroupHeader extends StatelessWidget {
  final ServiceKey service;
  final ActivityCount count;

  /// The rows of this service drawn under the header.
  final int shown;
  final bool collapsed;
  final VoidCallback onToggle;

  const _ServiceGroupHeader({
    required this.service,
    required this.count,
    required this.shown,
    required this.collapsed,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = count.total;
    final missing = count.notCounted.isEmpty
        ? null
        : notCountedClause(count.notCounted);
    // A connection that lost a page has the right total over rows that are
    // not all of it, and no Show more to fetch the rest, so the header says
    // how many it is drawing: `120 · 70 shown`.
    final drawn = total != null && count.incomplete ? '$shown shown' : null;
    // A queue that sent a full page and no count has a floor and nothing to
    // name, so the header marks it the way its tile does: `200+`.
    final atLeast = count.cutShort;
    final figure = [
      total == null ? '$shown shown' : '$total${atLeast ? '+' : ''}',
      ?drawn,
      ?missing,
    ];
    final spoken = [
      service.title,
      total == null
          ? '$shown shown'
          : '${atLeast ? 'at least ' : ''}$total '
                '${total == 1 ? 'item' : 'items'}',
      ?drawn,
      ?missing,
    ];

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        header: true,
        button: true,
        expanded: !collapsed,
        label: spoken.join(', '),
        hint: collapsed ? 'expands this service' : 'collapses this service',
        onTap: onToggle,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onToggle();
          },
          excludeFromSemantics: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: ExcludeSemantics(
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: collapsed ? 0.0 : 0.25,
                    duration: AppAnimation.durationSm,
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 22,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  // The name at its own width and the figure taking the rest,
                  // so a figure that names a missing connection ellipsises
                  // inside the row instead of pushing it past the edge.
                  Text(
                    service.title,
                    style: theme.textTheme.titleLarge?.weight(FontWeight.w600),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      figure.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: theme.textTheme.labelMedium
                          ?.weight(FontWeight.w600)
                          .tabular
                          .copyWith(
                            color: ServiceTheme.onTint(
                              service.accent,
                              surface: theme.colorScheme.surface,
                              tintAlpha: 0,
                            ),
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Says which services answered and which did not.
///
/// This is the fact the screen used to compute and then throw away: the provider
/// asked four services, caught each failure separately, and merged the
/// survivors — so a dead Sonarr looked exactly like an idle one. It is also the
/// only thing on this screen that a single-service client could not show, which
/// is why it belongs here rather than in Settings.
class _StackHealthStrip extends StatelessWidget {
  final ActivityFeed feed;
  final VoidCallback onRetry;

  const _StackHealthStrip({required this.feed, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final failures = feed.failures.toList(growable: false);
    if (failures.isEmpty) return const SizedBox.shrink();

    // Classified before painted: a connection that did not answer and one that
    // answered with a refusal are two bands, in two tones, with two remedies.
    // This band used to say "did not respond" in red for a 403.
    final silent = failures
        .where((r) => r.didNotAnswer)
        .toList(growable: false);
    final faulted = failures
        .where((r) => !r.didNotAnswer)
        .toList(growable: false);

    // Each band in a subtree of its own key. Both lines carry the one
    // `activity-fault-line` key, so as bare siblings a load with one silent
    // connection and one refusing connection, both at once, threw "Duplicate
    // keys found" and took the page down with it.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (silent.isNotEmpty)
          KeyedSubtree(
            key: const ValueKey('activity-fault-line.silent'),
            child: _silentBand(context, silent),
          ),
        if (faulted.isNotEmpty)
          KeyedSubtree(
            key: const ValueKey('activity-fault-line.faulted'),
            child: _faultBand(context, faulted),
          ),
      ],
    );
  }

  /// The noun that follows a count: two failures of one service are two
  /// connections, not two services.
  static String _noun(List<ActivityServiceResult> results) =>
      results.any((r) => r.label.isNotEmpty) ? 'connections' : 'services';

  Widget _silentBand(BuildContext context, List<ActivityServiceResult> failed) {
    // Named by connection, never by service alone: "Sonarr did not answer" is
    // a false statement while the other Sonarr is answering, and it leaves the
    // user with no way to know which server to go and look at.
    final names = failed.map((r) => r.title).join(', ');
    return _band(
      context,
      // The one place in Activity that earns red. Every other fault on this
      // page — a stalled transfer, a failed grab, a refused key — is a service
      // answering and telling us something went wrong, which is amber. This
      // band says a connection did not answer at all, and that is the whole of
      // what red means in this app.
      tone: StatusTone.error,
      icon: failureIcon(ServiceFailureReason.unreachable),
      title: failed.length == 1
          ? failureHeadline(ServiceFailureReason.unreachable, subject: names)
          : '${failed.length} ${_noun(failed)} did not answer',
      body: failed.length == 1
          ? 'This list is incomplete, anything from $names is missing from '
                'it.'
          : 'This list is incomplete. Nothing came back from $names.',
      actionLabel: 'Retry',
      onAction: onRetry,
    );
  }

  Widget _faultBand(BuildContext context, List<ActivityServiceResult> failed) {
    final names = failed.map((r) => r.title).join(', ');
    final single = failed.length == 1 ? failed.single : null;
    final presentation = single == null
        ? null
        : describeFailure(
            single.service,
            single.failureReason ?? ServiceFailureReason.unknown,
            subject: single.title,
          );
    // The remedy, when the form holds it (`Paste the key again`), leads to that
    // connection's own form; otherwise Retry, which is what a 5xx or a timeout
    // asks for.
    final remedy = presentation?.remedy;
    return _band(
      context,
      tone: StatusTone.warning,
      icon: presentation?.icon ?? failureIcon(ServiceFailureReason.unknown),
      title:
          presentation?.headline ??
          '${failed.length} ${_noun(failed)} answered with a fault',
      body: 'This list is incomplete, anything from $names is missing from it.',
      actionLabel: remedy ?? 'Retry',
      onAction: remedy == null || single == null
          ? onRetry
          : () => context.push(
              ServiceRoutes.settingsForConnection(
                single.service,
                single.instanceId,
              ),
            ),
    );
  }

  /// A fault is a quiet line — glyph, sentence, remedy — and nothing else.
  ///
  /// It used to be a card: the tone at 7% under a 34% border of the same
  /// tone, with a pip beside the glyph. That is alarm chrome, and in a
  /// self-hosted stack a service that did not answer is a normal afternoon;
  /// the brand book's Presence Rule keeps the tone on the glyph and the title
  /// and leaves the remedy in ink, because a red cure looks like the disease.
  Widget _band(
    BuildContext context, {
    required StatusTone tone,
    required IconData icon,
    required String title,
    required String body,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    // Walked against the ground the line is drawn on: with no fill behind it
    // the glyph and the title carry the whole tone, and raw error red measures
    // 3.7:1 on paper.
    final ink = statusToneColor(
      colorScheme,
      tone,
      surface: colorScheme.surface,
    );

    return Padding(
      key: const ValueKey('activity-fault-line'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Semantics(
        container: true,
        // The remedy stays its own control; this node owns the sentence.
        explicitChildNodes: true,
        liveRegion: true,
        label: '$title. $body',
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Padding(
                // The glyph's optical centre on the title's first line.
                padding: const EdgeInsets.only(top: 2),
                child: Icon(icon, size: 18, color: ink),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall
                          ?.weight(FontWeight.w600)
                          .copyWith(color: ink),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      body,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            // In ink, never the fault tone.
            TextButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

/// One-tap service selection, shaped as instrument tiles rather than pills.
///
/// Each tile answers "how much is here, and did this service even answer?"
/// before it is tapped, so the strip doubles as the at-a-glance stack readout —
/// the thing only an aggregate screen can show.
class _ServiceStrip extends StatelessWidget {
  final List<ServiceKey> services;

  /// Null on the very first load, before any counts exist.
  final ActivityFeed? feed;
  final ServiceKey? selected;
  final ValueChanged<ServiceKey?> onSelected;

  const _ServiceStrip({
    required this.services,
    required this.feed,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final results = feed?.results ?? const <ActivityServiceResult>[];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          _ServiceTile(
            label: 'All',
            icon: Icons.all_inclusive_rounded,
            accent: Theme.of(context).colorScheme.primary,
            // The sum of the totals, not the loaded rows — the same rule as
            // each service's tile below.
            count: activityCount(results),
            selected: selected == null,
            onTap: () => onSelected(null),
          ),
          for (final service in services)
            _ServiceTile(
              label: service.title,
              icon: service.icon,
              accent: service.accent,
              // Summed over the service's connections. The pills stay per
              // service — which connection a row came off is what the row says
              // — so this figure has to be the whole of what that service is
              // doing, not whichever connection was merged last.
              count: activityCount(results, service: service),
              // A service that did not answer shows that instead of a count, so
              // the number 0 never stands in for "no idea". Only when *nothing*
              // of it was reached: with one connection down and another
              // answering, the number is short but it is still a number, and
              // saying "no idea" would hide the rows already on screen. It is
              // drawn as a floor (`12+`) and its spoken label names the
              // connection it leaves out; the health strip says why.
              failed: _allFailedFor(results, service),
              silent: _allSilentFor(results, service),
              selected: selected == service,
              onTap: () => onSelected(service),
            ),
        ],
      ),
    );
  }
}

/// Whether every configured connection of [service] failed.
bool _allFailedFor(List<ActivityServiceResult> results, ServiceKey service) {
  var any = false;
  for (final result in results) {
    if (result.service != service || !result.configured) continue;
    if (!result.failed) return false;
    any = true;
  }
  return any;
}

/// Whether every configured connection of [service] failed **because nothing
/// answered** — the only failure the tile paints red.
bool _allSilentFor(List<ActivityServiceResult> results, ServiceKey service) {
  var any = false;
  for (final result in results) {
    if (result.service != service || !result.configured) continue;
    if (!result.didNotAnswer) return false;
    any = true;
  }
  return any;
}

class _ServiceTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color accent;
  final ActivityCount count;
  final bool failed;

  /// With [failed]: every failure was silence. False when at least one
  /// connection answered with a refusal or a fault, which is amber.
  final bool silent;
  final bool selected;
  final VoidCallback onTap;

  const _ServiceTile({
    required this.label,
    required this.icon,
    required this.accent,
    required this.count,
    required this.selected,
    required this.onTap,
    this.failed = false,
    this.silent = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;
    // The same fact the health band reports, so the same ink. `failed` means
    // every connection of this service failed: red when all of them were
    // silent, amber when one answered with a refusal or a fault — a refused
    // key is the service speaking, not a dark box.
    final tone = failed
        ? statusToneColor(
            colorScheme,
            silent ? StatusTone.error : StatusTone.warning,
          )
        : accent;

    // Selected borrows the nav bar's pill treatment — the app's established
    // "this one is active" language — rather than inventing a third.
    final background = selected
        ? tone.withValues(alpha: isDark ? 0.16 : 0.13)
        : colorScheme.surfaceContainer;
    final border = selected
        ? tone.withValues(alpha: 0.27)
        : colorScheme.outlineVariant;

    // An em dash for "no figure", the same mark every other surface prints —
    // and to the ear it is "unavailable", never "0 items": a count nobody
    // could take is not zero.
    //
    // A floor carries a `+`, the mark the SABnzbd history header already uses
    // for a count it cannot stand behind as the whole: the chip has no room to
    // name what is missing, so the ear gets the name and the eye gets the
    // mark, and the health strip above the list says why. A queue that sent a
    // full page and no count is a floor with nothing to name, and the ear
    // hears "at least".
    final total = count.total;
    final countLabel = failed || total == null
        ? Lexicon.noFigure
        : '$total${count.isFloor ? '+' : ''}';
    final spoken = failed
        ? (silent ? '$label, did not answer' : '$label, answered with a fault')
        : total == null
        ? '$label, count unavailable'
        : [
            '$label, ${count.cutShort ? 'at least ' : ''}$total '
                '${total == 1 ? 'item' : 'items'}',
            if (count.notCounted.isNotEmpty) notCountedClause(count.notCounted),
          ].join(', ');

    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        button: true,
        selected: selected,
        label: spoken,
        onTap: onTap,
        child: Material(
          color: Colors.transparent,
          borderRadius: AppRadius.borderRadiusMd,
          child: InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            borderRadius: AppRadius.borderRadiusMd,
            excludeFromSemantics: true,
            child: Container(
              constraints: const BoxConstraints(minWidth: 84),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: background,
                borderRadius: AppRadius.borderRadiusMd,
                border: Border.all(color: border),
              ),
              child: ExcludeSemantics(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          failed ? Icons.cloud_off_rounded : icon,
                          size: 14,
                          color: tone,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          countLabel,
                          // `height` stays overridden: `titleMedium` carries a
                          // 1.32 reading leading, and this is a numeral stacked
                          // on a label inside a 84pt chip, where that buys
                          // nothing and costs the chip's height.
                          style: theme.textTheme.titleMedium
                              ?.weight(FontWeight.w600)
                              .tabular
                              .copyWith(
                                color: colorScheme.onSurface,
                                height: 1.1,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      label,
                      maxLines: 1,
                      // Sentence case on the label ramp: there is one of these
                      // per chip in a strip of them, and the Eyebrow Rule stops
                      // at repetition — a kicker that appears eight times
                      // across one scroll is not introducing anything, and the
                      // eyebrow is the only voice that uppercases.
                      style: theme.textTheme.labelSmall
                          ?.weight(FontWeight.w600)
                          .copyWith(
                            color: selected
                                ? tone
                                : colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ScrollableState extends StatelessWidget {
  final double bottomPadding;
  final Widget child;

  /// Optional content above the state — the health strip, so a user looking at
  /// an empty list can still see that a service failed to answer.
  final Widget? header;

  /// Optional content below it — "Finished today", which is at its most useful
  /// exactly when the queue is empty: nothing is downloading *because* it all
  /// landed an hour ago, and the empty state alone cannot say so.
  final Widget? footer;

  const _ScrollableState({
    required this.bottomPadding,
    required this.child,
    this.header,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(bottom: bottomPadding),
        children: [
          ?header,
          // A minimum, not a fixed height. This was `SizedBox(height: 320)`
          // wrapped around states that are columns of `Text`: at a large reading
          // size the content outgrew the box and Flutter painted its overflow
          // stripe across the message — on the state a partially-configured user
          // sees most often. A floor keeps the state optically centred while
          // letting it grow (The Grown Box Rule).
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight * 0.6),
            child: child,
          ),
          ?footer,
        ],
      ),
    );
  }
}

/// Drops every cached request list before the feed reloads.
///
/// The whole family, not just the lens's entry: /activity merges every
/// configured Seerr, and `requestsForProvider` collapses the lens's own id onto
/// [requestsProvider] — so dropping one and not the other leaves a pull-to-
/// refresh reading a stale list for some of the connections on screen.
void _invalidateRequests(WidgetRef ref) {
  ref.invalidate(requestsProvider);
  ref.invalidate(requestsForProvider);
}
