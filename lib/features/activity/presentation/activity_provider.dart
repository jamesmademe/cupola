import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/lifecycle/gated_poll.dart'; // ignore: implementation_imports
import 'package:flutter_riverpod/legacy.dart';

import 'package:cupola/core/api/base_arr_service.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/features/activity/domain/global_activity_status.dart';
import 'package:cupola/features/activity/domain/service_type.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_formatters.dart'
    show activitySecondaryLine;
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

export 'package:cupola/features/activity/domain/global_activity_status.dart'
    show GlobalActivityKind;

final activityRefreshVersionProvider = StateProvider<int>((ref) => 0);

/// Bumped by the 15s "Now" poll, and only by it.
///
/// Separate from [activityRefreshVersionProvider] on purpose: a poll tick must
/// reload the queues — the only rows that change by the second — without
/// refetching the Seerr request history, which is settled until the user acts
/// on it. Refetching every page of it every 15 seconds is a cost that grows
/// with the library for a list that is usually identical to the one already on
/// screen.
final activityQueuePollVersionProvider = StateProvider<int>((ref) => 0);

const _globalActivityPageSize = 50;

/// How often the "Now" bucket refreshes itself.
///
/// A bucket named "Now" that shows a snapshot from whenever the tab was last
/// opened is not a live readout — a download sat at 43% until the user pulled to
/// refresh. Deliberately far slower than qBittorrent's 3s: that polls one local
/// endpoint for one list, whereas each tick here fans out to three \*arr
/// services, over a LAN, VPN or Tailscale link where a request can take a
/// second. 15s keeps the number honest without hammering someone's home server.
const _nowPollInterval = Duration(seconds: 15);

/// One service's contribution to a feed load.
///
/// The whole point of this type is that a failure is *reportable*. Every service
/// used to be wrapped in `catch (_) { return const []; }`, so a dead Sonarr and
/// an idle Sonarr produced byte-identical output and the screen confidently
/// said "Nothing downloading right now". Errors are caught per service — one
/// unreachable instance must never blank the others — but they are carried, not
/// swallowed.
class ActivityServiceResult {
  final ServiceKey service;

  /// Which **connection** answered. Empty only for the placeholder a service
  /// with no connection at all produces.
  ///
  /// The unit this class is keyed on, and the reason it is not the service:
  /// two Sonarrs are two servers with two queues, and a result that can only
  /// say "Sonarr" cannot report that one of them is down while the other is
  /// merely idle.
  final String instanceId;

  /// What to call this connection in a sentence, and empty whenever the
  /// service has only one — the rule `ServiceConnectionRow` and
  /// `ServiceMatrixCell` already follow. A lone Radarr must not grow a name
  /// for the only Radarr there is.
  final String label;

  final List<GlobalActivityItem> items;

  /// Non-null when the service was configured but did not answer.
  final Object? error;

  /// False when the user has not set this service up at all.
  final bool configured;

  const ActivityServiceResult({
    required this.service,
    required this.items,
    required this.configured,
    this.instanceId = '',
    this.label = '',
    this.error,
  });

  const ActivityServiceResult.unconfigured(this.service)
    : items = const [],
      error = null,
      configured = false,
      instanceId = '',
      label = '';

  /// How this result names itself: the service alone when it is the only
  /// connection, `Sonarr · 2` when it is not.
  String get title =>
      label.isEmpty ? service.title : '${service.title} · $label';

  /// Configured, asked, and answered.
  bool get reached => configured && error == null;

  /// Configured, asked, and did not answer.
  bool get failed => configured && error != null;
}

/// A whole feed load: the merged items plus what happened to each service.
class ActivityFeed {
  final List<GlobalActivityItem> items;
  final List<ActivityServiceResult> results;

  const ActivityFeed({required this.items, required this.results});

  const ActivityFeed.empty() : items = const [], results = const [];

  Iterable<ActivityServiceResult> get configured =>
      results.where((r) => r.configured);

  Iterable<ActivityServiceResult> get failures =>
      results.where((r) => r.failed);

  Iterable<ActivityServiceResult> get unconfigured =>
      results.where((r) => !r.configured);

  /// Every connection of [service] that took part in this load.
  ///
  /// The filter strip and the group headers still speak in services, so they
  /// need the per-connection results folded back up — but only where a *number*
  /// is wanted. Anything that names a failure keeps the connection.
  Iterable<ActivityServiceResult> resultsFor(ServiceKey service) =>
      results.where((r) => r.service == service);

  bool get hasConfiguredService => configured.isNotEmpty;

  /// Nothing was actually reached — every configured service errored.
  ///
  /// This is the case that must surface as an error with a retry rather than as
  /// an empty state, because "no items" here means "we have no idea".
  bool get allConfiguredFailed =>
      hasConfiguredService && configured.every((r) => r.failed);

  /// Some services answered and some did not, so the list is incomplete.
  bool get isPartial => failures.isNotEmpty && !allConfiguredFailed;

  /// The first error, for the whole-feed error state.
  Object? get firstError => failures.isEmpty ? null : failures.first.error;
}

class GlobalActivityItem {
  final GlobalActivityKind kind;
  final ServiceKey service;
  final ServiceType serviceType;

  /// The connection this record came off.
  ///
  /// Carried on every row because the feed is now a merge of several servers,
  /// and the identity a write needs is this one: \*arr queue ids are per server
  /// and each server numbers from one, so `id: 7` names a different download on
  /// each Sonarr. Empty for a row whose connection is unknown, which is how
  /// every fixture predating the merge still reads — such a row falls back to
  /// the lens exactly as it always did.
  final String instanceId;

  /// The name to print on the row, and empty whenever the service has only one
  /// connection. See [ActivityServiceResult.label].
  final String instanceLabel;

  final String title;
  final String subtitle;

  /// The fully resolved status — tone, label, progress, warning and all.
  ///
  /// Replaces the previous `String status` + `double? progress` +
  /// `String? warning` triple. Those were flattened at load time, which left the
  /// tile with nothing to colour by except the row's *kind* — the bug that made
  /// a failed import render in the success green.
  final MediaStatusInfo status;

  final DateTime? sortDate;
  final Map<String, dynamic>? raw;
  final SeerrRequest? request;

  const GlobalActivityItem({
    required this.kind,
    required this.service,
    required this.serviceType,
    required this.title,
    required this.subtitle,
    required this.status,
    this.instanceId = '',
    this.instanceLabel = '',
    this.sortDate,
    this.raw,
    this.request,
  });

  double? get progress => status.progress;

  /// The service's own explanation, when it gave one.
  String? get detail => status.detail;

  /// Wants the user's eye: failed, stalled, blocked, missing.
  bool get needsAttention =>
      status.tone == StatusTone.error || status.tone == StatusTone.warning;

  /// The \*arr record id, used by the queue write actions.
  int? get recordId => intOrNull(raw?['id']);
}

/// Auto-refresh for the "Now" bucket.
///
/// Three services per tick, so it runs on two conditions at once: the Now bucket
/// is the selected one, and the Activity page is the page on screen. Each tick
/// bumps the queue-only version — the queues are live data, the Seerr requests
/// are not.
final activityNowPollingProvider = Provider.autoDispose<void>((ref) {
  ref.gatedPoll(
    id: 'activity.now',
    interval: _nowPollInterval,
    onTick: () => ref.read(activityQueuePollVersionProvider.notifier).state++,
  );
});

/// The services that can appear in the global feed, in display order.
const globalActivityServices = [
  ServiceKey.radarr,
  ServiceKey.sonarr,
  ServiceKey.lidarr,
  ServiceKey.seerr,
];

/// One connection the global feed reads: which \*arr it is, which server, and
/// the name its rows carry.
typedef ActivityConnection = ({
  ServiceType serviceType,
  ServiceKey service,
  String instanceId,
  String label,
});

/// What a paged bucket keys its cursors and its accumulated pages on.
///
/// Identity only, and deliberately not [ActivityConnection]: a record compares
/// by every field, and that one also carries `label` — a rendering detail
/// derived from settings, which flips from empty to a name the moment a second
/// connection of the same service is configured. Keyed on the whole record, a
/// cursor stored before that change can never be looked up after it, and the
/// bucket's Load more quietly stops answering. The connection travels
/// alongside, in [PagedArrFeedNotifier._connections].
typedef ActivityPageKey = (GlobalActivityKind, ServiceType, String);

ActivityPageKey _pageKey(GlobalActivityKind kind, ActivityConnection c) =>
    (kind, c.serviceType, c.instanceId);

/// Every configured \*arr connection, in the user's own instance order.
///
/// The unit the feed loads, and the change this whole pass is about: /activity
/// is the one screen that answers "what is my stack doing", and it was
/// answering for the lens. With two Sonarrs and eight downloads on the second
/// of them, moving the lens to the first turned the pill to 0 and printed
/// "Nothing from Sonarr right now" over eight live transfers.
List<ActivityConnection> activityArrConnections(SettingsModel settings) {
  return _connectionsOf(settings, _arrActivityServiceTypes);
}

/// Every configured Seerr connection, in the user's own instance order.
///
/// Seerr was the last service left on the lens here, and for a while
/// deliberately: a leg per connection is only honest if the row under it opens
/// the server that listed it, and every read in the Discover feature resolved
/// through the lens. That is no longer true of the two things an /activity
/// request row actually does — approve/decline now go through
/// `seerrServiceForProvider`, and the row opens `/activity/discover?i=` — so
/// the fan-out has something to stand on.
///
/// Global *search* stays on one Seerr section, and that is not an
/// inconsistency: a search row has no way to open a named connection, which is
/// what `ServiceKeyExtension.searchesPerConnection` records.
List<ActivityConnection> activitySeerrConnections(SettingsModel settings) {
  return _connectionsOf(settings, const [ServiceType.discover]);
}

/// The shared enumeration behind both lists above: one entry per configured
/// connection, in instance order, each carrying the name its rows will print.
List<ActivityConnection> _connectionsOf(
  SettingsModel settings,
  List<ServiceType> serviceTypes,
) {
  return [
    for (final serviceType in serviceTypes)
      for (final instance in settings.configuredInstancesOf(
        _serviceKeyFor(serviceType),
      ))
        (
          serviceType: serviceType,
          service: instance.service,
          instanceId: instance.id,
          // Named only when there is something to tell apart, which is the rule
          // `ServiceConnectionRow` and `ServiceMatrixCell` already follow: a
          // stack with one Radarr must not grow a badge naming the only Radarr
          // there is. The id is the fallback for a connection the user never
          // named — the first one usually has no label.
          label: settings.hasMultipleInstances(instance.service)
              ? (instance.label.isEmpty ? instance.id : instance.label)
              : '',
        ),
  ];
}

/// The \*arr service for **one connection**, whatever the lens is pointing at.
///
/// The write half of the aggregation. An aggregated queue lists rows from
/// several servers, and a queue record id is per server — every \*arr numbers
/// its queue from one — so "remove id 7" sent to the wrong Sonarr removes a
/// different download and reports success. Every action a row offers therefore
/// resolves through here with that row's own [ActivityConnection.instanceId].
///
/// The per-connection providers underneath resolve the lens's own id back onto
/// the plain `radarrServiceProvider`, so this neither mints a second client for
/// the connection already open nor bypasses the override every test supplies.
/// An empty id means "whatever the lens is on", which is what a row predating
/// the merge carries and what the per-service Activity screen wants.
final connectionArrServiceProvider =
    Provider.family<ArrActivityMixin, (ServiceType, String)>((ref, key) {
      final (serviceType, instanceId) = key;

      assert(
        serviceType.supportsArrActivity,
        'connectionArrServiceProvider only supports movies, series, and music.',
      );

      // "The lens" reached without asking settings which connection that is.
      // The per-connection provider would answer the same thing for an empty
      // id, but only after reading the lens — so a row carrying no connection
      // would start needing a settings scope it never needed before.
      if (instanceId.isEmpty) {
        return ref.watch(resolvedArrServiceProvider(serviceType));
      }

      return switch (serviceType) {
        ServiceType.movies => ref.watch(radarrServiceForProvider(instanceId)),
        ServiceType.series => ref.watch(sonarrServiceForProvider(instanceId)),
        ServiceType.music => ref.watch(lidarrServiceForProvider(instanceId)),
        ServiceType.discover => throw ArgumentError.value(
          serviceType,
          'serviceType',
          'ServiceType.discover does not have an *arr service',
        ),
      };
    });

/// Only the services the user has actually configured.
///
/// The filter row used to be a `static const` of four, so a user running Radarr
/// alone still got Sonarr, Lidarr and Seerr chips, each leading to a confident
/// "Nothing downloading right now".
final configuredActivityServicesProvider = Provider<List<ServiceKey>>((ref) {
  final settings = ref.watch(settingsProvider);
  return globalActivityServices
      .where(settings.isServiceConfigured)
      .toList(growable: false);
});

final globalActivityFeedProvider = FutureProvider<ActivityFeed>((ref) async {
  ref.watch(activityRefreshVersionProvider);
  ref.watch(activityQueuePollVersionProvider);
  return _merge(
    await Future.wait([
      ..._loadRequestResults(ref),
      ..._loadArrResults(ref, GlobalActivityKind.queue),
      ..._loadArrResults(ref, GlobalActivityKind.history),
    ]),
  );
});

final globalQueueItemsProvider = FutureProvider<ActivityFeed>((ref) async {
  ref.watch(activityRefreshVersionProvider);
  ref.watch(activityQueuePollVersionProvider);
  return _merge(
    await Future.wait(_loadArrResults(ref, GlobalActivityKind.queue)),
  );
});

/// "Now" bucket: active downloads (queue) plus current Seerr requests, so
/// requests remain first-class in the unified view.
///
/// Watches both versions: the poll tick (queues only, requests served from the
/// `requestsProvider` cache) and the manual refresh version (everything fresh,
/// requests invalidated by the pull).
final globalNowItemsProvider = FutureProvider<ActivityFeed>((ref) async {
  ref.watch(activityRefreshVersionProvider);
  ref.watch(activityQueuePollVersionProvider);
  return _merge(
    await Future.wait([
      ..._loadRequestResults(ref),
      ..._loadArrResults(ref, GlobalActivityKind.queue),
    ]),
  );
});

/// Blocklist, complete: `getBlocklist` now pages every record, so a one-shot
/// provider is all this bucket needs — blocklists are small enough that
/// fetching them whole is one request, unlike History or Wanted.
final globalBlocklistItemsProvider = FutureProvider<ActivityFeed>((ref) async {
  ref.watch(activityRefreshVersionProvider);
  return _merge(
    await Future.wait(_loadArrResults(ref, GlobalActivityKind.blocklist)),
  );
});

/// History, paged: the first window loads, "load more" fetches the rest.
///
/// History is the one bucket whose full contents can be thousands of rows with
/// embedded series/episode data — several megabytes and a dozen requests if
/// fetched up front. The official web UI pages it, and so does this: a window
/// of 50 per service, then explicit "load more" pages.
final globalHistoryFeedProvider =
    NotifierProvider<PagedArrFeedNotifier, PagedArrFeedState>(
      () => PagedArrFeedNotifier(kinds: const [GlobalActivityKind.history]),
    );

/// Wanted "All" bucket: missing and cutoff unmet, paged like History.
final globalWantedFeedProvider =
    NotifierProvider<PagedArrFeedNotifier, PagedArrFeedState>(
      () => PagedArrFeedNotifier(
        kinds: const [GlobalActivityKind.missing, GlobalActivityKind.cutoff],
      ),
    );

final globalMissingFeedProvider =
    NotifierProvider<PagedArrFeedNotifier, PagedArrFeedState>(
      () => PagedArrFeedNotifier(kinds: const [GlobalActivityKind.missing]),
    );

final globalCutoffFeedProvider =
    NotifierProvider<PagedArrFeedNotifier, PagedArrFeedState>(
      () => PagedArrFeedNotifier(kinds: const [GlobalActivityKind.cutoff]),
    );

/// How many records the first page of a paged bucket asks for.
///
/// Matches the web UI's initial page size, so the first paint costs the same
/// three requests it always did — just with pages big enough to matter.
const _pagedInitialPageSize = 50;

/// Page size for every "load more" page after the first.
///
/// 200 is the server's own cap for the queue and sits well inside every
/// endpoint's tolerance, which makes a huge list close in one or two taps
/// instead of a dozen.
const _pagedMorePageSize = 200;

/// One (kind, connection) pair's progress through a paged bucket.
class PagedCursor {
  final int fetched;
  final int nextPage;
  final bool lastPageFull;
  final bool configured;
  final Object? error;

  const PagedCursor({
    required this.fetched,
    required this.nextPage,
    required this.lastPageFull,
    required this.configured,
    this.error,
  });

  /// Whether another page might exist.
  ///
  /// The \*arr page endpoints do not hand their total count to callers of this
  /// shape, so "full last page" is the proxy: a page that came back with fewer
  /// records than requested was the last one. The only cost of the heuristic is
  /// one extra empty page when a list ends exactly on a page boundary.
  bool get hasMore => lastPageFull;

  bool get failed => error != null;
}

/// The window a paged bucket currently shows.
///
/// [feed] deliberately keeps the same shape the one-shot buckets produce — the
/// screen's four branches (loading, nothing configured, all failed, data) only
/// need a feed and a retry callback, and they get exactly those.
class PagedArrFeedState {
  final ActivityFeed? feed;
  final bool refreshing;
  final bool loadingMore;
  final bool loadMoreFailed;
  final Map<ActivityPageKey, PagedCursor> cursors;

  const PagedArrFeedState({
    this.feed,
    this.refreshing = false,
    this.loadingMore = false,
    this.loadMoreFailed = false,
    this.cursors = const {},
  });

  PagedArrFeedState copyWith({
    ActivityFeed? feed,
    bool? refreshing,
    bool? loadingMore,
    bool? loadMoreFailed,
    Map<ActivityPageKey, PagedCursor>? cursors,
  }) {
    return PagedArrFeedState(
      feed: feed ?? this.feed,
      refreshing: refreshing ?? this.refreshing,
      loadingMore: loadingMore ?? this.loadingMore,
      loadMoreFailed: loadMoreFailed ?? this.loadMoreFailed,
      cursors: cursors ?? this.cursors,
    );
  }

  bool get hasMore => cursors.values.any((c) => c.hasMore);
}

/// Loads a bucket's records a window at a time, the way the official web UI
/// pages its History, Wanted and Blocklist tables.
///
/// `build` watches [activityRefreshVersionProvider] so the one pull-to-refresh
/// mechanism reloads every bucket that is alive, paged or not; the previous
/// feed stays on screen (with the hairline "refreshing" bar) until the first
/// pages come back. [loadMore] then fetches the next page of every pair that
/// has one, in parallel, and re-merges — the merged feed is re-sorted whole, so
/// the severity-first order stays an order, not a per-page concatenation.
class PagedArrFeedNotifier extends Notifier<PagedArrFeedState> {
  PagedArrFeedNotifier({required this.kinds});

  /// The record kinds this bucket pages over, in display order.
  final List<GlobalActivityKind> kinds;

  /// Accumulated items per (kind, connection) pair.
  final Map<ActivityPageKey, List<GlobalActivityItem>> _items = {};

  /// The connection behind each key, for the sake of the label the rows and
  /// the health strip print. Rebuilt with the cursors on every reload, so it
  /// always describes the connections the current pages actually came from.
  final Map<ActivityPageKey, ActivityConnection> _connections = {};

  /// The most recent first-page load, so tests can await it.
  Future<void> _loading = Future.value();

  /// Guards the first-page loads against each other and against [loadMore]:
  /// whoever bumps the generation last owns `_items` and `state`.
  int _generation = 0;

  /// The first-page load, awaitable for tests.
  Future<void> get loading => _loading;

  @override
  PagedArrFeedState build() {
    ref.watch(activityRefreshVersionProvider);
    final previous = stateOrNull;
    _loading = _reload();
    return previous?.copyWith(refreshing: true) ?? const PagedArrFeedState();
  }

  /// Fetches the next page of every pair that still has one, in parallel, and
  /// merges the result into the window.
  Future<void> loadMore() async {
    final current = state;
    if (current.feed == null || current.loadingMore || !current.hasMore) return;

    final generation = _generation;
    state = current.copyWith(loadingMore: true, loadMoreFailed: false);

    final pairs = [
      for (final entry in current.cursors.entries)
        if (entry.value.hasMore) entry.key,
    ];
    final fetched = <ActivityPageKey, List<GlobalActivityItem>>{};
    await Future.wait([for (final pair in pairs) _loadNextPage(pair, fetched)]);

    if (generation != _generation) return;

    for (final entry in fetched.entries) {
      _items.putIfAbsent(entry.key, () => []).addAll(entry.value);
    }

    final cursors = <ActivityPageKey, PagedCursor>{};
    for (final entry in current.cursors.entries) {
      final pair = entry.key;
      final cursor = entry.value;
      final extra = fetched[pair];
      cursors[pair] = PagedCursor(
        fetched: cursor.fetched + (extra?.length ?? 0),
        nextPage: cursor.nextPage + (extra == null ? 0 : 1),
        lastPageFull: (extra?.length ?? 0) == _pagedMorePageSize,
        configured: cursor.configured,
        error: cursor.error,
      );
    }

    state = PagedArrFeedState(feed: _buildFeed(cursors), cursors: cursors);
  }

  Future<void> _reload() async {
    final generation = ++_generation;
    _items.clear();
    _connections.clear();

    final cursors = <ActivityPageKey, PagedCursor>{};
    final loaded = <ActivityPageKey, List<GlobalActivityItem>>{};
    final connections = activityArrConnections(ref.read(settingsProvider));

    await Future.wait([
      for (final kind in kinds)
        for (final connection in connections)
          _loadFirstPage(kind, connection, cursors, loaded),
    ]);

    if (generation != _generation) return;

    for (final entry in loaded.entries) {
      // Growable copy: `loadMore` appends to these lists.
      _items[entry.key] = [...entry.value];
    }

    state = PagedArrFeedState(feed: _buildFeed(cursors), cursors: cursors);
  }

  Future<void> _loadFirstPage(
    GlobalActivityKind kind,
    ActivityConnection connection,
    Map<ActivityPageKey, PagedCursor> cursors,
    Map<ActivityPageKey, List<GlobalActivityItem>> loaded,
  ) async {
    final pair = _pageKey(kind, connection);
    _connections[pair] = connection;

    try {
      final arrService = ref.read(
        connectionArrServiceProvider((
          connection.serviceType,
          connection.instanceId,
        )),
      );
      final raw = await _loadRawItems(
        arrService,
        kind,
        page: 1,
        pageSize: _pagedInitialPageSize,
      );
      final mapped = raw
          .whereType<Map>()
          .map((item) => _arrItem(kind, connection, stringKeyMap(item)))
          .toList(growable: false);
      loaded[pair] = mapped;
      cursors[pair] = PagedCursor(
        fetched: mapped.length,
        nextPage: 2,
        lastPageFull: mapped.length == _pagedInitialPageSize,
        configured: true,
      );
    } catch (error) {
      cursors[pair] = PagedCursor(
        fetched: 0,
        nextPage: 1,
        lastPageFull: false,
        configured: true,
        error: error,
      );
    }
  }

  Future<void> _loadNextPage(
    ActivityPageKey pair,
    Map<ActivityPageKey, List<GlobalActivityItem>> fetched,
  ) async {
    final (kind, serviceType, instanceId) = pair;
    final cursor = state.cursors[pair];
    final connection = _connections[pair];
    if (cursor == null || !cursor.hasMore || connection == null) return;

    try {
      final arrService = ref.read(
        connectionArrServiceProvider((serviceType, instanceId)),
      );
      final raw = await _loadRawItems(
        arrService,
        kind,
        page: cursor.nextPage,
        pageSize: _pagedMorePageSize,
      );
      fetched[pair] = raw
          .whereType<Map>()
          .map((item) => _arrItem(kind, connection, stringKeyMap(item)))
          .toList(growable: false);
    } catch (_) {
      // The pair keeps its cursor, so the footer can offer a retry.
    }
  }

  ActivityFeed _buildFeed(Map<ActivityPageKey, PagedCursor> cursors) {
    final results = <ActivityServiceResult>[
      // The services with nothing configured, once each rather than once per
      // kind — they have no connection to be keyed on.
      for (final service in _unconfiguredArrServices)
        ActivityServiceResult.unconfigured(service),
    ];
    for (final entry in cursors.entries) {
      final (_, serviceType, instanceId) = entry.key;
      final connection = _connections[entry.key];
      results.add(
        ActivityServiceResult(
          service: connection?.service ?? _serviceKeyFor(serviceType),
          instanceId: instanceId,
          label: connection?.label ?? '',
          items: _items[entry.key] ?? const [],
          configured: entry.value.configured,
          error: entry.value.error,
        ),
      );
    }
    return _merge(results);
  }

  /// The \*arr services this bucket asked nothing of, because the user has not
  /// set them up.
  List<ServiceKey> get _unconfiguredArrServices {
    final settings = ref.read(settingsProvider);
    return [
      for (final serviceType in _arrActivityServiceTypes)
        if (!settings.isServiceConfigured(_serviceKeyFor(serviceType)))
          _serviceKeyFor(serviceType),
    ];
  }
}

/// Resolves a [ServiceType] to the corresponding *arr service.
///
/// Discover uses Seerr rather than an *arr service, so it is not
/// supported by this provider.
///
/// **`watch`, not `read`, and the difference is a crash.** The three services
/// underneath are lens-aware: each is rebuilt by `watchApiClient` when the
/// connection it describes changes, and the outgoing `ApiClient` closes its
/// `Dio` on dispose. Read once and held, this provider kept handing out a
/// service whose transport had been shut — so a *write* from the Activity
/// control room (an auto-search, a queue removal) threw `StateError` on a
/// closed client, or, if the lens had moved before this ever rebuilt, went
/// quietly to the connection the user had just navigated away from.
///
/// Not a family key on the instance, which is the fix this looks like it should
/// need. The lens is already the identity of the service below; keying on it
/// here would be a second copy of that answer, and a second place to get it
/// wrong. `watch` says the same thing once.
///
/// Still the right provider for the surfaces that genuinely show **one**
/// connection — the per-service Activity screen, whose own title names the lens
/// it is reading. The aggregated feed reaches for [connectionArrServiceProvider]
/// instead, which is this provider for an empty id and a named connection
/// otherwise.
final resolvedArrServiceProvider =
    Provider.family<ArrActivityMixin, ServiceType>((ref, serviceType) {
      ref.watch(activityRefreshVersionProvider);

      assert(
        serviceType.supportsArrActivity,
        'resolvedArrServiceProvider only supports movies, series, and music.',
      );

      switch (serviceType) {
        case ServiceType.movies:
          return ref.watch(radarrServiceProvider);
        case ServiceType.series:
          return ref.watch(sonarrServiceProvider);
        case ServiceType.music:
          return ref.watch(lidarrServiceProvider);
        case ServiceType.discover:
          throw ArgumentError.value(
            serviceType,
            'serviceType',
            'ServiceType.discover does not have an *arr service',
          );
      }
    });

/// Folds per-connection results into one feed, merging duplicates.
///
/// A bucket can ask the same connection for two kinds (Wanted asks for missing
/// and cutoff), so results arrive keyed by connection more than once and have
/// to be combined before the health strip can report one row per connection.
///
/// Keyed on `(service, connection)` rather than on the service alone, which is
/// the whole of this pass in one map: folding two Sonarrs into one entry threw
/// away the answer the screen needs — which of them is down, and which of them
/// a row belongs to.
ActivityFeed _merge(List<ActivityServiceResult> results) {
  final byConnection = <(ServiceKey, String), ActivityServiceResult>{};
  // First-seen order, which for the loaders is the user's own instance order.
  final order = <(ServiceKey, String)>[];

  for (final result in results) {
    final key = (result.service, result.instanceId);
    final existing = byConnection[key];
    if (existing == null) {
      byConnection[key] = result;
      order.add(key);
      continue;
    }
    byConnection[key] = ActivityServiceResult(
      service: result.service,
      instanceId: result.instanceId,
      label: existing.label.isEmpty ? result.label : existing.label,
      items: [...existing.items, ...result.items],
      configured: existing.configured || result.configured,
      // Either half failing means the list for this connection is incomplete.
      error: existing.error ?? result.error,
    );
  }

  final ordered = <ActivityServiceResult>[
    for (final service in globalActivityServices)
      for (final key in order)
        if (key.$1 == service) byConnection[key]!,
  ];

  return ActivityFeed(
    items: _sortItems(
      ordered.expand((result) => result.items).toList(growable: false),
    ),
    results: ordered,
  );
}

/// Seerr's legs: one per configured connection, plus a placeholder when the
/// user has not set Seerr up at all.
///
/// The last service in this feed to be aggregated. With two Seerrs configured,
/// the second one's requests were simply not on the screen — /activity resolved
/// them through the lens from top to bottom, so the answer to "what is my stack
/// doing" silently excluded a whole server's worth of pending approvals.
///
/// Same failure discipline as the \*arr legs: one connection's error is caught
/// here and carried on that connection's own result, so a dead Seerr neither
/// blanks its sibling's list nor makes its sibling's empty list look like an
/// outage. That distinction only exists because `SeerrService.getRequests`
/// stopped turning an outage into `[]`.
List<Future<ActivityServiceResult>> _loadRequestResults(Ref ref) {
  final settings = ref.read(settingsProvider);
  if (!settings.isServiceConfigured(ServiceKey.seerr)) {
    return [
      Future.value(const ActivityServiceResult.unconfigured(ServiceKey.seerr)),
    ];
  }
  return [
    for (final connection in activitySeerrConnections(settings))
      _loadRequestConnection(ref, connection),
  ];
}

Future<ActivityServiceResult> _loadRequestConnection(
  Ref ref,
  ActivityConnection connection,
) async {
  try {
    final requests = await ref.read(
      requestsForProvider(connection.instanceId).future,
    );
    return ActivityServiceResult(
      service: ServiceKey.seerr,
      instanceId: connection.instanceId,
      label: connection.label,
      items: requests
          .map((request) => _requestItem(request, connection))
          .toList(growable: false),
      configured: true,
    );
  } catch (error) {
    return ActivityServiceResult(
      service: ServiceKey.seerr,
      instanceId: connection.instanceId,
      label: connection.label,
      items: const [],
      configured: true,
      error: error,
    );
  }
}

/// The three \*arr services that appear in the global feed, as service types.
const _arrActivityServiceTypes = [
  ServiceType.movies,
  ServiceType.series,
  ServiceType.music,
];

/// One future per configured connection, plus a placeholder for each \*arr the
/// user has not set up.
///
/// The failure of one connection is caught here and carried on that
/// connection's own result, never merged into its sibling's: an unreachable
/// second Sonarr must neither blank the first one's queue nor make the first
/// one's empty queue look like an outage.
List<Future<ActivityServiceResult>> _loadArrResults(
  Ref ref,
  GlobalActivityKind kind,
) {
  final settings = ref.read(settingsProvider);
  return [
    for (final serviceType in _arrActivityServiceTypes)
      if (!settings.isServiceConfigured(_serviceKeyFor(serviceType)))
        Future.value(
          ActivityServiceResult.unconfigured(_serviceKeyFor(serviceType)),
        ),
    for (final connection in activityArrConnections(settings))
      _loadArrConnection(ref, connection, kind),
  ];
}

Future<ActivityServiceResult> _loadArrConnection(
  Ref ref,
  ActivityConnection connection,
  GlobalActivityKind kind,
) async {
  try {
    final arrService = ref.read(
      connectionArrServiceProvider((
        connection.serviceType,
        connection.instanceId,
      )),
    );
    final items = await _loadRawItems(arrService, kind);
    return ActivityServiceResult(
      service: connection.service,
      instanceId: connection.instanceId,
      label: connection.label,
      items: items
          .whereType<Map>()
          .map((item) => _arrItem(kind, connection, stringKeyMap(item)))
          .toList(growable: false),
      configured: true,
    );
  } catch (error) {
    return ActivityServiceResult(
      service: connection.service,
      instanceId: connection.instanceId,
      label: connection.label,
      items: const [],
      configured: true,
      error: error,
    );
  }
}

Future<List<dynamic>> _loadRawItems(
  ArrActivityMixin service,
  GlobalActivityKind kind, {
  int page = 1,
  int pageSize = _globalActivityPageSize,
}) {
  return switch (kind) {
    GlobalActivityKind.queue => service.getQueue(),
    GlobalActivityKind.history => service.getHistory(
      page: page,
      pageSize: pageSize,
    ),
    GlobalActivityKind.blocklist => service.getBlocklist(),
    GlobalActivityKind.missing => service.getMissing(
      page: page,
      pageSize: pageSize,
    ),
    GlobalActivityKind.cutoff => service.getCutoff(
      page: page,
      pageSize: pageSize,
    ),
    GlobalActivityKind.request => Future.value(const <dynamic>[]),
  };
}

GlobalActivityItem _requestItem(
  SeerrRequest request,
  ActivityConnection connection,
) {
  final title = request.media?.title ?? 'Unknown request';
  final requester = request.requestedBy?.displayName;
  final type = request.type == 'tv' ? 'Series' : 'Movie';
  return GlobalActivityItem(
    kind: GlobalActivityKind.request,
    service: ServiceKey.seerr,
    serviceType: ServiceType.discover,
    instanceId: connection.instanceId,
    instanceLabel: connection.label,
    title: title,
    subtitle: [requester, type].whereType<String>().join(' · '),
    status: resolveRequestStatus(request),
    sortDate: DateTime.tryParse(request.createdAt),
    request: request,
  );
}

GlobalActivityItem _arrItem(
  GlobalActivityKind kind,
  ActivityConnection connection,
  Map<String, dynamic> item,
) {
  final serviceType = connection.serviceType;
  return GlobalActivityItem(
    kind: kind,
    service: connection.service,
    serviceType: serviceType,
    instanceId: connection.instanceId,
    instanceLabel: connection.label,
    title: _titleFor(kind, serviceType, item),
    subtitle: _subtitleFor(kind, serviceType, item),
    status: resolveActivityStatus(kind, item),
    sortDate: _sortDateFor(kind, item),
    raw: item,
  );
}

/// Orders a feed so trouble surfaces first.
///
/// The previous comparator sorted purely by date descending, which for the queue
/// meant `estimatedCompletionTime` descending: the download finishing soonest
/// went last, and anything stalled — no ETA at all — sorted dead last. The one
/// row the user opened the screen to find was at the bottom.
///
/// Three keys, in order:
///  1. severity: errors, then warnings, then everything calm;
///  2. liveness: an in-flight queue item outranks a request from last Tuesday;
///  3. time: soonest-first for the queue (an ETA counts down), newest-first for
///     everything else (history counts up). Undated rows go last.
///
/// Comparing dates only ever happens inside one liveness group, so the two
/// opposite directions never meet and the ordering stays a valid total order.
List<GlobalActivityItem> _sortItems(List<GlobalActivityItem> items) {
  int severity(GlobalActivityItem item) => switch (item.status.tone) {
    StatusTone.error => 0,
    StatusTone.warning => 1,
    _ => 2,
  };

  // Queue rows are live; everything else is a record of something settled.
  int liveness(GlobalActivityItem item) =>
      item.kind == GlobalActivityKind.queue ? 0 : 1;

  return [...items]..sort((a, b) {
    final bySeverity = severity(a).compareTo(severity(b));
    if (bySeverity != 0) return bySeverity;

    final byLiveness = liveness(a).compareTo(liveness(b));
    if (byLiveness != 0) return byLiveness;

    final left = a.sortDate;
    final right = b.sortDate;
    if (left == null && right == null) return 0;
    if (left == null) return 1;
    if (right == null) return -1;

    final chronological = left.compareTo(right);
    // Ascending for the queue: the nearest ETA is the most imminent.
    return liveness(a) == 0 ? chronological : -chronological;
  });
}

ServiceKey _serviceKeyFor(ServiceType serviceType) {
  return switch (serviceType) {
    ServiceType.discover => ServiceKey.seerr,
    ServiceType.movies => ServiceKey.radarr,
    ServiceType.series => ServiceKey.sonarr,
    ServiceType.music => ServiceKey.lidarr,
  };
}

String _titleFor(
  GlobalActivityKind kind,
  ServiceType serviceType,
  Map<String, dynamic> item,
) {
  return switch (kind) {
    GlobalActivityKind.queue =>
      arrPrimaryMediaTitle(item) ?? arrReleaseTitle(item) ?? 'Unknown release',
    GlobalActivityKind.history =>
      arrPrimaryMediaTitle(item) ?? arrReleaseTitle(item) ?? 'History item',
    GlobalActivityKind.blocklist =>
      arrPrimaryMediaTitle(item) ?? arrReleaseTitle(item) ?? 'Blocked release',
    GlobalActivityKind.missing ||
    GlobalActivityKind.cutoff => _wantedTitle(serviceType, item),
    GlobalActivityKind.request => 'Request',
  };
}

String _subtitleFor(
  GlobalActivityKind kind,
  ServiceType serviceType,
  Map<String, dynamic> item,
) {
  final title = _titleFor(kind, serviceType, item);

  return switch (kind) {
    GlobalActivityKind.queue =>
      activitySecondaryLine(
            serviceType,
            item,
            title: title,
            release: stringOrNull(item['title']),
          ) ??
          '',
    GlobalActivityKind.history =>
      activitySecondaryLine(
            serviceType,
            item,
            title: title,
            release: stringOrNull(item['sourceTitle']),
          ) ??
          '',
    GlobalActivityKind.blocklist =>
      activitySecondaryLine(
            serviceType,
            item,
            title: title,
            release: stringOrNull(item['sourceTitle']),
          ) ??
          '',
    GlobalActivityKind.missing || GlobalActivityKind.cutoff => [
      _serviceKeyFor(serviceType).title,
      _wantedContext(serviceType, item),
    ].whereType<String>().join(' · '),
    GlobalActivityKind.request => _serviceKeyFor(serviceType).title,
  };
}

DateTime? _sortDateFor(GlobalActivityKind kind, Map<String, dynamic> item) {
  return switch (kind) {
    GlobalActivityKind.queue => DateTime.tryParse(
      stringOrNull(item['estimatedCompletionTime']) ?? '',
    ),
    GlobalActivityKind.history || GlobalActivityKind.blocklist =>
      DateTime.tryParse(stringOrNull(item['date']) ?? ''),
    GlobalActivityKind.missing ||
    GlobalActivityKind.cutoff => DateTime.tryParse(
      stringOrNull(
            item['airDateUtc'] ?? item['releaseDate'] ?? item['added'],
          ) ??
          '',
    ),
    GlobalActivityKind.request => null,
  };
}

String _wantedTitle(ServiceType serviceType, Map<String, dynamic> item) {
  return switch (serviceType) {
    ServiceType.movies => stringOrNull(item['title']) ?? 'Missing movie',
    ServiceType.series =>
      stringOrNull(mapOrNull(item['series'])?['title']) ??
          stringOrNull(item['title']) ??
          'Missing episode',
    ServiceType.music =>
      stringOrNull(item['title']) ??
          stringOrNull(mapOrNull(item['album'])?['title']) ??
          'Missing album',
    ServiceType.discover => 'Request',
  };
}

String? _wantedContext(ServiceType serviceType, Map<String, dynamic> item) {
  return switch (serviceType) {
    ServiceType.movies => _yearLabel(item),
    ServiceType.series => _episodeLabel(item),
    ServiceType.music => stringOrNull(mapOrNull(item['artist'])?['artistName']),
    ServiceType.discover => null,
  };
}

String? _yearLabel(Map<String, dynamic> item) {
  final year = item['year'];
  if (year == null) return null;
  return year.toString();
}

String? _episodeLabel(Map<String, dynamic> item) {
  final season = intOrNull(item['seasonNumber']);
  final episode = intOrNull(item['episodeNumber']);
  if (season == null || episode == null) return stringOrNull(item['title']);
  return 'S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}';
}
