import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/features/bazarr/data/bazarr_service.dart';
import 'package:cupola/features/bazarr/domain/models/bazarr_models.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

const int _defaultDashboardPageSize = 20;

enum BazarrHistorySource { episodes, movies }

typedef BazarrHistoryQuery = ({
  BazarrHistorySource source,
  int start,
  int length,
});

/// Dashboard-ready alias for the underlying Bazarr service.
///
/// Throws if Bazarr is not configured; widgets must check
/// `settings.isServiceConfigured(ServiceKey.bazarr)` before reading.
final bazarrServiceProvider = Provider<BazarrService>((ref) {
  return _bazarrService(ref, instanceId: null);
});

/// Bazarr service bound to one named connection, independent of the lens.
final bazarrServiceForProvider = Provider.family<BazarrService, String>((
  ref,
  instanceId,
) {
  final lens = ref.read(activeInstanceProvider(ServiceKey.bazarr))?.id ?? '';
  if (instanceId.isEmpty || instanceId == lens) {
    return ref.watch(bazarrServiceProvider);
  }
  return _bazarrService(ref, instanceId: instanceId);
});

BazarrService _bazarrService(Ref ref, {required String? instanceId}) {
  return BazarrService(
    watchApiClient(ref, ServiceKey.bazarr, instanceId: instanceId),
  );
}

/// Aggregated counts for the Bazarr dashboard stat row.
final bazarrBadgesProvider = FutureProvider<BazarrBadges>((ref) async {
  return ref.watch(bazarrServiceProvider).getBadges();
});

/// Every provider Bazarr has enabled, ready or waited out.
final bazarrProviderStatusesProvider =
    FutureProvider<List<BazarrProviderStatus>>(
      (ref) async => ref.watch(bazarrServiceProvider).getProviderStatuses(),
      retry: noProviderRetry,
    );

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
    service.getEpisodeHistoryItems(start: 0, length: _defaultDashboardPageSize),
    service.getMovieHistoryItems(start: 0, length: _defaultDashboardPageSize),
  ]);
  final items = <BazarrHistoryItem>[...results[0].data, ...results[1].data];
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

/// One typed page from either half of Bazarr history.
final bazarrHistoryPageProvider = FutureProvider.autoDispose
    .family<BazarrPagedResult<BazarrHistoryItem>, BazarrHistoryQuery>((
      ref,
      query,
    ) async {
      final service = ref.watch(bazarrServiceProvider);
      return switch (query.source) {
        BazarrHistorySource.episodes => service.getEpisodeHistoryItems(
          start: query.start,
          length: query.length,
        ),
        BazarrHistorySource.movies => service.getMovieHistoryItems(
          start: query.start,
          length: query.length,
        ),
      };
      // `noProviderRetry`, like the two providers above: the History screen
      // reads this through `ref.read(...future)` inside its own try, and a
      // backing-off retry underneath that turns one failed page into a minute
      // of silence before the band it already draws can appear.
    }, retry: noProviderRetry);

/// The [BazarrSeries] Bazarr follows under a Sonarr series id, asked by id
/// ([BazarrService.getSeriesById]).
///
/// `noProviderRetry`, like the three lookups below it and the Radarr and Sonarr
/// detail reads: these back the two detail pages and nothing else, both offer
/// Retry and pull-to-refresh, and under the default policy a page opened cold
/// on a Bazarr that did not answer sat on its skeleton for the better part of
/// a minute before it said so.
final bazarrSeriesByIdProvider = FutureProvider.family<BazarrSeries?, int>((
  ref,
  sonarrSeriesId,
) async {
  if (sonarrSeriesId <= 0) return null;
  return ref.watch(bazarrServiceProvider).getSeriesById(sonarrSeriesId);
}, retry: noProviderRetry);

/// The [BazarrMovie] Bazarr follows under a Radarr id, asked by id. See
/// [bazarrSeriesByIdProvider] for the retry policy.
final bazarrMovieByIdProvider = FutureProvider.family<BazarrMovie?, int>((
  ref,
  radarrId,
) async {
  if (radarrId <= 0) return null;
  return ref.watch(bazarrServiceProvider).getMovieById(radarrId);
}, retry: noProviderRetry);

/// The wanted episodes of one series (empty when it wants nothing), read for
/// that series alone ([BazarrService.getWantedEpisodesForSeries]).
final bazarrWantedEpisodesForSeriesProvider =
    FutureProvider.family<List<BazarrWantedItem>, int>((
      ref,
      sonarrSeriesId,
    ) async {
      if (sonarrSeriesId <= 0) return const [];
      return ref
          .watch(bazarrServiceProvider)
          .getWantedEpisodesForSeries(sonarrSeriesId);
    }, retry: noProviderRetry);

/// The Wanted entry for a Radarr id (null when the movie wants nothing),
/// asked by id.
final bazarrWantedMovieByIdProvider =
    FutureProvider.family<BazarrWantedItem?, int>((ref, radarrId) async {
      if (radarrId <= 0) return null;
      return ref.watch(bazarrServiceProvider).getWantedMovieById(radarrId);
    }, retry: noProviderRetry);
