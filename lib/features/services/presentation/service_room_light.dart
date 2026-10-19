import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/core/title_light.dart';
import 'package:cupola/core/utils/arr_model_helpers.dart';
import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/features/discover/presentation/seerr_overview_provider.dart';
import 'package:cupola/features/home/domain/downloads.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/movies/presentation/radarr_overview_provider.dart';
import 'package:cupola/features/series/presentation/sonarr_overview_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The services whose room is lit by what they hold (brand book, *The title
/// light*): a library's room by the download that leads its queue, else by
/// what arrived last; Seerr's by what is trending. Every other service room (a
/// download client, the machines, the indexers) is lit by the lamp.
const _litByWhatTheyHold = {
  ServiceKey.radarr,
  ServiceKey.sonarr,
  ServiceKey.lidarr,
  ServiceKey.seerr,
};

/// The artwork that lights [service]'s room: the poster of its first download
/// stuck, else of its first one moving, else of what arrived last (Seerr: what
/// is trending); a public picture only; null for the lamp.
final serviceRoomSourceProvider = Provider.autoDispose
    .family<String?, ServiceKey>((ref, service) {
      if (!_litByWhatTheyHold.contains(service)) return null;
      if (!ref.watch(currentSettingsProvider).isServiceConfigured(service)) {
        return null;
      }
      String? public(String? url) =>
          url != null && url.startsWith('http') ? url : null;
      if (service == ServiceKey.seerr) {
        final trending = ref.watch(seerrOverviewTrendingProvider).value;
        return [
          for (final item in trending ?? const <MediaPreview>[])
            ?public(ImageUtils.buildTmdbPosterUrl(item.posterPath)),
        ].firstOrNull;
      }
      final items = ref.watch(servicesQueueProvider).value?.items ?? const [];
      String? posterOf(bool Function(ServiceQueueItem item) leads) => [
        for (final item in items)
          if (item.service == service && leads(item)) ?public(item.posterUrl),
      ].firstOrNull;
      final queued =
          posterOf((item) => isDownloadFault(item.fault)) ??
          posterOf((item) => item.isMoving);
      if (queued != null) return queued;
      return switch (service) {
        ServiceKey.radarr => [
          for (final RadarrMovie movie
              in ref.watch(radarrRecentlyAddedProvider).value ?? const [])
            ?public(extractPosterPathFromImages(movie.images)),
        ].firstOrNull,
        ServiceKey.sonarr => [
          for (final episode
              in ref.watch(sonarrRecentlyDownloadedProvider).value ?? const [])
            ?public(extractPosterPathFromImages(episode.images)),
        ].firstOrNull,
        _ => null,
      };
    });

/// The light of [service]'s room ([serviceRoomSourceProvider]), or null for
/// the lamp.
final serviceRoomLightProvider = Provider.autoDispose
    .family<TitleLight?, ServiceKey>((ref, service) {
      final url = ref.watch(serviceRoomSourceProvider(service));
      return url == null ? null : ref.watch(titleLightProvider(url)).value;
    });
