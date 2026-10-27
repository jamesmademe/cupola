import 'package:dio/dio.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/api/base_arr_service.dart';
import 'package:cupola/features/movies/domain/models/radarr_collection.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/settings/data/connection_providers.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

final radarrServiceProvider = _radarr.lens;

final radarrServiceForProvider = _radarr.forConnection;

final _radarr = ConnectionProviders<RadarrService>.apiClient(
  ServiceKey.radarr,
  create: RadarrService.new,
);

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
  /// ([getMovieByTmdbId]). The wall and every *figure* use [getMoviesOrThrow];
  /// see the note there, and on `fetchAllItems`, for why the two differ.
  Future<List<RadarrMovie>> getMovies() async {
    return fetchAllItems('movie', RadarrMovie.fromJson);
  }

  /// The same library, with a failed fetch allowed to reach the caller.
  ///
  /// See [fetchAllItemsOrThrow]. A Radarr that is unreachable, mis-keyed or
  /// 500-ing resolves [getMovies] *successfully* with an empty list, and the
  /// KPI rail printed `Movies 0 · Monitored 0 · Missing 0` off it: three
  /// fabrications on the first screen the app opens, each contradicting the
  /// identity band above them.
  Future<List<RadarrMovie>> getMoviesOrThrow() async {
    return fetchAllItemsOrThrow('movie', RadarrMovie.fromJson);
  }

  /// Fetches a single movie by its Radarr ID, with a failed fetch allowed to
  /// reach the caller.
  ///
  /// It used to answer `null` for every failure (`fetchItem`), so the detail
  /// page could not tell a Radarr that did not answer from a film it does not
  /// have: opened with a preloaded film, it drew that film as if Radarr had
  /// just confirmed it; opened cold, it reported the request as not completed
  /// in both cases. A 404 still answers `null`, because it is an answer
  /// (Radarr has no movie by that id), and every other failure travels.
  Future<RadarrMovie?> getMovieOrThrow(int movieId) async {
    try {
      final response = await client.get(
        '/api/${config.apiVersion}/movie/$movieId',
      );
      return RadarrMovie.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  /// On the **page** primitive, not on `getHistory`.
  ///
  /// `getHistory` delegates to this, so both spellings pick the parameter up,
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
  Future<List<dynamic>> getAllHistory({
    Map<String, dynamic>? queryParameters,
    void Function(List<dynamic> records)? onProgress,
  }) {
    return super.getAllHistory(
      queryParameters: {'includeMovie': true, ...?queryParameters},
      onProgress: onProgress,
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
  /// been superseded. See [ArrActivityMixin.lookupItems], which owns the
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

  /// Adds [movie] (a `movie/lookup` row) to this Radarr's library.
  ///
  /// [movie] is posted back very nearly as it arrived: Radarr builds the
  /// library entry from the metadata it proxied, and the three fields the user
  /// chose ([qualityProfileId], [rootFolderPath], [monitored]) are what turn a
  /// lookup row into one. `addOptions.searchForMovie` is the half that makes
  /// this an add rather than a bookmark: without it the movie is tracked and
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

  /// The lookup row of one film, by its TMDB id (`movie/lookup/tmdb`): what
  /// [addMovie] posts back. A failure travels.
  Future<RadarrMovie> lookupMovieByTmdbId(int tmdbId) async {
    final response = await client.get(
      '/api/v3/movie/lookup/tmdb',
      queryParameters: {'tmdbId': tmdbId},
    );
    final data = response.data;
    if (data is! Map) {
      throw const FormatException('Radarr answered without a movie');
    }
    return RadarrMovie.fromJson(data.cast<String, dynamic>());
  }

  /// The downloads the queue holds for one film (`queue/details?movieId=`),
  /// each record as the queue lists it. A failure travels.
  Future<List<Map<String, dynamic>>> getMovieQueue(int movieId) async {
    final response = await client.get(
      '/api/v3/queue/details',
      queryParameters: {'movieId': movieId},
    );
    final data = response.data;
    if (data is! List) {
      throw const FormatException('Radarr answered without a queue');
    }
    // Matched here as well: a Radarr that ignored the filter answers with
    // its whole queue.
    return [
      for (final item in data.whereType<Map>())
        if (item['movieId'] == movieId) item.cast<String, dynamic>(),
    ];
  }

  /// When a search for one film was asked, while it is queued or running:
  /// the earliest such `MoviesSearch` among Radarr's commands. Null when none
  /// is. A failure travels.
  Future<DateTime?> searchingSince(int movieId) async {
    final response = await client.get('/api/v3/command');
    final data = response.data;
    if (data is! List) {
      throw const FormatException('Radarr answered without its commands');
    }
    DateTime? since;
    for (final command in data.whereType<Map>()) {
      if (command['name'] != 'MoviesSearch') continue;
      if (command['status'] != 'queued' && command['status'] != 'started') {
        continue;
      }
      final body = command['body'];
      final ids = body is Map ? body['movieIds'] : null;
      if (ids is! List || !ids.contains(movieId)) continue;
      final at = DateTime.tryParse('${command['queued'] ?? ''}')?.toLocal();
      if (at != null && (since == null || at.isBefore(since))) since = at;
    }
    return since;
  }

  /// Fetches the root folders configured on this Radarr.
  Future<List<Map<String, dynamic>>> getRootFolders() async {
    return fetchRootFolders();
  }

  /// Finds a movie in the library by its TMDB ID, or null when Radarr holds
  /// none.
  ///
  /// Asks Radarr for that one film (`GET /api/v3/movie?tmdbId=`). It used to
  /// download the whole library to find one id for a Discover page, and to
  /// answer a Radarr that did not answer with null, which every caller read as
  /// "not in the library". A failure now travels: it is not an answer.
  Future<RadarrMovie?> getMovieByTmdbId(int tmdbId) async {
    final response = await client.get(
      '/api/v3/movie',
      queryParameters: {'tmdbId': tmdbId},
    );
    final data = response.data;
    if (data is! List) {
      throw const FormatException('Radarr answered without a movie list');
    }
    // Matched here as well: a Radarr that ignored the filter answers with its
    // whole library, and the first row of that is not this film.
    for (final item in data.whereType<Map>()) {
      final movie = RadarrMovie.fromJson(item.cast<String, dynamic>());
      if (movie.tmdbId == tmdbId) return movie;
    }
    return null;
  }

  /// The collections the library has a movie of (`GET /api/v3/collection`).
  /// A failure travels.
  Future<List<RadarrCollection>> getCollections() async {
    final response = await client.get('/api/v3/collection');
    final data = response.data;
    if (data is! List) {
      throw const FormatException('Radarr answered without a collection list');
    }
    return [
      for (final item in data.whereType<Map>())
        RadarrCollection.fromJson(item.cast<String, dynamic>()),
    ];
  }

  /// One film's history, newest first (`GET /api/v3/history/movie`,
  /// unpaged). A failure travels.
  Future<List<Map<String, dynamic>>> getMovieHistory(int movieId) async {
    final response = await client.get(
      '/api/v3/history/movie',
      queryParameters: {'movieId': movieId},
    );
    final data = response.data;
    if (data is! List) {
      throw const FormatException('Radarr answered without a history list');
    }
    final records = [
      for (final item in data.whereType<Map>()) item.cast<String, dynamic>(),
    ]..sort((a, b) => '${b['date'] ?? ''}'.compareTo('${a['date'] ?? ''}'));
    return records;
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
