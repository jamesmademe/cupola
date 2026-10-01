import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/core/providers/navigation_refresh_provider.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/music/domain/lidarr_status.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';
import 'package:cupola/features/music/presentation/music_provider.dart';
import 'package:cupola/features/music/presentation/music_search_provider.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The artist ids Lidarr reports under `wanted/cutoff`.
///
/// Lidarr answers that route with *albums*, so the fold is over `artistId`: an
/// artist with four albums below cutoff is one id, which is the grain this
/// library browses at.
///
/// `getAllCutoff()` answers `[]` on its own failures rather than throwing, so
/// an empty set is "Lidarr had nothing to say" as much as "nothing is below
/// cutoff". A Lidarr that is not answering at all never gets here: the library
/// provider fails first and the wall goes under a fault band.
final lidarrCutoffUnmetArtistIdsProvider = FutureProvider.autoDispose<Set<int>>(
  (ref) async {
    final records = await ref.watch(lidarrServiceProvider).getAllCutoff();
    return {
      for (final record in records.whereType<Map>())
        if (record['artistId'] case final int id) id,
    };
  },
);

/// `6 albums · complete` / `9 albums · 34 tracks missing` — the caption the
/// circular artist tile carries instead of a status dot.
///
/// Top-level and pure so the wording is assertable without a pumped wall.
///
/// Three honest answers, and the third is why this is not a one-liner:
/// * Lidarr omits `statistics` entirely on an artist it has not scanned. That
///   is not "0 albums", it is *no answer*, and it reads as an em dash.
/// * With tracks counted, the shortfall is stated **in tracks**, because tracks
///   are what Lidarr counts. The board writes `9 albums · 1 missing`, but the
///   artist payload carries no per-album file state, so saying "1 missing"
///   beside an album count would be a number in the wrong unit.
/// * An artist with albums but no tracks counted gets the album count alone
///   rather than a completeness claim nothing supports.
String lidarrArtistCaption(LidarrArtist artist) {
  if (artist.statistics == null) return '\u2014';

  final albums = artist.albumCount;
  final albumTerm = albums > 0
      ? '$albums album${albums == 1 ? '' : 's'}'
      : null;

  final tracks = artist.trackCount;
  if (tracks <= 0) return albumTerm ?? '\u2014';

  final missing = tracks - artist.trackFileCount;
  final completeness = missing <= 0
      ? 'complete'
      : '$missing track${missing == 1 ? '' : 's'} missing';

  return albumTerm == null ? completeness : '$albumTerm \u00b7 $completeness';
}

class MusicScreen extends ConsumerWidget {
  final bool showAppBar;
  final double topPadding;

  const MusicScreen({super.key, this.showAppBar = true, this.topPadding = 0});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // No badge until the queue answers: see `movies_screen.dart`.
    final queue = lidarrQueueSnapshotsOf(
      ref.watch(lidarrQueueSnapshotsProvider),
    ).byArtist;

    return MediaBrowseScaffold<LidarrArtist>(
      title: 'Music',
      searchHint: 'Search artists...',
      activityRoute: '/activity/music',
      navigationSection: NavigationSection.dashboard,
      serviceName: 'Lidarr',
      service: ServiceKey.lidarr,
      accentColor: ServiceKey.lidarr.accent,
      heroTagPrefix: 'artist',
      searchHeroTagPrefix: 'artist_search',
      libraryProvider: musicProvider,
      searchQueryProvider: musicSearchQueryProvider,
      searchResultsProvider: musicSearchResultsProvider,
      titleExtractor: (artist) => artist.artistName,
      subtitleExtractor: lidarrArtistCaption,
      sortTitleExtractor: (artist) => artist.artistName,
      imagesExtractor: (artist) => artist.images,
      idExtractor: (artist) => artist.id,
      statusExtractor: (artist) => badgeOverQueue(
        lidarrArtistStatus(
          artist,
          queueEntry: queue.entryFor(artist.id),
          queueUnknown: !queue.isWhole,
        ),
        queue,
      ),
      onRefresh: (ref) {
        // The family behind the snapshot, not the lens wrapper alone: that
        // one only resolves the lens and re-watches its family member, which
        // keeps the answer it already had.
        ref.invalidate(lidarrQueueSnapshotsForProvider);
        // The rail's own non-swallowing read. See `movies_screen.dart`.
        ref.invalidate(lidarrKpiLibraryProvider);
      },
      settingsSelector: (settings) =>
          (settings.lidarrUrl, settings.lidarrApiKey),
      onItemTap: (context, artist, heroTag) {
        context.push(
          ServiceRoutes.lidarrArtist(artist.id, heroTag: heroTag),
          extra: artist,
        );
      },
      coverTypes: const ['poster', 'fanart', 'banner'],
      // An artist is not a poster. `LidarrArtists` draws a circular portrait
      // because a 2:3 crop of a band photograph invents artwork that does not
      // exist and cuts a face in half to do it.
      tileShape: MediaBrowseTileShape.circle,
      showAppBar: showAppBar,
      topPadding: topPadding,
      sorts: [
        MediaBrowseSort<LidarrArtist>.dateAdded((artist) => artist.added),
        MediaBrowseSort<LidarrArtist>.size(
          (artist) => switch (artist.statistics?['sizeOnDisk']) {
            final int bytes => bytes,
            final num bytes => bytes.toInt(),
            _ => 0,
          },
        ),
      ],
      // Null until the answer lands, so the chip appears with its set rather
      // than appearing first and filtering to nothing while the fetch is out.
      cutoffUnmetIds: ref
          .watch(lidarrCutoffUnmetArtistIdsProvider)
          .maybeWhen(data: (ids) => ids, orElse: () => null),
      kpiPeek: ServiceKpiPeek(
        kpis: ref.watch(serviceKpiProvider(ServiceKey.lidarr)),
        accent: ServiceKey.lidarr.accent,
      ),
    );
  }
}
