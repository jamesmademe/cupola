import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/domain/models/seerr_admin_models.dart';
import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/services/domain/request_ordering.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cupola/core/providers/provider_retry.dart';

/// The request history of the Seerr the lens is on, **as Seerr's rows carry
/// it**: no title, no artwork, no score.
///
/// The source of every list of requests, and what a figure is counted from: the
/// KPI strip, how many wait for a decision. Those need each request's state
/// and nothing of its title, and used to wait for a title page to be read for
/// every row first. A surface that draws rows reads [requestsProvider], which
/// is these rows with their titles; one that draws a few hands those to
/// `SeerrService.hydrate`.
///
/// **The one to drop** for a read again, through [invalidateSeerrRequests]:
/// [requestsProvider] derives from it and cannot re-read the pages by itself
/// (`requests_invalidation_guard_test.dart`).
final requestRowsProvider = FutureProvider<List<SeerrRequest>>((ref) async {
  return ref.watch(seerrServiceProvider).getRequestRows();
}, retry: noProviderRetry);

/// The request history of the Seerr the lens is on, every row with its title.
///
/// Still the right provider for every surface that shows **one** Seerr's rows:
/// Discover, the services dashboard, and the one the whole suite overrides to
/// supply a fake. /activity, which merges every configured connection, reaches
/// for [requestsForProvider] instead.
///
/// Derived from [requestRowsProvider]: the pages are read once, whoever asks
/// first, and this adds the title reads. Never invalidated on its own, since
/// that would read the titles again over the rows it already has.
final requestsProvider = FutureProvider<List<SeerrRequest>>((ref) async {
  final rows = await ref.watch(requestRowsProvider.future);
  return ref.watch(seerrServiceProvider).hydrate(rows);
}, retry: noProviderRetry);

final seerrIssuesProvider = FutureProvider.autoDispose
    .family<SeerrAdminResult<SeerrIssue>, SeerrIssueFilter>((
      ref,
      filter,
    ) async {
      return ref.watch(seerrServiceProvider).getIssuesResult(filter: filter);
    }, retry: noProviderRetry);

final seerrUsersProvider =
    FutureProvider.autoDispose<SeerrAdminResult<SeerrUser>>((ref) async {
      return ref.watch(seerrServiceProvider).getUsersResult();
    }, retry: noProviderRetry);

/// The rows of **one named connection's** request history, without titles
/// (see [requestRowsProvider]). Whatever the lens is on.
///
/// A Seerr request id is per instance: two servers both number from one, so a
/// list merged across them cannot be acted on by id alone, and the row that
/// carries the id has to carry the connection with it.
///
/// The lens's own id collapses back onto [requestRowsProvider] rather than
/// fetching the same server twice, and, as with the service families, that
/// collapse is what keeps an override of the plain provider from being bypassed
/// by the path that names a connection. `read` of the lens for the reason
/// `seerrServiceForProvider` documents at length: watching it would re-fetch
/// every entry of this family every time the user moved the lens.
final requestRowsForProvider =
    FutureProvider.family<List<SeerrRequest>, String>((ref, instanceId) async {
      final lens = ref.read(activeInstanceProvider(ServiceKey.seerr))?.id ?? '';
      if (instanceId.isEmpty || instanceId == lens) {
        return ref.watch(requestRowsProvider.future);
      }
      return ref.watch(seerrServiceForProvider(instanceId)).getRequestRows();
    }, retry: noProviderRetry);

/// The request history of **one named connection**, every row with its title,
/// whatever the lens is on. Derived from [requestRowsForProvider], and dropped
/// through [invalidateSeerrRequests] only, for the reason [requestsProvider]
/// gives.
final requestsForProvider = FutureProvider.family<List<SeerrRequest>, String>((
  ref,
  instanceId,
) async {
  final lens = ref.read(activeInstanceProvider(ServiceKey.seerr))?.id ?? '';
  if (instanceId.isEmpty || instanceId == lens) {
    return ref.watch(requestsProvider.future);
  }
  final rows = await ref.watch(requestRowsForProvider(instanceId).future);
  return ref.watch(seerrServiceForProvider(instanceId)).hydrate(rows);
}, retry: noProviderRetry);

/// The requests of one named connection still in motion: waiting for
/// approval, being processed, or failed ([SeerrService.getActiveRequests]).
/// What Activity's Now reads, where it used to read [requestsForProvider],
/// every request the server ever held. Empty id means the lens.
final activeRequestsForProvider =
    FutureProvider.family<List<SeerrRequest>, String>((ref, instanceId) {
      return ref.watch(seerrServiceForProvider(instanceId)).getActiveRequests();
    }, retry: noProviderRetry);

/// The requests of one named connection waiting for a decision, one page
/// with Seerr's count of them ([SeerrService.getPendingRequests]). What the
/// Home's Requests module reads. Empty id means the lens.
final pendingRequestsForProvider =
    FutureProvider.family<List<SeerrRequest>, String>((ref, instanceId) {
      return ref
          .watch(seerrServiceForProvider(instanceId))
          .getPendingRequests();
    }, retry: noProviderRetry);

/// Reads every list that shows Seerr's requests again: the lens's history,
/// every connection's, the ones in motion and the ones waiting for a decision.
///
/// **The only way to drop them** (with [invalidateSeerrRequestsOf]):
/// `requests_invalidation_guard_test.dart` fails a direct drop of
/// [requestsProvider] or [requestsForProvider]. The lists with titles derive
/// from the rows, so dropping them alone re-reads the titles over rows as old
/// as before, and reads no page.
///
/// Through the [container] rather than a ref, so a write that outlasts the page
/// that made it can still say what it changed. Dropping the family is dropping
/// every connection's entry, and the lens's own id collapses onto the plain
/// provider: dropping one and not the other leaves a stale copy behind.
void invalidateSeerrRequests(ProviderContainer container) {
  container
    ..invalidate(requestRowsProvider)
    ..invalidate(requestRowsForProvider)
    ..invalidate(activeRequestsForProvider)
    ..invalidate(pendingRequestsForProvider);
}

/// [invalidateSeerrRequests] for the history of one connection alone, the lens
/// when [instanceId] is empty: the lists in motion and waiting for a decision
/// stay as they are. A connection that is the lens is dropped as both.
void invalidateSeerrRequestsOf(ProviderContainer container, String instanceId) {
  final lens = container.read(activeInstanceProvider(ServiceKey.seerr))?.id;
  if (instanceId.isEmpty || instanceId == lens) {
    container.invalidate(requestRowsProvider);
  }
  if (instanceId.isNotEmpty) {
    container.invalidate(requestRowsForProvider(instanceId));
  }
}

/// How many waiting requests the Seerr home lists before deferring to the full
/// list.
///
/// Its own constant rather than a reuse of the /services hub's budget: that
/// number governs the hub, where the Requests region sorts pending first
/// *without filtering it out of the rest*. A later change to the hub's budget
/// must not silently re-cut the decisions list on this page.
const int seerrDecisionsPreviewLimit = 5;

/// The requests waiting on a human, and how many there are in all.
///
/// [total] is counted before [preview] is cut, so a header built from it tells
/// the truth when there are more decisions than the section has room for.
/// [isFloor] says it is only true of the rows that arrived: drawn `3+`.
typedef SeerrDecisions = ({
  List<SeerrRequest> preview,
  int total,
  bool isFloor,
});

/// Whether [requests] holds every request its Seerr has, so a count filtered
/// out of it is a total rather than a floor.
///
/// Seerr has no count of the waiting requests to hand, only of all of them, so
/// a waiting figure is counted over the rows. Rows that are not all of them
/// make it a floor: a page that did not arrive ([SeerrRequestList.isPartial]),
/// rows short of Seerr's own count (a request in a shape this app cannot read
/// is still a request, and may be one waiting on a person), or no count at
/// all, which leaves the first page as everything that was read. A list that
/// is not a [SeerrRequestList] was built whole by whoever made it and claims
/// nothing about pages.
bool holdsEveryRequest(List<SeerrRequest> requests) => switch (requests) {
  SeerrRequestList(:final total?, :final isPartial) =>
    !isPartial && requests.length >= total,
  SeerrRequestList() => false,
  _ => true,
};

/// The Seerr home's first region: what is waiting on a decision.
///
/// Derived from [requestsProvider] rather than fetched again: one request list
/// per Seerr per refresh, and the KPI readout, the hub region and this section
/// all read the same one.
///
/// The filter goes through `isAwaitingApproval`, which reads the request's OWN
/// status and never `displayStatus`. That is the whole trap on this service:
/// `displayStatus` lets the media's availability override the request, so a
/// request that is still `pendingApproval` for a title Radarr already holds
/// reports as "Available". A decisions list keyed off it would silently drop
/// exactly the approvals that matter most, and no amount of testing against a
/// freshly made request would ever surface it.
///
/// `noProviderRetry` for the same reason [requestsProvider] carries it, one step
/// further down: the source has already settled on its first failure, so the ten
/// backed-off re-runs Riverpod would otherwise do here cannot reach the server
/// again, they only hold this section in its loading state for the best part of
/// a minute before showing the same error. The retry that matters is the one on
/// the card the section draws, which the user presses.
final seerrDecisionsProvider = FutureProvider<SeerrDecisions>((ref) async {
  final requests = await ref.watch(requestsProvider.future);
  final waiting = requests.where(isAwaitingApproval).toList(growable: false);
  return (
    // The set is already filtered to pending, so this sort is doing its second
    // job only: newest first inside the group.
    preview: sortRequestsPendingFirst(
      waiting,
      limit: seerrDecisionsPreviewLimit,
    ),
    // Counted over the rows, so only as whole as they are. A lost page used
    // to come out as a smaller, confident "3 waiting".
    total: waiting.length,
    isFloor: !holdsEveryRequest(requests),
  );
}, retry: noProviderRetry);

// The trending titles Seerr's room shows on its Overview. Fails when Seerr did
// not answer or answered with a failure (`SeerrService._discover` no longer
// turns that into `[]`); `noProviderRetry`, because a backoff would hold the
// section on its skeleton for the better part of a minute. The Discover tab
// reads its own (`catalog_providers.dart`).
final discoverTrendingProvider = FutureProvider<List<MediaPreview>>((
  ref,
) async {
  final service = ref.watch(seerrServiceProvider);
  return service.getDiscoverTrending(page: 1);
}, retry: noProviderRetry);
