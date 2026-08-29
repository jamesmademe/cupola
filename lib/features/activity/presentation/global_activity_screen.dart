import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: implementation_imports
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/lifecycle/refresh_on_return.dart';
import 'package:cupola/core/lifecycle/page_activity.dart';
import 'package:cupola/core/providers/navigation_refresh_provider.dart';
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
import 'package:cupola/features/activity/presentation/widgets/activity_item_tiles.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/import/presentation/import_service_picker_sheet.dart';
import 'package:cupola/features/stream/presentation/widgets/stream_activity_section.dart';
import 'package:cupola/features/release_search/presentation/release_searches_body.dart';
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

  const _ActivitySub(this.label, this.provider, this.emptyMessage)
    : pagedProvider = null,
      body = null;

  const _ActivitySub.paged(this.label, this.pagedProvider, this.emptyMessage)
    : provider = null,
      body = null;

  const _ActivitySub.custom({required this.label, required this.body})
    : provider = null,
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
    _ActivitySub.custom(label: _searchingSubLabel, body: _releaseSearchesBody),
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
      'Cutoff Unmet',
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
          title: const Text('Activity'),
          actions: [
            IconButton(
              tooltip: 'Manual Import',
              icon: const Icon(Icons.download_for_offline_outlined),
              onPressed: () => showImportServicePickerSheet(context),
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

    final customBody = sub.body;
    if (customBody != null) {
      return Column(
        children: [
          _SubPills(section: section, subs: subs, subIndex: subIndex),
          Expanded(child: customBody(bottomPadding)),
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

    if (visible.isEmpty) {
      return _ScrollableState(
        bottomPadding: bottomPadding,
        header: health,
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

    // Flat list when a single service is selected.
    if (filter != null) {
      final footerVisible = hasMore || loadingMore || loadMoreFailed;
      final headerCount = health == null ? 0 : 1;
      return ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(top: AppSpacing.md, bottom: bottomPadding),
        itemCount: visible.length + headerCount + (footerVisible ? 1 : 0),
        itemBuilder: (context, index) {
          if (health != null && index == 0) return health;
          final itemIndex = index - headerCount;
          if (itemIndex >= visible.length) {
            return _FeedFooter(
              loadingMore: loadingMore,
              loadMoreFailed: loadMoreFailed,
              onLoadMore: onLoadMore,
            );
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
      if (health != null) health,
      for (final service in orderedServices) ...[
        service,
        if (!collapsed.contains(service)) ...grouped[service]!,
      ],
      if (hasMore || loadingMore || loadMoreFailed) const _FooterRow(),
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
                        FontWeight.bold,
                      ),
                    ),
                  ),
                  Text(
                    '$count',
                    style: theme.textTheme.labelMedium
                        ?.weight(FontWeight.w800)
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: AppCard.outlined(
        backgroundColor: AppColors.warning.withValues(alpha: 0.10),
        borderColor: AppColors.warning.withValues(alpha: 0.35),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 20,
              color: statusToneColor(colorScheme, StatusTone.warning),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    failed.length == 1
                        ? '$names did not respond'
                        : '${failed.length} $noun did not respond',
                    style: theme.textTheme.titleSmall?.weight(FontWeight.w700),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    failed.length == 1
                        ? 'This list is incomplete — anything from $names is '
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
    final warning = statusToneColor(colorScheme, StatusTone.warning);
    final tone = failed ? warning : accent;

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
                              ?.weight(FontWeight.w800)
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
                          ?.weight(FontWeight.w700)
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

  const _ScrollableState({
    required this.bottomPadding,
    required this.child,
    this.header,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(bottom: bottomPadding),
        children: [
          if (header != null) header!,
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
