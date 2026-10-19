/// The public poster the arrs hold for a title: where a room or a slab whose
/// own pictures sit behind a key (a media server's, Bazarr, which has none)
/// reads the light of what it is about.
///
/// The arr record's remote artwork only (TMDB's, TheTVDB's), never the arr's
/// own copy, which is behind its key too: a light is read from a public
/// picture only.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/core/utils/arr_model_helpers.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/media/presentation/media_sources_provider.dart'
    show mediaTvdbIdProvider;
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The connections of [service] set up enough to ask, in the order the
/// settings keep them.
List<String> _askable(Ref ref, ServiceKey service) => [
  for (final instance
      in ref.watch(currentSettingsProvider).instancesOf(service))
    if (instance.isConfigured) instance.id,
];

/// The public poster of the title [MediaKey] names: Radarr's record of a movie
/// by TMDB's id, Sonarr's of a series by TVDB's, asked of each connection set
/// up until one holds it. Null when no arr holds the title, none answered, or
/// the record has no remote artwork.
final arrPublicPosterProvider = FutureProvider.autoDispose
    .family<String?, MediaKey>((ref, key) async {
      // Every service is subscribed before the first wait.
      if (key.isMovie) {
        final tmdbId = key.tmdbId;
        if (tmdbId == null) return null;
        final radarrs = [
          for (final id in _askable(ref, ServiceKey.radarr))
            ref.watch(radarrServiceForProvider(id)),
        ];
        for (final radarr in radarrs) {
          try {
            final movie = await radarr.getMovieByTmdbId(tmdbId);
            if (movie == null) continue;
            if (remotePosterOf(movie.images) case final poster?) return poster;
          } catch (_) {
            // That Radarr did not answer; another may hold the movie.
          }
        }
        return null;
      }
      final sonarrs = [
        for (final id in _askable(ref, ServiceKey.sonarr))
          ref.watch(sonarrServiceForProvider(id)),
      ];
      if (sonarrs.isEmpty) return null;
      final tvdbId = await ref.watch(mediaTvdbIdProvider(key).future);
      if (tvdbId == null) return null;
      for (final sonarr in sonarrs) {
        try {
          final series = await sonarr.getSeriesByTvdbId(tvdbId);
          if (series == null) continue;
          if (remotePosterOf(series.images) case final poster?) return poster;
        } catch (_) {
          // That Sonarr did not answer; another may hold the series.
        }
      }
      return null;
    }, retry: noProviderRetry);

/// A title as an arr knows it, by the arr's own id: what Bazarr names a movie
/// or a series by (`radarrId`, `sonarrSeriesId`), with the title it gives it.
typedef ArrTitleRef = ({ServiceKey service, int id, String title});

/// The public poster of the title [ArrTitleRef] names by an arr's own id: that
/// id's record on each connection of the arr set up, taken only when its title
/// is the one named. Bazarr follows one Radarr and one Sonarr, and the same id
/// on another connection is another title.
final arrPublicPosterByIdProvider = FutureProvider.autoDispose
    .family<String?, ArrTitleRef>((ref, title) async {
      final named = _comparable(title.title);
      if (named.isEmpty || title.id <= 0) return null;
      switch (title.service) {
        case ServiceKey.radarr:
          final radarrs = [
            for (final id in _askable(ref, ServiceKey.radarr))
              ref.watch(radarrServiceForProvider(id)),
          ];
          for (final radarr in radarrs) {
            try {
              final movie = await radarr.getMovieOrThrow(title.id);
              if (movie == null || _comparable(movie.title) != named) continue;
              return remotePosterOf(movie.images);
            } catch (_) {
              // That Radarr did not answer.
            }
          }
        case ServiceKey.sonarr:
          final sonarrs = [
            for (final id in _askable(ref, ServiceKey.sonarr))
              ref.watch(sonarrServiceForProvider(id)),
          ];
          for (final sonarr in sonarrs) {
            try {
              final series = await sonarr.getSeriesByIdOrThrow(title.id);
              if (series == null || _comparable(series.title) != named) {
                continue;
              }
              return remotePosterOf(series.images);
            } catch (_) {
              // That Sonarr did not answer.
            }
          }
        default:
          return null;
      }
      return null;
    }, retry: noProviderRetry);

/// [title] as two spellings of one title compare: its letters and digits,
/// lower case.
String _comparable(String title) =>
    title.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');
