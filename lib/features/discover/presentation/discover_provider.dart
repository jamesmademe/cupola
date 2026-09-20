import 'package:cupola/features/discover/domain/models/seerr_genre.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/domain/models/seerr_admin_models.dart';
import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/services/domain/request_ordering.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cupola/core/providers/provider_retry.dart';

/// Sort key for the "Top Rated" rows.
const kTopRatedSort = 'vote_average.desc';

/// Identifies a per-genre discover row.
typedef GenreRowKey = ({String mediaType, int genreId});

/// The request history of the Seerr the lens is on.
///
/// Still the right provider for every surface that shows **one** Seerr —
/// Discover, the services dashboard, the KPI strip — and the one the whole
/// suite overrides to supply a fake. /activity, which merges every configured
/// connection, reaches for [requestsForProvider] instead.
final requestsProvider = FutureProvider<List<SeerrRequest>>((ref) async {
  final service = ref.watch(seerrServiceProvider);
  return service.getRequests();
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

/// The request history of **one named connection**, whatever the lens is on.
///
/// A Seerr request id is per instance: two servers both number from one, so a
/// list merged across them cannot be acted on by id alone, and the row that
/// carries the id has to carry the connection with it.
///
/// The lens's own id collapses back onto [requestsProvider] rather than
/// fetching the same server twice — and, as with the service families, that
/// collapse is what keeps an override of the plain provider from being bypassed
/// by the path that names a connection. `read` of the lens for the reason
/// `seerrServiceForProvider` documents at length: watching it would re-fetch
/// every entry of this family every time the user moved the lens.
final requestsForProvider = FutureProvider.family<List<SeerrRequest>, String>((
  ref,
  instanceId,
) async {
  final lens = ref.read(activeInstanceProvider(ServiceKey.seerr))?.id ?? '';
  if (instanceId.isEmpty || instanceId == lens) {
    return ref.watch(requestsProvider.future);
  }
  return ref.watch(seerrServiceForProvider(instanceId)).getRequests();
}, retry: noProviderRetry);

/// How many waiting requests the Seerr home lists before deferring to the full
/// list.
///
/// Its own constant rather than a reuse of `servicesRequestsPreviewLimit`: that
/// number governs the /services hub, where the Requests region sorts pending
/// first *without filtering it out of the rest*. A later change to the hub's
/// budget must not silently re-cut the decisions list on this page.
const int seerrDecisionsPreviewLimit = 5;

/// The requests waiting on a human, and how many there are in all.
///
/// [total] is counted before [preview] is cut, so a header built from it tells
/// the truth when there are more decisions than the section has room for.
typedef SeerrDecisions = ({List<SeerrRequest> preview, int total});

/// The Seerr home's first region: what is waiting on a decision.
///
/// Derived from [requestsProvider] rather than fetched again — one request list
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
/// again — they only hold this section in its loading state for the best part of
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
    total: waiting.length,
  );
}, retry: noProviderRetry);

// Basic providers for the main Discover screen (Carousels) - fetching page 1
final discoverMoviesProvider = FutureProvider<List<MediaPreview>>((ref) async {
  final service = ref.watch(seerrServiceProvider);
  return service.getDiscoverMovies(page: 1);
});

final discoverTVProvider = FutureProvider<List<MediaPreview>>((ref) async {
  final service = ref.watch(seerrServiceProvider);
  return service.getDiscoverTV(page: 1);
});

final discoverTrendingProvider = FutureProvider<List<MediaPreview>>((
  ref,
) async {
  final service = ref.watch(seerrServiceProvider);
  return service.getDiscoverTrending(page: 1);
});

// Upcoming + top-rated carousels (page 1)
final discoverUpcomingMoviesProvider = FutureProvider<List<MediaPreview>>((
  ref,
) async {
  final service = ref.watch(seerrServiceProvider);
  return service.getDiscoverUpcomingMovies(page: 1);
});

final discoverUpcomingTvProvider = FutureProvider<List<MediaPreview>>((
  ref,
) async {
  final service = ref.watch(seerrServiceProvider);
  return service.getDiscoverUpcomingTv(page: 1);
});

final discoverTopRatedMoviesProvider = FutureProvider<List<MediaPreview>>((
  ref,
) async {
  final service = ref.watch(seerrServiceProvider);
  return service.getDiscoverMovies(page: 1, sortBy: kTopRatedSort);
});

// Genre list + per-genre carousels
final movieGenresProvider = FutureProvider<List<SeerrGenre>>((ref) async {
  final service = ref.watch(seerrServiceProvider);
  return service.getMovieGenres();
});

final discoverByGenreProvider =
    FutureProvider.family<List<MediaPreview>, GenreRowKey>((ref, key) async {
      final service = ref.watch(seerrServiceProvider);
      if (key.mediaType == 'tv') {
        return service.getDiscoverTV(page: 1, genre: key.genreId);
      }
      return service.getDiscoverMovies(page: 1, genre: key.genreId);
    });

// Paginated per-genre + top-rated providers for "See All" screens
final discoverByGenrePageProvider =
    FutureProvider.family<List<MediaPreview>, ({GenreRowKey key, int page})>((
      ref,
      args,
    ) async {
      final service = ref.watch(seerrServiceProvider);
      if (args.key.mediaType == 'tv') {
        return service.getDiscoverTV(page: args.page, genre: args.key.genreId);
      }
      return service.getDiscoverMovies(
        page: args.page,
        genre: args.key.genreId,
      );
    });

// Family providers for pagination in "See All" screens
final discoverMoviesPageProvider =
    FutureProvider.family<List<MediaPreview>, int>((ref, page) async {
      final service = ref.watch(seerrServiceProvider);
      return service.getDiscoverMovies(page: page);
    });

final discoverTVPageProvider = FutureProvider.family<List<MediaPreview>, int>((
  ref,
  page,
) async {
  final service = ref.watch(seerrServiceProvider);
  return service.getDiscoverTV(page: page);
});

final discoverTrendingPageProvider =
    FutureProvider.family<List<MediaPreview>, int>((ref, page) async {
      final service = ref.watch(seerrServiceProvider);
      return service.getDiscoverTrending(page: page);
    });
