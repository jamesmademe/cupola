import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/bazarr/data/bazarr_service.dart';
import 'package:cupola/features/bazarr/domain/models/bazarr_models.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

const int _lookupPageSize = 500;

const int _defaultDashboardPageSize = 20;

/// Dashboard-ready alias for the underlying Bazarr service.
///
/// Throws if Bazarr is not configured; widgets must check
/// `settings.isServiceConfigured(ServiceKey.bazarr)` before reading.
final bazarrServiceProvider = Provider<BazarrService>((ref) {
  return BazarrService(watchApiClient(ref, ServiceKey.bazarr));
});

/// Aggregated counts for the Bazarr dashboard stat row.
final bazarrBadgesProvider = FutureProvider<BazarrBadges>((ref) async {
  return ref.watch(bazarrServiceProvider).getBadges();
});

/// Merged first page of wanted episodes + movies for the dashboard.
final bazarrDashboardWantedProvider = FutureProvider<List<BazarrWantedItem>>((
  ref,
) async {
  final service = ref.watch(bazarrServiceProvider);
  final results = await Future.wait([
    service.getWantedEpisodes(start: 0, length: _defaultDashboardPageSize),
    service.getWantedMovies(start: 0, length: _defaultDashboardPageSize),
  ]);
  return [...results[0].data, ...results[1].data];
});

/// Recent subtitle activity merged from episodes + movies history.
final bazarrDashboardHistoryProvider = FutureProvider<List<BazarrHistoryItem>>((
  ref,
) async {
  final service = ref.watch(bazarrServiceProvider);
  final results = await Future.wait([
    service.getEpisodesHistory(start: 0, length: _defaultDashboardPageSize),
    service.getMoviesHistory(start: 0, length: _defaultDashboardPageSize),
  ]);
  final items = <BazarrHistoryItem>[
    ...results[0].data.map(BazarrHistoryItem.fromEpisodeMap),
    ...results[1].data.map(BazarrHistoryItem.fromMovieMap),
  ];
  items.sort((a, b) {
    final ta = a.parsedTimestamp;
    final tb = b.parsedTimestamp;
    if (ta == null && tb == null) return 0;
    if (ta == null) return 1;
    if (tb == null) return -1;
    return tb.compareTo(ta);
  });
  return items;
});

/// Fetch a single [BazarrSeries] by Sonarr series id.
///
/// Bazarr does not expose a `/api/series/:id` endpoint, so this provider walks
/// the paged list and returns the first match.
final bazarrSeriesByIdProvider = FutureProvider.family<BazarrSeries?, int>((
  ref,
  sonarrSeriesId,
) async {
  if (sonarrSeriesId <= 0) return null;
  final service = ref.watch(bazarrServiceProvider);
  var start = 0;
  while (true) {
    final page = await service.getSeries(start: start, length: _lookupPageSize);
    for (final s in page.data) {
      if (s.sonarrSeriesId == sonarrSeriesId) return s;
    }
    if (!page.hasMore) return null;
    start += page.data.length;
  }
});

/// Fetch a single [BazarrMovie] by Radarr id.
final bazarrMovieByIdProvider = FutureProvider.family<BazarrMovie?, int>((
  ref,
  radarrId,
) async {
  if (radarrId <= 0) return null;
  final service = ref.watch(bazarrServiceProvider);
  var start = 0;
  while (true) {
    final page = await service.getMovies(start: start, length: _lookupPageSize);
    for (final m in page.data) {
      if (m.radarrId == radarrId) return m;
    }
    if (!page.hasMore) return null;
    start += page.data.length;
  }
});

/// Fetch all wanted items of a series (or empty if not in wanted list).
final bazarrWantedEpisodesForSeriesProvider =
    FutureProvider.family<List<BazarrWantedItem>, int>((
      ref,
      sonarrSeriesId,
    ) async {
      if (sonarrSeriesId <= 0) return const [];
      final service = ref.watch(bazarrServiceProvider);
      final result = <BazarrWantedItem>[];
      var start = 0;
      while (true) {
        final page = await service.getWantedEpisodes(
          start: start,
          length: _lookupPageSize,
        );
        for (final item in page.data) {
          if (item.sonarrSeriesId == sonarrSeriesId) result.add(item);
        }
        if (!page.hasMore) break;
        start += page.data.length;
      }
      return result;
    });

/// Fetch the wanted movie entry for a Radarr id (or empty if not wanted).
final bazarrWantedMovieByIdProvider =
    FutureProvider.family<BazarrWantedItem?, int>((ref, radarrId) async {
      if (radarrId <= 0) return null;
      final service = ref.watch(bazarrServiceProvider);
      var start = 0;
      while (true) {
        final page = await service.getWantedMovies(
          start: start,
          length: _lookupPageSize,
        );
        for (final item in page.data) {
          if (item.radarrId == radarrId) return item;
        }
        if (!page.hasMore) return null;
        start += page.data.length;
      }
    });
