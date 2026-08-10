import 'dart:isolate';
import 'package:dio/dio.dart';
import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/discover/domain/models/seerr_genre.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/core/models/media_preview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Thrown when a request has already been acted on somewhere else.
///
/// Worth a type of its own because it is the *only* way the request write
/// actions realistically fail, and it is not an error on our side. Cupola
/// authenticates to Seerr with the instance API key, which Seerr treats as
/// admin — so approve and decline are never refused for lack of permission,
/// there is no per-user permission bitfield to read first, and no 403 to design
/// around. What does happen is a race: the same request approved from the web UI
/// a moment earlier, or deleted outright. Seerr answers 404 or 409, and the
/// honest response is to say the state moved and reload — not to report a
/// transport failure for something that already succeeded, by someone else.
class SeerrRequestConflict implements Exception {
  final String message;

  const SeerrRequestConflict(this.message);

  @override
  String toString() => message;
}

/// Row count above which a discover page is mapped off the main isolate.
///
/// Same number and the same reasoning as the qBittorrent torrent parse and the
/// Jellyfin item mapper: below it the isolate spawn costs more than the mapping
/// does. Discover pages are TMDB-shaped and hold twenty rows, so in practice
/// they map here — the gate exists for a server that answers with more.
const int _seerrIsolateMapThreshold = 200;

/// Maps a decoded discover page, moving to an isolate once it is big enough to
/// be worth the port.
///
/// Top-level rather than a method on purpose: the closure handed to
/// `Isolate.run` must capture only sendable values (here a decoded list and a
/// `String?`), and one written inside an instance method can drag `this` —
/// which holds an [ApiClient] — across the boundary.
Future<List<MediaPreview>> _mapPreviews(
  List<dynamic> results,
  String? forcedMediaType,
) async {
  if (results.length <= _seerrIsolateMapThreshold) {
    return results
        .map((e) => MediaPreview.fromJson(e, forcedMediaType: forcedMediaType))
        .toList();
  }
  return Isolate.run(
    () => results
        .map((e) => MediaPreview.fromJson(e, forcedMediaType: forcedMediaType))
        .toList(),
  );
}

final seerrServiceProvider = Provider<SeerrService>((ref) {
  final settings = ref.watch(currentSettingsProvider);
  return SeerrService(apiClientFor(settings, ServiceKey.seerr));
});

class SeerrService {
  final ApiClient _client;

  /// Page size for the request list.
  ///
  /// Seerr puts no cap on `take` and answers with `pageInfo.results`, so pages
  /// of 50 keep fetching every request to one round-trip until a request
  /// history genuinely outgrows it.
  static const int _requestPageSize = 50;

  /// How many title hydrations may run at once.
  ///
  /// Each one is a TMDB call proxied by Seerr, and a request list full of
  /// "Unknown Media" rows used to fire one for every row simultaneously. Eight
  /// at a time keeps a burst of refreshes polite to the server without making
  /// the first paint wait for a serial walk.
  static const int _hydrationConcurrency = 8;

  /// tmdbId → hydrated title metadata.
  ///
  /// Without this every refresh re-fetched the details of the same unknown
  /// titles from Seerr's TMDB passthrough — the list only grows, so a refresh
  /// that ran N calls ran N calls every time.
  final Map<int, ({String? title, String? year, String? posterPath})>
  _mediaCache = {};

  SeerrService(this._client);

  Future<List<SeerrRequest>> getRequests() async {
    try {
      final first = await _requestPage(0);
      final all = <SeerrRequest>[...first.items];

      // The server reports the true count on the first page, so the remaining
      // pages can all be asked for in parallel.
      if (all.length < first.total) {
        final pages = await Future.wait([
          for (
            var skip = _requestPageSize;
            skip < first.total;
            skip += _requestPageSize
          )
            _requestPageSafely(skip),
        ]);
        for (final page in pages) {
          all.addAll(page.items);
        }
      }

      return await _hydrateRequests(all);
    } catch (e) {
      return [];
    }
  }

  Future<({List<SeerrRequest> items, int total})> _requestPage(int skip) async {
    final response = await _client.get(
      '/api/v1/request',
      queryParameters: {
        'take': _requestPageSize,
        'skip': skip,
        'sort': 'added',
        'filter': 'all',
      },
    );
    final data = response.data as Map<String, dynamic>;
    final results = data['results'] as List<dynamic>? ?? const [];
    final pageInfo = data['pageInfo'];
    final total = pageInfo is Map<String, dynamic>
        ? (pageInfo['results'] as num?)?.toInt() ?? 0
        : 0;
    final items = results
        .map((e) {
          try {
            return SeerrRequest.fromJson(e);
          } catch (e) {
            return null;
          }
        })
        .whereType<SeerrRequest>()
        .toList(growable: false);
    return (items: items, total: total);
  }

  /// A later page failing must not blank the requests that did arrive — the
  /// caller gets the pages that answered and moves on.
  Future<({List<SeerrRequest> items, int total})> _requestPageSafely(
    int skip,
  ) async {
    try {
      return await _requestPage(skip);
    } catch (_) {
      return (items: const <SeerrRequest>[], total: 0);
    }
  }

  Future<List<SeerrRequest>> _hydrateRequests(
    List<SeerrRequest> requests,
  ) async {
    if (requests.isEmpty) return requests;

    final hydrated = List<SeerrRequest?>.filled(requests.length, null);
    var next = 0;

    Future<void> worker() async {
      while (true) {
        final index = next++;
        if (index >= requests.length) return;
        hydrated[index] = await _hydrateRequest(requests[index]);
      }
    }

    final workers = _hydrationConcurrency < requests.length
        ? _hydrationConcurrency
        : requests.length;
    await Future.wait(List.generate(workers, (_) => worker()));

    return hydrated.whereType<SeerrRequest>().toList(growable: false);
  }

  Future<SeerrRequest> _hydrateRequest(SeerrRequest request) async {
    final media = request.media;
    if (media == null) return request;

    final title = media.title;
    final needsTitle =
        title == null ||
        title == 'Unknown Media' ||
        title.startsWith('Unknown Media (');
    if (!needsTitle && media.posterPath != null) return request;

    final tmdbId = media.tmdbId;
    if (tmdbId == null) return request;

    final cached = _mediaCache[tmdbId];
    if (cached != null) {
      return _applyHydration(request, cached);
    }

    try {
      if (media.mediaType == 'movie') {
        final details = await getMovie(tmdbId);
        _mediaCache[tmdbId] = (
          title: details['title']?.toString(),
          year: details['releaseDate']?.toString().substring(0, 4),
          posterPath:
              details['posterPath']?.toString() ??
              details['poster_path']?.toString(),
        );
      } else if (media.mediaType == 'tv') {
        final details = await getTv(tmdbId);
        _mediaCache[tmdbId] = (
          title: details['name']?.toString(),
          year: details['firstAirDate']?.toString().substring(0, 4),
          posterPath:
              details['posterPath']?.toString() ??
              details['poster_path']?.toString(),
        );
      } else {
        return request;
      }
      return _applyHydration(request, _mediaCache[tmdbId]!);
    } catch (e) {
      // Ignore hydration errors
      return request;
    }
  }

  SeerrRequest _applyHydration(
    SeerrRequest request,
    ({String? title, String? year, String? posterPath}) entry,
  ) {
    final media = request.media;
    if (media == null) return request;
    return request.copyWith(
      media: media.copyWith(
        title: entry.title ?? media.title,
        year: entry.year ?? media.year,
        posterPath: entry.posterPath ?? media.posterPath,
      ),
    );
  }

  Future<void> deleteRequest(int requestId) async {
    await _guardConflict(() => _client.delete('/api/v1/request/$requestId'));
  }

  /// Approves a request that is waiting for approval.
  ///
  /// The request then goes to whichever \*arr handles that media type, which is
  /// why Activity can show a request turning into a queue row minutes later.
  Future<void> approveRequest(int requestId) async {
    await _guardConflict(
      () => _client.post('/api/v1/request/$requestId/approve'),
    );
  }

  /// Declines a request, leaving the media untouched.
  Future<void> declineRequest(int requestId) async {
    await _guardConflict(
      () => _client.post('/api/v1/request/$requestId/decline'),
    );
  }

  /// Translates the one HTTP outcome these writes actually produce.
  ///
  /// See [SeerrRequestConflict]: with an admin API key there is no authorisation
  /// failure to handle, only the race.
  Future<void> _guardConflict(Future<void> Function() action) async {
    try {
      await action();
    } on DioException catch (error) {
      final code = error.response?.statusCode;
      if (code == 404 || code == 409) {
        throw const SeerrRequestConflict(
          'That request had already been updated somewhere else.',
        );
      }
      rethrow;
    }
  }

  /// The one discover body: every `/discover/*` row differs only in path, in
  /// the media type it forces onto rows that do not carry one, and in whether
  /// the caller filters or sorts.
  ///
  /// The conditional spreads are what keep the query maps identical to the
  /// per-row methods they replaced — the upcoming and trending rows take no
  /// genre or sort, so they still send `page` alone.
  Future<List<MediaPreview>> _discover(
    String path, {
    required int page,
    int? genre,
    String? sortBy,
    String? forcedMediaType,
  }) async {
    try {
      final response = await _client.get(
        path,
        queryParameters: {
          'page': page,
          if (genre != null) 'genre': genre,
          if (sortBy != null) 'sortBy': sortBy,
        },
      );
      final results = response.data['results'] as List<dynamic>;
      return await _mapPreviews(results, forcedMediaType);
    } catch (e) {
      return [];
    }
  }

  Future<List<MediaPreview>> getDiscoverMovies({
    int page = 1,
    int? genre,
    String? sortBy,
  }) {
    return _discover(
      '/api/v1/discover/movies',
      page: page,
      genre: genre,
      sortBy: sortBy,
      forcedMediaType: 'movie',
    );
  }

  Future<List<MediaPreview>> getDiscoverTV({
    int page = 1,
    int? genre,
    String? sortBy,
  }) {
    return _discover(
      '/api/v1/discover/tv',
      page: page,
      genre: genre,
      sortBy: sortBy,
      forcedMediaType: 'tv',
    );
  }

  /// Upcoming movies (Overseerr/Jellyseerr `/discover/movies/upcoming`).
  Future<List<MediaPreview>> getDiscoverUpcomingMovies({int page = 1}) {
    return _discover(
      '/api/v1/discover/movies/upcoming',
      page: page,
      forcedMediaType: 'movie',
    );
  }

  /// Upcoming TV (Overseerr/Jellyseerr `/discover/tv/upcoming`).
  Future<List<MediaPreview>> getDiscoverUpcomingTv({int page = 1}) {
    return _discover(
      '/api/v1/discover/tv/upcoming',
      page: page,
      forcedMediaType: 'tv',
    );
  }

  /// Available movie genres (used to build per-genre discover rows).
  Future<List<SeerrGenre>> getMovieGenres() => _getGenres('movie');

  /// Available TV genres.
  Future<List<SeerrGenre>> getTvGenres() => _getGenres('tv');

  Future<List<SeerrGenre>> _getGenres(String mediaType) async {
    try {
      final response = await _client.get(
        '/api/v1/discover/genreslider/$mediaType',
      );
      final results = (response.data as List<dynamic>);
      return results
          .whereType<Map<String, dynamic>>()
          .map(SeerrGenre.fromJson)
          .where((g) => g.id > 0 && g.name.isNotEmpty)
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Trending rows mix movies and TV, so the media type stays whatever each row
  /// declares.
  Future<List<MediaPreview>> getDiscoverTrending({int page = 1}) {
    return _discover('/api/v1/discover/trending', page: page);
  }

  Future<Map<String, dynamic>> getMovie(int movieId) async {
    final response = await _client.get('/api/v1/movie/$movieId');
    return response.data;
  }

  Future<Map<String, dynamic>> getTv(int tvId) async {
    final response = await _client.get('/api/v1/tv/$tvId');
    return response.data;
  }

  Future<Map<String, dynamic>> getCollection(int collectionId) async {
    try {
      final response = await _client.get('/api/v1/collection/$collectionId');
      return response.data;
    } catch (_) {
      return {};
    }
  }

  /// TMDB person details (bio, department, birthday) proxied by Overseerr /
  /// Jellyseerr. Returns `{}` on any error so the UI can degrade gracefully.
  Future<Map<String, dynamic>> getPerson(int personId) async {
    try {
      final response = await _client.get('/api/v1/person/$personId');
      return response.data as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  /// A person's combined movie + TV cast filmography, de-duped by id and sorted
  /// by rating so the strongest credits lead. Returns `[]` on error.
  Future<List<MediaPreview>> getPersonCombinedCredits(int personId) async {
    try {
      final response = await _client.get(
        '/api/v1/person/$personId/combinedCredits',
      );
      final cast = (response.data['cast'] as List<dynamic>? ?? const []);
      final seen = <int>{};
      final items = <MediaPreview>[];
      for (final entry in cast) {
        if (entry is! Map<String, dynamic>) continue;
        final mediaType = entry['mediaType'] ?? entry['media_type'];
        if (mediaType != 'movie' && mediaType != 'tv') continue;
        final id = (entry['id'] as num?)?.toInt();
        if (id == null || !seen.add(id)) continue;
        items.add(MediaPreview.fromJson(entry));
      }
      items.sort((a, b) => (b.voteAverage ?? 0).compareTo(a.voteAverage ?? 0));
      return items;
    } catch (_) {
      return const [];
    }
  }

  /// Searches for movies and TV shows by query string.
  /// Filters out 'person' results to only return movies and TV shows.
  ///
  /// [cancelToken] aborts the request once the search that asked for it has
  /// been superseded: global search re-runs every service leg on each debounced
  /// keystroke, and a discarded round should stop paying for itself rather than
  /// run to completion.
  Future<List<MediaPreview>> search(
    String query, {
    int page = 1,
    CancelToken? cancelToken,
  }) async {
    if (query.isEmpty) return [];
    try {
      // URL-encode the query to handle spaces and special characters
      final encodedQuery = Uri.encodeComponent(query);
      final response = await _client.get(
        '/api/v1/search',
        queryParameters: {'query': encodedQuery, 'page': page},
        cancelToken: cancelToken,
      );
      final results = response.data['results'] as List<dynamic>;
      // Filter out 'person' results - only keep movies and TV shows
      return results
          .where((e) {
            final mediaType = e['mediaType'] ?? e['media_type'];
            return mediaType == 'movie' || mediaType == 'tv';
          })
          .map((e) => MediaPreview.fromJson(e))
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Gets available Radarr servers from Seerr.
  Future<List<Map<String, dynamic>>> getRadarrServers() async {
    try {
      final response = await _client.get('/api/v1/service/radarr');
      final data = response.data as List<dynamic>;
      return data.cast<Map<String, dynamic>>();
    } catch (e) {
      return [];
    }
  }

  /// Gets available Sonarr servers from Seerr.
  Future<List<Map<String, dynamic>>> getSonarrServers() async {
    try {
      final response = await _client.get('/api/v1/service/sonarr');
      final data = response.data as List<dynamic>;
      return data.cast<Map<String, dynamic>>();
    } catch (e) {
      return [];
    }
  }

  /// Gets quality profiles for a specific Radarr server.
  Future<Map<String, dynamic>> getRadarrProfiles(int serverId) async {
    final response = await _client.get('/api/v1/service/radarr/$serverId');
    return response.data;
  }

  /// Gets quality profiles for a specific Sonarr server.
  Future<Map<String, dynamic>> getSonarrProfiles(int serverId) async {
    final response = await _client.get('/api/v1/service/sonarr/$serverId');
    return response.data;
  }

  /// Creates a new media request.
  /// [mediaType] should be 'movie' or 'tv'.
  /// [mediaId] is the TMDB ID of the media.
  Future<void> createRequest({
    required String mediaType,
    required int mediaId,
    int? profileId,
    String? rootFolder, // Root folder path
    int? serverId,
    bool is4k = false,
    List<int>? seasons, // For TV shows - if null, requests all seasons
  }) async {
    final body = <String, dynamic>{
      'mediaType': mediaType,
      'mediaId': mediaId,
      'is4k': is4k,
    };

    // For TV shows, seasons is required - use 'all' or specific season numbers
    if (mediaType == 'tv') {
      if (seasons != null && seasons.isNotEmpty) {
        body['seasons'] = seasons;
      } else {
        body['seasons'] = 'all';
      }
    }

    if (profileId != null) body['profileId'] = profileId;
    if (rootFolder != null) body['rootFolder'] = rootFolder;
    if (serverId != null) body['serverId'] = serverId;

    await _client.post('/api/v1/request', data: body);
  }

  /// Deletes a media item from Seerr tracking.
  /// This removes the media record but does NOT delete files from Radarr/Sonarr.
  /// [mediaId] is the Seerr internal media ID (not TMDB ID).
  Future<void> deleteMedia(int mediaId) async {
    await _client.delete('/api/v1/media/$mediaId');
  }

  /// Deletes the media files from Radarr/Sonarr via Seerr.
  /// This removes the actual files from the media server.
  /// [mediaId] is the Seerr internal media ID (not TMDB ID).
  Future<void> deleteMediaFile(int mediaId) async {
    await _client.delete('/api/v1/media/$mediaId/file');
  }
}
