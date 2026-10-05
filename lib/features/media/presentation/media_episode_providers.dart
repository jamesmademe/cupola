import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/media/domain/media_series.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/series/domain/models/sonarr_episode_file.dart';

/// The episodes of one season as TMDB keeps them, through the Seerr
/// [connectionId]: read when an episode's sheet, or the graph, opens.
final mediaSeasonFactsProvider = FutureProvider.autoDispose
    .family<
      List<MediaEpisodeFacts>,
      ({String connectionId, int tvId, int season})
    >((ref, source) async {
      final seerr = ref.watch(seerrServiceForProvider(source.connectionId));
      return mediaEpisodeFactsOf(
        await seerr.getTvSeason(source.tvId, source.season),
      );
    }, retry: noProviderRetry);

/// The files the Sonarr [connectionId] holds for the series [seriesId], by
/// file id: read when an episode's sheet opens.
final mediaEpisodeFilesProvider = FutureProvider.autoDispose
    .family<Map<int, SonarrEpisodeFile>, ({String connectionId, int seriesId})>(
      (ref, source) async {
        final files = await ref
            .watch(sonarrServiceForProvider(source.connectionId))
            .getEpisodeFiles(source.seriesId);
        return {for (final file in files) file.id: file};
      },
      retry: noProviderRetry,
    );

/// The resolution the Sonarr [connectionId]'s profile [profileId] stops at,
/// `1080p`; null when it names none or could not be read.
final mediaSonarrCutoffProvider = FutureProvider.autoDispose
    .family<String?, ({String connectionId, int profileId})>((
      ref,
      source,
    ) async {
      try {
        final profiles = await ref
            .watch(sonarrServiceForProvider(source.connectionId))
            .getQualityProfiles();
        for (final profile in profiles) {
          if (profile['id'] == source.profileId) {
            return sonarrCutoffResolution(profile);
          }
        }
      } catch (_) {
        // No cutoff to name: the sheet says the file is below it.
      }
      return null;
    }, retry: noProviderRetry);

/// The quality profiles of the Sonarr [connectionId], by id: what a series'
/// profile row is called and may become.
final mediaSonarrProfilesProvider = FutureProvider.autoDispose
    .family<Map<int, String>, String>((ref, connectionId) async {
      final profiles = await ref
          .watch(sonarrServiceForProvider(connectionId))
          .getQualityProfiles();
      return {
        for (final profile in profiles)
          if (profile['id'] case final int id) id: '${profile['name'] ?? ''}',
      };
    }, retry: noProviderRetry);

/// The Sonarr [connectionId]'s history of the series [seriesId], newest
/// first: read when Manage's History opens.
final mediaSonarrHistoryProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, ({String connectionId, int seriesId})>((
      ref,
      source,
    ) {
      return ref
          .watch(sonarrServiceForProvider(source.connectionId))
          .getSeriesHistory(source.seriesId);
    }, retry: noProviderRetry);
