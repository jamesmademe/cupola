import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/widgets/service_tab_bar.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/services/presentation/service_tab_placeholder.dart';
import 'package:cupola/features/services/presentation/service_tab_scaffold.dart';
import 'package:cupola/core/utils/route_utils.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/prowlarr/domain/models/prowlarr_models.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/movies/presentation/radarr_overview_screen.dart';
import 'package:cupola/features/series/domain/models/sonarr_series.dart';
import 'package:cupola/features/settings/domain/nav_tab.dart';
import 'package:cupola/features/shell/domain/shell_branches.dart';
import 'package:cupola/features/shell/presentation/branch_transition.dart';
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
import 'package:cupola/features/services/presentation/service_home_screen.dart';
import 'package:cupola/features/services/presentation/dashboard_screen.dart';
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

const double _serviceHomeTopPadding = kToolbarHeight;

/// Room the service band AND the tab bar take above a tab's content.
///
/// Composed rather than written out: the two bands stack, so a hosted screen
/// inside a tabbed service has to clear both, and a literal here would be a
/// second place for the bar's height to be wrong.
const double _serviceTabTopPadding =
    _serviceHomeTopPadding + ServiceTabBar.height;

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
    return RouteUtils.redirectPage(
      key: state.pageKey,
      location: ServiceRoutes.dashboard,
    );
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
  required Widget Function(
    int id,
    String heroTag,
    T? initialItem,
    String? instanceId,
  )
  buildChild,
}) {
  final id = RouteUtils.safeIntParam(state, 'id');
  if (id == null) {
    return RouteUtils.redirectPage(
      key: state.pageKey,
      location: ServiceRoutes.dashboard,
    );
  }
  final item = RouteUtils.safeExtra<T>(state);
  final heroTag = state.uri.queryParameters['heroTag'] ?? '${heroPrefix}_$id';
  // Null when the link did not name one, which is every link that predates a
  // service being able to have two — see `ServiceRoutes` for why this rides in
  // the query rather than in a path segment or in `extra`.
  return RouteUtils.cupertinoPage(
    key: state.pageKey,
    child: buildChild(id, heroTag, item, state.uri.queryParameters['i']),
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
  Widget Function(ServiceKey service, int? targetId, String? instanceId)
  buildChild,
) {
  final service = manualImportServiceFromRoute(
    state.uri.queryParameters['service'],
  );
  if (service == null) {
    return RouteUtils.redirectPage(key: state.pageKey, location: '/activity');
  }

  final targetId = int.tryParse(state.uri.queryParameters['targetId'] ?? '');
  // `?i=` names the connection the wizard is bound to, exactly as
  // `_libraryDetailPage` reads it for the detail routes. It has to be read
  // here or `manualImportLocation`'s whole `instanceId` argument is inert: a
  // failed-import row on a non-lensed connection would open a wizard that
  // re-resolves the service through the lens, browse the wrong server's disk
  // and move the files into the wrong library. Null when the link named none,
  // which is every link that predates a service being able to have two.
  return RouteUtils.cupertinoPage(
    key: state.pageKey,
    child: buildChild(service, targetId, state.uri.queryParameters['i']),
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
            child: ServiceHomeScreen(
              service: ServiceKey.seerr,
              child: const DiscoverScreen(
                showAppBar: false,
                topPadding: _serviceHomeTopPadding,
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
          return genreId == null ? ServiceRoutes.seerr : null;
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
            RouteUtils.safeIntParam(state, 'id') == null
            ? ServiceRoutes.dashboard
            : null,
        pageBuilder: (context, state) =>
            _discoverDetailPage(state, mediaType: 'movie'),
      ),
      GoRoute(
        path: 'tv/:id',
        redirect: (context, state) =>
            RouteUtils.safeIntParam(state, 'id') == null
            ? ServiceRoutes.dashboard
            : null,
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
            RouteUtils.safeIntParam(state, 'id') == null
            ? ServiceRoutes.dashboard
            : null,
      ),
      _page(
        'collection/:id',
        (state) => CollectionDetailScreen(
          collectionId: RouteUtils.safeIntParam(state, 'id')!,
          heroTag: state.uri.queryParameters['heroTag'],
        ),
        redirect: (context, state) =>
            RouteUtils.safeIntParam(state, 'id') == null
            ? ServiceRoutes.dashboard
            : null,
      ),
    ],
  );
}

/// The pre-tab-model `/movies` tree, which now exists only to redirect.
///
/// Radarr itself lives in [_radarrRoutes]. This kept its `:id` child so the
/// redirect can carry a deep link's own parameters across in ONE hop —
/// `/movies/42?heroTag=x` lands directly on the film inside the Library tab
/// rather than bouncing through the service root and losing where it was going.
GoRoute _moviesRoutes({required String path}) {
  return GoRoute(
    path: path,
    redirect: (context, state) => _redirectLegacyLibrary(
      state,
      legacyBase: '/movies',
      serviceBase: ServiceRoutes.radarrMovieBase,
    ),
    builder: (context, state) => const MoviesScreen(),
    routes: [
      GoRoute(
        path: ':id',
        redirect: (context, state) =>
            RouteUtils.safeIntParam(state, 'id') == null
            ? ServiceRoutes.dashboard
            : null,
        pageBuilder: (context, state) => _libraryDetailPage<RadarrMovie>(
          state,
          heroPrefix: 'movie',
          buildChild: (id, heroTag, movie, instanceId) => MovieDetailScreen(
            movieId: id,
            heroTag: heroTag,
            initialMovie: movie,
            instanceId: instanceId,
          ),
        ),
      ),
    ],
  );
}

/// Radarr: one shell, one branch per tab.
///
/// **Nested inside the Dashboard branch, not mounted beside it.** Everything
/// the app shell owns — the nav bar, the Portal, the whole desktop chrome —
/// hangs off the page the four-branch shell builds. A sibling shell at root
/// would replace that page, so opening a service would take the app's own
/// navigation away with it.
///
/// The `radarr` node itself builds nothing: it is a redirect-only prefix whose
/// entire job is to send the bare service path to Overview. **Its guard is
/// load-bearing.** A route-level redirect fires for every match in the list,
/// descendants included, so an unguarded one here would bounce
/// `/dashboard/radarr/library` back to Overview forever.
RouteBase _radarrRoutes() {
  const service = ServiceKey.radarr;
  final tabs = tabsFor(service)!;

  return GoRoute(
    path: service.routeParam,
    redirect: (context, state) => state.uri.path == ServiceRoutes.radarr
        ? _preserveQuery(state.uri, ServiceRoutes.radarrOverview)
        : null,
    routes: [
      // The tab-less tails, childless on purpose: the matcher treats a prefix
      // hit with no complete match as no match at all, so `movie/:id` here
      // cannot shadow `library/movie/:id` inside the shell below.
      GoRoute(
        path: 'media',
        redirect: (context, state) =>
            _preserveQuery(state.uri, ServiceRoutes.radarrLibrary),
      ),
      // Every link the app shipped before the tab model, and the second hop of
      // every `/services/radarr/movie/42`. No id validation here: the canonical
      // route below owns it, and doing it twice is two places to get it wrong.
      GoRoute(
        path: 'movie/:id',
        redirect: (context, state) => _preserveQuery(
          state.uri,
          '${ServiceRoutes.radarrMovieBase}/${state.pathParameters['id']}',
        ),
      ),
      StatefulShellRoute(
        navigatorContainerBuilder: buildBranchTransition,
        // `pageBuilder`, not `builder`: without it the shell's page takes the
        // platform default transition, and the push from the Dashboard into a
        // service would stop matching every other service in the app.
        pageBuilder: (context, state, navigationShell) =>
            RouteUtils.cupertinoPage(
              key: state.pageKey,
              child: ServiceHomeScreen(
                service: service,
                // The band is drawn above every branch navigator, so a pushed
                // page cannot cover it the way it covers the tab bar. It hides
                // itself instead — the film brings its own back control.
                showAppBar: isServiceTabRoot(service, state.uri.path),
                child: navigationShell,
              ),
            ),
        branches: [
          for (final tab in tabs)
            StatefulShellBranch(
              navigatorKey: serviceBranchNavigatorKeyFor(service, tab),
              routes: [_radarrBranchRoot(tab)],
            ),
        ],
      ),
    ],
  );
}

/// The route at the root of one Radarr tab.
///
/// Branch order is `tabsFor(ServiceKey.radarr)` and nothing else, because the
/// bar is generated from the same list: an index that named a different branch
/// would light one tab and show another. The wildcard throws rather than
/// quietly rendering a placeholder — a seventh tab added to that table with no
/// case here is a bar and a router disagreeing, and that has to fail loudly.
GoRoute _radarrBranchRoot(ServiceTab tab) => switch (tab) {
  ServiceTab.overview => _page(
    tab.segment,
    (state) => const ServiceTabScaffold(
      service: ServiceKey.radarr,
      tab: ServiceTab.overview,
      child: RadarrOverviewScreen(topPadding: _serviceTabTopPadding),
    ),
  ),
  ServiceTab.library => _page(
    tab.segment,
    (state) => const ServiceTabScaffold(
      service: ServiceKey.radarr,
      tab: ServiceTab.library,
      child: MoviesScreen(showAppBar: false, topPadding: _serviceTabTopPadding),
    ),
    routes: [
      // The detail, now INSIDE the Library branch. Pushing it keeps the branch,
      // so leaving Radarr for another app tab and coming back returns to the
      // film — and the Hero still flies, because source and destination are in
      // one Navigator.
      GoRoute(
        path: 'movie/:id',
        redirect: (context, state) =>
            RouteUtils.safeIntParam(state, 'id') == null
            ? ServiceRoutes.radarrLibrary
            : null,
        pageBuilder: (context, state) => _libraryDetailPage<RadarrMovie>(
          state,
          heroPrefix: 'movie',
          buildChild: (id, heroTag, movie, instanceId) => MovieDetailScreen(
            movieId: id,
            heroTag: heroTag,
            initialMovie: movie,
            instanceId: instanceId,
          ),
        ),
      ),
    ],
  ),
  // The four whose data the client cannot fetch yet. The branch is declared
  // from day one because the bar draws all six labels off `tabsFor`; a missing
  // branch would be a tab that 404s rather than one that says it is not built.
  ServiceTab.calendar ||
  ServiceTab.queue ||
  ServiceTab.wanted ||
  ServiceTab.history => _page(
    tab.segment,
    (state) => ServiceTabScaffold(
      service: ServiceKey.radarr,
      tab: tab,
      child: ServiceTabPlaceholder(service: ServiceKey.radarr, tab: tab),
    ),
  ),
  _ => throw UnsupportedError(
    'ServiceTab.${tab.name} is on radarr\'s bar with no branch root',
  ),
};

/// The pre-tab-model `/series` tree, which now exists only to redirect.
///
/// Sonarr itself lives in [_sonarrRoutes]. Like `/movies` this keeps its `:id`
/// child so a deep link crosses in ONE hop — `/series/55?heroTag=x` lands on
/// the show inside the Library tab rather than bouncing through the service
/// root and losing where it was going.
GoRoute _seriesRoutes({required String path}) {
  return GoRoute(
    path: path,
    redirect: (context, state) => _redirectLegacyLibrary(
      state,
      legacyBase: '/series',
      serviceBase: ServiceRoutes.sonarrSeriesBase,
    ),
    builder: (context, state) => const SeriesScreen(),
    routes: [
      GoRoute(
        path: ':id',
        redirect: (context, state) =>
            RouteUtils.safeIntParam(state, 'id') == null
            ? ServiceRoutes.dashboard
            : null,
        pageBuilder: (context, state) => _libraryDetailPage<SonarrSeries>(
          state,
          heroPrefix: 'series',
          buildChild: (id, heroTag, series, instanceId) => SeriesDetailScreen(
            seriesId: id,
            heroTag: heroTag,
            initialSeries: series,
            instanceId: instanceId,
          ),
        ),
      ),
    ],
  );
}

/// Sonarr: the same shell as Radarr, and deliberately the same bar.
///
/// [_radarrRoutes] carries the reasoning in full and none of it is Radarr's:
/// the shell is nested inside the Dashboard branch rather than mounted beside
/// it, this node builds nothing and only sends the bare service path to
/// Overview, **its guard is load-bearing** (a route-level redirect fires for
/// every match in the list, so an unguarded one would bounce
/// `/dashboard/sonarr/library` back to Overview forever), and the tails are
/// childless so that `series/:id` here cannot shadow `library/series/:id`
/// inside the shell.
///
/// Two files agreeing by accident is what this comment is trying not to be: the
/// four \*arr share one bar so a user who has learned Radarr has learned this,
/// and the only per-service facts below are the record's name and its screens.
RouteBase _sonarrRoutes() {
  const service = ServiceKey.sonarr;
  final tabs = tabsFor(service)!;

  return GoRoute(
    path: service.routeParam,
    redirect: (context, state) => state.uri.path == ServiceRoutes.sonarr
        ? _preserveQuery(state.uri, ServiceRoutes.sonarrOverview)
        : null,
    routes: [
      // `media` was the all-list tail every arr carried; on the tab model the
      // whole library IS a tab, so it has somewhere real to land now.
      GoRoute(
        path: 'media',
        redirect: (context, state) =>
            _preserveQuery(state.uri, ServiceRoutes.sonarrLibrary),
      ),
      // Every link the app shipped before the tab model, and the second hop of
      // every `/services/sonarr/series/55`. No id validation here: the
      // canonical route below owns it, and doing it twice is two places to get
      // it wrong.
      GoRoute(
        path: 'series/:id',
        redirect: (context, state) => _preserveQuery(
          state.uri,
          '${ServiceRoutes.sonarrSeriesBase}/${state.pathParameters['id']}',
        ),
      ),
      StatefulShellRoute(
        navigatorContainerBuilder: buildBranchTransition,
        // `pageBuilder`, not `builder`: without it the shell's page takes the
        // platform default transition, and the push from the Dashboard into a
        // service would stop matching every other service in the app.
        pageBuilder: (context, state, navigationShell) =>
            RouteUtils.cupertinoPage(
              key: state.pageKey,
              child: ServiceHomeScreen(
                service: service,
                showAppBar: isServiceTabRoot(service, state.uri.path),
                child: navigationShell,
              ),
            ),
        branches: [
          for (final tab in tabs)
            StatefulShellBranch(
              navigatorKey: serviceBranchNavigatorKeyFor(service, tab),
              routes: [_sonarrBranchRoot(tab)],
            ),
        ],
      ),
    ],
  );
}

/// The route at the root of one Sonarr tab.
///
/// Branch order is `tabsFor(ServiceKey.sonarr)` and nothing else, because the
/// bar is generated from the same list and taps it by index. The wildcard
/// throws rather than quietly rendering a placeholder — a seventh tab added to
/// that table with no case here is a bar and a router disagreeing.
GoRoute _sonarrBranchRoot(ServiceTab tab) => switch (tab) {
  ServiceTab.library => _page(
    tab.segment,
    (state) => const ServiceTabScaffold(
      service: ServiceKey.sonarr,
      tab: ServiceTab.library,
      child: SeriesScreen(showAppBar: false, topPadding: _serviceTabTopPadding),
    ),
    routes: [
      // The show, now INSIDE the Library branch. Pushing it keeps the branch,
      // so leaving Sonarr for another app tab and coming back returns to the
      // show — and the Hero still flies, because source and destination are in
      // one Navigator.
      GoRoute(
        path: 'series/:id',
        redirect: (context, state) =>
            RouteUtils.safeIntParam(state, 'id') == null
            ? ServiceRoutes.sonarrLibrary
            : null,
        pageBuilder: (context, state) => _libraryDetailPage<SonarrSeries>(
          state,
          heroPrefix: 'series',
          buildChild: (id, heroTag, series, instanceId) => SeriesDetailScreen(
            seriesId: id,
            heroTag: heroTag,
            initialSeries: series,
            instanceId: instanceId,
          ),
        ),
      ),
    ],
  ),
  // Overview is in this list and that is the honest state, not an oversight:
  // Sonarr's home has always BEEN the library grid, and there is no
  // identity-and-readouts page for it the way `RadarrOverviewScreen` is
  // Radarr's. Drawing the grid here as well would give the bar two tabs showing
  // one thing, which teaches the wrong shape of the service; the well says what
  // is true, and Library is one tap away.
  //
  // Calendar is not a missing screen but a missing call, and it is the one tab
  // Radarr could build and Sonarr cannot: a film's dates are on the film, so
  // Radarr's calendar is derivable from the library list it already holds,
  // while episodes are not in `GET /api/v3/series` at all. Sonarr's needs
  // `GET /api/v3/calendar`, which `SonarrService` has never called. Queue,
  // Wanted and History are the same shape as Radarr's and wait on the same
  // work.
  ServiceTab.overview ||
  ServiceTab.calendar ||
  ServiceTab.queue ||
  ServiceTab.wanted ||
  ServiceTab.history => _page(
    tab.segment,
    (state) => ServiceTabScaffold(
      service: ServiceKey.sonarr,
      tab: tab,
      child: ServiceTabPlaceholder(service: ServiceKey.sonarr, tab: tab),
    ),
  ),
  _ => throw UnsupportedError(
    'ServiceTab.${tab.name} is on sonarr\'s bar with no branch root',
  ),
};

/// The pre-tab-model `/music` tree, which now exists only to redirect.
///
/// Lidarr itself lives in [_lidarrRoutes]. Like `/movies` and `/series` it
/// keeps its `:id` child so a deep link crosses in ONE hop.
GoRoute _musicRoutes({required String path}) {
  return GoRoute(
    path: path,
    redirect: (context, state) => _redirectLegacyLibrary(
      state,
      legacyBase: '/music',
      serviceBase: ServiceRoutes.lidarrArtistBase,
    ),
    builder: (context, state) => const MusicScreen(),
    routes: [
      GoRoute(
        path: ':id',
        redirect: (context, state) =>
            RouteUtils.safeIntParam(state, 'id') == null
            ? ServiceRoutes.dashboard
            : null,
        pageBuilder: (context, state) => _libraryDetailPage<LidarrArtist>(
          state,
          heroPrefix: 'artist',
          buildChild: (id, heroTag, artist, instanceId) => MusicDetailScreen(
            artistId: id,
            heroTag: heroTag,
            initialArtist: artist,
            instanceId: instanceId,
          ),
        ),
      ),
    ],
  );
}

/// Lidarr: the third of the four \*arr on one shell and one bar.
///
/// [_radarrRoutes] carries the reasoning for every structural choice here — the
/// nesting inside the Dashboard branch, the redirect-only node, the guard on
/// the full location, the childless tails — and [_sonarrRoutes] is the same
/// function with another record's name in it. That sameness is the feature.
RouteBase _lidarrRoutes() {
  const service = ServiceKey.lidarr;
  final tabs = tabsFor(service)!;

  return GoRoute(
    path: service.routeParam,
    redirect: (context, state) => state.uri.path == ServiceRoutes.lidarr
        ? _preserveQuery(state.uri, ServiceRoutes.lidarrOverview)
        : null,
    routes: [
      GoRoute(
        path: 'media',
        redirect: (context, state) =>
            _preserveQuery(state.uri, ServiceRoutes.lidarrLibrary),
      ),
      GoRoute(
        path: 'artist/:id',
        redirect: (context, state) => _preserveQuery(
          state.uri,
          '${ServiceRoutes.lidarrArtistBase}/${state.pathParameters['id']}',
        ),
      ),
      StatefulShellRoute(
        navigatorContainerBuilder: buildBranchTransition,
        pageBuilder: (context, state, navigationShell) =>
            RouteUtils.cupertinoPage(
              key: state.pageKey,
              child: ServiceHomeScreen(
                service: service,
                showAppBar: isServiceTabRoot(service, state.uri.path),
                child: navigationShell,
              ),
            ),
        branches: [
          for (final tab in tabs)
            StatefulShellBranch(
              navigatorKey: serviceBranchNavigatorKeyFor(service, tab),
              routes: [_lidarrBranchRoot(tab)],
            ),
        ],
      ),
    ],
  );
}

/// The route at the root of one Lidarr tab.
GoRoute _lidarrBranchRoot(ServiceTab tab) => switch (tab) {
  ServiceTab.library => _page(
    tab.segment,
    (state) => const ServiceTabScaffold(
      service: ServiceKey.lidarr,
      tab: ServiceTab.library,
      child: MusicScreen(showAppBar: false, topPadding: _serviceTabTopPadding),
    ),
    routes: [
      GoRoute(
        path: 'artist/:id',
        redirect: (context, state) =>
            RouteUtils.safeIntParam(state, 'id') == null
            ? ServiceRoutes.lidarrLibrary
            : null,
        pageBuilder: (context, state) => _libraryDetailPage<LidarrArtist>(
          state,
          heroPrefix: 'artist',
          buildChild: (id, heroTag, artist, instanceId) => MusicDetailScreen(
            artistId: id,
            heroTag: heroTag,
            initialArtist: artist,
            instanceId: instanceId,
          ),
        ),
      ),
    ],
  ),
  // Overview for the reason [_sonarrBranchRoot] gives: Lidarr's home is the
  // artist wall and there is no readouts page behind it yet.
  //
  // Calendar is blocked the same way Sonarr's is, one level further down: a
  // release date belongs to an *album*, and `GET /api/v1/artist` does not carry
  // the albums. It needs `GET /api/v1/calendar`, which `LidarrService` has
  // never called.
  ServiceTab.overview ||
  ServiceTab.calendar ||
  ServiceTab.queue ||
  ServiceTab.wanted ||
  ServiceTab.history => _page(
    tab.segment,
    (state) => ServiceTabScaffold(
      service: ServiceKey.lidarr,
      tab: tab,
      child: ServiceTabPlaceholder(service: ServiceKey.lidarr, tab: tab),
    ),
  ),
  _ => throw UnsupportedError(
    'ServiceTab.${tab.name} is on lidarr\'s bar with no branch root',
  ),
};

GoRoute _qbittorrentRoutes({required String path}) {
  return _page(
    path,
    (state) => ServiceHomeScreen(
      service: ServiceKey.qbittorrent,
      trailingAction: const QbittorrentActionsBar(),
      child: const QbittorrentScreen(topPadding: _serviceHomeTopPadding),
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
    (state) => ServiceHomeScreen(
      service: ServiceKey.bazarr,
      child: const BazarrScreen(
        showAppBar: false,
        topPadding: _serviceHomeTopPadding,
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
            RouteUtils.safeIntParam(state, 'id') == null
            ? ServiceRoutes.dashboard
            : null,
      ),
      // See the series route above: no Hero source, so no `heroTag`.
      _page(
        'movie/:id',
        (state) => BazarrMovieDetailScreen(
          radarrId: RouteUtils.safeIntParam(state, 'id')!,
          initialWanted: RouteUtils.safeExtra<BazarrWantedItem>(state),
        ),
        redirect: (context, state) =>
            RouteUtils.safeIntParam(state, 'id') == null
            ? ServiceRoutes.dashboard
            : null,
      ),
    ],
  );
}

GoRoute _dockgeRoutes({required String path}) {
  return _page(
    path,
    (state) => ServiceHomeScreen(
      service: ServiceKey.dockge,
      child: const DockgeScreen(
        showAppBar: false,
        topPadding: _serviceHomeTopPadding,
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
    (state) => ServiceHomeScreen(
      service: ServiceKey.prowlarr,
      child: const ProwlarrScreen(
        showAppBar: false,
        topPadding: _serviceHomeTopPadding,
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
            RouteUtils.safeIntParam(state, 'id') == null
            ? ServiceRoutes.dashboard
            : null,
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

/// Readarr: the last of the four \*arr on one shell and one bar.
///
/// [_radarrRoutes] carries the reasoning for the shape. Two things are Readarr's
/// own. It needs no compatibility tails, because the only two paths it ever
/// shipped are the two the model already spells: the bare service root, which
/// this node redirects like the other three, and `/dashboard/readarr/library`,
/// which was the pushed author list and is now the Library tab's root at the
/// same address. And its Library pushes nothing, because there is no author
/// detail to push: `ReadarrService` has `getAuthors()` and no
/// `GET /api/v1/author/{id}`.
RouteBase _readarrRoutes() {
  const service = ServiceKey.readarr;
  final tabs = tabsFor(service)!;

  return GoRoute(
    path: service.routeParam,
    redirect: (context, state) => state.uri.path == ServiceRoutes.readarr
        ? _preserveQuery(state.uri, ServiceRoutes.readarrOverview)
        : null,
    routes: [
      StatefulShellRoute(
        navigatorContainerBuilder: buildBranchTransition,
        pageBuilder: (context, state, navigationShell) =>
            RouteUtils.cupertinoPage(
              key: state.pageKey,
              child: ServiceHomeScreen(
                service: service,
                showAppBar: isServiceTabRoot(service, state.uri.path),
                child: navigationShell,
              ),
            ),
        branches: [
          for (final tab in tabs)
            StatefulShellBranch(
              navigatorKey: serviceBranchNavigatorKeyFor(service, tab),
              routes: [_readarrBranchRoot(tab)],
            ),
        ],
      ),
    ],
  );
}

/// The route at the root of one Readarr tab.
///
/// Readarr is the one arr whose Overview is real on the first day of the model,
/// and not because more was built for it: `ReadarrScreen` was already a
/// readouts-and-sections dashboard rather than a browse grid, so the tab model
/// found its Overview written and only had to stop calling it the home.
GoRoute _readarrBranchRoot(ServiceTab tab) => switch (tab) {
  ServiceTab.overview => _page(
    tab.segment,
    (state) => const ServiceTabScaffold(
      service: ServiceKey.readarr,
      tab: ServiceTab.overview,
      child: ReadarrScreen(
        showAppBar: false,
        topPadding: _serviceTabTopPadding,
      ),
    ),
  ),
  ServiceTab.library => _page(
    tab.segment,
    (state) => const ServiceTabScaffold(
      service: ServiceKey.readarr,
      tab: ServiceTab.library,
      child: ReadarrLibraryScreen(
        showAppBar: false,
        topPadding: _serviceTabTopPadding,
      ),
    ),
  ),
  // Calendar is blocked exactly as Sonarr's and Lidarr's are — a book's release
  // date is not on the author — and needs `GET /api/v1/calendar`, which
  // `ReadarrService` has never called. Queue, Wanted and History wait on the
  // same work as the other three; upstream being archived at least makes that
  // a frozen target (decision 13).
  ServiceTab.calendar ||
  ServiceTab.queue ||
  ServiceTab.wanted ||
  ServiceTab.history => _page(
    tab.segment,
    (state) => ServiceTabScaffold(
      service: ServiceKey.readarr,
      tab: tab,
      child: ServiceTabPlaceholder(service: ServiceKey.readarr, tab: tab),
    ),
  ),
  _ => throw UnsupportedError(
    'ServiceTab.${tab.name} is on readarr\'s bar with no branch root',
  ),
};

GoRoute _sabnzbdRoutes({required String path}) {
  return _page(
    path,
    (state) => ServiceHomeScreen(
      service: ServiceKey.sabnzbd,
      child: const SabnzbdScreen(
        showAppBar: false,
        topPadding: _serviceHomeTopPadding,
      ),
    ),
  );
}

GoRoute _nzbgetRoutes({required String path}) {
  return _page(
    path,
    (state) => ServiceHomeScreen(
      service: ServiceKey.nzbget,
      child: const NzbgetScreen(
        showAppBar: false,
        topPadding: _serviceHomeTopPadding,
      ),
    ),
  );
}

GoRoute _unraidRoutes({required String path}) {
  return _page(
    path,
    (state) => ServiceHomeScreen(
      service: ServiceKey.unraid,
      child: const UnraidScreen(
        showAppBar: false,
        topPadding: _serviceHomeTopPadding,
      ),
    ),
  );
}

GoRoute _transmissionRoutes({required String path}) {
  return _page(
    path,
    (state) => ServiceHomeScreen(
      service: ServiceKey.transmission,
      child: const TransmissionScreen(
        showAppBar: false,
        topPadding: _serviceHomeTopPadding,
      ),
    ),
  );
}

GoRoute _npmRoutes({required String path}) {
  return _page(
    path,
    (state) => ServiceHomeScreen(
      service: ServiceKey.nginxProxyManager,
      child: const NpmScreen(
        showAppBar: false,
        topPadding: _serviceHomeTopPadding,
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
      topPadding: _serviceHomeTopPadding,
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
            ? ServiceRoutes.forService(service)
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
            ? ServiceRoutes.forService(service)
            : null,
      ),
    ],
  );
}

GoRoute _truenasRoutes({required String path}) {
  return _page(
    path,
    (state) => ServiceHomeScreen(
      service: ServiceKey.truenas,
      child: const TrueNasHubScreen(
        showAppBar: false,
        topPadding: _serviceHomeTopPadding,
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
            ? ServiceRoutes.truenasDatasets
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
  if (path == '/discover') return ServiceRoutes.dashboard;

  const legacyBase = '/discover/';
  if (!path.startsWith(legacyBase)) return null;

  final suffix = path.substring(legacyBase.length);
  if (suffix == 'movies/all' ||
      suffix == 'tv/all' ||
      suffix == 'trending/all' ||
      suffix.startsWith('movie/') ||
      suffix.startsWith('tv/')) {
    return _preserveQuery(state.uri, '${ServiceRoutes.seerr}/$suffix');
  }

  return ServiceRoutes.dashboard;
}

String? _redirectLegacyLibrary(
  GoRouterState state, {
  required String legacyBase,
  required String serviceBase,
}) {
  final path = state.uri.path;
  if (path == legacyBase) return ServiceRoutes.dashboard;

  final prefix = '$legacyBase/';
  if (!path.startsWith(prefix)) return null;

  final id = path.substring(prefix.length);
  if (id.isEmpty || id.contains('/')) return ServiceRoutes.dashboard;
  return _preserveQuery(state.uri, '$serviceBase/$id');
}

String _preserveQuery(Uri source, String path) {
  final query = source.hasQuery ? '?${source.query}' : '';
  return '$path$query';
}

/// The route at the root of each tab's own navigator.
///
/// A switch on [NavTab] rather than a hand-ordered list, so the branch order
/// cannot drift from `NavTab.values`: the shell maps
/// `StatefulNavigationShell.currentIndex` straight onto that enum, and a
/// mismatch would quietly select the wrong tab instead of failing anywhere
/// visible. Exhaustive, so a fifth tab cannot be added without deciding what
/// its branch opens on.
RouteBase _branchRootFor(NavTab tab) => switch (tab) {
  NavTab.dashboard => GoRoute(
    path: ServiceRoutes.dashboard,
    pageBuilder: (context, state) => _tabPage(state, const DashboardScreen()),
    routes: [
      // Every mount takes its segment from `ServiceKey.routeParam` rather than
      // repeating the literal. Sixteen of these were spelled out by hand and
      // one — `npm`, the single segment that is *not* the enum name — was not,
      // which is exactly the asymmetry that makes a hand-spelled table worth
      // deleting: the one path a typo would break was the only one guarded.
      _discoverRoutes(path: ServiceKey.seerr.routeParam),
      _radarrRoutes(),
      _sonarrRoutes(),
      _lidarrRoutes(),
      _qbittorrentRoutes(path: ServiceKey.qbittorrent.routeParam),
      _bazarrRoutes(path: ServiceKey.bazarr.routeParam),
      _truenasRoutes(path: ServiceKey.truenas.routeParam),
      _dockgeRoutes(path: ServiceKey.dockge.routeParam),
      _prowlarrRoutes(path: ServiceKey.prowlarr.routeParam),
      _readarrRoutes(),
      _sabnzbdRoutes(path: ServiceKey.sabnzbd.routeParam),
      _nzbgetRoutes(path: ServiceKey.nzbget.routeParam),
      _unraidRoutes(path: ServiceKey.unraid.routeParam),
      _transmissionRoutes(path: ServiceKey.transmission.routeParam),
      _npmRoutes(path: ServiceKey.nginxProxyManager.routeParam),
      _streamRoutes(
        service: ServiceKey.jellyfin,
        path: ServiceKey.jellyfin.routeParam,
      ),
      _streamRoutes(service: ServiceKey.plex, path: ServiceKey.plex.routeParam),
    ],
  ),
  NavTab.activity => GoRoute(
    path: '/activity',
    pageBuilder: (context, state) =>
        _tabPage(state, const GlobalActivityScreen()),
  ),
  NavTab.search => GoRoute(
    path: '/search',
    pageBuilder: (context, state) => _tabPage(state, const SearchScreen()),
  ),
  NavTab.settings => GoRoute(
    path: '/settings',
    pageBuilder: (context, state) =>
        _tabPage(state, const SettingsHomeScreen()),
    routes: [
      // `_page`, like its six siblings, rather than the bare `GoRoute` with a
      // `builder` it was: that form gave this route a Material page while every
      // other settings destination got `RouteUtils.cupertinoPage`, so the one
      // section owned by another feature was also the one that transitioned
      // differently and lost the rail. Nothing else about the route changes —
      // same path, same screen, same location in the rail's `sections` list.
      _page(
        'background-search',
        (state) => const ReleaseSearchSettingsScreen(),
      ),
      _page('appearance', (state) => const SettingsAppearanceScreen()),
      _page('hints', (state) => const SettingsHintsScreen()),
      _page('connections', (state) => const SettingsConnectionsScreen()),
      // Former name of the connections screen, kept so an existing
      // deep link or a shortcut does not dead-end.
      GoRoute(
        path: 'services',
        redirect: (context, state) => '/settings/connections',
      ),
      _page('region', (state) => const SettingsRegionScreen()),
      _page('certificates', (state) => const TrustedCertificatesScreen()),
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
        // Query rather than a path segment: a connection is a parameter of
        // the form, not a level of the hierarchy, and threading a segment
        // through would have every nested settings route grow one it never
        // reads.
        return ServiceSettingsScreen(
          service: service,
          instanceId: state.uri.queryParameters['i'],
          isNew: state.uri.queryParameters['new'] == '1',
        );
      }),
    ],
  ),
};

/// Rewrites a pre-rename `/services…` location onto `/dashboard…`.
///
/// Returns null for anything else, so the redirect callback can fall through.
/// Matching is on the path *segment* rather than a bare `startsWith`, or a
/// future `/services-of-mine` would be rewritten to something that does not
/// exist.
String? _rewriteLegacyServicesPath(Uri uri) {
  const legacy = ServiceRoutes.legacyServices;
  final path = uri.path;
  if (path != legacy && !path.startsWith('$legacy/')) return null;
  final rewritten =
      '${ServiceRoutes.dashboard}${path.substring(legacy.length)}';
  return uri.hasQuery ? '$rewritten?${uri.query}' : rewritten;
}

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = ref.watch(routerRefreshNotifierProvider);
  final onboardingDone = ref.read(onboardingCompletedProvider);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    refreshListenable: notifier,
    initialLocation: onboardingDone ? ServiceRoutes.dashboard : '/onboarding',
    redirect: (context, state) {
      final done = ref.read(onboardingCompletedProvider);
      final isOnboarding = state.matchedLocation == '/onboarding';
      if (!done && !isOnboarding) return '/onboarding';
      if (done && isOnboarding) return ServiceRoutes.dashboard;

      // Everything that used to live under `/services` still resolves.
      //
      // One rewrite here rather than a shadow copy of the tree: the rename
      // moved thirty-four routes and every detail tail under them, and
      // re-declaring each one as a legacy twin would double the surface that
      // has to stay in sync for the rest of the app's life. A prefix swap
      // keeps the whole subtree — `/services/radarr/movie/42?heroTag=…`
      // included — and preserves the query, which is where the instance lens
      // travels.
      final legacy = _rewriteLegacyServicesPath(state.uri);
      if (legacy != null) return legacy;

      return null;
    },
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      // One Navigator per tab, all four alive at once behind a cross-fade.
      //
      // The order of [branches] is a contract, not a layout: the shell maps a
      // bar tap and `StatefulNavigationShell.currentIndex` straight onto
      // `NavTab.values[index]`, so a branch out of `NavTab` order would select
      // the wrong tab rather than fail. Asserted below.
      StatefulShellRoute(
        navigatorContainerBuilder: buildBranchTransition,
        builder: (context, state, navigationShell) =>
            ShellScreen(navigationShell: navigationShell),
        branches: [
          for (final tab in NavTab.values)
            StatefulShellBranch(
              navigatorKey: branchNavigatorKeyFor(tab),
              routes: [_branchRootFor(tab)],
            ),
        ],
      ),
      // The manual-import flow: three stations, on the ROOT navigator rather
      // than inside a branch.
      //
      // It is full-bleed (it reserves no nav-bar clearance and the bar is not
      // drawn over it) and it belongs to no tab: it is reached from a service
      // page, from a queue item, from a review screen. Left inside a branch it
      // would be a page on that tab's stack, so its flow state and its
      // two-second command poll would survive a switch away from it — the exact
      // leak this architecture exists to remove. At root it unmounts when left.
      //
      // Every entry point uses `push`, and must keep doing so: a `go` here would
      // replace the shell page in the root navigator and take all four branch
      // stacks with it.
      GoRoute(
        path: manualImportBrowsePath,
        pageBuilder: (context, state) => _manualImportPage(
          state,
          (service, targetId, instanceId) => ManualImportLocateScreen(
            service: service,
            targetId: targetId,
            instanceId: instanceId,
            initialPath: state.uri.queryParameters['path'],
          ),
        ),
      ),
      GoRoute(
        path: manualImportReviewPath,
        pageBuilder: (context, state) => _manualImportPage(
          state,
          (service, targetId, instanceId) => ManualImportReviewScreen(
            service: service,
            targetId: targetId,
            instanceId: instanceId,
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
          // Station 3 takes no `instanceId`: by the time a command is running
          // the binding is already on the flow state, and a second source of
          // truth here could only disagree with it.
          (service, targetId, instanceId) =>
              ManualImportProgressScreen(service: service),
        ),
      ),
      // The retired top-level locations, kept so old deep links land somewhere.
      // Every path they match resolves to a redirect into `/services/...`, so
      // their builders are unreachable — they exist only to give the matcher
      // something to match before the redirect runs.
      //
      // At root because under a `StatefulShellRoute` there is no shell level to
      // be a sibling of any more: the route list is derived from the branches.
      // Putting four dead trees inside the services branch would read as part of
      // that tab's subtree and invite someone to give them a real builder.
      _discoverRoutes(
        path: '/discover',
        redirectLocation: ServiceRoutes.dashboard,
      ),
      _moviesRoutes(path: '/movies'),
      _seriesRoutes(path: '/series'),
      _musicRoutes(path: '/music'),
      // The per-service activity drill-down: already full-screen above the
      // shell, and unchanged by the migration.
      GoRoute(
        path: '/activity/:type',
        builder: (context, state) {
          final typeStr = state.pathParameters['type']!;
          final type = ServiceType.values.firstWhere(
            (e) => e.name == typeStr,
            orElse: () => ServiceType.movies,
          );
          // `?i=` reaches the requests branch only, because that is the only
          // branch that honours it: the \*arr tabs under here read their queue
          // through the lens from top to bottom, and handing them a connection
          // they ignore is how this route grew a parameter nothing read the
          // first time. Giving those tabs one is that feature's work.
          return ActivityScreen(
            serviceType: type,
            instanceId: type == ServiceType.discover
                ? state.uri.queryParameters['i']
                : null,
          );
        },
      ),
    ],
  );
});
