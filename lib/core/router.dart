import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/utils/route_utils.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/prowlarr/domain/models/prowlarr_models.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/series/domain/models/sonarr_series.dart';
import 'package:cupola/features/shell/presentation/shell_screen.dart';
import 'package:cupola/features/discover/presentation/discover_screen.dart';
import 'package:cupola/features/activity/domain/service_type.dart';
import 'package:cupola/features/activity/presentation/activity_screen.dart';
import 'package:cupola/features/activity/presentation/global_activity_screen.dart';
import 'package:cupola/features/movies/presentation/movies_screen.dart';
import 'package:cupola/features/movies/presentation/movie_detail_screen.dart';
import 'package:cupola/features/series/presentation/series_screen.dart';
import 'package:cupola/features/series/presentation/series_detail_screen.dart';
import 'package:cupola/features/music/presentation/music_screen.dart';
import 'package:cupola/features/music/presentation/music_detail_screen.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';
import 'package:cupola/features/search/presentation/search_screen.dart';
import 'package:cupola/features/services/presentation/service_all_screens.dart';
import 'package:cupola/features/services/presentation/service_dashboard_screen.dart';
import 'package:cupola/features/services/presentation/services_screen.dart';
import 'package:cupola/features/discover/presentation/discover_detail_screen.dart';
import 'package:cupola/features/discover/presentation/discover_see_all_screen.dart';
import 'package:cupola/features/release_search/presentation/release_search_settings_screen.dart';
import 'package:cupola/features/settings/presentation/settings_appearance_screen.dart';
import 'package:cupola/features/settings/presentation/settings_hints_screen.dart';
import 'package:cupola/features/settings/presentation/settings_home_screen.dart';
import 'package:cupola/features/settings/presentation/settings_region_screen.dart';
import 'package:cupola/features/settings/presentation/settings_connections_screen.dart';
import 'package:cupola/features/settings/presentation/service_settings_screen.dart';
import 'package:cupola/features/settings/presentation/trusted_certificates_screen.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/import/presentation/manual_import_locate_screen.dart';
import 'package:cupola/features/import/presentation/manual_import_progress_screen.dart';
import 'package:cupola/features/import/presentation/manual_import_review_screen.dart';
import 'package:cupola/features/import/presentation/manual_import_routes.dart';
import 'package:cupola/features/onboarding/data/onboarding_provider.dart';
import 'package:cupola/features/onboarding/presentation/onboarding_screen.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_screen.dart';
import 'package:cupola/features/qbittorrent/presentation/torrent_detail_screen.dart';
import 'package:cupola/features/qbittorrent/presentation/widgets/qbittorrent_actions_bar.dart';
import 'package:cupola/features/bazarr/domain/models/bazarr_models.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_library_screen.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_movie_detail_screen.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_screen.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_screen.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_library_screen.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_indexer_detail_screen.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_settings_screen.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_provider_list_screen.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_app_profiles_screen.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_tags_screen.dart';
import 'package:cupola/features/readarr/presentation/readarr_screen.dart';
import 'package:cupola/features/readarr/presentation/readarr_library_screen.dart';
import 'package:cupola/features/sabnzbd/presentation/sabnzbd_screen.dart';
import 'package:cupola/features/npm/presentation/npm_screen.dart';
import 'package:cupola/features/transmission/presentation/transmission_screen.dart';
import 'package:cupola/features/nzbget/presentation/nzbget_screen.dart';
import 'package:cupola/features/stream/presentation/stream_dashboard_screen.dart';
import 'package:cupola/features/stream/presentation/stream_item_screen.dart';
import 'package:cupola/features/stream/presentation/stream_library_screen.dart';
import 'package:cupola/features/unraid/presentation/unraid_screen.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_series_detail_screen.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_wanted_screen.dart';
import 'package:cupola/features/dockge/presentation/dockge_screen.dart';
import 'package:cupola/features/dockge/presentation/dockge_stack_detail_screen.dart';
import 'package:cupola/features/dockge/presentation/dockge_stack_edit_screen.dart';
import 'package:cupola/features/truenas/presentation/truenas_hub_screen.dart';
import 'package:cupola/features/truenas/presentation/dashboard/truenas_dashboard_screen.dart';
import 'package:cupola/features/truenas/presentation/storage/truenas_storage_screen.dart';
import 'package:cupola/features/truenas/presentation/storage/truenas_pool_detail_screen.dart';
import 'package:cupola/features/truenas/presentation/datasets/truenas_datasets_screen.dart';
import 'package:cupola/features/truenas/presentation/datasets/truenas_dataset_detail_screen.dart';
import 'package:cupola/features/truenas/presentation/shares/truenas_shares_screen.dart';
import 'package:cupola/features/truenas/presentation/data_protection/truenas_data_protection_screen.dart';
import 'package:cupola/features/truenas/presentation/virt/truenas_virt_screen.dart';
import 'package:cupola/features/truenas/presentation/virt/truenas_virt_detail_screen.dart';
import 'package:cupola/features/truenas/presentation/apps/truenas_apps_screen.dart';
import 'package:cupola/features/truenas/presentation/apps/truenas_app_detail_screen.dart';
import 'package:cupola/features/truenas/presentation/reporting/truenas_reporting_screen.dart';
import 'package:cupola/features/truenas/presentation/system/truenas_system_hub_screen.dart';
import 'package:cupola/features/truenas/presentation/system/truenas_services_screen.dart';
import 'package:cupola/features/truenas/presentation/system/truenas_credentials_screen.dart';
import 'package:cupola/features/truenas/presentation/system/truenas_system_config_screens.dart';
import 'package:cupola/features/discover/presentation/person_detail_screen.dart';
import 'package:cupola/features/discover/presentation/collection_detail_screen.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final _shellNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'shell');

const double _serviceDashboardTopPadding = kToolbarHeight;

/// The page for a top-level tab: a short fade instead of the platform default.
///
/// Android's default here was [ZoomPageTransitionsBuilder], and on device it
/// was the tab switch's whole stutter: every switch spent 5–8 frames at
/// 30–38ms of raster scaling and cross-fading two full opaque screens — the
/// same cost on every switch, so not shader warm-up. Tabs are siblings, not a
/// hierarchy; a fade is what Material prescribes for top-level destinations,
/// and it costs one blend per frame instead of the Zoom's layered scale.
Page<void> _tabPage(GoRouterState state, Widget child) => CustomTransitionPage(
  key: state.pageKey,
  transitionDuration: AppAnimation.durationSm,
  reverseTransitionDuration: AppAnimation.durationSm,
  transitionsBuilder: (context, animation, secondaryAnimation, child) =>
      FadeTransition(
        opacity: animation.drive(CurveTween(curve: Curves.easeOut)),
        child: child,
      ),
  child: child,
);

/// A route whose page is a plain [RouteUtils.cupertinoPage] around [child].
///
/// Collapses the `pageBuilder: (context, state) => RouteUtils.cupertinoPage(
/// key: state.pageKey, child: ...)` shape that every non-redirecting page
/// route repeats. `state.pageKey` stays the page key, so go_router's page
/// identity is unchanged.
///
/// Routes whose page is *not* plain — the ones that return a redirect page for
/// bad params ([_discoverDetailPage], [_libraryDetailPage], [_manualImportPage])
/// or that swap between `builder` and `pageBuilder` — keep their long form.
GoRoute _page(
  String path,
  Widget Function(GoRouterState state) child, {
  GoRouterRedirect? redirect,
  List<RouteBase> routes = const [],
}) => GoRoute(
  path: path,
  redirect: redirect,
  routes: routes,
  pageBuilder: (context, state) =>
      RouteUtils.cupertinoPage(key: state.pageKey, child: child(state)),
);

Page<void> _discoverDetailPage(
  GoRouterState state, {
  required String mediaType,
}) {
  final id = RouteUtils.safeIntParam(state, 'id');
  if (id == null) {
    return RouteUtils.redirectPage(key: state.pageKey, location: '/services');
  }
  final heroTag =
      state.uri.queryParameters['heroTag'] ?? 'discover_${mediaType}_$id';
  // go_router already URL-decodes queryParameters; decoding again here would
  // double-decode a poster URL that contains a literal `%` sequence.
  final posterUrl = state.uri.queryParameters['posterUrl'];
  return RouteUtils.cupertinoPage(
    key: state.pageKey,
    child: DiscoverDetailScreen(
      mediaId: id,
      mediaType: mediaType,
      heroTag: heroTag,
      initialPosterUrl: posterUrl,
    ),
  );
}

Page<void> _libraryDetailPage<T>(
  GoRouterState state, {
  required String heroPrefix,
  required Widget Function(int id, String heroTag, T? initialItem) buildChild,
}) {
  final id = RouteUtils.safeIntParam(state, 'id');
  if (id == null) {
    return RouteUtils.redirectPage(key: state.pageKey, location: '/services');
  }
  final item = RouteUtils.safeExtra<T>(state);
  final heroTag = state.uri.queryParameters['heroTag'] ?? '${heroPrefix}_$id';
  return RouteUtils.cupertinoPage(
    key: state.pageKey,
    child: buildChild(id, heroTag, item),
  );
}

String _redirectLegacyManualImport(GoRouterState state) {
  return Uri(
    path: manualImportReviewPath,
    queryParameters: state.uri.queryParameters.isEmpty
        ? null
        : state.uri.queryParameters,
  ).toString();
}

Page<void> _manualImportPage(
  GoRouterState state,
  Widget Function(ServiceKey service, int? targetId) buildChild,
) {
  final service = manualImportServiceFromRoute(
    state.uri.queryParameters['service'],
  );
  if (service == null) {
    return RouteUtils.redirectPage(key: state.pageKey, location: '/activity');
  }

  final targetId = int.tryParse(state.uri.queryParameters['targetId'] ?? '');
  return RouteUtils.cupertinoPage(
    key: state.pageKey,
    child: buildChild(service, targetId),
  );
}

GoRoute _discoverRoutes({required String path, String? redirectLocation}) {
  return GoRoute(
    path: path,
    redirect: redirectLocation == null
        ? null
        : (context, state) => _redirectLegacyDiscover(state),
    builder: path.startsWith('/')
        ? (context, state) => const DiscoverScreen()
        : null,
    pageBuilder: path.startsWith('/')
        ? null
        : (context, state) => RouteUtils.cupertinoPage(
            key: state.pageKey,
            child: ServiceDashboardScreen(
              service: ServiceKey.seerr,
              child: const DiscoverScreen(
                showAppBar: false,
                topPadding: _serviceDashboardTopPadding,
              ),
            ),
          ),
    routes: [
      GoRoute(
        path: 'requests',
        builder: (context, state) => const ServiceAllRequestsScreen(),
      ),
      GoRoute(
        path: 'movies/all',
        builder: (context, state) =>
            const DiscoverSeeAllScreen(type: 'movies', title: 'Movies'),
      ),
      GoRoute(
        path: 'tv/all',
        builder: (context, state) =>
            const DiscoverSeeAllScreen(type: 'tv', title: 'TV Series'),
      ),
      GoRoute(
        path: 'trending/all',
        builder: (context, state) =>
            const DiscoverSeeAllScreen(type: 'trending', title: 'Trending'),
      ),
      GoRoute(
        path: 'genre/:mediaType/:genreId',
        redirect: (context, state) {
          final genreId = RouteUtils.safeIntParam(state, 'genreId');
          return genreId == null ? '/services/seerr' : null;
        },
        builder: (context, state) {
          final mediaType = state.pathParameters['mediaType'] == 'tv'
              ? 'tv'
              : 'movie';
          final genreId = RouteUtils.safeIntParam(state, 'genreId')!;
          final title = state.uri.queryParameters['title'] ?? 'Genre';
          return DiscoverSeeAllScreen(
            type: 'genre',
            title: title,
            genreKey: (mediaType: mediaType, genreId: genreId),
          );
        },
      ),
      GoRoute(
        path: 'movie/:id',
        redirect: (context, state) =>
            RouteUtils.safeIntParam(state, 'id') == null ? '/services' : null,
        pageBuilder: (context, state) =>
            _discoverDetailPage(state, mediaType: 'movie'),
      ),
      GoRoute(
        path: 'tv/:id',
        redirect: (context, state) =>
            RouteUtils.safeIntParam(state, 'id') == null ? '/services' : null,
        pageBuilder: (context, state) =>
            _discoverDetailPage(state, mediaType: 'tv'),
      ),
      _page(
        'person/:id',
        (state) => PersonDetailScreen(
          personId: RouteUtils.safeIntParam(state, 'id')!,
          heroTag: state.uri.queryParameters['heroTag'],
          initialProfileUrl: state.uri.queryParameters['posterUrl'],
        ),
        redirect: (context, state) =>
            RouteUtils.safeIntParam(state, 'id') == null ? '/services' : null,
      ),
      _page(
        'collection/:id',
        (state) => CollectionDetailScreen(
          collectionId: RouteUtils.safeIntParam(state, 'id')!,
          heroTag: state.uri.queryParameters['heroTag'],
        ),
        redirect: (context, state) =>
            RouteUtils.safeIntParam(state, 'id') == null ? '/services' : null,
      ),
    ],
  );
}

GoRoute _moviesRoutes({required String path, String? redirectLocation}) {
  return GoRoute(
    path: path,
    redirect: redirectLocation == null
        ? null
        : (context, state) => _redirectLegacyLibrary(
            state,
            legacyBase: '/movies',
            serviceBase: '/services/radarr/movie',
          ),
    builder: path.startsWith('/')
        ? (context, state) => const MoviesScreen()
        : null,
    pageBuilder: path.startsWith('/')
        ? null
        : (context, state) => RouteUtils.cupertinoPage(
            key: state.pageKey,
            child: ServiceDashboardScreen(
              service: ServiceKey.radarr,
              child: const MoviesScreen(
                showAppBar: false,
                topPadding: _serviceDashboardTopPadding,
              ),
            ),
          ),
    routes: [
      GoRoute(
        path: 'media',
        redirect: (context, state) =>
            _preserveQuery(state.uri, '/services/radarr'),
      ),
      GoRoute(
        path: path.startsWith('/') ? ':id' : 'movie/:id',
        redirect: (context, state) =>
            RouteUtils.safeIntParam(state, 'id') == null ? '/services' : null,
        pageBuilder: (context, state) => _libraryDetailPage<RadarrMovie>(
          state,
          heroPrefix: 'movie',
          buildChild: (id, heroTag, movie) => MovieDetailScreen(
            movieId: id,
            heroTag: heroTag,
            initialMovie: movie,
          ),
        ),
      ),
    ],
  );
}

GoRoute _seriesRoutes({required String path, String? redirectLocation}) {
  return GoRoute(
    path: path,
    redirect: redirectLocation == null
        ? null
        : (context, state) => _redirectLegacyLibrary(
            state,
            legacyBase: '/series',
            serviceBase: '/services/sonarr/series',
          ),
    builder: path.startsWith('/')
        ? (context, state) => const SeriesScreen()
        : null,
    pageBuilder: path.startsWith('/')
        ? null
        : (context, state) => RouteUtils.cupertinoPage(
            key: state.pageKey,
            child: ServiceDashboardScreen(
              service: ServiceKey.sonarr,
              child: const SeriesScreen(
                showAppBar: false,
                topPadding: _serviceDashboardTopPadding,
              ),
            ),
          ),
    routes: [
      GoRoute(
        path: 'media',
        redirect: (context, state) =>
            _preserveQuery(state.uri, '/services/sonarr'),
      ),
      GoRoute(
        path: path.startsWith('/') ? ':id' : 'series/:id',
        redirect: (context, state) =>
            RouteUtils.safeIntParam(state, 'id') == null ? '/services' : null,
        pageBuilder: (context, state) => _libraryDetailPage<SonarrSeries>(
          state,
          heroPrefix: 'series',
          buildChild: (id, heroTag, series) => SeriesDetailScreen(
            seriesId: id,
            heroTag: heroTag,
            initialSeries: series,
          ),
        ),
      ),
    ],
  );
}

GoRoute _musicRoutes({required String path, String? redirectLocation}) {
  return GoRoute(
    path: path,
    redirect: redirectLocation == null
        ? null
        : (context, state) => _redirectLegacyLibrary(
            state,
            legacyBase: '/music',
            serviceBase: '/services/lidarr/artist',
          ),
    builder: path.startsWith('/')
        ? (context, state) => const MusicScreen()
        : null,
    pageBuilder: path.startsWith('/')
        ? null
        : (context, state) => RouteUtils.cupertinoPage(
            key: state.pageKey,
            child: ServiceDashboardScreen(
              service: ServiceKey.lidarr,
              child: const MusicScreen(
                showAppBar: false,
                topPadding: _serviceDashboardTopPadding,
              ),
            ),
          ),
    routes: [
      GoRoute(
        path: 'media',
        redirect: (context, state) =>
            _preserveQuery(state.uri, '/services/lidarr'),
      ),
      GoRoute(
        path: path.startsWith('/') ? ':id' : 'artist/:id',
        redirect: (context, state) =>
            RouteUtils.safeIntParam(state, 'id') == null ? '/services' : null,
        pageBuilder: (context, state) => _libraryDetailPage<LidarrArtist>(
          state,
          heroPrefix: 'artist',
          buildChild: (id, heroTag, artist) => MusicDetailScreen(
            artistId: id,
            heroTag: heroTag,
            initialArtist: artist,
          ),
        ),
      ),
    ],
  );
}

GoRoute _qbittorrentRoutes({required String path}) {
  return _page(
    path,
    (state) => ServiceDashboardScreen(
      service: ServiceKey.qbittorrent,
      trailingAction: const QbittorrentActionsBar(),
      child: const QbittorrentScreen(topPadding: _serviceDashboardTopPadding),
    ),
    routes: [
      _page(
        'torrent/:hash',
        (state) =>
            TorrentDetailScreen(hash: state.pathParameters['hash'] ?? ''),
      ),
    ],
  );
}

GoRoute _bazarrRoutes({required String path}) {
  return _page(
    path,
    (state) => ServiceDashboardScreen(
      service: ServiceKey.bazarr,
      child: const BazarrScreen(
        showAppBar: false,
        topPadding: _serviceDashboardTopPadding,
      ),
    ),
    routes: [
      _page('wanted', (state) => const BazarrWantedScreen()),
      _page('library', (state) => const BazarrLibraryScreen()),
      // No `heroTag`: the Bazarr lead is a figure plate, not a poster, so
      // there is no source counterpart on a Bazarr row to fly from and an
      // orphan flight would fade in from nothing. The route still accepts the
      // query param (global search builds one for every service uniformly);
      // nothing reads it.
      _page(
        'series/:id',
        (state) => BazarrSeriesDetailScreen(
          sonarrSeriesId: RouteUtils.safeIntParam(state, 'id')!,
          initialWanted: RouteUtils.safeExtra<BazarrWantedItem>(state),
        ),
        redirect: (context, state) =>
            RouteUtils.safeIntParam(state, 'id') == null ? '/services' : null,
      ),
      // See the series route above: no Hero source, so no `heroTag`.
      _page(
        'movie/:id',
        (state) => BazarrMovieDetailScreen(
          radarrId: RouteUtils.safeIntParam(state, 'id')!,
          initialWanted: RouteUtils.safeExtra<BazarrWantedItem>(state),
        ),
        redirect: (context, state) =>
            RouteUtils.safeIntParam(state, 'id') == null ? '/services' : null,
      ),
    ],
  );
}

GoRoute _dockgeRoutes({required String path}) {
  return _page(
    path,
    (state) => ServiceDashboardScreen(
      service: ServiceKey.dockge,
      child: const DockgeScreen(
        showAppBar: false,
        topPadding: _serviceDashboardTopPadding,
      ),
    ),
    routes: [
      _page('new', (state) => const DockgeStackEditScreen()),
      _page(
        'stack/:name',
        (state) =>
            DockgeStackDetailScreen(name: state.pathParameters['name'] ?? ''),
        routes: [
          _page(
            'edit',
            (state) =>
                DockgeStackEditScreen(name: state.pathParameters['name'] ?? ''),
          ),
        ],
      ),
    ],
  );
}

GoRoute _prowlarrRoutes({required String path}) {
  return _page(
    path,
    (state) => ServiceDashboardScreen(
      service: ServiceKey.prowlarr,
      child: const ProwlarrScreen(
        showAppBar: false,
        topPadding: _serviceDashboardTopPadding,
      ),
    ),
    routes: [
      _page('library', (state) => const ProwlarrLibraryScreen()),
      _page(
        'indexer/:id',
        (state) => ProwlarrIndexerDetailScreen(
          indexerId: RouteUtils.safeIntParam(state, 'id')!,
        ),
        redirect: (context, state) =>
            RouteUtils.safeIntParam(state, 'id') == null ? '/services' : null,
      ),
      _page(
        'settings',
        (state) => const ProwlarrSettingsScreen(),
        routes: [
          _page('sync-profiles', (state) => const ProwlarrAppProfilesScreen()),
          _page('tags', (state) => const ProwlarrTagsScreen()),
          // One route for the four field-driven sections; an unknown segment
          // falls back to the hub rather than a blank screen.
          _page(
            ':section',
            (state) => ProwlarrProviderListScreen(
              kind: ProwlarrProviderKind.fromRouteSegment(
                state.pathParameters['section']!,
              )!,
            ),
            redirect: (context, state) =>
                ProwlarrProviderKind.fromRouteSegment(
                      state.pathParameters['section'] ?? '',
                    ) ==
                    null
                ? ServiceRoutes.prowlarrSettings
                : null,
          ),
        ],
      ),
    ],
  );
}

GoRoute _readarrRoutes({required String path}) {
  return _page(
    path,
    (state) => ServiceDashboardScreen(
      service: ServiceKey.readarr,
      child: const ReadarrScreen(
        showAppBar: false,
        topPadding: _serviceDashboardTopPadding,
      ),
    ),
    routes: [_page('library', (state) => const ReadarrLibraryScreen())],
  );
}

GoRoute _sabnzbdRoutes({required String path}) {
  return _page(
    path,
    (state) => ServiceDashboardScreen(
      service: ServiceKey.sabnzbd,
      child: const SabnzbdScreen(
        showAppBar: false,
        topPadding: _serviceDashboardTopPadding,
      ),
    ),
  );
}

GoRoute _nzbgetRoutes({required String path}) {
  return _page(
    path,
    (state) => ServiceDashboardScreen(
      service: ServiceKey.nzbget,
      child: const NzbgetScreen(
        showAppBar: false,
        topPadding: _serviceDashboardTopPadding,
      ),
    ),
  );
}

GoRoute _unraidRoutes({required String path}) {
  return _page(
    path,
    (state) => ServiceDashboardScreen(
      service: ServiceKey.unraid,
      child: const UnraidScreen(
        showAppBar: false,
        topPadding: _serviceDashboardTopPadding,
      ),
    ),
  );
}

GoRoute _transmissionRoutes({required String path}) {
  return _page(
    path,
    (state) => ServiceDashboardScreen(
      service: ServiceKey.transmission,
      child: const TransmissionScreen(
        showAppBar: false,
        topPadding: _serviceDashboardTopPadding,
      ),
    ),
  );
}

GoRoute _npmRoutes({required String path}) {
  return _page(
    path,
    (state) => ServiceDashboardScreen(
      service: ServiceKey.nginxProxyManager,
      child: const NpmScreen(
        showAppBar: false,
        topPadding: _serviceDashboardTopPadding,
      ),
    ),
  );
}

/// Dashboard, library browse and item detail for a media server.
///
/// One builder serves both Jellyfin and Plex: the Stream surfaces are written
/// against `StreamServerClient`, so the only per-service input is the [service]
/// key itself.
///
/// **The nested routes resolve from their path parameters alone.** `library/:id`
/// takes the display name as an optional `?title=` query so a caller that already
/// knows it can spare the destination a fetch, but a cold deep link works without
/// it. `item/:id` is a single recursive route covering film, show, season, episode,
/// album and track, because a Jellyfin `BaseItemDto` and a Plex `Metadata` describe
/// all of them with the same fields — where the arrs needed three screens.
///
/// Ids travel as path segments rather than through `_libraryDetailPage`, whose
/// `RouteUtils.safeIntParam` cannot represent a Jellyfin GUID or a Plex
/// `ratingKey`. They are guarded for emptiness here rather than dereferenced with
/// `!` or defaulted to `''`, which is the pattern the older string-id routes
/// (`torrent/:hash`, `stack/:name`) left unguarded.
GoRoute _streamRoutes({required ServiceKey service, required String path}) {
  return _page(
    path,
    (state) => StreamDashboardScreen(
      service: service,
      showAppBar: false,
      topPadding: _serviceDashboardTopPadding,
    ),
    routes: [
      _page(
        'library/:id',
        (state) => StreamLibraryScreen(
          service: service,
          libraryId: state.pathParameters['id']!,
          libraryTitle: state.uri.queryParameters['title'],
        ),
        redirect: (context, state) =>
            (state.pathParameters['id']?.trim().isEmpty ?? true)
            ? '/services/${service.routeParam}'
            : null,
      ),
      _page(
        'item/:id',
        (state) => StreamItemScreen(
          service: service,
          itemId: state.pathParameters['id']!,
        ),
        redirect: (context, state) =>
            (state.pathParameters['id']?.trim().isEmpty ?? true)
            ? '/services/${service.routeParam}'
            : null,
      ),
    ],
  );
}

GoRoute _truenasRoutes({required String path}) {
  return _page(
    path,
    (state) => ServiceDashboardScreen(
      service: ServiceKey.truenas,
      child: const TrueNasHubScreen(
        showAppBar: false,
        topPadding: _serviceDashboardTopPadding,
      ),
    ),
    routes: _truenasSectionRoutes(),
  );
}

/// Child routes for each TrueNAS management section.
List<GoRoute> _truenasSectionRoutes() => <GoRoute>[
  _page('dashboard', (state) => const TrueNasDashboardScreen()),
  _page(
    'storage',
    (state) => const TrueNasStorageScreen(),
    routes: [
      _page(
        'pool/:name',
        (state) =>
            TrueNasPoolDetailScreen(poolName: state.pathParameters['name']!),
      ),
    ],
  ),
  _page(
    'datasets',
    (state) => const TrueNasDatasetsScreen(),
    routes: [
      _page(
        'detail',
        (state) => TrueNasDatasetDetailScreen(
          datasetId: state.uri.queryParameters['id']!,
        ),
        redirect: (context, state) =>
            (state.uri.queryParameters['id'] ?? '').isEmpty
            ? '/services/truenas/datasets'
            : null,
      ),
    ],
  ),
  _page('shares', (state) => const TrueNasSharesScreen()),
  _page('data-protection', (state) => const TrueNasDataProtectionScreen()),
  _page(
    'containers',
    (state) => const TrueNasVirtScreen(
      type: 'CONTAINER',
      title: 'Containers',
      experimental: true,
    ),
    routes: [
      _page(
        'instance/:id',
        (state) => TrueNasVirtDetailScreen(
          id: state.pathParameters['id']!,
          type: 'CONTAINER',
        ),
      ),
    ],
  ),
  _page(
    'vms',
    (state) => const TrueNasVirtScreen(type: 'VM', title: 'Virtual Machines'),
    routes: [
      _page(
        'instance/:id',
        (state) => TrueNasVirtDetailScreen(
          id: state.pathParameters['id']!,
          type: 'VM',
        ),
      ),
    ],
  ),
  _page(
    'apps',
    (state) => const TrueNasAppsScreen(),
    routes: [
      _page(
        'app/:name',
        (state) => TrueNasAppDetailScreen(name: state.pathParameters['name']!),
      ),
    ],
  ),
  _page('reporting', (state) => const TrueNasReportingScreen()),
  _page(
    'system',
    (state) => const TrueNasSystemHubScreen(),
    routes: [
      _page('general', (state) => const TrueNasGeneralScreen()),
      _page('advanced', (state) => const TrueNasAdvancedScreen()),
      _page('services', (state) => const TrueNasServicesScreen()),
      _page('network', (state) => const TrueNasNetworkScreen()),
      _page('credentials', (state) => const TrueNasCredentialsScreen()),
      _page('certificates', (state) => const TrueNasCertificatesScreen()),
      _page('email', (state) => const TrueNasEmailScreen()),
      _page('update', (state) => const TrueNasUpdateScreen()),
      _page('ntp', (state) => const TrueNasNtpScreen()),
      _page('alert-settings', (state) => const TrueNasAlertSettingsScreen()),
    ],
  ),
];

String? _redirectLegacyDiscover(GoRouterState state) {
  final path = state.uri.path;
  if (path == '/discover') return '/services';

  const legacyBase = '/discover/';
  if (!path.startsWith(legacyBase)) return null;

  final suffix = path.substring(legacyBase.length);
  if (suffix == 'movies/all' ||
      suffix == 'tv/all' ||
      suffix == 'trending/all' ||
      suffix.startsWith('movie/') ||
      suffix.startsWith('tv/')) {
    return _preserveQuery(state.uri, '/services/seerr/$suffix');
  }

  return '/services';
}

String? _redirectLegacyLibrary(
  GoRouterState state, {
  required String legacyBase,
  required String serviceBase,
}) {
  final path = state.uri.path;
  if (path == legacyBase) return '/services';

  final prefix = '$legacyBase/';
  if (!path.startsWith(prefix)) return null;

  final id = path.substring(prefix.length);
  if (id.isEmpty || id.contains('/')) return '/services';
  return _preserveQuery(state.uri, '$serviceBase/$id');
}

String _preserveQuery(Uri source, String path) {
  final query = source.hasQuery ? '?${source.query}' : '';
  return '$path$query';
}

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = ref.watch(routerRefreshNotifierProvider);
  final onboardingDone = ref.read(onboardingCompletedProvider);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    refreshListenable: notifier,
    initialLocation: onboardingDone ? '/services' : '/onboarding',
    redirect: (context, state) {
      final done = ref.read(onboardingCompletedProvider);
      final isOnboarding = state.matchedLocation == '/onboarding';
      if (!done && !isOnboarding) return '/onboarding';
      if (done && isOnboarding) return '/services';
      return null;
    },
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) {
          return ShellScreen(child: child);
        },
        routes: [
          GoRoute(
            path: '/services',
            pageBuilder: (context, state) =>
                _tabPage(state, const ServicesScreen()),
            routes: [
              _discoverRoutes(path: 'seerr'),
              _moviesRoutes(path: 'radarr'),
              _seriesRoutes(path: 'sonarr'),
              _musicRoutes(path: 'lidarr'),
              _qbittorrentRoutes(path: 'qbittorrent'),
              _bazarrRoutes(path: 'bazarr'),
              _truenasRoutes(path: 'truenas'),
              _dockgeRoutes(path: 'dockge'),
              _prowlarrRoutes(path: 'prowlarr'),
              _readarrRoutes(path: 'readarr'),
              _sabnzbdRoutes(path: 'sabnzbd'),
              _nzbgetRoutes(path: 'nzbget'),
              _unraidRoutes(path: 'unraid'),
              _transmissionRoutes(path: 'transmission'),
              // `npm`, not `nginxProxyManager` — see `ServiceKey.routeParam`.
              _npmRoutes(path: ServiceKey.nginxProxyManager.routeParam),
              _streamRoutes(service: ServiceKey.jellyfin, path: 'jellyfin'),
              _streamRoutes(service: ServiceKey.plex, path: 'plex'),
            ],
          ),
          GoRoute(
            path: '/activity',
            pageBuilder: (context, state) =>
                _tabPage(state, const GlobalActivityScreen()),
          ),
          GoRoute(
            path: manualImportBrowsePath,
            pageBuilder: (context, state) => _manualImportPage(
              state,
              (service, targetId) => ManualImportLocateScreen(
                service: service,
                targetId: targetId,
                initialPath: state.uri.queryParameters['path'],
              ),
            ),
          ),
          GoRoute(
            path: manualImportReviewPath,
            pageBuilder: (context, state) => _manualImportPage(
              state,
              (service, targetId) => ManualImportReviewScreen(
                service: service,
                targetId: targetId,
              ),
            ),
          ),
          // Steps of the retired four-screen flow; an old deep link lands on
          // the merged Review station instead of dead-ending.
          GoRoute(
            path: manualImportFolderPath,
            redirect: (context, state) => _redirectLegacyManualImport(state),
          ),
          GoRoute(
            path: manualImportMatchPath,
            redirect: (context, state) => _redirectLegacyManualImport(state),
          ),
          GoRoute(
            path: manualImportProgressPath,
            pageBuilder: (context, state) => _manualImportPage(
              state,
              (service, targetId) =>
                  ManualImportProgressScreen(service: service),
            ),
          ),
          GoRoute(
            path: '/search',
            pageBuilder: (context, state) =>
                _tabPage(state, const SearchScreen()),
          ),
          _discoverRoutes(path: '/discover', redirectLocation: '/services'),
          _moviesRoutes(path: '/movies', redirectLocation: '/services'),
          _seriesRoutes(path: '/series', redirectLocation: '/services'),
          _musicRoutes(path: '/music', redirectLocation: '/services'),
          GoRoute(
            path: '/settings',
            pageBuilder: (context, state) =>
                _tabPage(state, const SettingsHomeScreen()),
            routes: [
              GoRoute(
                path: 'background-search',
                builder: (context, state) =>
                    const ReleaseSearchSettingsScreen(),
              ),
              _page('appearance', (state) => const SettingsAppearanceScreen()),
              _page('hints', (state) => const SettingsHintsScreen()),
              _page(
                'connections',
                (state) => const SettingsConnectionsScreen(),
              ),
              // Former name of the connections screen, kept so an existing
              // deep link or a shortcut does not dead-end.
              GoRoute(
                path: 'services',
                redirect: (context, state) => '/settings/connections',
              ),
              _page('region', (state) => const SettingsRegionScreen()),
              _page(
                'certificates',
                (state) => const TrustedCertificatesScreen(),
              ),
              _page('service/:service', (state) {
                final serviceParam = state.pathParameters['service'];
                // Accept 'jellyseerr' as a legacy alias for 'seerr'.
                final normalizedParam = serviceParam == 'jellyseerr'
                    ? 'seerr'
                    : serviceParam;
                final service = ServiceKey.values.firstWhere(
                  (s) => s.routeParam == normalizedParam,
                  orElse: () => ServiceKey.seerr,
                );
                return ServiceSettingsScreen(service: service);
              }),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/activity/:type',
        builder: (context, state) {
          final typeStr = state.pathParameters['type']!;
          final type = ServiceType.values.firstWhere(
            (e) => e.name == typeStr,
            orElse: () => ServiceType.movies,
          );
          return ActivityScreen(serviceType: type);
        },
      ),
    ],
  );
});
