import 'dart:isolate';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/api/base_arr_service.dart';
import 'package:cupola/features/series/domain/models/sonarr_episode.dart';
import 'package:cupola/features/series/domain/models/sonarr_series.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

final sonarrServiceProvider = Provider<SonarrService>((ref) {
  return SonarrService(watchApiClient(ref, ServiceKey.sonarr));
});

/// Sonarr bound to one named connection, whatever the lens is pointing at.
///
/// For the work that belongs to a *connection* rather than to a screen: a
/// release search runs on the server it was started against, and the lens can
/// move while it is queued. Empty id means the lens, which is what the plain
/// [sonarrServiceProvider] answers; an id naming nothing throws "not configured"
/// rather than quietly answering about some other server.
///
/// Not `autoDispose`: a caller reads this, awaits a request on it, and a
/// disposal scheduled at the end of the read would close the `Dio` under the
/// request. One live client per configured connection is the same bound the
/// per-service providers already carry.
final sonarrServiceForProvider = Provider.family<SonarrService, String>((
  ref,
  instanceId,
) {
  // The lens's own connection resolves to [sonarrServiceProvider] rather than to
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
  final lens = ref.read(activeInstanceProvider(ServiceKey.sonarr))?.id ?? '';
  if (instanceId.isEmpty || instanceId == lens) {
    return ref.watch(sonarrServiceProvider);
  }
  return SonarrService(
    watchApiClient(ref, ServiceKey.sonarr, instanceId: instanceId),
  );
});

/// Service for interacting with Sonarr API.
///
/// Provides series-specific operations plus shared activity operations
/// via [ArrActivityMixin].
class SonarrService with ArrActivityMixin {
  @override
  final ApiClient client;

  @override
  final ArrServiceConfig config = ArrServiceConfig.sonarr;

  SonarrService(this.client);

  /// On the queue's **page** primitive, which `getQueue` delegates to, so the
  /// figure and the rows come off one request that carries the series.
  @override
  Future<ArrRecordPage> getQueuePage({Map<String, dynamic>? queryParameters}) {
    return super.getQueuePage(
      queryParameters: {
        'includeSeries': true,
        'includeEpisode': true,
        'includeUnknownSeriesItems': true,
        ...?queryParameters,
      },
    );
  }

  /// Fetches all series from Sonarr, answering `[]` when it cannot be read.
  ///
  /// The degrading read: `fetchAllItems` swallows everything, which is the
  /// right shape only for a join that can go on without the library
  /// ([getSeriesByTvdbId]), and the wrong one for the wall or anything that
  /// *counts* — an unreachable server and an empty library arrive as the same
  /// value. Those use [getSeriesOrThrow].
  Future<List<SonarrSeries>> getSeries() async {
    return fetchAllItems('series', SonarrSeries.fromJson);
  }

  /// The same library, with a failed fetch allowed to reach the caller.
  ///
  /// A Sonarr that is unreachable, mis-keyed or 500-ing resolves [getSeries]
  /// *successfully* with an empty list, and every figure derived from that
  /// printed a confident zero — the Overview's "next 7 days · 0 series" over
  /// "Nothing airing this week", directly under an identity band whose own
  /// probe already read Unreachable. Two contradictory claims on one screenful,
  /// and the confident one was fabricated. A figure whose source did not answer
  /// has to read an em dash, and the only way a reader can tell the two cases
  /// apart is for the failure to survive the fetch.
  ///
  /// Mapping matches `fetchAllItems`: straight through for a small library,
  /// through an isolate once it is large enough to be worth the port. The whole
  /// library arrives in one response, so this is the list where that threshold
  /// is regularly crossed.
  Future<List<SonarrSeries>> getSeriesOrThrow() async {
    final response = await client.get('/api/${config.apiVersion}/series');
    final data = response.data as List<dynamic>;
    if (data.length <= _seriesIsolateMapThreshold) return _mapSeries(data);
    return Isolate.run(() => _mapSeries(data));
  }

  /// Fetches a single series by its Sonarr ID, with a failed fetch allowed to
  /// reach the caller. See
  /// `RadarrService.getMovieOrThrow`: a 404 is an answer and reads `null`,
  /// everything else travels, so the detail page can say Sonarr did not
  /// answer instead of drawing what it was handed as confirmed.
  Future<SonarrSeries?> getSeriesByIdOrThrow(int seriesId) async {
    try {
      final response = await client.get(
        '/api/${config.apiVersion}/series/$seriesId',
      );
      return SonarrSeries.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  /// On the **page** primitive, not on `getHistory`.
  ///
  /// `getHistory` delegates to this, so both spellings pick the parameters up —
  /// but only this way round. Hung off `getHistory` instead, as they were, a
  /// caller that reached for `getHistoryPage` (the one that carries the
  /// envelope's total, and therefore the only one a count may be derived from)
  /// got records with no embedded `series` and no embedded `episode` — and on
  /// Sonarr those are the whole row: a history record on its own names a season
  /// and episode number against a series id, so without them the row has
  /// nothing to print but the id.
  @override
  Future<ArrRecordPage> getHistoryPage({
    int page = 1,
    int pageSize = 20,
    Map<String, dynamic>? queryParameters,
  }) {
    return super.getHistoryPage(
      page: page,
      pageSize: pageSize,
      queryParameters: {
        'includeSeries': true,
        'includeEpisode': true,
        ...?queryParameters,
      },
    );
  }

  @override
  Future<List<dynamic>> getAllHistory({Map<String, dynamic>? queryParameters}) {
    return super.getAllHistory(
      queryParameters: {
        'includeSeries': true,
        'includeEpisode': true,
        ...?queryParameters,
      },
    );
  }

  /// Triggers an automatic search for the given series ID (entire series).
  Future<void> searchSeries(int seriesId) async {
    await _postCommand({'name': 'SeriesSearch', 'seriesId': seriesId});
  }

  /// Triggers an automatic search for a specific season.
  Future<void> searchSeason(int seriesId, int seasonNumber) async {
    await _postCommand({
      'name': 'SeasonSearch',
      'seriesId': seriesId,
      'seasonNumber': seasonNumber,
    });
  }

  /// Triggers an automatic search for specific episodes.
  Future<void> searchEpisodes(List<int> episodeIds) async {
    await _postCommand({'name': 'EpisodeSearch', 'episodeIds': episodeIds});
  }

  Future<void> _postCommand(Map<String, dynamic> data) async {
    await client.post('/api/v3/command', data: data);
  }

  /// Fetches all episodes for a series.
  Future<List<SonarrEpisode>> getEpisodes(int seriesId) async {
    return fetchListItems('episode', {
      'seriesId': seriesId,
    }, SonarrEpisode.fromJson);
  }

  /// Fetches releases for interactive search.
  /// Note: Sonarr requires either episodeId or seriesId+seasonNumber for proper results.
  Future<List<dynamic>> getReleases({
    int? seriesId,
    int? seasonNumber,
    int? episodeId,
    CancelToken? cancelToken,
    Duration? receiveTimeout,
  }) async {
    final params = <String, dynamic>{};
    if (seriesId != null) params['seriesId'] = seriesId;
    if (seasonNumber != null) params['seasonNumber'] = seasonNumber;
    if (episodeId != null) params['episodeId'] = episodeId;

    return fetchReleases(
      params,
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

  /// Searches for series by term using the lookup API.
  ///
  /// [cancelToken] aborts the request once the search that asked for it has
  /// been superseded — see [ArrActivityMixin.lookupItems], which owns the
  /// empty-term guard, the isolate mapping and the degrade-to-`[]` rule the
  /// three arr lookups share.
  Future<List<SonarrSeries>> lookupSeries(
    String term, {
    CancelToken? cancelToken,
    bool reportFailure = false,
  }) {
    return lookupItems(
      'series/lookup',
      term,
      SonarrSeries.fromJson,
      cancelToken: cancelToken,
      reportFailure: reportFailure,
    );
  }

  /// Adds [series] — a `series/lookup` row — to this Sonarr's library.
  ///
  /// The seasons travel back untouched: Sonarr builds the library entry from
  /// them, and an add that drops them lands a series with no seasons to
  /// monitor. `addOptions.searchForMissingEpisodes` is the half that makes
  /// this an add rather than a bookmark.
  ///
  /// [monitored] decides both halves at once — the series flag and
  /// `addOptions.monitor` — because a series that is not monitored with every
  /// episode monitored is a contradiction Sonarr resolves by grabbing nothing,
  /// having first queued a search sweep for the lot.
  ///
  /// Throws on failure rather than degrading; see [RadarrService.addMovie].
  Future<SonarrSeries> addSeries(
    SonarrSeries series, {
    required int qualityProfileId,
    required String rootFolderPath,
    bool monitored = true,
    bool searchForMissingEpisodes = true,
  }) async {
    final response = await client.post(
      '/api/v3/series',
      data: {
        'title': series.title,
        // Sonarr keys the new entry on these two, not on the title.
        'titleSlug': series.titleSlug,
        'tvdbId': series.tvdbId,
        'year': series.year,
        'images': series.images,
        'seasons': series.seasons,
        'seriesType': series.seriesType ?? 'standard',
        'qualityProfileId': qualityProfileId,
        'rootFolderPath': rootFolderPath,
        'monitored': monitored,
        'seasonFolder': true,
        'addOptions': {
          'monitor': monitored ? 'all' : 'none',
          'searchForMissingEpisodes': searchForMissingEpisodes,
          'searchForCutoffUnmetEpisodes': false,
        },
      },
    );
    return SonarrSeries.fromJson(response.data as Map<String, dynamic>);
  }

  /// Fetches the root folders configured on this Sonarr.
  Future<List<Map<String, dynamic>>> getRootFolders() async {
    return fetchRootFolders();
  }

  /// Finds a series in the library by its TVDB ID.
  /// Returns null if not found in the library.
  Future<SonarrSeries?> getSeriesByTvdbId(int tvdbId) async {
    try {
      final series = await getSeries();
      return series.where((s) => s.tvdbId == tvdbId).firstOrNull;
    } catch (_) {
      return null;
    }
  }

  /// Fetches all quality profiles.
  Future<List<Map<String, dynamic>>> getQualityProfiles() async {
    return fetchQualityProfiles();
  }

  /// Updates a series's quality profile.
  Future<void> updateSeriesProfile(int seriesId, int qualityProfileId) async {
    await updateItemProfile('series', seriesId, qualityProfileId);
  }

  /// Updates a series's monitored state.
  Future<void> updateSeriesMonitored(int seriesId, bool monitored) async {
    await updateItemMonitored('series', seriesId, monitored);
  }

  /// Changes how Sonarr numbers this series's episodes.
  ///
  /// Read-modify-write against the same `PUT /api/v3/series/{id}` the monitor
  /// and profile writes use: Sonarr's series endpoint takes the whole resource
  /// and silently resets any field left out, so the body has to be the record
  /// it just returned with one key changed. This is not a variant of
  /// `updateItemProfile` that could be folded into it — that helper is shared
  /// by four services whose resources have a `qualityProfileId`, and
  /// `seriesType` exists on Sonarr alone.
  ///
  /// [seriesType] is a `SonarrSeriesType.wireValue`, never a UI label: Sonarr
  /// matches the string exactly and answers 400 to "Anime".
  ///
  /// Throws on failure. This is a user action with a visible outcome — the
  /// field's whole point is that it changes what imports — so a silent
  /// degrade would leave the row showing the old value as if it were the new
  /// one.
  Future<void> updateSeriesType(int seriesId, String seriesType) async {
    final response = await client.get('/api/v3/series/$seriesId');
    final series = response.data as Map<String, dynamic>;
    series['seriesType'] = seriesType;
    await client.put('/api/v3/series/$seriesId', data: series);
  }

  /// Deletes a series from Sonarr.
  Future<void> deleteSeries(
    int seriesId, {
    bool deleteFiles = false,
    bool addImportListExclusion = false,
  }) async {
    await client.delete(
      '/api/v3/series/$seriesId',
      queryParameters: {
        'deleteFiles': deleteFiles,
        'addImportListExclusion': addImportListExclusion,
      },
    );
  }
}

/// Above this many rows the library is mapped off the platform thread.
///
/// The same number `base_arr_service.dart` uses for its own list mapping, kept
/// here because that one is private to its library.
const int _seriesIsolateMapThreshold = 200;

/// Top-level and pure, so it can cross an isolate port.
List<SonarrSeries> _mapSeries(List<dynamic> data) {
  return data
      .map((item) => SonarrSeries.fromJson(item as Map<String, dynamic>))
      .toList(growable: false);
}
