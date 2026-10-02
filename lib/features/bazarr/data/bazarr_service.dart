import 'package:dio/dio.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/features/bazarr/domain/models/bazarr_models.dart';

/// Service for interacting with the Bazarr API.
///
/// Bazarr is intentionally NOT modeled via the *arr activity mixin because the
/// envelope shape and data model diverge (e.g. episodes/movies wanted, badges
/// count). The Riverpod provider wiring lives in `bazarr_provider.dart`; this
/// file only defines the transport class.
class BazarrService {
  final ApiClient client;

  BazarrService(this.client);

  /// Returns aggregated counts exposed by the navbar (episodes/movies wanted
  /// plus signalR/provider indicators).
  Future<BazarrBadges> getBadges() async {
    final response = await client.get('/api/badges');
    final raw = response.data;
    if (raw is Map<String, dynamic>) {
      return BazarrBadges.fromJson(raw);
    }
    // Not a zero. A body that is not the badge map — a proxy's login page, an
    // HTML error — answered this with all-zero badges, and the rail printed
    // "Wanted 0" for a Bazarr that had said nothing about its backlog.
    throw Exception('Bazarr returned an unreadable badge payload');
  }

  /// Returns the aggregate configured-provider count exposed by `/api/badges`.
  ///
  /// This is intentionally separate from [getProviderStatuses]: Bazarr's
  /// `/api/providers` response reports providers currently carrying throttle
  /// or degraded status, not a complete configured-provider registry. Healthy
  /// provider names, quotas and throttle windows therefore remain unavailable
  /// rather than guessed.
  Future<BazarrProviderSummary> getProviderSummary() async {
    final response = await client.get('/api/badges');
    final raw = response.data;
    if (raw is Map<String, dynamic>) {
      return BazarrProviderSummary.fromJson(raw);
    }
    return const BazarrProviderSummary();
  }

  /// Returns the providers Bazarr currently reports as throttled or degraded.
  ///
  /// The upstream endpoint intentionally does not return every configured
  /// provider on the default request; the configured count still comes from
  /// `/api/badges`. Keeping these as two contracts lets the UI distinguish
  /// "no provider needs attention" from "the status request failed".
  Future<List<BazarrProviderStatus>> getProviderStatuses() async {
    final response = await client.get('/api/providers');
    final raw = response.data;
    final data = raw is Map ? raw['data'] : raw;
    if (data is! List) return const [];
    return data
        .map(BazarrProviderStatus.fromJson)
        .where((provider) => provider.name != null)
        .toList(growable: false);
  }

  /// Clears Bazarr's provider throttle state.
  Future<void> resetProviderStatuses() async {
    await client.post('/api/providers', queryParameters: {'action': 'reset'});
  }

  /// Paged list of series known to Bazarr.
  Future<BazarrPagedResult<BazarrSeries>> getSeries({
    int start = 0,
    int length = 50,
  }) async {
    final response = await client.get(
      '/api/series',
      queryParameters: {'start': start, 'length': length},
    );
    return _parsePaged(response.data, BazarrSeries.fromJson, start: start);
  }

  /// Paged list of movies known to Bazarr.
  Future<BazarrPagedResult<BazarrMovie>> getMovies({
    int start = 0,
    int length = 50,
  }) async {
    final response = await client.get(
      '/api/movies',
      queryParameters: {'start': start, 'length': length},
    );
    return _parsePaged(response.data, BazarrMovie.fromJson, start: start);
  }

  /// The series Bazarr follows under [sonarrSeriesId], or null when it
  /// follows none.
  ///
  /// Asked by id (`seriesid[]`), which `/api/series` has taken since Bazarr
  /// 1.0: the detail page used to walk the whole library, 500 series a page,
  /// to find one. The row is still matched here, so a Bazarr that ignored
  /// the filter would answer right, only slower. Throws when Bazarr does not
  /// answer.
  Future<BazarrSeries?> getSeriesById(int sonarrSeriesId) async {
    final response = await client.get(
      '/api/series',
      queryParameters: {'seriesid[]': sonarrSeriesId},
    );
    final page = _parsePaged(response.data, BazarrSeries.fromJson);
    for (final series in page.data) {
      if (series.sonarrSeriesId == sonarrSeriesId) return series;
    }
    return null;
  }

  /// The movie Bazarr follows under [radarrId], or null. Asked by id
  /// (`radarrid[]`); see [getSeriesById].
  Future<BazarrMovie?> getMovieById(int radarrId) async {
    final response = await client.get(
      '/api/movies',
      queryParameters: {'radarrid[]': radarrId},
    );
    final page = _parsePaged(response.data, BazarrMovie.fromJson);
    for (final movie in page.data) {
      if (movie.radarrId == radarrId) return movie;
    }
    return null;
  }

  /// Client-side search across the Bazarr library.
  ///
  /// Bazarr exposes no search endpoint, so matching happens here, against a
  /// cached snapshot of the library's titles — see [_libraryIndex].
  ///
  /// [cancelToken] is honoured *cooperatively*, and only after the snapshot
  /// resolves: the download itself is shared with whatever query comes next, so
  /// aborting it would abandon the request the successor is waiting on (again,
  /// see [_libraryIndex]). What a superseded caller does skip is scanning a
  /// thousand titles for an answer nobody will read.
  Future<List<BazarrSearchHit>> searchLibrary(
    String query, {
    int length = _searchIndexLength,
    CancelToken? cancelToken,
  }) async {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return const [];

    final index = await _libraryIndex(length);
    if (cancelToken?.isCancelled ?? false) return const [];
    return index
        .where((hit) => hit.title.toLowerCase().contains(needle))
        .toList(growable: false);
  }

  /// Every title Bazarr knows, as `(id, title, isMovie)` triples.
  ///
  /// Two mechanisms, both about the same problem: with no server-side search,
  /// one query means downloading the whole series list *and* the whole movie
  /// list, and the global search surface re-runs its query on every debounced
  /// keystroke pause. That turned typing one title into several thousand
  /// records over the wire.
  ///
  /// **The snapshot is reused for [_searchIndexTtl].** Library membership does
  /// not churn on a typing timescale — a series added while the user is midway
  /// through a word is not what the search is for — so after the first query a
  /// keystroke costs nothing at all.
  ///
  /// **A fetch already in flight is shared, not restarted.** This is also why
  /// the fetch deliberately takes no `CancelToken`: cancelling the in-flight
  /// download when a superseded query is discarded would abort the very request
  /// the *next* query is waiting on, and the round would start over. Sharing it
  /// gets what cancellation was after — one download, not one per keystroke —
  /// without that trade.
  Future<List<BazarrSearchHit>> _libraryIndex(int length) {
    final cached = _searchIndex;
    final cachedAt = _searchIndexAt;
    if (cached != null &&
        cachedAt != null &&
        _searchIndexLengthUsed == length &&
        DateTime.now().difference(cachedAt) < _searchIndexTtl) {
      return Future.value(cached);
    }

    return _searchIndexInFlight ??= _fetchLibraryIndex(length);
  }

  Future<List<BazarrSearchHit>> _fetchLibraryIndex(int length) async {
    try {
      final (series, movies) = await (
        getSeries(length: length),
        getMovies(length: length),
      ).wait;

      final hits = <BazarrSearchHit>[
        for (final item in series.data)
          if (item.title case final title? when title.isNotEmpty)
            BazarrSearchHit(
              id: item.sonarrSeriesId,
              title: title,
              isMovie: false,
            ),
        for (final item in movies.data)
          if (item.title case final title? when title.isNotEmpty)
            BazarrSearchHit(id: item.radarrId, title: title, isMovie: true),
      ];

      _searchIndex = hits;
      _searchIndexAt = DateTime.now();
      _searchIndexLengthUsed = length;
      return hits;
    } finally {
      // Released whether the fetch succeeded or threw: a failed round must not
      // leave every later query awaiting a future that already lost.
      _searchIndexInFlight = null;
    }
  }

  /// How long a library snapshot stays usable for search.
  static const _searchIndexTtl = Duration(minutes: 2);

  /// Page size of the snapshot. Large enough to hold an ordinary library in one
  /// round trip; a smaller window would silently drop titles from the results.
  static const _searchIndexLength = 500;

  List<BazarrSearchHit>? _searchIndex;
  DateTime? _searchIndexAt;
  int? _searchIndexLengthUsed;
  Future<List<BazarrSearchHit>>? _searchIndexInFlight;

  /// Paged list of missing episode subtitles.
  Future<BazarrPagedResult<BazarrWantedItem>> getWantedEpisodes({
    int start = 0,
    int length = 50,
  }) async {
    final response = await client.get(
      '/api/episodes/wanted',
      queryParameters: {'start': start, 'length': length},
    );
    return _parsePaged(response.data, BazarrWantedItem.fromJson, start: start);
  }

  /// The episodes of one series that want subtitles, as Bazarr's Wanted
  /// lists them.
  ///
  /// `/api/episodes/wanted` filters by episode, never by series, so this asks
  /// for the series' episodes first (`/api/episodes?seriesid[]=`), keeps
  /// those missing a subtitle, and asks Wanted for those ids only, which
  /// leaves Bazarr's own exclusions (monitored, tags, series type) to Bazarr.
  /// Two reads bounded by the series, where the detail page used to walk the
  /// whole Wanted list. The ids go in chunks, so a long series never makes a
  /// URL a proxy refuses. Throws when Bazarr does not answer.
  Future<List<BazarrWantedItem>> getWantedEpisodesForSeries(
    int sonarrSeriesId,
  ) async {
    final response = await client.get(
      '/api/episodes',
      queryParameters: {'seriesid[]': sonarrSeriesId},
    );
    final episodes = mapOrNull(response.data)?['data'];
    final missing = <int>[
      if (episodes is List)
        for (final episode in episodes.whereType<Map>())
          if (_wantsSubtitles(episode)) ?intOrNull(episode['sonarrEpisodeId']),
    ];
    if (missing.isEmpty) return const [];
    final pages = await Future.wait([
      for (var i = 0; i < missing.length; i += _wantedIdChunk)
        client.get(
          '/api/episodes/wanted',
          queryParameters: {
            'episodeid[]': ListParam<int>(
              missing.sublist(
                i,
                i + _wantedIdChunk < missing.length
                    ? i + _wantedIdChunk
                    : missing.length,
              ),
              ListFormat.multi,
            ),
          },
        ),
    ]);
    return [
      for (final page in pages)
        for (final item in _parsePaged(
          page.data,
          BazarrWantedItem.fromJson,
        ).data)
          if (item.sonarrSeriesId == sonarrSeriesId) item,
    ];
  }

  /// Episode ids per Wanted read: about 2 KB of query string.
  static const _wantedIdChunk = 100;

  static bool _wantsSubtitles(Map<dynamic, dynamic> episode) {
    final missing = episode['missing_subtitles'];
    return missing is List && missing.isNotEmpty;
  }

  /// The Wanted entry of the movie Bazarr follows under [radarrId], or null
  /// when it wants nothing for it. Asked by id (`radarrid[]`), which
  /// `/api/movies/wanted` takes; see [getSeriesById].
  Future<BazarrWantedItem?> getWantedMovieById(int radarrId) async {
    final response = await client.get(
      '/api/movies/wanted',
      queryParameters: {'radarrid[]': radarrId},
    );
    final page = _parsePaged(response.data, BazarrWantedItem.fromJson);
    for (final item in page.data) {
      if (item.radarrId == radarrId) return item;
    }
    return null;
  }

  /// Paged list of missing movie subtitles.
  Future<BazarrPagedResult<BazarrWantedItem>> getWantedMovies({
    int start = 0,
    int length = 50,
  }) async {
    final response = await client.get(
      '/api/movies/wanted',
      queryParameters: {'start': start, 'length': length},
    );
    return _parsePaged(response.data, BazarrWantedItem.fromJson, start: start);
  }

  /// Returns recent history events for episodes.
  Future<BazarrPagedResult<Map<String, dynamic>>> getEpisodesHistory({
    int start = 0,
    int length = 50,
  }) async {
    final response = await client.get(
      '/api/episodes/history',
      queryParameters: {'start': start, 'length': length},
    );
    return _parsePaged(response.data, (m) => m, start: start);
  }

  /// Returns recent history events for movies.
  Future<BazarrPagedResult<Map<String, dynamic>>> getMoviesHistory({
    int start = 0,
    int length = 50,
  }) async {
    final response = await client.get(
      '/api/movies/history',
      queryParameters: {'start': start, 'length': length},
    );
    return _parsePaged(response.data, (m) => m, start: start);
  }

  /// Typed episode history used by the full History tab.
  ///
  /// The raw spelling stays available for older callers and test doubles; this
  /// wrapper is deliberately expressed through it so those overrides keep
  /// working while new UI never has to cast Bazarr's maps itself.
  Future<BazarrPagedResult<BazarrHistoryItem>> getEpisodeHistoryItems({
    int start = 0,
    int length = 50,
  }) async {
    final page = await getEpisodesHistory(start: start, length: length);
    return BazarrPagedResult(
      data: page.data
          .map(BazarrHistoryItem.fromEpisodeMap)
          .toList(growable: false),
      total: page.total,
      start: page.start,
    );
  }

  /// Typed movie history used by the full History tab.
  Future<BazarrPagedResult<BazarrHistoryItem>> getMovieHistoryItems({
    int start = 0,
    int length = 50,
  }) async {
    final page = await getMoviesHistory(start: start, length: length);
    return BazarrPagedResult(
      data: page.data
          .map(BazarrHistoryItem.fromMovieMap)
          .toList(growable: false),
      total: page.total,
      start: page.start,
    );
  }

  // Bazarr's write layer does not exist here, and two commissioned decisions
  // sit behind it. Naming the calls is the deliverable until they land; a pill
  // over an empty list and a Sync button with nothing behind it would both be
  // controls that fail, which is worse than their absence.
  //
  // DECISION 22 — History and Blacklist are one tab with a pill, so Bazarr
  // keeps six tabs. Neutral throughout: blacklisting is a choice, not a fault.
  // Missing:
  //   GET    /api/episodes/blacklist   (paged, same envelope as the histories)
  //   GET    /api/movies/blacklist
  //   DELETE /api/episodes/blacklist   ({provider, subs_id}) — the row's ✕
  //   DELETE /api/movies/blacklist
  //   POST   /api/episodes/blacklist   — blacklist-and-search from a history
  //   POST   /api/movies/blacklist       row, the action that makes the list
  //                                      worth having
  //
  // DECISION 23 — one Sync action per subtitle row, on the detail. The Feature
  // map had left it out and the detail drew it; the detail was right. Missing:
  //   PATCH  /api/subtitles  ({action: 'sync', language, path, type, id})
  // and, for the rest of the row's verbs the same boards draw:
  //   PATCH  /api/episodes/subtitles / /api/movies/subtitles  (search one)
  //   POST   /api/episodes/subtitles / /api/movies/subtitles  (upload)
  //   DELETE /api/episodes/subtitles / /api/movies/subtitles  (remove)
  //
  // The models are as thin as the client: `BazarrWantedItem` carries the
  // missing languages and nothing that identifies an *existing* subtitle file,
  // so even once PATCH exists a row has no `path` to send. `GET
  // /api/episodes` (with `seriesid`/`episodeid`) is the read that supplies it.
}

/// A single global-search match from the Bazarr library.
///
/// [id] is the upstream Sonarr series id or Radarr movie id, matching the
/// route parameters used by [ServiceRoutes.bazarrSeries] / `bazarrMovie`.
class BazarrSearchHit {
  final int id;
  final String title;
  final bool isMovie;

  const BazarrSearchHit({
    required this.id,
    required this.title,
    required this.isMovie,
  });
}

/// Paged result from a Bazarr list endpoint.
///
/// Bazarr returns the total count of the entire filtered list (not the
/// current page), so [hasMore] must combine [start] with [data.length].
class BazarrPagedResult<T> {
  final List<T> data;
  final int? total;
  final int start;

  const BazarrPagedResult({required this.data, this.total, this.start = 0});

  bool get hasMore => total == null ? false : start + data.length < total!;
}

BazarrPagedResult<T> _parsePaged<T>(
  dynamic raw,
  T Function(Map<String, dynamic>) builder, {
  int start = 0,
}) {
  final map = mapOrNull(raw);
  final data = map?['data'];
  final total = intOrNull(map?['total']);
  if (data is List) {
    final items = data
        .whereType<Map>()
        .map(stringKeyMap)
        .map(builder)
        .toList(growable: false);
    return BazarrPagedResult(data: items, total: total, start: start);
  }
  return BazarrPagedResult(data: const [], total: total, start: start);
}
