import 'package:cupola/features/discover/domain/models/seerr_genre.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
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
