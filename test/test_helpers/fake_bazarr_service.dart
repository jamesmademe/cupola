import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/features/bazarr/data/bazarr_service.dart';
import 'package:cupola/features/bazarr/domain/models/bazarr_models.dart';

ApiClient _client(String baseUrl) => ApiClient(baseUrl: baseUrl, apiKey: 'key');

class FakeBazarrService extends BazarrService {
  FakeBazarrService() : super(_client('https://bazarr.example.com'));

  BazarrBadges badges = const BazarrBadges(
    episodes: 0,
    movies: 0,
    providers: 0,
    status: false,
    sonarrSignalR: false,
    radarrSignalR: false,
    announcements: 0,
  );
  BazarrProviderSummary providerSummary = const BazarrProviderSummary(
    configuredCount: 0,
  );
  List<BazarrProviderStatus> providerStatuses = const [];
  bool resetProviderStatusesCalled = false;
  BazarrPagedResult<BazarrSeries> seriesResult = const BazarrPagedResult(
    data: [],
    total: 0,
  );
  BazarrPagedResult<BazarrMovie> moviesResult = const BazarrPagedResult(
    data: [],
    total: 0,
  );
  BazarrPagedResult<BazarrWantedItem> wantedEpisodesResult =
      const BazarrPagedResult(data: [], total: 0);
  BazarrPagedResult<BazarrWantedItem> wantedMoviesResult =
      const BazarrPagedResult(data: [], total: 0);
  BazarrPagedResult<Map<String, dynamic>> episodesHistoryResult =
      const BazarrPagedResult(data: [], total: 0);
  BazarrPagedResult<Map<String, dynamic>> moviesHistoryResult =
      const BazarrPagedResult(data: [], total: 0);

  /// What the by-id lookups find: [seriesByIdOverride] or
  /// [movieByIdOverride] when set, otherwise the row of [seriesResult] /
  /// [moviesResult] with that id, as Bazarr's `seriesid[]`/`radarrid[]`
  /// filter would answer.
  BazarrSeries? seriesByIdOverride;
  BazarrMovie? movieByIdOverride;
  List<BazarrWantedItem> wantedEpisodesForSeriesResult = const [];
  BazarrWantedItem? wantedMovieByIdOverride;

  Object? throwOnCall;

  /// Thrown only by the wanted endpoints, so a test can fail the secondary
  /// section while the primary lookup succeeds.
  Object? throwOnWanted;

  /// Call counters for retry assertions.
  int wantedMoviesCalls = 0;
  int wantedEpisodesCalls = 0;

  @override
  Future<BazarrBadges> getBadges() async {
    if (throwOnCall != null) throw throwOnCall!;
    return badges;
  }

  @override
  Future<BazarrProviderSummary> getProviderSummary() async {
    if (throwOnCall != null) throw throwOnCall!;
    return providerSummary;
  }

  @override
  Future<List<BazarrProviderStatus>> getProviderStatuses() async {
    if (throwOnCall != null) throw throwOnCall!;
    return providerStatuses;
  }

  @override
  Future<void> resetProviderStatuses() async {
    if (throwOnCall != null) throw throwOnCall!;
    resetProviderStatusesCalled = true;
  }

  @override
  Future<BazarrPagedResult<BazarrSeries>> getSeries({
    int start = 0,
    int length = 50,
  }) async {
    if (throwOnCall != null) throw throwOnCall!;
    if (seriesByIdOverride != null) {
      return BazarrPagedResult(
        data: [seriesByIdOverride!],
        total: 1,
        start: start,
      );
    }
    return seriesResult;
  }

  @override
  Future<BazarrPagedResult<BazarrMovie>> getMovies({
    int start = 0,
    int length = 50,
  }) async {
    if (throwOnCall != null) throw throwOnCall!;
    if (movieByIdOverride != null) {
      return BazarrPagedResult(
        data: [movieByIdOverride!],
        total: 1,
        start: start,
      );
    }
    return moviesResult;
  }

  @override
  Future<BazarrSeries?> getSeriesById(int sonarrSeriesId) async {
    if (throwOnCall != null) throw throwOnCall!;
    final rows = seriesByIdOverride != null
        ? [seriesByIdOverride!]
        : seriesResult.data;
    for (final series in rows) {
      if (series.sonarrSeriesId == sonarrSeriesId) return series;
    }
    return null;
  }

  @override
  Future<BazarrMovie?> getMovieById(int radarrId) async {
    if (throwOnCall != null) throw throwOnCall!;
    final rows = movieByIdOverride != null
        ? [movieByIdOverride!]
        : moviesResult.data;
    for (final movie in rows) {
      if (movie.radarrId == radarrId) return movie;
    }
    return null;
  }

  @override
  Future<List<BazarrWantedItem>> getWantedEpisodesForSeries(
    int sonarrSeriesId,
  ) async {
    wantedEpisodesCalls++;
    if (throwOnCall != null) throw throwOnCall!;
    if (throwOnWanted != null) throw throwOnWanted!;
    final rows = wantedEpisodesForSeriesResult.isNotEmpty
        ? wantedEpisodesForSeriesResult
        : wantedEpisodesResult.data;
    return [
      for (final item in rows)
        if (item.sonarrSeriesId == sonarrSeriesId) item,
    ];
  }

  @override
  Future<BazarrWantedItem?> getWantedMovieById(int radarrId) async {
    wantedMoviesCalls++;
    if (throwOnCall != null) throw throwOnCall!;
    if (throwOnWanted != null) throw throwOnWanted!;
    final rows = wantedMovieByIdOverride != null
        ? [wantedMovieByIdOverride!]
        : wantedMoviesResult.data;
    for (final item in rows) {
      if (item.radarrId == radarrId) return item;
    }
    return null;
  }

  @override
  Future<BazarrPagedResult<BazarrWantedItem>> getWantedEpisodes({
    int start = 0,
    int length = 50,
  }) async {
    wantedEpisodesCalls++;
    if (throwOnCall != null) throw throwOnCall!;
    if (throwOnWanted != null) throw throwOnWanted!;
    if (wantedEpisodesForSeriesResult.isNotEmpty) {
      return BazarrPagedResult(
        data: wantedEpisodesForSeriesResult,
        total: wantedEpisodesForSeriesResult.length,
        start: start,
      );
    }
    return wantedEpisodesResult;
  }

  @override
  Future<BazarrPagedResult<BazarrWantedItem>> getWantedMovies({
    int start = 0,
    int length = 50,
  }) async {
    wantedMoviesCalls++;
    if (throwOnCall != null) throw throwOnCall!;
    if (throwOnWanted != null) throw throwOnWanted!;
    if (wantedMovieByIdOverride != null) {
      return BazarrPagedResult(
        data: [wantedMovieByIdOverride!],
        total: 1,
        start: start,
      );
    }
    return wantedMoviesResult;
  }

  @override
  Future<BazarrPagedResult<Map<String, dynamic>>> getEpisodesHistory({
    int start = 0,
    int length = 50,
  }) async {
    if (throwOnCall != null) throw throwOnCall!;
    return episodesHistoryResult;
  }

  @override
  Future<BazarrPagedResult<Map<String, dynamic>>> getMoviesHistory({
    int start = 0,
    int length = 50,
  }) async {
    if (throwOnCall != null) throw throwOnCall!;
    return moviesHistoryResult;
  }
}
