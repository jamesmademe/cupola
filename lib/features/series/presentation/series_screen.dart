import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/core/providers/navigation_refresh_provider.dart';
import 'package:cupola/core/utils/arr_model_helpers.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/media/presentation/open_media.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/series/domain/models/sonarr_series.dart';
import 'package:cupola/features/series/domain/sonarr_status.dart';
import 'package:cupola/features/series/presentation/series_provider.dart';
import 'package:cupola/features/series/presentation/series_search_provider.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/connection_reach_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The series ids Sonarr reports under `wanted/cutoff`.
///
/// Sonarr answers that route with *episodes*, not series, so the fold is over
/// `seriesId` and a series with nine episodes below cutoff is one id, which is
/// exactly what a library chip over series needs, and is why this cannot be the
/// same provider Radarr uses.
///
/// `getAllCutoff()` answers `[]` on its own failures rather than throwing (the
/// route is absent on some builds), so an empty set is "Sonarr had nothing to
/// say" as much as "nothing is below cutoff". A Sonarr that is not answering at
/// all never gets here: the library provider fails first.
final sonarrCutoffUnmetSeriesIdsProvider = FutureProvider.autoDispose<Set<int>>(
  (ref) async {
    final records = await ref.watch(sonarrServiceProvider).getAllCutoff();
    return {
      for (final record in records.whereType<Map>())
        if (record['seriesId'] case final int id) id,
    };
  },
);

class SeriesScreen extends ConsumerWidget {
  final bool showAppBar;
  final double topPadding;

  const SeriesScreen({super.key, this.showAppBar = true, this.topPadding = 0});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // No badge until the queue answers: see `movies_screen.dart`.
    final queue = queueSnapshotOf(ref.watch(sonarrQueueSnapshotProvider));
    final lens = ref.watch(activeInstanceProvider(ServiceKey.sonarr))?.id ?? '';
    // Which of its addresses the lens's connection is reached at: the
    // posters go where the library is read from.
    final route = ref.watch(connectionRouteProvider(lens));

    return MediaBrowseScaffold<SonarrSeries>(
      title: 'TV series',
      searchHint: 'Search series',
      activityRoute: '${ServiceRoutes.sonarr}/queue',
      navigationSection: NavigationSection.stack,
      serviceName: 'Sonarr',
      service: ServiceKey.sonarr,
      posterFallbackIcon: Icons.tv_outlined,
      accentColor: ServiceKey.sonarr.accent,
      heroTagPrefix: 'series',
      searchHeroTagPrefix: 'series_search',
      libraryProvider: seriesProvider,
      searchQueryProvider: seriesSearchQueryProvider,
      searchResultsProvider: seriesSearchResultsProvider,
      titleExtractor: (series) => series.title,
      subtitleExtractor: (series) => series.year > 0 ? '${series.year}' : '',
      sortTitleExtractor: (series) => series.sortTitle,
      imagesExtractor: (series) => series.images,
      idExtractor: (series) => series.id,
      statusExtractor: (series) => badgeOverQueue(
        sonarrSeriesStatus(
          series,
          queueEntry: queue.entryFor(series.id),
          queueUnknown: !queue.isWhole,
        ),
        queue,
      ),
      onRefresh: (ref) {
        // The family behind the snapshot, not the lens wrapper: see
        // `movies_screen.dart`. The read itself, which the series index is a
        // view of.
        ref.invalidate(sonarrQueueSnapshotsForProvider);
        // The rail's own non-swallowing read. See `movies_screen.dart`.
        ref.invalidate(sonarrKpiLibraryProvider);
      },
      // The lens's connection, never the first one's: see `movies_screen.dart`.
      settingsSelector: (settings) => settings.artworkKeyOf(lens, route),
      onItemTap: (context, series, heroTag) {
        // The series' own page, under this tab, opened on this Sonarr's copy;
        // with no TMDB id, the way through its id here, where a Seerr can
        // name TMDB's from TVDB's.
        if (series.tmdbId <= 0) {
          context.push(ServiceRoutes.sonarrSeries(series.id, heroTag: heroTag));
          return;
        }
        context.openMedia(
          MediaKey.tv(series.tmdbId),
          focus: lens.isEmpty ? null : lens,
          heroTag: heroTag,
          posterUrl: remotePosterOf(series.images),
        );
      },
      showAppBar: showAppBar,
      topPadding: topPadding,
      sorts: [
        MediaBrowseSort<SonarrSeries>.dateAdded((series) => series.added),
        MediaBrowseSort<SonarrSeries>.year((series) => series.year),
        MediaBrowseSort<SonarrSeries>.size(
          // `statistics` is absent on a freshly added series, which is a zero
          // on disk and not an unknown: the series genuinely has no files yet.
          (series) => switch (series.statistics?['sizeOnDisk']) {
            final int bytes => bytes,
            final num bytes => bytes.toInt(),
            _ => 0,
          },
        ),
      ],
      // Null until the answer lands, so the chip appears with its set rather
      // than appearing first and filtering to nothing while the fetch is out.
      cutoffUnmetIds: ref
          .watch(sonarrCutoffUnmetSeriesIdsProvider)
          .maybeWhen(data: (ids) => ids, orElse: () => null),
      kpiPeek: ServiceKpiPeek(
        kpis: ref.watch(serviceKpiProvider(ServiceKey.sonarr)),
        service: ServiceKey.sonarr,
      ),
    );
  }
}
