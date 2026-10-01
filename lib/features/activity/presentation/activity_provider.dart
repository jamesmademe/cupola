import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/lifecycle/gated_poll.dart'; // ignore: implementation_imports
import 'package:flutter_riverpod/legacy.dart';

import 'package:cupola/core/api/base_arr_service.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/core/utils/episode_code.dart';
import 'package:cupola/features/activity/domain/global_activity_status.dart';
import 'package:cupola/features/activity/domain/service_type.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_formatters.dart'
    show activitySecondaryLine, formatActivityDuration, formatActivitySize;
import 'package:cupola/features/discover/data/seerr_service.dart'
    show SeerrRequestList;
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/services/domain/download_join.dart';
import 'package:cupola/features/services/domain/in_flight.dart'
    show arrQueueFault;
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/services/presentation/services_provider.dart'
    show ServiceQueueItem, ServicesQueue, downloadClientQueues;
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

  /// How many records this connection **has** of this kind, as the server
  /// reported it — or null when it did not say.
  ///
  /// Not `items.length`, and the gap between the two is the whole reason this
  /// field exists: the arr paged endpoints serve twenty rows by default, so a
  /// count taken from the list said twenty for every library with more than
  /// twenty gaps in it. Wrong in the one direction that matters, since it makes
  /// a large backlog look small and a full queue look idle.
  ///
  /// **Null means unanswered, never none.** A caller that gets null must print
  /// a figure it can defend — "20 shown" — or no figure at all; falling back to
  /// `items.length` reinstates the defect one layer up. The service tiles read
  /// this through [activityCount], and print `—` for null.
  final int? total;

  /// Non-null when the service was configured but did not answer.
  final Object? error;

  /// False when the user has not set this service up at all.
  final bool configured;

  /// Answered, but a page of it did not arrive, and nothing will fetch it
  /// until the next load: [items] is short of [total] with no Show more to
  /// close the gap.
  ///
  /// [total] still stands, because it is the server's own count. What this
  /// flag forbids is reading the rows as all of them. A queue walk that ran
  /// out of pages with the count still naming more is the same case.
  final bool incomplete;

  /// [total] is only how many rows arrived: the queue walk got a full page
  /// and no count to say whether another followed, so there are at least
  /// that many. A floor, drawn `200+`, never the total.
  final bool cutShort;

  const ActivityServiceResult({
    required this.service,
    required this.items,
    required this.configured,
    this.instanceId = '',
    this.label = '',
    this.total,
    this.error,
    this.incomplete = false,
    this.cutShort = false,
  });

  const ActivityServiceResult.unconfigured(this.service)
    : items = const [],
      total = null,
      error = null,
      configured = false,
      instanceId = '',
      label = '',
      incomplete = false,
      cutShort = false;

  /// This result with [items] in place of its own: the same connection, the
  /// same answer.
  ActivityServiceResult withItems(List<GlobalActivityItem> items) =>
      ActivityServiceResult(
        service: service,
        items: items,
        configured: configured,
        instanceId: instanceId,
        label: label,
        total: total,
        error: error,
        incomplete: incomplete,
        cutShort: cutShort,
      );

  /// How this result names itself: the service alone when it is the only
  /// connection, `Sonarr · Anime` or `Sonarr 2` when it is not.
  String get title => serviceWithConnection(service, label);

  /// The same name for inside a line whose clauses are already joined with
  /// ` · `: `Sonarr Anime`, never `Sonarr · Anime`, which would read as two
  /// clauses of the line it sits in.
  String get name => serviceWithConnection(service, label, joiner: ' ');

  /// Configured, asked, and answered.
  bool get reached => configured && error == null;

  /// Configured, asked, and failed — silent or refused; see [didNotAnswer].
  bool get failed => configured && error != null;

  /// Why it failed, classified. Null when it did not.
  ServiceFailureReason? get failureReason =>
      failed ? classifyConnectionFailure(error) : null;

  /// Failed because nothing answered — the red case. A connection that
  /// answered with a refusal or a fault failed too, and is amber.
  bool get didNotAnswer {
    final reason = failureReason;
    return reason != null && failureDidNotAnswer(reason);
  }
}

/// A whole feed load: the merged items plus what happened to each service.
class ActivityFeed {
  final List<GlobalActivityItem> items;
  final List<ActivityServiceResult> results;

  /// The download clients the queue's records were joined against, and which
  /// of them answered. [SourceCoverage.none] for a feed with no queue in it.
  ///
  /// Kept apart from [results] on purpose: a client that does not answer
  /// takes no row out of the list, which is what [results] counts, it only
  /// leaves its records with the arr's word for their state.
  final SourceCoverage clients;

  const ActivityFeed({
    required this.items,
    required this.results,
    this.clients = SourceCoverage.none,
  });

  const ActivityFeed.empty()
    : items = const [],
      results = const [],
      clients = SourceCoverage.none;

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

  /// The configured \*arr connections: the ones a queue, a history or a
  /// wanted list comes from.
  ///
  /// Seerr is left out because its rows are requests. A Seerr that did not
  /// answer makes the request list short, and leaves every queue figure
  /// exactly as true as it was.
  Iterable<ActivityServiceResult> get arrConnections =>
      configured.where((r) => r.service != ServiceKey.seerr);

  /// Every configured \*arr connection was asked and none of them answered,
  /// so nothing on this load can say how much is in the queue.
  bool get noArrAnswered =>
      arrConnections.isNotEmpty && arrConnections.every((r) => r.failed);

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

/// The clause that keeps a figure honest about what it leaves out:
/// `Sonarr Anime not counted`, `Radarr 4K and Lidarr not counted`.
///
/// The brand book's rule for a total across sources is that it covers only the
/// sources that answered and names the ones missing. Why each one is missing,
/// silence or a refusal, is the health strip's sentence and not this one's,
/// which is why these words are the same for both.
String notCountedClause(Iterable<ActivityServiceResult> missing) =>
    '${Lexicon.names(missing.map((r) => r.name))} not counted';

/// How many records some connections hold, **as their servers reported it**,
/// and which connections that figure leaves out.
class ActivityCount {
  const ActivityCount({
    required this.total,
    required this.notCounted,
    this.incomplete = false,
    this.cutShort = false,
  });

  /// The sum of the totals the answering connections reported, or null when
  /// none answered, or when one that answered did not say how many it has: a
  /// sum with an unknown term is unknown.
  final int? total;

  /// The connections that were asked and failed. [total] is short by
  /// whatever they hold.
  final List<ActivityServiceResult> notCounted;

  /// A connection that answered is missing a page of its rows: [total] is
  /// right, and the rows under it are not all of them.
  final bool incomplete;

  /// A connection that answered could only say how many rows reached us, not
  /// how many it has ([ActivityServiceResult.cutShort]), so its share of
  /// [total] is a floor. Nothing is missing to name: the mark says it alone.
  final bool cutShort;

  /// [total] is true of the connections that answered and short of the whole,
  /// or holds a share that is itself a floor: never to be printed as the
  /// total.
  bool get isFloor => total != null && (notCounted.isNotEmpty || cutShort);
}

/// How many records [service] has in a bucket across its connections, or
/// every service when [service] is null.
///
/// Summed from [ActivityServiceResult.total], never from `items.length`.
/// History and Wanted load fifty rows per connection and then page, so a count
/// of the loaded rows said "Sonarr 50" over a backlog of 2 369, and "100" after
/// one Show more: a number that moved while the data did not.
///
/// A connection that failed adds nothing to the sum and is listed in
/// [ActivityCount.notCounted], so a caller can say the figure is a floor and
/// name what it is missing. It used to be left out without a word, which made
/// one Sonarr's queue read as the queue of every Sonarr.
ActivityCount activityCount(
  Iterable<ActivityServiceResult> results, {
  ServiceKey? service,
}) {
  var total = 0;
  var any = false;
  var unknown = false;
  var incomplete = false;
  var cutShort = false;
  final notCounted = <ActivityServiceResult>[];
  for (final result in results) {
    if (service != null && result.service != service) continue;
    if (result.failed) {
      notCounted.add(result);
      continue;
    }
    if (!result.reached) continue;
    incomplete = incomplete || result.incomplete;
    cutShort = cutShort || result.cutShort;
    final count = result.total;
    if (count == null) {
      unknown = true;
      continue;
    }
    any = true;
    total += count;
  }
  return ActivityCount(
    total: any && !unknown ? total : null,
    notCounted: notCounted,
    incomplete: incomplete,
    cutShort: cutShort,
  );
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

  /// The figures, pre-formatted, for the desktop table's one right-aligned
  /// tabular cell.
  ///
  /// Separate from [subtitle] because they are not the same fact and the
  /// desktop row was printing the wrong one. `subtitle` is prose — the release
  /// name, the episode code, the artist — and the table was right-aligning it
  /// in tabular mono under a column the class doc called "the figures", so a
  /// 60-character release filename arrived ellipsised in a numeric column and
  /// the size and time left were nowhere on the row.
  ///
  /// Four columns were never an option: `GlobalActivityItem` has no
  /// size/speed/eta fields and \*arr reports no transfer rate on a queue record
  /// at all, so splitting this would be a data change with a comparator per
  /// column. One cell, joined with ` · `, is what the data honestly supports.
  /// Empty for the kinds that have no figures — a wanted row is a title and a
  /// date, not a measurement.
  final String figures;

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

  /// The download client's own row for this queue record, when a configured
  /// client is moving its bytes: matched on the record's `downloadId` by
  /// [joinDownloads], the join Home's In flight reads. Null for every other
  /// kind, and for a record no client answered for.
  final ServiceQueueItem? download;

  const GlobalActivityItem({
    required this.kind,
    required this.service,
    required this.serviceType,
    required this.title,
    required this.subtitle,
    required this.status,
    this.figures = '',
    this.instanceId = '',
    this.instanceLabel = '',
    this.sortDate,
    this.raw,
    this.request,
    this.download,
  });

  /// This record, joined to [client]: the client's row on it, and its status
  /// read through the client as Home reads it ([queueStatusWithClient]).
  GlobalActivityItem withDownload(ServiceQueueItem client) {
    final record = raw;
    return GlobalActivityItem(
      kind: kind,
      service: service,
      serviceType: serviceType,
      title: title,
      subtitle: subtitle,
      status: queueStatusWithClient(
        status,
        arrFault: record == null ? null : arrQueueFault(record),
        clientFault: client.fault,
        clientReason: client.warning,
        clientProgress: client.progress,
      ),
      figures: figures,
      instanceId: instanceId,
      instanceLabel: instanceLabel,
      sortDate: sortDate,
      raw: raw,
      request: request,
      download: client,
    );
  }

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
          // Named only when there is something to tell apart: a stack with one
          // Radarr must not grow a badge naming the only Radarr there is. The
          // name is the app's one rule for it, so a connection the user never
          // named reads `Radarr 2` here as everywhere, never its id.
          label: settings.connectionName(instance.id) ?? '',
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
  final clients = _readClients(ref);
  return _mergeJoined(
    await Future.wait([
      ..._loadRequestResults(ref),
      ..._loadArrResults(ref, GlobalActivityKind.queue),
      ..._loadArrResults(ref, GlobalActivityKind.history),
    ]),
    await clients,
  );
});

final globalQueueItemsProvider = FutureProvider<ActivityFeed>((ref) async {
  ref.watch(activityRefreshVersionProvider);
  ref.watch(activityQueuePollVersionProvider);
  final clients = _readClients(ref);
  return _mergeJoined(
    await Future.wait(_loadArrResults(ref, GlobalActivityKind.queue)),
    await clients,
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
  final clients = _readClients(ref);
  return _mergeJoined(
    await Future.wait([
      ..._loadRequestResults(ref),
      ..._loadArrResults(ref, GlobalActivityKind.queue),
    ]),
    await clients,
  );
});

/// The download clients' own queues, for the \*arr queue records to be
/// joined against, or null when no \*arr is set up and there is no record to
/// join. Read beside the \*arr queues, never after them, and asked fresh on
/// every load: the poll that re-reads the queues re-reads the clients.
Future<ServicesQueue?> _readClients(Ref ref) {
  if (activityArrConnections(ref.read(settingsProvider)).isEmpty) {
    return Future.value();
  }
  return downloadClientQueues(ref);
}

/// [_merge], with every \*arr queue record joined to its client's row.
///
/// The join is Home's ([joinDownloads], on the record's `downloadId`), so a
/// torrent qBittorrent calls stalled is a stall here as it is under In
/// flight, even while its arr still calls it downloading. A record whose
/// client did not answer keeps the arr's word for its state; which client did
/// not answer is in [ActivityFeed.clients].
ActivityFeed _mergeJoined(
  List<ActivityServiceResult> results,
  ServicesQueue? clients,
) {
  if (clients == null) return _merge(results);
  final join = joinDownloads<GlobalActivityItem, ServiceQueueItem>(
    arr: [
      for (final result in results)
        for (final item in result.items)
          if (item.kind == GlobalActivityKind.queue) item,
    ],
    clients: clients.items,
    arrDownloadId: (item) => stringOrNull(item.raw?['downloadId']),
    clientDownloadId: (row) => row.id,
  );
  final matched = Map<GlobalActivityItem, ServiceQueueItem>.identity();
  for (final (:arr, :client) in join.joined) {
    if (client != null) matched[arr] = client;
  }
  return _merge([
    for (final result in results)
      matched.isEmpty
          ? result
          : result.withItems([
              for (final item in result.items)
                if (matched[item] case final client?)
                  item.withDownload(client)
                else
                  item,
            ]),
  ], clients: clients.coverage);
}

/// Blocklist, complete: `getBlocklistPage` pages every record, so a one-shot
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

/// How many rows "Finished today" shows.
///
/// Six, and the cap is the point: the band is a glance at the day, not a second
/// history list. What it cannot show is reachable through the `Open history`
/// beside its heading, which is why the cap is allowed to be this low.
const finishedTodayLimit = 6;

/// What landed today: the rows the band draws, and how many there were.
class FinishedToday {
  const FinishedToday({
    required this.rows,
    required this.count,
    required this.complete,
  });

  static const none = FinishedToday(rows: [], count: 0, complete: true);

  /// Today's records, capped at [finishedTodayLimit].
  final List<GlobalActivityItem> rows;

  /// Every one of today's records among what arrived, before the cap. The
  /// heading's figure: "Finished today · 6 items" over six rows used to be the
  /// cap speaking, on a day with twenty.
  final int count;

  /// Whether [count] is the day. False when it is only a floor: a connection
  /// failed, or its first page was full of today and so cannot prove there
  /// were no more.
  final bool complete;
}

/// What landed today, with its true count beside the capped rows.
///
/// In the history feed's own order, which is faults first and then newest —
/// deliberately not re-sorted by time here, because a failed import is the row
/// worth surfacing and re-sorting would bury it under five successes.
///
/// A provider rather than a filter inside a widget because **two** surfaces
/// draw this — the Activity page and the desktop inspector pane — and a second
/// hand-rolled `date.year == now.year && …` is how two readouts of one day
/// start disagreeing at midnight. The pane's own copy had already drifted: it
/// compared the UTC date of each record with the local day.
///
/// Reading it starts the history feed's first page, which is why the page only
/// watches it on the Now section and the pane only when it is open: an
/// inspector nobody opened must not cost a round of history requests per
/// service.
final finishedTodayProvider = Provider<FinishedToday>((ref) {
  return finishedTodayOf(
    ref.watch(globalHistoryFeedProvider),
    now: DateTime.now(),
  );
});

/// The day [now] falls on, read off a history window.
///
/// "Finished today" comes from the history's first page of fifty, and a count
/// taken inside a page is the day only when the page proves it reaches past
/// the day, connection by connection. Either of two things proves it:
///
///  * the connection has nothing more to give — its total is in hand, or its
///    last page came back short; or
///  * one of its records is older than today. History is served newest first,
///    so every one of today's is above that one.
///
/// When neither holds, or a connection failed, the count is a **floor**, and
/// the heading says `12+` rather than a total it cannot stand behind. A record
/// with no readable date is dropped: it cannot be placed in the day, and it
/// proves nothing about where the page ends.
FinishedToday finishedTodayOf(
  PagedArrFeedState state, {
  required DateTime now,
}) {
  final feed = state.feed;
  if (feed == null) return FinishedToday.none;

  final local = now.toLocal();
  final startOfDay = DateTime(local.year, local.month, local.day);
  bool isToday(DateTime date) {
    final day = date.toLocal();
    return day.year == local.year &&
        day.month == local.month &&
        day.day == local.day;
  }

  final today = [
    for (final item in feed.items)
      if (item.sortDate case final date? when isToday(date)) item,
  ];

  var complete = true;
  for (final MapEntry(key: (_, serviceType, instanceId), value: cursor)
      in state.cursors.entries) {
    if (!cursor.configured) continue;
    if (cursor.failed) {
      complete = false;
      continue;
    }
    if (!cursor.hasMore) continue;
    final reachedBeforeToday = feed.items.any(
      (item) =>
          item.serviceType == serviceType &&
          item.instanceId == instanceId &&
          (item.sortDate?.toLocal().isBefore(startOfDay) ?? false),
    );
    if (!reachedBeforeToday) complete = false;
  }

  return FinishedToday(
    rows: today.take(finishedTodayLimit).toList(growable: false),
    count: today.length,
    complete: complete,
  );
}

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

/// What one "load more" round brought back for one pair.
///
/// Three numbers rather than the item list alone, because after the overlap
/// [PagedCursor.requestAt] introduces, the list's length answers none of the
/// questions the next cursor needs: [received] is how far the offset advanced
/// (records past the skip), and [pageWasFull] is whether the *server* filled the
/// window — the fallback signal for a server that sends no total.
typedef _PageDelta = ({
  List<GlobalActivityItem> items,
  int received,
  bool pageWasFull,
});

/// One (kind, connection) pair's progress through a paged bucket.
class PagedCursor {
  /// How many records of the set this pair has walked past — the **offset**,
  /// not the number of rows on screen.
  ///
  /// Counted in records the server sent rather than in items we managed to map,
  /// because this is the number the next request's position is derived from:
  /// the two differ only for a record shaped like nothing this app understands,
  /// and on that day the offset still has to be right or every later page lands
  /// somewhere else in the list.
  final int fetched;

  final bool lastPageFull;
  final bool configured;

  /// How many records exist across every page, as the server reported it, or
  /// null when it did not say. Carried from [ArrRecordPage.total].
  final int? total;

  final Object? error;

  const PagedCursor({
    required this.fetched,
    required this.lastPageFull,
    required this.configured,
    this.total,
    this.error,
  });

  /// Where the next request has to start, in the only terms the \*arr APIs
  /// accept: a 1-based page over a window of [pageSize], plus however many
  /// records of that window this pair already holds and must drop.
  ///
  /// Derived, and no longer a stored `nextPage` incremented once per load —
  /// that is correct only while every page is the same size, and these are not.
  /// The first page asks for 50 and every page after it asks for 200, so
  /// `page: 2, pageSize: 200` requested records 201-400 and **records 51-200
  /// were never asked for at all**: the list skipped 150 rows in silence. Once
  /// the envelope's total started deciding [hasMore] the same gap turned the
  /// footer into a control that could not be satisfied — `fetched` stalled
  /// short of `total` while every further page came back empty, so "load more"
  /// stayed lit and each press spent a request on nothing.
  ///
  /// The cost of doing it this way is one overlap, once: the first wide page
  /// re-downloads the 50 records the narrow page already brought. Cheaper than
  /// a second page size, and far cheaper than a hole in the list.
  ({int page, int skip}) requestAt(int pageSize) =>
      (page: fetched ~/ pageSize + 1, skip: fetched % pageSize);

  /// Whether another page might exist.
  ///
  /// [total] answers this outright when the server sent one: the list is
  /// exhausted once we hold as many rows as it says there are, so the extra
  /// empty round-trip a list ending exactly on a page boundary used to cost is
  /// gone, and so is the footer spinner that came with it.
  ///
  /// The heuristic survives underneath for the servers that send no total — an
  /// older build, a proxy that rewrote the body. There "full last page" is the
  /// only signal there is: a page that came back short was the last one.
  bool get hasMore => total != null ? fetched < total! : lastPageFull;

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
/// pages its History and Wanted tables. The blocklist is not paged here: it is
/// small, and `globalBlocklistItemsProvider` reads it whole in one walk.
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
    final fetched = <ActivityPageKey, _PageDelta>{};
    final failed = <ActivityPageKey>{};
    await Future.wait([
      for (final pair in pairs) _loadNextPage(pair, fetched, failed),
    ]);

    if (generation != _generation) return;

    for (final entry in fetched.entries) {
      _items.putIfAbsent(entry.key, () => []).addAll(entry.value.items);
    }

    final cursors = <ActivityPageKey, PagedCursor>{};
    for (final entry in current.cursors.entries) {
      final pair = entry.key;
      final cursor = entry.value;
      final extra = fetched[pair];
      final didFail = failed.contains(pair);
      cursors[pair] = PagedCursor(
        fetched: cursor.fetched + (extra?.received ?? 0),
        // A page that never arrived says nothing about whether one exists, so
        // the pair keeps the answer it already had and stays retryable. Derived
        // from the missing page instead, `lastPageFull` came out false, `hasMore`
        // went false with it, and one unreachable connection ended its own half
        // of the list for good — looking, on screen, exactly like a list that
        // had run out.
        lastPageFull: didFail
            ? cursor.lastPageFull
            : (extra?.pageWasFull ?? false),
        // The size of the set does not change because we fetched another window
        // of it, and a page that never arrived cannot revise it either.
        total: cursor.total,
        configured: cursor.configured,
        error: cursor.error,
      );
    }

    // Reported, so the footer offers the retry it already knows how to draw.
    // Nothing ever set this, which left `_LoadMoreFooter`'s failure branch
    // unreachable code.
    state = PagedArrFeedState(
      feed: _buildFeed(cursors),
      cursors: cursors,
      loadMoreFailed: failed.isNotEmpty,
    );
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
      final page = await _loadPage(
        arrService,
        kind,
        page: 1,
        pageSize: _pagedInitialPageSize,
      );
      final mapped = page.records
          .whereType<Map>()
          .map((item) => _arrItem(kind, connection, stringKeyMap(item)))
          .toList(growable: false);
      loaded[pair] = mapped;
      cursors[pair] = PagedCursor(
        // The records, not the mapped items: this is an offset into the set.
        fetched: page.records.length,
        lastPageFull: page.records.length == _pagedInitialPageSize,
        total: page.total,
        configured: true,
      );
    } catch (error) {
      cursors[pair] = PagedCursor(
        fetched: 0,
        lastPageFull: false,
        configured: true,
        error: error,
      );
    }
  }

  Future<void> _loadNextPage(
    ActivityPageKey pair,
    Map<ActivityPageKey, _PageDelta> fetched,
    Set<ActivityPageKey> failed,
  ) async {
    final (kind, serviceType, instanceId) = pair;
    final cursor = state.cursors[pair];
    final connection = _connections[pair];
    if (cursor == null || !cursor.hasMore || connection == null) return;

    try {
      final arrService = ref.read(
        connectionArrServiceProvider((serviceType, instanceId)),
      );
      final request = cursor.requestAt(_pagedMorePageSize);
      final page = await _loadPage(
        arrService,
        kind,
        page: request.page,
        pageSize: _pagedMorePageSize,
      );
      // The leading slice is the overlap [PagedCursor.requestAt] documents —
      // records this pair already shows. Appending it would print each of them
      // twice, which is the one way this fix could be worse than the gap it
      // closes.
      final fresh = page.records.skip(request.skip).toList(growable: false);
      fetched[pair] = (
        items: fresh
            .whereType<Map>()
            .map((item) => _arrItem(kind, connection, stringKeyMap(item)))
            .toList(growable: false),
        received: fresh.length,
        // The window the *server* filled, not the part of it that was new —
        // measured after the skip, a full page would read short and end the
        // list one page early on every server that sends no total.
        pageWasFull: page.records.length == _pagedMorePageSize,
      );
    } catch (_) {
      // Recorded so [loadMore] can leave this pair's `hasMore` alone and light
      // the footer's retry. Swallowed silently, the pair looked exhausted.
      failed.add(pair);
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
          total: entry.value.total,
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
ActivityFeed _merge(
  List<ActivityServiceResult> results, {
  SourceCoverage clients = SourceCoverage.none,
}) {
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
    final existingTotal = existing.total;
    final resultTotal = result.total;
    byConnection[key] = ActivityServiceResult(
      service: result.service,
      instanceId: result.instanceId,
      label: existing.label.isEmpty ? result.label : existing.label,
      items: [...existing.items, ...result.items],
      // The two halves' sizes add up — Wanted asks one connection for missing
      // and for cutoff unmet, which are disjoint sets. Dropped here, every
      // merged connection came out "unanswered", and a half that did not say
      // leaves the sum unsaid too rather than shrinking it to the other half.
      total: existingTotal == null || resultTotal == null
          ? null
          : existingTotal + resultTotal,
      configured: existing.configured || result.configured,
      // Either half failing means the list for this connection is incomplete.
      error: existing.error ?? result.error,
      incomplete: existing.incomplete || result.incomplete,
      cutShort: existing.cutShort || result.cutShort,
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
    clients: clients,
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
    // Seerr's own count, from `pageInfo.results`, and never the length of
    // what arrived. `getRequests` absorbs a later page that fails, so the
    // length used to be short by that page's rows while reading as the whole
    // history. A list that carries no count from Seerr has told us nothing
    // about the total, and says so.
    final (total, incomplete) = switch (requests) {
      SeerrRequestList(:final total, :final isPartial) => (total, isPartial),
      _ => (null, false),
    };
    return ActivityServiceResult(
      service: ServiceKey.seerr,
      instanceId: connection.instanceId,
      label: connection.label,
      items: requests
          .map((request) => _requestItem(request, connection))
          .toList(growable: false),
      total: total,
      incomplete: incomplete,
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
    final page = await _loadPage(arrService, kind);
    // A walk cut short with the count in hand keeps the count and says the
    // rows are not all of it; one cut short without a count has only its rows
    // to go on, and they are a floor.
    final floor = page.cutShort && page.total == null;
    return ActivityServiceResult(
      service: connection.service,
      instanceId: connection.instanceId,
      label: connection.label,
      items: page.records
          .whereType<Map>()
          .map((item) => _arrItem(kind, connection, stringKeyMap(item)))
          .toList(growable: false),
      total: floor ? page.records.length : page.total,
      incomplete: page.cutShort && !floor,
      cutShort: floor,
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

/// One page of a bucket, **with however many records the server says exist**.
///
/// It used to return the bare record list, which is why every figure this feed
/// produced answered the wrong question. `wanted/missing` serves twenty rows by
/// default, so a library with 340 gaps reported "20 missing" — not an
/// approximation, a different question ("how many did we fetch") that happened
/// to look like an answer to the one the user asked. The paged primitives carry
/// the envelope's `totalRecords`, so the count and the rows now come from the
/// same response.
///
/// The queue and the blocklist are walks rather than pages: [getQueuePage]
/// and [getBlocklistPage] fetch every page the envelope's total names, and say
/// when they could not. They used to hand back the bare rows, and this counted
/// them — so the two ends where a walk proves nothing were stated as totals: a
/// server that sends no `totalRecords` stops the walk after one full page of
/// 200, and the walk gives up after fifty pages. Every other total may still
/// be null — a server that did not send `totalRecords` has told us nothing,
/// and `records.length` would be the old lie with a fresh coat on it.
Future<ArrRecordPage> _loadPage(
  ArrActivityMixin service,
  GlobalActivityKind kind, {
  int page = 1,
  int pageSize = _globalActivityPageSize,
}) async {
  switch (kind) {
    case GlobalActivityKind.queue:
      return service.getQueuePage();
    case GlobalActivityKind.blocklist:
      return service.getBlocklistPage();
    // The page variants, not the record-only ones — and on Radarr and Sonarr
    // that is now also what attaches `includeMovie` / `includeSeries` +
    // `includeEpisode`, since both services hang those off this primitive.
    case GlobalActivityKind.history:
      return service.getHistoryPage(page: page, pageSize: pageSize);
    case GlobalActivityKind.missing:
      return service.getMissingPage(page: page, pageSize: pageSize);
    case GlobalActivityKind.cutoff:
      return service.getCutoffPage(page: page, pageSize: pageSize);
    // Seerr answers this kind on its own leg; nothing here asked a server. The
    // total is therefore **unknown**, not zero — a confident "0 requests" from
    // a question that was never put is exactly the failure this type exists to
    // stop.
    case GlobalActivityKind.request:
      return const ArrRecordPage(records: [], total: null);
  }
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
    figures: _figuresFor(kind, item),
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

/// The measurements on a record, pre-formatted and joined.
///
/// Built here, once, rather than in the row: the desktop table wants them
/// tabular and right-aligned, and a widget that parses English back out of a
/// prose line to find a number is wrong the first time a service words it
/// differently. Only the two kinds that carry a measurement produce anything —
/// the rest return empty and the column collapses to whitespace rather than to
/// an em dash per row, which would draw a ladder of nothing down the page.
///
/// No speed. \*arr's queue record reports `size`, `sizeleft` and `timeleft`
/// and no rate at all: the rate belongs to the download client, which is a
/// different connection. Printing one would mean deriving it from two polls
/// 15 s apart and calling the result a measurement.
String _figuresFor(GlobalActivityKind kind, Map<String, dynamic> item) {
  switch (kind) {
    case GlobalActivityKind.queue:
      final size = formatActivitySize(item['size']);
      final left = formatActivityDuration(stringOrNull(item['timeleft']));
      return [
        if (size != '—') size,
        if (left != '—' && left.isNotEmpty) '$left left',
      ].join(' · ');
    case GlobalActivityKind.history:
      // \*arr files the imported file's size under `data`, not at the top
      // level where the queue keeps it.
      final size = formatActivitySize(mapOrNull(item['data'])?['size']);
      return size == '—' ? '' : size;
    case GlobalActivityKind.blocklist:
    case GlobalActivityKind.missing:
    case GlobalActivityKind.cutoff:
    case GlobalActivityKind.request:
      return '';
  }
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
  return formatArrEpisodeCode(season, episode) ?? stringOrNull(item['title']);
}
