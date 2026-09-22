import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: implementation_imports
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_breakpoints.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/lifecycle/refresh_on_return.dart';
import 'package:cupola/core/lifecycle/page_activity.dart';
import 'package:cupola/core/providers/navigation_refresh_provider.dart';
import 'package:cupola/core/text_scale.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/ambient_scaffold.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/app_empty_state.dart';
import 'package:cupola/core/widgets/app_error_state.dart';
import 'package:cupola/core/widgets/app_skeleton.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/widgets/glass_app_bar.dart';
import 'package:cupola/core/widgets/selection_pills.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/activity/presentation/activity_provider.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_formatters.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_item_tiles.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/import/presentation/import_service_picker_sheet.dart';
import 'package:cupola/features/stream/presentation/widgets/stream_activity_section.dart';
import 'package:cupola/features/release_search/presentation/release_search_jobs_provider.dart';
import 'package:cupola/features/release_search/presentation/release_searches_body.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
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
/// their own sub-lines (`4 blocklisted`, `63 wanted · 54 missing`), and those
/// are totals the client does not hold: `getHistory`/`getMissing`/`getCutoff`
/// return `records` and drop the `totalRecords` envelope, so the only figure
/// available is "how many rows are loaded", which changes every time the user
/// taps Show more. A number that moves while the data does not is worse than no
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
    final readout = feed == null ? null : _nowReadout(feed);

    final title = Text(
      'Activity',
      style: theme.appBarTheme.titleTextStyle ?? theme.textTheme.titleLarge,
    );
    if (readout == null) return title;

    return Semantics(
      container: true,
      header: true,
      label: 'Activity, $readout',
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            title,
            Text(
              readout,
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

/// "6 in the queue · 2 stalled · 2 importing" — and only the clauses that are
/// true. A readout that prints "0 stalled" spends a third of its width telling
/// the user that nothing happened.
String _nowReadout(ActivityFeed feed) {
  final queued = feed.items
      .where((i) => i.kind == GlobalActivityKind.queue)
      .toList(growable: false);
  if (queued.isEmpty) return 'Nothing in the queue';

  var stalled = 0;
  var importing = 0;
  for (final item in queued) {
    switch (item.status.pipeline) {
      case MediaPipeline.stalled:
        stalled++;
      case MediaPipeline.importing:
      case MediaPipeline.importPending:
      case MediaPipeline.importBlocked:
        importing++;
      default:
        break;
    }
  }

  return [
    '${queued.length} in the queue',
    if (stalled > 0) '$stalled stalled',
    if (importing > 0) '$importing importing',
  ].join(' · ');
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

    // Nothing is set up at all — the honest answer is "connect something",
    // not "nothing is downloading".
    if (!feed.hasConfiguredService) {
      return _ScrollableState(
        bottomPadding: bottomPadding,
        child: AppEmptyState(
          icon: Icons.settings_ethernet_rounded,
          title: 'No services connected',
          message:
              'Add Radarr, Sonarr, Lidarr or Seerr in Settings and their '
              'activity will show up here.',
          action: FilledButton(
            onPressed: () => context.go('/settings'),
            child: const Text('Open Settings'),
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
          count: grouped[service]!.length,
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
    final items = ref.watch(finishedTodayProvider);
    if (items.isEmpty) return const SizedBox.shrink();

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
                  'Finished today · ${items.length} '
                  '${items.length == 1 ? 'item' : 'items'}',
                  style: AppTheme.eyebrow(
                    CupolaThemeColors.of(context).dimText,
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

class _FinishedTodayRow extends ConsumerWidget {
  const _FinishedTodayRow({required this.item, required this.colorScheme});

  final GlobalActivityItem item;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tone = statusToneColor(colorScheme, item.status.tone);
    final dim = CupolaThemeColors.of(context).dimText;
    // The two reads the annotation names and nothing in the app performed:
    // where the file landed, and — when it did not — what the service said.
    final destination = item.raw == null ? null : historyFilePath(item.raw!);
    final canImport = canManualImportFrom(ref, item);

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
            "Couldn't load more.",
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
class _ServiceGroupHeader extends StatelessWidget {
  final ServiceKey service;
  final int count;
  final bool collapsed;
  final VoidCallback onToggle;

  const _ServiceGroupHeader({
    required this.service,
    required this.count,
    required this.collapsed,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        header: true,
        button: true,
        expanded: !collapsed,
        label:
            '${service.title}, $count '
            '${count == 1 ? 'item' : 'items'}',
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
                  Expanded(
                    child: Text(
                      service.title,
                      style: theme.textTheme.titleLarge?.weight(
                        FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '$count',
                    style: theme.textTheme.labelMedium
                        ?.weight(FontWeight.w600)
                        .tabular
                        .copyWith(color: service.accent),
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final failed = feed.failures.toList(growable: false);
    if (failed.isEmpty) return const SizedBox.shrink();

    // Named by connection, never by service alone: "Sonarr did not respond"
    // is a false statement while the other Sonarr is answering, and it leaves
    // the user with no way to know which server to go and look at.
    final names = failed.map((r) => r.title).join(', ');
    // And the noun follows: two failures of one service are two connections,
    // not two services.
    final noun = failed.any((r) => r.label.isNotEmpty)
        ? 'connections'
        : 'services';

    // The one place in Activity that earns red. Every other fault on this page
    // — a stalled transfer, a failed grab, a failed import — is a service
    // answering and telling us something went wrong, which is amber. This band
    // says a connection did not answer at all, and that is the whole of what
    // red means in this app. It was amber, which put it in the same tone as the
    // rows it is warning about.
    //
    // The fill and border are walked against the surface the card composites
    // on, not the raw token: error red is 3.74:1 on paper.
    final alarm = statusToneColor(colorScheme, StatusTone.error);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: AppCard.outlined(
        backgroundColor: alarm.withValues(alpha: 0.07),
        borderColor: alarm.withValues(alpha: 0.34),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Red never travels alone: the pip is the non-colour half of the
            // signal, so the band still reads as an alarm to a user who cannot
            // separate red from amber. It sits before the glyph, not on it.
            Container(
              // 7pt, and nudged down by the glyph's own optical centre so the
              // dot sits on the first line of type rather than above it.
              margin: const EdgeInsets.only(top: 6),
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: alarm, shape: BoxShape.circle),
            ),
            const SizedBox(width: AppSpacing.sm),
            Icon(Icons.cloud_off_rounded, size: 20, color: alarm),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    failed.length == 1
                        ? '$names did not respond'
                        : '${failed.length} $noun did not respond',
                    style: theme.textTheme.titleSmall?.weight(FontWeight.w600),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    failed.length == 1
                        ? 'This list is incomplete, anything from $names is '
                              'missing from it.'
                        : 'This list is incomplete. No response from $names.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
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
            count: feed?.items.length,
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
              count: _countFor(results, service),
              // A service that did not answer shows that instead of a count, so
              // the number 0 never stands in for "no idea". Only when *nothing*
              // of it was reached: with one connection down and another
              // answering, the number is short but it is still a number, and
              // saying "no idea" would hide the rows already on screen. The
              // health strip is what reports the shortfall, by connection.
              failed: _allFailedFor(results, service),
              selected: selected == service,
              onTap: () => onSelected(service),
            ),
        ],
      ),
    );
  }
}

/// [service]'s items across every connection, or null while none has answered.
int? _countFor(List<ActivityServiceResult> results, ServiceKey service) {
  var total = 0;
  var any = false;
  for (final result in results) {
    if (result.service != service || !result.configured) continue;
    any = true;
    total += result.items.length;
  }
  return any ? total : null;
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

class _ServiceTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color accent;
  final int? count;
  final bool failed;
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
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;
    // The same fact the health band reports, so the same ink. `failed` here
    // means every connection of this service was unreachable — silence, which
    // is red — and it was amber, which is the tone reserved for a service that
    // answered and said something was wrong.
    final tone = failed
        ? statusToneColor(colorScheme, StatusTone.error)
        : accent;

    // Selected borrows the nav bar's pill treatment — the app's established
    // "this one is active" language — rather than inventing a third.
    final background = selected
        ? tone.withValues(alpha: isDark ? 0.16 : 0.13)
        : colorScheme.surfaceContainer;
    final border = selected
        ? tone.withValues(alpha: 0.27)
        : colorScheme.outlineVariant;

    final countLabel = failed ? '—' : (count?.toString() ?? '–');
    final spoken = failed
        ? '$label, did not respond'
        : '$label, ${count ?? 0} ${count == 1 ? 'item' : 'items'}';

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
                      label.toUpperCase(),
                      maxLines: 1,
                      // Off `AppTheme.eyebrow` and onto the label ramp: there is
                      // one of these per chip in a strip of them, and the Eyebrow
                      // Rule stops at repetition — a kicker that appears eight
                      // times across one scroll is not introducing anything. The
                      // selected/unselected tone is unchanged.
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
