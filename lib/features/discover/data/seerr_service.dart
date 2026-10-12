import 'dart:collection';
import 'dart:isolate';
import 'package:dio/dio.dart';
import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/features/discover/data/seerr_session.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/discover/domain/catalog_query.dart';
import 'package:cupola/features/discover/domain/models/person_credits.dart';
import 'package:cupola/features/discover/domain/models/seerr_genre.dart';
import 'package:cupola/features/discover/domain/models/seerr_admin_models.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/domain/seerr_arr_server.dart';
import 'package:cupola/features/discover/domain/seerr_known_arr.dart';
import 'package:cupola/features/discover/domain/seerr_quota.dart';
import 'package:cupola/features/discover/domain/seerr_refusal.dart';
import 'package:cupola/features/discover/domain/seerr_search.dart';
import 'package:cupola/core/models/media_preview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What a request's row lacks and its title's page has: the name, the year,
/// the artwork and TMDB's score.
typedef _RequestTitle = ({
  String? title,
  String? year,
  String? posterPath,
  String? backdropPath,
  double? voteAverage,
  int? voteCount,
});

/// Thrown when a request has already been acted on somewhere else.
///
/// Worth a type of its own because it is not an error on our side: the same
/// request approved from the web UI a moment earlier, or deleted outright.
/// Seerr answers 404 or 409, and the honest response is to say the state moved
/// and reload, not to report a transport failure for something that already
/// succeeded, by someone else.
///
/// It is not the only way a write fails. A 403 is three different refusals:
/// Seerr's CSRF guard, which the transport answers by itself; an account whose
/// session ended; and an account without the permission. `seerr_session.dart`
/// tells them apart (`SeerrSessionEnded`, `SeerrCsrfRefused`, `SeerrRefused`).
class SeerrRequestConflict implements Exception {
  final String message;

  const SeerrRequestConflict(this.message);

  @override
  String toString() => message;
}

/// Seerr answered a request `202 No seasons available to request`: a
/// success status, and nothing was asked for, because every season of the
/// series is on the server or asked for already.
class SeerrNothingRequested implements Exception {
  const SeerrNothingRequested();

  @override
  String toString() => 'SeerrNothingRequested';
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
/// they map here; the gate exists for a server that answers with more.
const int _seerrIsolateMapThreshold = 200;

/// Maps a decoded discover page, moving to an isolate once it is big enough to
/// be worth the port.
///
/// Top-level rather than a method on purpose: the closure handed to
/// `Isolate.run` must capture only sendable values (here a decoded list and a
/// `String?`), and one written inside an instance method can drag `this`,
/// which holds an [ApiClient], across the boundary.
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
  return SeerrService(watchSeerrClient(ref));
});

/// Seerr bound to one named connection, whatever the lens is pointing at.
///
/// The same shape, and for the same reasons, as `radarrServiceForProvider`;
/// read its comment before touching this one. What it buys here is /activity:
/// the feed lists the requests of every configured Seerr, and a request id is
/// **per instance**, so approving id 42 through the lens approves a different
/// person's request on a different server and reports success.
///
/// Empty id means the lens, which is what the plain [seerrServiceProvider]
/// answers. The lens's own id collapses onto that provider too, rather than
/// opening a second `Dio` at the same address, and, just as load-bearing, so
/// that an override of the plain provider (how the whole suite supplies a fake
/// Seerr) is not quietly bypassed on the path that names a connection.
///
/// `read` of the lens, deliberately: watching it would rebuild every entry of
/// this family whenever the lens moved, entries for connections that did not
/// change, and `watchApiClient` closes the outgoing client on dispose, which
/// would cut a request already in flight. The cost is that an entry minted
/// before the lens landed on its id keeps a client of its own until disposal.
///
/// The client is [watchSeerrClient]'s: the key or the account's session, and
/// the CSRF token either way.
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
  return SeerrService(watchSeerrClient(ref, instanceId: instanceId));
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

  /// `movie:550` → hydrated title metadata. Keyed by kind as well as TMDB
  /// id, since a movie and a series can share the number.
  ///
  /// Without this every refresh re-fetched the details of the same unknown
  /// titles from Seerr's TMDB passthrough: the list only grows, so a refresh
  /// that ran N calls ran N calls every time.
  final Map<String, _RequestTitle> _mediaCache = {};

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

  /// How much of its request quota user [userId] has left: an account asks
  /// for its own (`GET /user/{id}/quota`).
  Future<SeerrQuota> getQuota(int userId) async {
    final response = await _client.get('/api/v1/user/$userId/quota');
    final data = response.data;
    if (data is! Map) throw const FormatException('Seerr sent no quota');
    return SeerrQuota.fromJson(data.cast<String, dynamic>());
  }

  static const _adminPageSize = 50;

  /// Reads every admin page while preserving the distinction between a complete
  /// empty list and a first page followed by a failed later page.
  ///
  /// The first page is awaited alone because it carries `pageInfo.results`:
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
  /// the point of `Future.wait` here: every page is observed, so one refusal
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
  /// with no requests produced byte-identical output, and no caller could tell
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
    final walk = await _walkRequests('all', numbering: numberingRead);
    return SeerrRequestList(
      await _hydrateRequests(walk.items),
      total: walk.total,
      isPartial: walk.isPartial,
    );
  }

  /// The requests still in motion: waiting for approval, being processed, or
  /// failed. What Activity's Now lists.
  ///
  /// Asked of Seerr by its own filters rather than read off [getRequests]:
  /// Now used to page the whole history, every request ever made, and
  /// hydrate each one, to show the handful still moving, and it listed
  /// requests delivered two years ago under "Downloading". Same contract as
  /// [getRequests]: throws when a first page does not come back, and says
  /// when a later one went missing; [SeerrRequestList.total] is the sum of
  /// Seerr's own counts, or null when one of them did not say.
  Future<List<SeerrRequest>> getActiveRequests() async {
    final numberingRead = numbering();
    final walks = await Future.wait([
      for (final filter in activeRequestFilters)
        _walkRequests(filter, numbering: numberingRead),
    ]);
    final seen = <int>{};
    final items = [
      for (final walk in walks)
        for (final request in walk.items)
          if (seen.add(request.id)) request,
    ];
    final totals = [for (final walk in walks) walk.total];
    return SeerrRequestList(
      await _hydrateRequests(items),
      total: totals.contains(null)
          ? null
          : totals.fold<int>(0, (sum, total) => sum + total!),
      isPartial: walks.any((walk) => walk.isPartial),
    );
  }

  /// The requests waiting for a decision, one page of them: what the Home's
  /// Requests module lists.
  ///
  /// One page, never the walk: the module shows a few rows, and states how
  /// many wait from Seerr's own count of them ([SeerrRequestList.total], the
  /// page's `pageInfo.results`), never from the rows. Throws when the page
  /// does not come back.
  Future<List<SeerrRequest>> getPendingRequests() async {
    final page = await _requestPage(
      0,
      numbering: numbering(),
      filter: 'pending',
    );
    return SeerrRequestList(
      await _hydrateRequests(page.items),
      total: page.total,
      // With no count, a full page may have more behind it.
      isPartial: page.total == null && page.items.length >= _requestPageSize,
    );
  }

  /// Seerr's own filters for a request still in motion: waiting for a
  /// decision, approved and being fetched, or failed and needing one.
  static const activeRequestFilters = ['pending', 'processing', 'failed'];

  /// Every page of the requests [filter] selects, the first one throwing.
  Future<({List<SeerrRequest> items, int? total, bool isPartial})>
  _walkRequests(
    String filter, {
    required Future<SeerrNumbering?> numbering,
  }) async {
    final first = await _requestPage(0, numbering: numbering, filter: filter);
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
          _requestPageSafely(skip, numbering: numbering, filter: filter),
      ]);
      for (final page in pages) {
        if (page == null) {
          isPartial = true;
          continue;
        }
        all.addAll(page.items);
      }
    }
    return (items: all, total: total, isPartial: isPartial);
  }

  Future<({List<SeerrRequest> items, int? total})> _requestPage(
    int skip, {
    required Future<SeerrNumbering?> numbering,
    String filter = 'all',
  }) async {
    final response = await _client.get(
      '/api/v1/request',
      queryParameters: {
        'take': _requestPageSize,
        'skip': skip,
        'sort': 'added',
        'filter': filter,
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

  /// A later page failing must not blank the requests that did arrive; the
  /// caller gets the pages that answered and moves on. Null for a page that
  /// did not, so the caller can say the list is short; it used to come back
  /// as an empty page, which nothing could tell from the end of the list.
  Future<({List<SeerrRequest> items, int? total})?> _requestPageSafely(
    int skip, {
    required Future<SeerrNumbering?> numbering,
    String filter = 'all',
  }) async {
    try {
      return await _requestPage(skip, numbering: numbering, filter: filter);
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
    // Seerr's request rows carry no title, so a real one is always
    // hydrated, and takes its artwork and score with it.
    if (!needsTitle && media.posterPath != null) return request;

    final tmdbId = media.tmdbId;
    if (tmdbId == null) return request;

    final key = '${media.mediaType}:$tmdbId';
    final cached = _mediaCache[key];
    if (cached != null) {
      return _applyHydration(request, cached);
    }

    try {
      final movie = media.mediaType == 'movie';
      if (!movie && media.mediaType != 'tv') return request;
      final details = movie ? await getMovie(tmdbId) : await getTv(tmdbId);
      final entry = _mediaCache[key] = (
        title: details[movie ? 'title' : 'name']?.toString(),
        year: details[movie ? 'releaseDate' : 'firstAirDate']
            ?.toString()
            .substring(0, 4),
        posterPath:
            details['posterPath']?.toString() ??
            details['poster_path']?.toString(),
        backdropPath:
            details['backdropPath']?.toString() ??
            details['backdrop_path']?.toString(),
        voteAverage: doubleOrNull(
          details['voteAverage'] ?? details['vote_average'],
        ),
        voteCount: intOrNull(details['voteCount'] ?? details['vote_count']),
      );
      return _applyHydration(request, entry);
    } catch (e) {
      // Ignore hydration errors
      return request;
    }
  }

  SeerrRequest _applyHydration(SeerrRequest request, _RequestTitle entry) {
    final media = request.media;
    if (media == null) return request;
    return request.copyWith(
      media: media.copyWith(
        title: entry.title ?? media.title,
        year: entry.year ?? media.year,
        posterPath: entry.posterPath ?? media.posterPath,
        backdropPath: entry.backdropPath,
        voteAverage: entry.voteAverage,
        voteCount: entry.voteCount,
      ),
    );
  }

  /// One request, as Seerr holds it now: its server, profile and folder, and
  /// whether it is still waiting. A 404 is a request removed elsewhere, and
  /// reads as the [SeerrRequestConflict] it is.
  Future<SeerrRequest> getRequest(int requestId) async {
    final numberingRead = numbering();
    try {
      final response = await _client.get('/api/v1/request/$requestId');
      final data = response.data;
      if (data is! Map) {
        throw const FormatException('Seerr answered without a request');
      }
      return SeerrRequest.fromJson(
        data.cast<String, dynamic>(),
        numbering: await numberingRead,
      );
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) {
        throw const SeerrRequestConflict(
          'That request had already been updated somewhere else.',
        );
      }
      rethrow;
    }
  }

  /// The servers Seerr sends [arr] requests to, with their addresses: Seerr's
  /// own settings (`GET /api/v1/settings/radarr` or `/sonarr`, admin only).
  ///
  /// An empty list means Seerr answered with none; a failure throws. Each
  /// server carries this Seerr's address and the key Seerr uses for it, to
  /// tell which of Cupola's connections it is and nothing else: see
  /// [SeerrArrServer.reaches].
  Future<List<SeerrArrServer>> getArrServers(ServiceKey arr) async {
    if (arr != ServiceKey.radarr && arr != ServiceKey.sonarr) {
      throw ArgumentError.value(arr, 'arr', 'Seerr sends only to the arrs');
    }
    final response = await _client.get(
      arr == ServiceKey.radarr
          ? '/api/v1/settings/radarr'
          : '/api/v1/settings/sonarr',
    );
    final data = response.data;
    if (data is! List) {
      throw const FormatException('Seerr answered without a server list');
    }
    return [
      for (final raw in data)
        if (raw is Map)
          SeerrArrServer.fromSettingsJson(
            raw.cast<String, dynamic>(),
            service: arr,
            seenFrom: _client.baseUrl,
          ),
    ];
  }

  /// The Radarr and Sonarr servers Seerr knows, each with the address Seerr
  /// reaches it at and the key it reaches it with: Seerr's own settings
  /// (`GET /api/v1/settings/radarr` and `/sonarr`), Radarr's first.
  ///
  /// Admin only. A household member's session, or any account without
  /// ADMIN, gets [SeerrKnownArrsNotAllowed]: Seerr answered, and said no.
  /// Never an empty list, which would claim Seerr knows nothing, and never a
  /// failure, which would read as a server that did not answer. A surface
  /// that holds the account's grant need not ask at all
  /// (`SeerrAbility.readSettings`).
  ///
  /// The API key is user 1, an admin, so it always may: a refusal there is
  /// the key refused, and throws as one. Every other failure throws too,
  /// classified as any Seerr read is, an ended session included.
  ///
  /// The keys are secrets: see [SeerrKnownArr].
  Future<SeerrKnownArrs> knownServers() async {
    Future<({List<SeerrKnownArr>? servers, Object? error, StackTrace? stack})>
    read(ServiceKey arr) async {
      try {
        return (servers: await _knownArrs(arr), error: null, stack: null);
      } catch (error, stack) {
        return (servers: null, error: error, stack: stack);
      }
    }

    final reads = await Future.wait([
      read(ServiceKey.radarr),
      read(ServiceKey.sonarr),
    ]);
    // The session transport has already asked `/auth/me` and decided that
    // the account lacks the permission, rather than that its session ended.
    bool notAllowed(Object? error) =>
        error is DioException && error.error is SeerrRefused;
    if (reads.any((r) => notAllowed(r.error))) {
      return const SeerrKnownArrsNotAllowed();
    }
    for (final r in reads) {
      if (r.error case final error?) {
        Error.throwWithStackTrace(error, r.stack ?? StackTrace.current);
      }
    }
    return SeerrKnownArrsRead(
      List.unmodifiable([for (final r in reads) ...?r.servers]),
    );
  }

  Future<List<SeerrKnownArr>> _knownArrs(ServiceKey arr) async {
    final response = await _client.get(
      arr == ServiceKey.radarr
          ? '/api/v1/settings/radarr'
          : '/api/v1/settings/sonarr',
    );
    final data = response.data;
    if (data is! List) {
      throw const FormatException('Seerr answered without a server list');
    }
    return [
      for (final raw in data)
        if (raw is Map)
          SeerrKnownArr.fromSettingsJson(
            raw.cast<String, dynamic>(),
            service: arr,
            seenFrom: _client.baseUrl,
          ),
    ];
  }

  Future<void> deleteRequest(int requestId) async {
    await _guardConflict(() => _client.delete('/api/v1/request/$requestId'));
  }

  /// Puts a title on the watchlist of the user this connection acts as
  /// (`POST /api/v1/watchlist`; "chi sei in Seerr" decides who that is). A
  /// failure travels.
  Future<void> addToWatchlist({
    required int tmdbId,
    required String mediaType,
    required String title,
  }) async {
    await _client.post(
      '/api/v1/watchlist',
      data: {'tmdbId': tmdbId, 'mediaType': mediaType, 'title': title},
    );
  }

  /// Takes a title off that watchlist (`DELETE /api/v1/watchlist/:tmdbId`,
  /// which Seerr refuses without the media type). A failure travels.
  Future<void> removeFromWatchlist({
    required int tmdbId,
    required String mediaType,
  }) async {
    await _client.delete(
      '/api/v1/watchlist/$tmdbId',
      queryParameters: {'mediaType': mediaType},
    );
  }

  /// Approves a request that is waiting for approval.
  ///
  /// Seerr then sends it to the server [SeerrApproveTarget] names: the one the
  /// request carries, or the default of its resolution. That is why Activity
  /// can show a request turning into a queue row minutes later.
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

  /// The one body of a list of titles that is not a catalogue page: Seerr
  /// room's trending rail and a title's recommendations. They differ only in
  /// path and in the media type forced onto rows that carry none; a
  /// catalogue page, with its filters and its totals, is [getCatalogPage].
  ///
  /// **Throws when Seerr did not answer, or answered with a failure.** It used
  /// to answer every failure with `[]`, so a rail whose source was dark was a
  /// rail with nothing in it, and the Discover page quietly lost it. An empty
  /// list now means Seerr answered with none.
  Future<List<MediaPreview>> _discover(
    String path, {
    required int page,
    String? forcedMediaType,
  }) async {
    final response = await _client.get(path, queryParameters: {'page': page});
    // Every rail this reads is a rail of titles, and trending is TMDB's,
    // which mixes people in with them. A person kept here opened as the movie
    // her id happens to name, and led the featured banner when she trended
    // first.
    return _mapPreviews(
      _resultsOf(response.data).where(_isTitle).toList(growable: false),
      forcedMediaType,
    );
  }

  /// Whether one discover result is a film or a series rather than a person.
  static bool _isTitle(Object? result) {
    final type = result is Map
        ? result['mediaType'] ?? result['media_type']
        : null;
    return type != 'person';
  }

  /// The `results` array of a Seerr list response, or a [FormatException],
  /// an answer nobody can read, when the body is not one.
  static List<dynamic> _resultsOf(Object? data) {
    final results = data is Map ? data['results'] : null;
    if (results is List) return results;
    throw const FormatException('Seerr answered without a results list');
  }

  /// A Seerr 404 is an answer: the TMDB record it proxies does not exist.
  static bool _isNotFound(Object error) =>
      error is DioException && error.response?.statusCode == 404;

  /// The movie genres, each with a few backdrops (`/discover/genreslider`).
  Future<List<SeerrGenre>> getMovieGenres() => _getGenres('movie');

  /// The series genres, the same way.
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

  /// One page of a catalogue: a door of the atrium, a "See all", a filter
  /// over either. The titles come with what Seerr says of the whole list,
  /// which the page's foot states (`catalogCountPhrase`).
  ///
  /// Throws when Seerr did not answer or answered with a failure, as
  /// [_discover] does. Trending mixes films and series, and each title keeps
  /// the type it declares; every other base fixes it.
  Future<CatalogPageResult> getCatalogPage(
    CatalogQuery query, {
    int page = 1,
    DateTime? today,
  }) async {
    final response = await _client.get(
      query.path,
      queryParameters: query.parameters(page, today: today ?? DateTime.now()),
    );
    final data = response.data;
    final items = await _mapPreviews(
      _resultsOf(data).where(_isTitle).toList(growable: false),
      query.base == CatalogBase.trending ? null : query.kind.mediaType,
    );
    final body = data as Map;
    return CatalogPageResult(
      items: items,
      page: intOrNull(body['page']) ?? page,
      totalPages: intOrNull(body['totalPages']) ?? page,
      totalResults: intOrNull(body['totalResults']) ?? items.length,
    );
  }

  /// TMDB's recommendations for a title, as Seerr relays them: the first
  /// page, titles only.
  Future<List<MediaPreview>> getRecommendations(String mediaType, int tmdbId) {
    return _discover(
      '/api/v1/$mediaType/$tmdbId/recommendations',
      page: 1,
      forcedMediaType: mediaType,
    );
  }

  Future<Map<String, dynamic>> getMovie(int movieId) async {
    final response = await _client.get('/api/v1/movie/$movieId');
    return response.data;
  }

  Future<Map<String, dynamic>> getTv(int tvId) async {
    final response = await _client.get('/api/v1/tv/$tvId');
    return response.data;
  }

  /// One season of a series as TMDB keeps it (`/tv/:id/season/:n`): its
  /// episodes with their stills, synopses and votes. Throws on a remote
  /// failure.
  Future<Map<String, dynamic>> getTvSeason(int tvId, int season) async {
    final response = await _client.get('/api/v1/tv/$tvId/season/$season');
    return response.data;
  }

  /// Rotten Tomatoes' critics score for a series (`/tv/:id/ratings`), 0..100;
  /// null when Rotten Tomatoes has none for it. Throws on a remote failure.
  Future<int?> getTvCriticsScore(int tvId) async {
    final response = await _client.get('/api/v1/tv/$tvId/ratings');
    final data = response.data;
    final score = data is Map ? data['criticsScore'] : null;
    return score is num && score > 0 ? score.round() : null;
  }

  /// A collection and its member films, `{}` when Seerr answered that there is
  /// no such collection (404).
  ///
  /// **Throws for every other failure.** It used to answer all of them with
  /// `{}`, so a Seerr that did not answer read "Seerr answered, but it has
  /// nothing filed under this collection", an answer nobody gave.
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
      final response = await _client.get(
        '/api/v1/person/$personId/combined_credits',
      );
      final data = response.data;
      if (data is! Map) return PersonCombinedCredits.empty;
      return PersonCombinedCredits.fromJson(data.cast<String, dynamic>());
    } catch (error) {
      if (_isNotFound(error)) return PersonCombinedCredits.empty;
      rethrow;
    }
  }

  /// Searches TMDB through Seerr: the first page of movies, series and
  /// people, each in Seerr's order. A Seerr that did not answer, or refused,
  /// throws: a Seerr that found nothing is an empty answer, never the same
  /// fact as one that is off.
  ///
  /// [cancelToken] aborts the request once the search that asked for it has
  /// been superseded: the global search runs again on each debounced
  /// keystroke, and a discarded round should stop paying for itself. A
  /// superseded round is a `DioException` of type `cancel`, which the caller
  /// that cancelled it knows how to tell from a dead server.
  ///
  /// The text is encoded here and again by Dio: Seerr refuses a space, an `&`
  /// or an apostrophe encoded once ("must be url encoded").
  Future<SeerrSearchAnswer> search(
    String query, {
    CancelToken? cancelToken,
  }) async {
    if (query.isEmpty) return const SeerrSearchAnswer();
    final response = await _client.get(
      '/api/v1/search',
      queryParameters: {'query': Uri.encodeComponent(query), 'page': 1},
      cancelToken: cancelToken,
    );
    final titles = <MediaPreview>[];
    final people = <SeerrSearchPerson>[];
    bool? personFirst;
    for (final result in _resultsOf(response.data)) {
      if (result is! Map) continue;
      final json = result.cast<String, dynamic>();
      final mediaType = json['mediaType'] ?? json['media_type'];
      if (mediaType == 'movie' || mediaType == 'tv') {
        titles.add(MediaPreview.fromJson(json));
        personFirst ??= false;
      } else if (mediaType == 'person') {
        if (SeerrSearchPerson.fromJson(json) case final person?) {
          people.add(person);
          personFirst ??= true;
        }
      }
    }
    return SeerrSearchAnswer(
      titles: titles,
      people: people,
      leadsWithPeople: personFirst ?? false,
    );
  }

  /// TMDB's id of the series TVDB knows as [tvdbId], by Seerr's `tvdb:`
  /// search; null when Seerr finds none. A failure throws.
  ///
  /// Encoded once, unlike [search]: Seerr matches `tvdb:` on the query as it
  /// arrives, so the double encoding a typed term needs (Seerr refuses a
  /// space or an `&` encoded once) would hide the prefix and find nothing.
  Future<int?> findTvByTvdbId(int tvdbId) async {
    final response = await _client.get(
      '/api/v1/search',
      queryParameters: {'query': 'tvdb:$tvdbId', 'page': 1},
    );
    final results = mapOrNull(response.data)?['results'];
    if (results is! List) return null;
    for (final result in results) {
      final row = mapOrNull(result);
      if ((row?['mediaType'] ?? row?['media_type']) != 'tv') continue;
      final id = intOrNull(row?['id']);
      if (id != null && id > 0) return id;
    }
    return null;
  }

  /// The Radarr servers Seerr sends requests to. An empty list means Seerr
  /// answered with none; a failure throws.
  ///
  /// It used to answer every failure with `[]`, so the request sheet said "no
  /// Radarr servers" in red, about a Seerr that had not answered at all.
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
    List<int>? seasons, // A series' seasons; null asks for every one
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

    final response = await _client.post('/api/v1/request', data: body);
    // A success status that asked for nothing: every season is on the
    // server or asked for already, and no request was made.
    if (classifySeerrRefusal(
          status: response.statusCode,
          method: 'POST',
          path: '/api/v1/request',
          body: response.data,
        ) ==
        SeerrRefusal.noSeasonsLeft) {
      throw const SeerrNothingRequested();
    }
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
  ///
  /// [is4k] says which copy: Seerr removes the one it keeps on the 4K server
  /// only when asked to (`?is4k=true`), and the standard one otherwise. This
  /// used to send neither, so removing a 4K copy removed the standard one.
  Future<void> deleteMediaFile(int mediaId, {bool is4k = false}) async {
    await _client.delete(
      '/api/v1/media/$mediaId/file',
      queryParameters: {'is4k': is4k ? 'true' : 'false'},
    );
  }
}
