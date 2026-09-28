import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Opens a Seerr item in the Radarr or Sonarr that tracks it.
///
/// The jump is a cross-service control: callers draw it with
/// `CrossServiceAction`, which answers the not-set-up case itself.
Future<bool> openMediaInService({
  required BuildContext context,
  required WidgetRef ref,
  required String mediaType,
  required int tmdbId,
  int? tvdbId,
  VoidCallback? dismissSheet,
  String movieNotFoundMessage = 'Movie not found in Radarr',
  String seriesNotFoundMessage = 'Series not found in Sonarr',
}) async {
  if (mediaType == 'movie') {
    return _openMovieInService(
      context: context,
      ref: ref,
      tmdbId: tmdbId,
      dismissSheet: dismissSheet,
      notFoundMessage: movieNotFoundMessage,
    );
  }

  return _openSeriesInService(
    context: context,
    ref: ref,
    tvdbId: tvdbId,
    dismissSheet: dismissSheet,
    notFoundMessage: seriesNotFoundMessage,
  );
}

Future<bool> _openMovieInService({
  required BuildContext context,
  required WidgetRef ref,
  required int tmdbId,
  VoidCallback? dismissSheet,
  required String notFoundMessage,
}) async {
  // Callers gate this jump with `CrossServiceAction`, whose toast is the
  // not-set-up answer; reaching here unconfigured is a race, and it opens
  // nothing rather than stacking a second, modal answer on the first.
  if (!ref
      .read(currentSettingsProvider)
      .isServiceConfigured(ServiceKey.radarr)) {
    return false;
  }

  try {
    final radarrService = ref.read(radarrServiceProvider);
    final movie = await radarrService.getMovieByTmdbId(tmdbId);
    if (!context.mounted) {
      return false;
    }

    if (movie == null) {
      SnackBarHelper.info(context, notFoundMessage);
      return false;
    }

    final router = GoRouter.of(context);
    dismissSheet?.call();
    router.push(
      ServiceRoutes.radarrMovie(movie.id, heroTag: 'radarr_${movie.id}'),
      extra: movie,
    );
    return true;
  } catch (error) {
    if (!context.mounted) {
      return false;
    }

    SnackBarHelper.error(
      context,
      "Couldn't open this in Radarr.",
      detail: error,
    );
    return false;
  }
}

Future<bool> _openSeriesInService({
  required BuildContext context,
  required WidgetRef ref,
  required int? tvdbId,
  VoidCallback? dismissSheet,
  required String notFoundMessage,
}) async {
  // Callers gate this jump with `CrossServiceAction`, whose toast is the
  // not-set-up answer; reaching here unconfigured is a race, and it opens
  // nothing rather than stacking a second, modal answer on the first.
  if (!ref
      .read(currentSettingsProvider)
      .isServiceConfigured(ServiceKey.sonarr)) {
    return false;
  }

  if (tvdbId == null) {
    SnackBarHelper.info(context, 'TVDB ID not available');
    return false;
  }

  try {
    final sonarrService = ref.read(sonarrServiceProvider);
    final series = await sonarrService.getSeriesByTvdbId(tvdbId);
    if (!context.mounted) {
      return false;
    }

    if (series == null) {
      SnackBarHelper.info(context, notFoundMessage);
      return false;
    }

    final router = GoRouter.of(context);
    dismissSheet?.call();
    router.push(
      ServiceRoutes.sonarrSeries(series.id, heroTag: 'sonarr_${series.id}'),
      extra: series,
    );
    return true;
  } catch (error) {
    if (!context.mounted) {
      return false;
    }

    SnackBarHelper.error(
      context,
      "Couldn't open this in Sonarr.",
      detail: error,
    );
    return false;
  }
}
