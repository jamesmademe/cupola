import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/core/providers/navigation_refresh_provider.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/movies/domain/radarr_status.dart';
import 'package:cupola/features/movies/presentation/movies_provider.dart';
import 'package:cupola/features/movies/presentation/movies_search_provider.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The movie ids Radarr reports under `wanted/cutoff`.
///
/// Screen-local because the chip is the only thing that reads it: the Overview's
/// `radarrCutoffUnmetCountProvider` wants a count, this wants a membership test,
/// and folding one into the other would make a library chip re-fetch every time
/// a KPI refreshed.
///
/// The honest limit: `getAllCutoff()` answers `[]` on its own failures rather
/// than throwing, because the endpoint is missing on some *arr builds. So an
/// empty set here means "Radarr had nothing to say", not strictly "nothing is
/// below cutoff". A Radarr that is not answering at all never reaches this
/// chip — the library provider fails first and the wall goes under a fault
/// band — so the residue is a reachable Radarr with a dead cutoff route, which
/// reads as an empty chip rather than a wrong number.
final radarrCutoffUnmetIdsProvider = FutureProvider.autoDispose<Set<int>>((
  ref,
) async {
  final records = await ref.watch(radarrServiceProvider).getAllCutoff();
  return {
    for (final record in records.whereType<Map>())
      if (record['id'] case final int id) id,
  };
});

class MoviesScreen extends ConsumerWidget {
  final bool showAppBar;
  final double topPadding;

  const MoviesScreen({super.key, this.showAppBar = true, this.topPadding = 0});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // No badge until the queue answers, never an empty queue: a film with no
    // file reads `Missing` only once a queue read whole has no entry for it,
    // and `Unknown` only once the read failed (`badgeOverQueue`).
    final queue = queueSnapshotOf(ref.watch(radarrQueueSnapshotProvider));
    final lens = ref.watch(activeInstanceProvider(ServiceKey.radarr))?.id ?? '';

    return MediaBrowseScaffold<RadarrMovie>(
      title: 'Movies',
      searchHint: 'Search movies...',
      activityRoute: '/activity/movies',
      navigationSection: NavigationSection.dashboard,
      serviceName: 'Radarr',
      service: ServiceKey.radarr,
      accentColor: ServiceKey.radarr.accent,
      heroTagPrefix: 'movie',
      searchHeroTagPrefix: 'movie_search',
      libraryProvider: moviesProvider,
      searchQueryProvider: moviesSearchQueryProvider,
      searchResultsProvider: moviesSearchResultsProvider,
      titleExtractor: (movie) => movie.title,
      subtitleExtractor: (movie) => movie.year > 0 ? '${movie.year}' : '',
      sortTitleExtractor: (movie) => movie.sortTitle,
      imagesExtractor: (movie) => movie.images,
      idExtractor: (movie) => movie.id,
      statusExtractor: (movie) => badgeOverQueue(
        radarrMovieStatus(
          movie,
          queueEntry: queue.entryFor(movie.id),
          queueUnknown: !queue.isWhole,
        ),
        queue,
      ),
      onRefresh: (ref) {
        // The family behind the snapshot, not the lens wrapper alone: that
        // one only resolves the lens and re-watches its family member, which
        // keeps the answer it already had, so a pull redrew every badge over
        // the queue from before it.
        ref.invalidate(radarrQueueSnapshotForProvider);
        // The rail above this grid reads its own non-swallowing copy of the
        // library, so that a dark Radarr prints "—" and not "Movies 0". The
        // scaffold invalidates `libraryProvider` for the grid; without this
        // line the pull refreshed the posters and left the figures frozen.
        ref.invalidate(radarrKpiLibraryProvider);
      },
      // The connection the grid shows, which is the lens's, never the first
      // one's: the posters are built off this address and key, so a 4K grid
      // keyed on the first Radarr drew its movies' artwork from the other
      // server, under that server's ids. Editing the lens's connection re-keys
      // the grid, and editing another does not.
      settingsSelector: (settings) => settings.addressAndCredentialOf(lens),
      onItemTap: (context, movie, heroTag) {
        context.push(
          ServiceRoutes.radarrMovie(movie.id, heroTag: heroTag),
          extra: movie,
        );
      },
      showAppBar: showAppBar,
      topPadding: topPadding,
      sorts: [
        MediaBrowseSort<RadarrMovie>.dateAdded((movie) => movie.added),
        MediaBrowseSort<RadarrMovie>.year((movie) => movie.year),
        MediaBrowseSort<RadarrMovie>.size((movie) => movie.sizeOnDisk),
      ],
      // Null until the answer lands, so the chip appears with its set rather
      // than appearing first and filtering to nothing while the fetch is out.
      cutoffUnmetIds: ref
          .watch(radarrCutoffUnmetIdsProvider)
          .maybeWhen(data: (ids) => ids, orElse: () => null),
      kpiPeek: ServiceKpiPeek(
        kpis: ref.watch(serviceKpiProvider(ServiceKey.radarr)),
        accent: ServiceKey.radarr.accent,
      ),
    );
  }
}
