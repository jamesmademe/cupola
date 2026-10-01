import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/api/base_arr_service.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

final radarrServiceProvider = Provider<RadarrService>((ref) {
  return RadarrService(watchApiClient(ref, ServiceKey.radarr));
});

/// Radarr bound to one named connection, whatever the lens is pointing at.
///
/// For the work that belongs to a *connection* rather than to a screen: a
/// release search runs on the server it was started against, and the lens can
/// move while it is queued. Empty id means the lens, which is what the plain
/// [radarrServiceProvider] answers; an id naming nothing throws "not configured"
/// rather than quietly answering about some other server.
///
/// Not `autoDispose`: a caller reads this, awaits a request on it, and a
/// disposal scheduled at the end of the read would close the `Dio` under the
/// request. One live client per configured connection is the same bound the
/// per-service providers already carry.
final radarrServiceForProvider = Provider.family<RadarrService, String>((
  ref,
  instanceId,
) {
  // The lens's own connection resolves to [radarrServiceProvider] rather than to
  // a second client for the same server. Without this the app kept two live
  // `Dio`s pointed at one address whenever anything asked by id — and any
  // override of the plain provider, which is how every test supplies a fake,
  // was quietly bypassed on the path that names a connection.
  //
  // `read`, deliberately, and this is the load-bearing part. Watching the lens
  // would rebuild EVERY entry of this family whenever the lens moved — entries
  // for connections that did not change — and `watchApiClient` closes the
  // outgoing client on dispose. A release search running against the seedbox
  // would have its `Dio` shut under it because the user tapped a badge on
  // another screen. The cost of reading is that an entry minted before the lens
  // landed on its id keeps a client of its own until it is disposed: one extra
  // connection, rather than a request that fails.
  final lens = ref.read(activeInstanceProvider(ServiceKey.radarr))?.id ?? '';
  if (instanceId.isEmpty || instanceId == lens) {
    return ref.watch(radarrServiceProvider);
  }
  return RadarrService(
    watchApiClient(ref, ServiceKey.radarr, instanceId: instanceId),
  );
});

/// Service for interacting with Radarr API.
///
/// Provides movie-specific operations plus shared activity operations
/// via [ArrActivityMixin].
class RadarrService with ArrActivityMixin {
  @override
  final ApiClient client;

  @override
  final ArrServiceConfig config = ArrServiceConfig.radarr;

  RadarrService(this.client);

  /// On the queue's **page** primitive, which `getQueue` delegates to, so the
  /// figure and the rows come off one request that carries the movie.
  @override
  Future<ArrRecordPage> getQueuePage({Map<String, dynamic>? queryParameters}) {
    return super.getQueuePage(
      queryParameters: {'includeMovie': true, ...?queryParameters},
    );
  }

  /// Fetches all movies from Radarr, answering `[]` when it cannot be read.
  ///
  /// The degrading read, for joins that can go on without the library
  /// ([getMovieByTmdbId]). The wall and every *figure* use [getMoviesOrThrow] —
  /// see the note there, and on `fetchAllItems`, for why the two differ.
  Future<List<RadarrMovie>> getMovies() async {
    return fetchAllItems('movie', RadarrMovie.fromJson);
  }

  /// The same library, with a failed fetch allowed to reach the caller.
  ///
  /// See [fetchAllItemsOrThrow]. A Radarr that is unreachable, mis-keyed or
  /// 500-ing resolves [getMovies] *successfully* with an empty list, and the
  /// KPI rail printed `Movies 0 · Monitored 0 · Missing 0` off it — three
  /// fabrications on the first screen the app opens, each contradicting the
  /// identity band above them.
  Future<List<RadarrMovie>> getMoviesOrThrow() async {
    return fetchAllItemsOrThrow('movie', RadarrMovie.fromJson);
  }

  /// Fetches a single movie by its Radarr ID.
  Future<RadarrMovie?> getMovie(int movieId) async {
    return fetchItem('movie', movieId, RadarrMovie.fromJson);
  }

  /// On the **page** primitive, not on `getHistory`.
  ///
  /// `getHistory` delegates to this, so both spellings pick the parameter up —
  /// but only this way round. Hung off `getHistory` instead, as it was, a caller
  /// that reached for `getHistoryPage` (the one that carries the envelope's
  /// total, and therefore the only one a count may be derived from) got records
  /// with no embedded `movie`, and the embedded movie is what the row draws: a
  /// title, a poster and a year, all silently absent. So the count and the
  /// content could not both be right at the same time.
  @override
  Future<ArrRecordPage> getHistoryPage({
    int page = 1,
    int pageSize = 20,
    Map<String, dynamic>? queryParameters,
  }) {
    return super.getHistoryPage(
      page: page,
      pageSize: pageSize,
      queryParameters: {'includeMovie': true, ...?queryParameters},
    );
  }

  @override
  Future<List<dynamic>> getAllHistory({Map<String, dynamic>? queryParameters}) {
    return super.getAllHistory(
      queryParameters: {'includeMovie': true, ...?queryParameters},
    );
  }

  /// Triggers an automatic search for the given movie ID.
  Future<void> searchMovie(int movieId) async {
    await client.post(
      '/api/v3/command',
      data: {
        'name': 'MoviesSearch',
        'movieIds': [movieId],
      },
    );
  }

  /// Fetches releases for interactive search.
  Future<List<dynamic>> getReleases(
    int movieId, {
    CancelToken? cancelToken,
    Duration? receiveTimeout,
  }) async {
    return fetchReleases(
      {'movieId': movieId},
      cancelToken: cancelToken,
      receiveTimeout: receiveTimeout,
    );
  }

  /// Grabs a specific release for download.
  Future<void> grabRelease({
    required String guid,
    required int indexerId,
  }) async {
    await grabReleaseByGuid(guid: guid, indexerId: indexerId);
  }

  /// Searches for movies by term using the lookup API.
  ///
  /// [cancelToken] aborts the request once the search that asked for it has
  /// been superseded — see [ArrActivityMixin.lookupItems], which owns the
  /// empty-term guard, the isolate mapping and the degrade-to-`[]` rule the
  /// three arr lookups share.
  Future<List<RadarrMovie>> lookupMovies(
    String term, {
    CancelToken? cancelToken,
    bool reportFailure = false,
  }) {
    return lookupItems(
      'movie/lookup',
      term,
      RadarrMovie.fromJson,
      cancelToken: cancelToken,
      reportFailure: reportFailure,
    );
  }

  /// Adds [movie] — a `movie/lookup` row — to this Radarr's library.
  ///
  /// [movie] is posted back very nearly as it arrived: Radarr builds the
  /// library entry from the metadata it proxied, and the three fields the user
  /// chose ([qualityProfileId], [rootFolderPath], [monitored]) are what turn a
  /// lookup row into one. `addOptions.searchForMovie` is the half that makes
  /// this an add rather than a bookmark — without it the movie is tracked and
  /// nothing is ever grabbed.
  ///
  /// [minimumAvailability] defaults to whatever the lookup row carried, which
  /// is the server's own configured default for new movies.
  ///
  /// Throws on failure rather than degrading. Radarr answers 400 for a movie
  /// it already holds, and a caller that cannot tell that from a success would
  /// report an add that never happened.
  Future<RadarrMovie> addMovie(
    RadarrMovie movie, {
    required int qualityProfileId,
    required String rootFolderPath,
    bool monitored = true,
    bool searchForMovie = true,
  }) async {
    final response = await client.post(
      '/api/v3/movie',
      data: {
        'title': movie.title,
        // Radarr keys the new entry on these two, not on the title.
        'titleSlug': movie.titleSlug,
        'tmdbId': movie.tmdbId,
        'year': movie.year,
        // Posted back so the library entry has artwork before the first
        // metadata refresh runs.
        'images': movie.images,
        'qualityProfileId': qualityProfileId,
        'rootFolderPath': rootFolderPath,
        'monitored': monitored,
        'minimumAvailability': movie.minimumAvailability ?? 'released',
        'addOptions': {'searchForMovie': searchForMovie},
      },
    );
    return RadarrMovie.fromJson(response.data as Map<String, dynamic>);
  }

  /// Fetches the root folders configured on this Radarr.
  Future<List<Map<String, dynamic>>> getRootFolders() async {
    return fetchRootFolders();
  }

  /// Finds a movie in the library by its TMDB ID.
  /// Returns null if not found in the library.
  Future<RadarrMovie?> getMovieByTmdbId(int tmdbId) async {
    try {
      final movies = await getMovies();
      return movies.where((m) => m.tmdbId == tmdbId).firstOrNull;
    } catch (_) {
      return null;
    }
  }

  /// Fetches all quality profiles.
  Future<List<Map<String, dynamic>>> getQualityProfiles() async {
    return fetchQualityProfiles();
  }

  /// Updates a movie's quality profile.
  Future<void> updateMovieProfile(int movieId, int qualityProfileId) async {
    await updateItemProfile('movie', movieId, qualityProfileId);
  }

  /// Updates a movie's monitored state.
  Future<void> updateMovieMonitored(int movieId, bool monitored) async {
    await updateItemMonitored('movie', movieId, monitored);
  }

  /// Deletes a movie from Radarr.
  Future<void> deleteMovie(
    int movieId, {
    bool deleteFiles = false,
    bool addImportExclusion = false,
  }) async {
    await client.delete(
      '/api/v3/movie/$movieId',
      queryParameters: {
        'deleteFiles': deleteFiles,
        'addImportExclusion': addImportExclusion,
      },
    );
  }
}
