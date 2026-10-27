import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/api/base_arr_service.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/features/activity/domain/service_type.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_formatters.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/release_search/domain/release_search_target.dart';
import 'package:cupola/features/release_search/presentation/release_search_entry.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

int? extractWantedItemId(ServiceType serviceType, Map<String, dynamic> item) {
  switch (serviceType) {
    case ServiceType.movies:
      return intOrNull(item['id'] ?? item['movieId']);
    case ServiceType.series:
      return intOrNull(item['id']);
    case ServiceType.music:
      return intOrNull(item['id'] ?? item['albumId']);
    case ServiceType.discover:
      return null;
  }
}

Future<void> runWantedAutoSearch(
  BuildContext context,
  ArrActivityMixin service,
  ServiceType serviceType,
  Map<String, dynamic> item,
) async {
  final itemId = extractWantedItemId(serviceType, item);
  if (itemId == null) return;

  try {
    switch (serviceType) {
      case ServiceType.movies:
        await (service as RadarrService).searchMovie(itemId);
        break;
      case ServiceType.series:
        await (service as SonarrService).searchEpisodes([itemId]);
        break;
      case ServiceType.music:
        await (service as LidarrService).searchAlbums([itemId]);
        break;
      case ServiceType.discover:
        return;
    }

    if (!context.mounted) return;
    // "<Service> is searching <what>": the one shape every detail page uses.
    // This surface is one tap from those pages and used to answer a search with
    // a bare "Search started", which named neither the actor nor the scope.
    SnackBarHelper.success(
      context,
      '${_serviceName(serviceType)} is searching ${_scopeLabel(serviceType)}',
    );
  } catch (error) {
    if (!context.mounted) return;
    SnackBarHelper.error(
      context,
      "Could not start a search in ${_serviceName(serviceType)}.",
      detail: error,
    );
  }
}

/// Opens interactive search for a Wanted row.
///
/// Takes a [WidgetRef] rather than a service because the single entry point
/// resolves the service from the target, which is also what makes this row obey
/// the same adoption and cache rules as the detail screens.
Future<void> showWantedInteractiveSearch(
  BuildContext context,
  WidgetRef ref,
  ServiceType serviceType,
  Map<String, dynamic> item, {
  String? title,

  /// The connection this row came off, for the surfaces that show more than
  /// one. Empty leaves the target unstamped, and `showReleaseSearch` falls back
  /// to the lens exactly as it did before, which is what the per-service
  /// Activity screen, whose title names its lens, actually wants.
  String instanceId = '',
}) async {
  final itemId = extractWantedItemId(serviceType, item);
  if (itemId == null) return;

  // The sheet heads itself "Releases" and this string lands in its subtitle, so
  // "Releases for X" printed the word twice. Capped for the same reason the
  // detail screens cap it: the subtitle is where an untrusted service title
  // lands, and a 200-character one grows the header until it eats the list.
  final sheetTitle = truncateTitle(
    title ?? stringOrNull(item['title']) ?? _fallbackLabel(serviceType),
  );

  final target = switch (serviceType) {
    ServiceType.movies => ReleaseSearchTarget.movie(
      movieId: itemId,
      label: sheetTitle,
    ),
    // A Wanted row knows the episode but not its season, so this target cannot
    // be matched to a running season search: the containment check requires
    // both, and guessing would adopt a job that does not cover this episode.
    ServiceType.series => ReleaseSearchTarget.episode(
      episodeId: itemId,
      label: sheetTitle,
    ),
    ServiceType.music => ReleaseSearchTarget.album(
      albumId: itemId,
      label: sheetTitle,
    ),
    ServiceType.discover => null,
  };
  if (target == null) return;

  await showReleaseSearch(
    context,
    ref,
    instanceId.isEmpty ? target : target.stampedWith(instanceId),
  );
}

String _fallbackLabel(ServiceType serviceType) {
  return switch (serviceType) {
    ServiceType.movies => 'Movie',
    ServiceType.series => 'Episode',
    ServiceType.music => 'Album',
    ServiceType.discover => 'Item',
  };
}

/// The service that will actually do the work, named in its own confirmation.
String _serviceName(ServiceType serviceType) {
  return switch (serviceType) {
    ServiceType.movies => ServiceKey.radarr.title,
    ServiceType.series => ServiceKey.sonarr.title,
    ServiceType.music => ServiceKey.lidarr.title,
    ServiceType.discover => ServiceKey.seerr.title,
  };
}

/// What the search covers, in the words the detail pages use.
String _scopeLabel(ServiceType serviceType) {
  return switch (serviceType) {
    ServiceType.movies => 'for this movie',
    ServiceType.series => 'this episode',
    ServiceType.music => 'this album',
    ServiceType.discover => 'this title',
  };
}
