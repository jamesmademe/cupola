import 'dart:collection';
import 'dart:isolate';
import 'package:dio/dio.dart';
import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/discover/domain/models/person_credits.dart';
import 'package:cupola/features/discover/domain/models/seerr_genre.dart';
import 'package:cupola/features/discover/domain/models/seerr_admin_models.dart';
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

int? _asInt(Object? value) =>
    value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');

/// A Seerr request history, carrying what Seerr said about its size.
///
/// A list, so every reader of [SeerrService.getRequests] goes on reading rows
/// exactly as before. What it adds is the two facts a figure needs and a bare
/// list threw away: how many requests the server holds, from its own
/// `pageInfo.results`, and whether a page of them did not arrive. A count taken
/// from the list's length was the rows that came back, and a later page that
/// failed shortened it without a word.
class SeerrRequestList extends ListBase<SeerrRequest> {
  SeerrRequestList(
    Iterable<SeerrRequest> rows, {
    this.total,
    this.isPartial = false,
  }) : _rows = List.of(rows, growable: false);

  final List<SeerrRequest> _rows;

  /// How many requests the server says it holds, or null when its answer did
  /// not say. Not [length]: a row Seerr sent in a shape this app cannot read is
  /// still a request, and a page that did not arrive still holds its rows.
  final int? total;

  /// A page after the first did not arrive. The rows are short of [total],
  /// and nothing more will be fetched until the list is read again.
  final bool isPartial;

  @override
  int get length => _rows.length;

  // Fixed length, as the list this replaced was: rows can be replaced in
  // place, and adding one throws.
  @override
  set length(int value) => _rows.length = value;

  @override
  SeerrRequest operator [](int index) => _rows[index];

  @override
  void operator []=(int index, SeerrRequest value) => _rows[index] = value;
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
  return SeerrService(watchApiClient(ref, ServiceKey.seerr));
});

/// Seerr bound to one named connection, whatever the lens is pointing at.
///
/// The same shape — and for the same reasons — as `radarrServiceForProvider`;
/// read its comment before touching this one. What it buys here is /activity:
/// the feed lists the requests of every configured Seerr, and a request id is
/// **per instance**, so approving id 42 through the lens approves a different
/// person's request on a different server and reports success.
///
/// Empty id means the lens, which is what the plain [seerrServiceProvider]
/// answers. The lens's own id collapses onto that provider too, rather than
/// opening a second `Dio` at the same address — and, just as load-bearing, so
/// that an override of the plain provider (how the whole suite supplies a fake
/// Seerr) is not quietly bypassed on the path that names a connection.
///
/// `read` of the lens, deliberately: watching it would rebuild every entry of
/// this family whenever the lens moved — entries for connections that did not
/// change — and `watchApiClient` closes the outgoing client on dispose, which
/// would cut a request already in flight. The cost is that an entry minted
/// before the lens landed on its id keeps a client of its own until disposal.
///
/// Not `autoDispose`: a caller reads this, awaits on it, and a disposal
/// scheduled at the end of the read would close the `Dio` under the request.
final seerrServiceForProvider = Provider.family<SeerrService, String>((
  ref,
  instanceId,
) {
  final lens = ref.read(activeInstanceProvider(ServiceKey.seerr))?.id ?? '';
  if (instanceId.isEmpty || instanceId == lens) {
    return ref.watch(seerrServiceProvider);
  }
  return SeerrService(
    watchApiClient(ref, ServiceKey.seerr, instanceId: instanceId),
  );
});

class SeerrService {
  final ApiClient _client;

  /// The cheapest authenticated Seerr read.
  ///
  /// `/api/v1/status` is a reachability endpoint and is public on Seerr. It
  /// cannot prove that the API key the user pasted will work for the requests
  /// and discover surfaces that follow. A one-row request query is enough to
  /// exercise the actual API-key boundary while remaining cheap on an empty
  /// server.
  static const Map<String, dynamic> authProbeQuery = {
    'take': 1,
    'skip': 0,
    'sort': 'added',
    'filter': 'all',
  };

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

  /// [numbering] when the caller already knows what the server follows, as
  /// a test does; otherwise [numbering()] asks the server the first time a
  /// code needs decoding.
  SeerrService(this._client, {SeerrNumbering? numbering})
    : _numbering = numbering;

  /// Which numbering this server's media codes follow, once it has said.
  SeerrNumbering? _numbering;
  Future<SeerrNumbering?>? _numberingRead;

  /// The numbering of this server's media codes, from the version
  /// `/api/v1/status` reports (`SeerrNumbering.fromVersion`).
  ///
  /// Read once per connection and kept for as long as this client lives: a
  /// service is built per connection, so the answer belongs to the server it
  /// came from, and a changed address builds a new one. Never kept in the
  /// settings, which hold what the user typed, not what a server says.
  ///
  /// Null, and asked again next time, when the server did not answer or said
  /// no version: a code it sends is then decoded without guessing.
  /// `/api/v1/status` is public on Seerr, so this costs no key and fails only
  /// where everything else would.
  Future<SeerrNumbering?> numbering() {
    final known = _numbering;
    if (known != null) return Future.value(known);
    return _numberingRead ??= _readNumbering();
  }

  Future<SeerrNumbering?> _readNumbering() async {
    try {
      final response = await _client.get('/api/v1/status');
      final data = response.data;
      final version = data is Map ? data['version']?.toString() : null;
      return _numbering = SeerrNumbering.fromVersion(version);
    } catch (_) {
      return null;
    } finally {
      _numberingRead = null;
    }
  }

  /// Proves that Seerr accepts the configured API key.
  ///
  /// This deliberately does not call [getRequests], which hydrates every row
  /// and is far too expensive for a connection test or a health poll.
  Future<void> testConnection() async {
    await _client.get('/api/v1/request', queryParameters: authProbeQuery);
  }

  static const _adminPageSize = 50;

  /// Reads every admin page while preserving the distinction between a complete
  /// empty list and a first page followed by a failed later page.
  ///
  /// The first page is awaited alone because it carries `pageInfo.results` —
  /// there is no way to know how many pages exist before asking for one. Once
  /// that number is in hand the rest are **fetched together**: the old serial
  /// loop turned a 500-user server into ten round trips in single file for no
  /// reason, since none of them depends on the one before it.
  Future<SeerrAdminResult<SeerrIssue>> getIssuesResult({
    SeerrIssueFilter filter = SeerrIssueFilter.open,
  }) async {
    final first = await _issuePage(0, filter: filter);
    return _collect(
      first,
      (skip) async => (await _issuePage(skip, filter: filter)).items,
    );
  }

  /// Folds the remaining pages of an admin list onto its first one.
  ///
  /// A later page that fails does not take the rows already in hand with it,
  /// but it does set [SeerrAdminResult.isPartial]: the caller must keep the
  /// rows and must not present them as the whole list. `eagerError: false` is
  /// the point of `Future.wait` here — every page is observed, so one refusal
  /// cannot leave the others as unhandled errors.
  Future<SeerrAdminResult<T>> _collect<T>(
    ({List<T> items, int total}) first,
    Future<List<T>> Function(int skip) page,
  ) async {
    final skips = [
      for (
        var skip = _adminPageSize;
        skip < first.total;
        skip += _adminPageSize
      )
        skip,
    ];
    final rest = await Future.wait(
      skips.map((skip) async {
        try {
          return await page(skip);
        } catch (_) {
          return null;
        }
      }),
    );
    return SeerrAdminResult(
      items: List.unmodifiable([
        ...first.items,
        for (final chunk in rest) ...?chunk,
      ]),
      total: first.total,
      isPartial: rest.any((chunk) => chunk == null),
    );
  }

  Future<({List<SeerrIssue> items, int total})> _issuePage(
    int skip, {
    required SeerrIssueFilter filter,
  }) async {
    final response = await _client.get(
      '/api/v1/issue',
      queryParameters: {
        'take': _adminPageSize,
        'skip': skip,
        'sort': 'modified',
        'filter': filter.apiValue,
      },
    );
    final data = response.data;
    final results = data is Map ? data['results'] : data;
    final pageInfo = data is Map ? data['pageInfo'] : null;
    final total = pageInfo is Map
        ? (_asInt(pageInfo['results']) ?? _asInt(pageInfo['total']) ?? 0)
        : results is List
        ? results.length
        : 0;
    final items = results is List
        ? results
              .map(SeerrIssue.fromJson)
              .where((issue) => issue.id > 0)
              .toList(growable: false)
        : const <SeerrIssue>[];
    return (items: items, total: total);
  }

  Future<void> resolveIssue(int issueId) async {
    await _client.post('/api/v1/issue/$issueId/resolved');
  }

  /// Every user this server holds, with the same partial-page contract as
  /// [getIssuesResult].
  ///
  /// There is deliberately no `getUsers()` returning a bare list: it existed,
  /// it threw `isPartial` away, and a caller holding 50 of 300 users with no
  /// way to know it is exactly the failure `SeerrAdminResult` was added for.
  Future<SeerrAdminResult<SeerrUser>> getUsersResult() async {
    final first = await _userPage(0);
    return _collect(first, (skip) async => (await _userPage(skip)).items);
  }

  Future<({List<SeerrUser> items, int total})> _userPage(int skip) async {
    final response = await _client.get(
      '/api/v1/user',
      queryParameters: {
        'take': _adminPageSize,
        'skip': skip,
        'sort': 'displayname',
        'sortDirection': 'asc',
      },
    );
    final data = response.data;
    final results = data is Map ? data['results'] : data;
    final pageInfo = data is Map ? data['pageInfo'] : null;
    final total = pageInfo is Map
        ? (_asInt(pageInfo['results']) ?? _asInt(pageInfo['total']) ?? 0)
        : results is List
        ? results.length
        : 0;
    final items = results is List
        ? results
              .map(SeerrUser.fromJson)
              .where((user) => user.id > 0)
              .toList(growable: false)
        : const <SeerrUser>[];
    return (items: items, total: total);
  }

  /// Every request this server holds, hydrated.
  ///
  /// **Throws when the first page does not come back**, and that is the
  /// contract rather than an oversight. This used to wrap the whole load in
  /// `catch (e) { return []; }`, so a Seerr that was unreachable and a Seerr
  /// with no requests produced byte-identical output — and no caller could tell
  /// them apart, least of all /activity, which now lists several Seerrs at once
  /// and has to say which of them did not answer. A *later* page failing is
  /// still absorbed by [_requestPageSafely]: the pages that arrived are real,
  /// and blanking them would be the same lie in the other direction.
  ///
  /// The list returned is a [SeerrRequestList]: it says how many requests the
  /// server holds and whether a later page went missing, so a count can be
  /// Seerr's own rather than the length of whatever arrived. Declared as a
  /// plain list so that the fakes overriding this, and the providers typed on
  /// it, stay as they are.
  Future<List<SeerrRequest>> getRequests() async {
    // Asked beside the pages rather than before them: a page waits for it
    // only to decode its rows, never to be sent.
    final numberingRead = numbering();
    final first = await _requestPage(0, numbering: numberingRead);
    final total = first.total;
    final all = <SeerrRequest>[...first.items];
    var isPartial = false;

    // The server reports the true count on the first page, so the remaining
    // pages can all be asked for in parallel. With no count there is nothing
    // to page towards, and the first page is all that can be claimed.
    if (total != null) {
      final pages = await Future.wait([
        for (
          var skip = _requestPageSize;
          skip < total;
          skip += _requestPageSize
        )
          _requestPageSafely(skip, numbering: numberingRead),
      ]);
      for (final page in pages) {
        if (page == null) {
          isPartial = true;
          continue;
        }
        all.addAll(page.items);
      }
    }

    return SeerrRequestList(
      await _hydrateRequests(all),
      total: total,
      isPartial: isPartial,
    );
  }

  Future<({List<SeerrRequest> items, int? total})> _requestPage(
    int skip, {
    required Future<SeerrNumbering?> numbering,
  }) async {
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
    // Null when the server did not say, never 0: a zero here used to end the
    // walk after the first page and stand in for a count nobody gave.
    final total = pageInfo is Map ? _asInt(pageInfo['results']) : null;
    final decodeWith = await numbering;
    final items = results
        .map((e) {
          try {
            return SeerrRequest.fromJson(e, numbering: decodeWith);
          } catch (e) {
            return null;
          }
        })
        .whereType<SeerrRequest>()
        .toList(growable: false);
    return (items: items, total: total);
  }

  /// A later page failing must not blank the requests that did arrive — the
  /// caller gets the pages that answered and moves on. Null for a page that
  /// did not, so the caller can say the list is short; it used to come back
  /// as an empty page, which nothing could tell from the end of the list.
  Future<({List<SeerrRequest> items, int? total})?> _requestPageSafely(
    int skip, {
    required Future<SeerrNumbering?> numbering,
  }) async {
    try {
      return await _requestPage(skip, numbering: numbering);
    } catch (_) {
      return null;
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
  ///
  /// **Throws when Seerr did not answer, or answered with a failure.** It used
  /// to answer every failure with `[]`, so a rail whose source was dark was a
  /// rail with nothing in it, and the Discover page quietly lost it. An empty
  /// list now means Seerr answered with none.
  Future<List<MediaPreview>> _discover(
    String path, {
    required int page,
    int? genre,
    String? sortBy,
    String? forcedMediaType,
  }) async {
    final response = await _client.get(
      path,
      queryParameters: {'page': page, 'genre': ?genre, 'sortBy': ?sortBy},
    );
    return _mapPreviews(_resultsOf(response.data), forcedMediaType);
  }

  /// The `results` array of a Seerr list response, or a [FormatException] —
  /// an answer nobody can read — when the body is not one.
  static List<dynamic> _resultsOf(Object? data) {
    final results = data is Map ? data['results'] : null;
    if (results is List) return results;
    throw const FormatException('Seerr answered without a results list');
  }

  /// A Seerr 404 is an answer: the TMDB record it proxies does not exist.
  static bool _isNotFound(Object error) =>
      error is DioException && error.response?.statusCode == 404;

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

  /// Throws when Seerr did not answer or answered with a failure, like
  /// [_discover]: the genre rows are rails too.
  Future<List<SeerrGenre>> _getGenres(String mediaType) async {
    final response = await _client.get(
      '/api/v1/discover/genreslider/$mediaType',
    );
    final results = response.data;
    if (results is! List) {
      throw const FormatException('Seerr answered without a genre list');
    }
    return results
        .whereType<Map<String, dynamic>>()
        .map(SeerrGenre.fromJson)
        .where((g) => g.id > 0 && g.name.isNotEmpty)
        .toList();
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

  /// A collection and its member films, `{}` when Seerr answered that there is
  /// no such collection (404).
  ///
  /// **Throws for every other failure.** It used to answer all of them with
  /// `{}`, so a Seerr that did not answer read "Seerr answered, but it has
  /// nothing filed under this collection" — an answer nobody gave.
  Future<Map<String, dynamic>> getCollection(int collectionId) async {
    try {
      final response = await _client.get('/api/v1/collection/$collectionId');
      final data = response.data;
      return data is Map ? data.cast<String, dynamic>() : {};
    } catch (error) {
      if (_isNotFound(error)) return {};
      rethrow;
    }
  }

  /// TMDB person details (bio, department, birthday) proxied by Overseerr /
  /// Jellyseerr; `{}` when Seerr answered that it has no such person (404).
  ///
  /// **Throws for every other failure**, for the reason [getCollection] does:
  /// "Seerr answered, but it has no record of them" is only true when it did.
  Future<Map<String, dynamic>> getPerson(int personId) async {
    try {
      final response = await _client.get('/api/v1/person/$personId');
      final data = response.data;
      return data is Map ? data.cast<String, dynamic>() : {};
    } catch (error) {
      if (_isNotFound(error)) return {};
      rethrow;
    }
  }

  /// A person's combined movie + TV credits, cast **and** crew, each with the
  /// job or character it was credited for and Seerr's own status for the
  /// title. [PersonCombinedCredits.empty] when Seerr answered with none (a
  /// 404 included); throws when it did not answer or answered with a failure,
  /// so a dark Seerr is not an empty filmography.
  ///
  /// The route is `combined_credits`, snake case (Seerr's
  /// `server/routes/person.ts`). This used to ask for `combinedCredits`, which
  /// Seerr answers with a 404, so every Person page drew an empty filmography.
  Future<PersonCombinedCredits> getPersonCredits(int personId) async {
    try {
      final numberingRead = numbering();
      final response = await _client.get(
        '/api/v1/person/$personId/combined_credits',
      );
      final data = response.data;
      if (data is! Map) return PersonCombinedCredits.empty;
      return PersonCombinedCredits.fromJson(
        data.cast<String, dynamic>(),
        numbering: await numberingRead,
      );
    } catch (error) {
      if (_isNotFound(error)) return PersonCombinedCredits.empty;
      rethrow;
    }
  }

  /// A person's combined movie + TV cast filmography, de-duped by id and sorted
  /// by rating so the strongest credits lead. Returns `[]` on error.
  Future<List<MediaPreview>> getPersonCombinedCredits(int personId) async {
    return (await getPersonCredits(personId)).castFilmography;
  }

  /// Searches for movies and TV shows by query string.
  /// Filters out 'person' results to only return movies and TV shows.
  ///
  /// [cancelToken] aborts the request once the search that asked for it has
  /// been superseded: global search re-runs every service leg on each debounced
  /// keystroke, and a discarded round should stop paying for itself rather than
  /// run to completion.
  ///
  /// [reportFailure] decides whether a Seerr that did not answer is allowed to
  /// look like a Seerr that found nothing — the same switch, the same default
  /// and the same reasoning as `BaseArrService.lookupItems`, which the three arr
  /// lookups already took and this one did not.
  ///
  /// The default keeps the old behaviour on purpose: inside Seerr's own
  /// search-as-you-type field the user is mid-word, the box is theirs, and an
  /// error card that appears and vanishes between keystrokes is noise. It was
  /// the wrong behaviour for the **global** search, which draws one lane per
  /// connection. This method used to swallow every failure unconditionally, so
  /// an unreachable Seerr, a Seerr that refused the API key and a Seerr with no
  /// match all produced one empty list: the lane could only ever say "no
  /// results", and there was nothing for it to colour red. Pass true and the
  /// failure travels, cancellation included — a superseded round is a
  /// `DioException` of type `cancel`, which the caller that cancelled it already
  /// knows how to tell from a dead server.
  Future<List<MediaPreview>> search(
    String query, {
    int page = 1,
    CancelToken? cancelToken,
    bool reportFailure = false,
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
    } catch (_) {
      if (reportFailure) rethrow;
      return [];
    }
  }

  /// The Radarr servers Seerr sends requests to. An empty list means Seerr
  /// answered with none; a failure throws.
  ///
  /// It used to answer every failure with `[]`, so the request sheet said "no
  /// Radarr servers" — in red — about a Seerr that had not answered at all.
  Future<List<Map<String, dynamic>>> getRadarrServers() =>
      _servers('/api/v1/service/radarr');

  /// The Sonarr servers Seerr sends requests to. See [getRadarrServers].
  Future<List<Map<String, dynamic>>> getSonarrServers() =>
      _servers('/api/v1/service/sonarr');

  Future<List<Map<String, dynamic>>> _servers(String path) async {
    final response = await _client.get(path);
    final data = response.data;
    if (data is! List) {
      throw const FormatException('Seerr answered without a server list');
    }
    return data.whereType<Map<String, dynamic>>().toList(growable: false);
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
