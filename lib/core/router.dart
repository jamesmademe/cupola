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
import 'package:cupola/features/discover/presentation/seerr_overview_screen.dart';
import 'package:cupola/features/activity/domain/service_type.dart';
import 'package:cupola/features/activity/presentation/activity_screen.dart';
import 'package:cupola/features/activity/presentation/global_activity_screen.dart';
import 'package:cupola/features/movies/presentation/movies_screen.dart';
import 'package:cupola/features/movies/presentation/movie_detail_screen.dart';
import 'package:cupola/features/series/presentation/series_screen.dart';
import 'package:cupola/features/series/presentation/series_detail_screen.dart';
import 'package:cupola/features/series/presentation/sonarr_overview_screen.dart';
import 'package:cupola/features/music/presentation/music_screen.dart';
import 'package:cupola/features/music/presentation/music_detail_screen.dart';
import 'package:cupola/features/music/presentation/lidarr_overview_screen.dart';
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
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_overview_screen.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_screen.dart';
import 'package:cupola/features/qbittorrent/presentation/torrent_detail_screen.dart';
import 'package:cupola/features/qbittorrent/presentation/widgets/qbittorrent_actions_bar.dart';
import 'package:cupola/features/bazarr/domain/models/bazarr_models.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_library_screen.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_movie_detail_screen.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_overview_screen.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_overview_screen.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_library_screen.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_indexer_detail_screen.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_settings_screen.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_provider_list_screen.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_app_profiles_screen.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_tags_screen.dart';
import 'package:cupola/features/readarr/presentation/readarr_overview_screen.dart';
import 'package:cupola/features/readarr/presentation/readarr_library_screen.dart';
import 'package:cupola/features/sabnzbd/presentation/sabnzbd_overview_screen.dart';
import 'package:cupola/features/sabnzbd/presentation/sabnzbd_screen.dart';
import 'package:cupola/features/npm/presentation/npm_overview_screen.dart';
import 'package:cupola/features/npm/presentation/npm_screen.dart';
import 'package:cupola/features/transmission/presentation/transmission_overview_screen.dart';
import 'package:cupola/features/transmission/presentation/transmission_screen.dart';
import 'package:cupola/features/nzbget/presentation/nzbget_overview_screen.dart';
import 'package:cupola/features/nzbget/presentation/nzbget_screen.dart';
import 'package:cupola/features/stream/presentation/stream_libraries_screen.dart';
import 'package:cupola/features/stream/presentation/stream_overview_screen.dart';
import 'package:cupola/features/stream/presentation/stream_item_screen.dart';
import 'package:cupola/features/stream/presentation/stream_library_screen.dart';
import 'package:cupola/features/unraid/presentation/unraid_overview_screen.dart';
import 'package:cupola/features/unraid/presentation/unraid_screen.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_series_detail_screen.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_wanted_screen.dart';
import 'package:cupola/features/dockge/presentation/dockge_agent_lens_button.dart';
import 'package:cupola/features/dockge/presentation/dockge_overview_screen.dart';
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
      location: ServiceRoutes.seerrDiscover,
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
  required String fallbackLocation,
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
      location: fallbackLocation,
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

/// The pre-rename `/discover` tree, which now exists only to redirect.
///
/// Seerr itself lives in [_seerrRoutes]. Every node here is redirect-only, and
/// the children exist for one reason: a redirect cannot run until something
/// matches, so a shape with no route to match would 404 instead of being
/// rewritten. Nothing in this tree ever builds.
///
/// `tv/all` is declared before `tv/:id` for the reason it is in [_seerrRoutes]:
/// routes are matched in declaration order, and the other way round
/// `/discover/tv/all` is a media detail whose id is the word `all`.
GoRoute _legacyDiscoverRoutes({required String path}) {
  String? rewrite(BuildContext context, GoRouterState state) =>
      _redirectLegacyDiscover(state);

  return GoRoute(
    path: path,
    redirect: rewrite,
    routes: [
      for (final tail in const [
        'requests',
        'movies/all',
        'tv/all',
        'trending/all',
        'genre/:mediaType/:genreId',
        'movie/:id',
        'tv/:id',
        'person/:id',
        'collection/:id',
      ])
        GoRoute(path: tail, redirect: rewrite),
    ],
  );
}

/// One Seerr compatibility tail whose target is a fixed location.
///
/// Childless on purpose, like every other tail in this file: the matcher treats
/// a prefix hit with no complete match as no match at all, which is what stops
/// these from shadowing the real routes inside the shell.
GoRoute _seerrTail(String path, String target) => GoRoute(
  path: path,
  redirect: (context, state) => _preserveQuery(state.uri, target),
);

/// One Seerr compatibility tail for a `<segment>/:id` detail.
///
/// The four detail shapes Seerr shipped — `movie`, `tv`, `person`,
/// `collection` — differ only in the segment, and each lands on the same
/// segment under `discover/`. No id validation: the canonical route inside the
/// branch owns it, and doing it twice is two places to get it wrong.
GoRoute _seerrIdTail(String segment) => GoRoute(
  path: '$segment/:id',
  redirect: (context, state) => _preserveQuery(
    state.uri,
    '${ServiceRoutes.seerrDiscover}/$segment/${state.pathParameters['id']}',
  ),
);

/// Seerr: one shell, one branch per tab.
///
/// [_radarrRoutes] carries the reasoning for every structural choice and none
/// of it is Radarr's — the nesting inside the Dashboard branch, the
/// redirect-only node whose guard is on the full location, the childless
/// compatibility tails, the wildcard that throws.
///
/// What is Seerr's own is the *number* of those tails. It shipped more link
/// shapes than any other service — three see-alls, a genre tree, two media
/// details, a person and a collection — and every one of them hung off the
/// service root, because the service root **was** the Discover page. They now
/// hang off the Discover tab's branch, exactly as Radarr's film moved inside
/// Library and for the same two reasons: leaving Seerr and coming back returns
/// to the page rather than to the top of the carousel, and the poster's Hero
/// still flies because the row it left and the page it lands on share one
/// Navigator. Each old spelling keeps a tail that rewrites to the new one in a
/// single hop, query intact.
RouteBase _seerrRoutes() {
  const service = ServiceKey.seerr;
  final tabs = tabsFor(service)!;

  return GoRoute(
    path: service.routeParam,
    redirect: (context, state) => state.uri.path == ServiceRoutes.seerr
        ? _preserveQuery(state.uri, ServiceRoutes.seerrOverview)
        : null,
    routes: [
      // `requests` needs no tail: the all-requests list was already a page at
      // `/dashboard/seerr/requests`, which is exactly where its tab mounts.
      //
      // Order is load-bearing here. Routes match in declaration order, so the
      // three `.../all` literals come before `movie/:id` and `tv/:id` — the
      // other way round, `/dashboard/seerr/tv/all` rewrites as a media detail
      // whose id is the word `all`.
      _seerrTail('movies/all', ServiceRoutes.seerrMoviesAll),
      _seerrTail('tv/all', ServiceRoutes.seerrTvAll),
      _seerrTail('trending/all', ServiceRoutes.seerrTrendingAll),
      GoRoute(
        path: 'genre/:mediaType/:genreId',
        redirect: (context, state) => _preserveQuery(
          state.uri,
          '${ServiceRoutes.seerrGenreBase}/${state.pathParameters['mediaType']}'
          '/${state.pathParameters['genreId']}',
        ),
      ),
      _seerrIdTail('movie'),
      _seerrIdTail('tv'),
      _seerrIdTail('person'),
      _seerrIdTail('collection'),
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
              routes: [_seerrBranchRoot(tab)],
            ),
        ],
      ),
    ],
  );
}

/// The route at the root of one Seerr tab.
///
/// Branch order is `tabsFor(ServiceKey.seerr)` and nothing else, because the
/// bar is generated from the same list and taps it by index. The wildcard
/// throws rather than quietly rendering a placeholder: a sixth tab added to
/// that table with no case here is a bar and a router disagreeing.
GoRoute _seerrBranchRoot(ServiceTab tab) => switch (tab) {
  ServiceTab.overview => _page(
    tab.segment,
    (state) => const ServiceTabScaffold(
      service: ServiceKey.seerr,
      tab: ServiceTab.overview,
      child: SeerrOverviewScreen(topPadding: _serviceTabTopPadding),
    ),
  ),
  ServiceTab.requests => _page(
    tab.segment,
    (state) => const ServiceTabScaffold(
      service: ServiceKey.seerr,
      tab: ServiceTab.requests,
      child: ServiceAllRequestsScreen(
        showAppBar: false,
        topPadding: _serviceTabTopPadding,
      ),
    ),
  ),
  // Discover, and the whole tree that used to hang off the service root with
  // it. Every one of these is reached by tapping a row of the Discover page,
  // which is what makes this the tab that owns them.
  ServiceTab.discover => _page(
    tab.segment,
    (state) => const ServiceTabScaffold(
      service: ServiceKey.seerr,
      tab: ServiceTab.discover,
      child: DiscoverScreen(
        showAppBar: false,
        topPadding: _serviceTabTopPadding,
      ),
    ),
    routes: [
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
          return genreId == null ? ServiceRoutes.seerrDiscover : null;
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
      // A bad id falls back to the tab this page was pushed from, not to the
      // app home: the branch is where the user still is, and sending them out
      // of the service would be a bigger move than the mistake.
      GoRoute(
        path: 'movie/:id',
        redirect: (context, state) =>
            RouteUtils.safeIntParam(state, 'id') == null
            ? ServiceRoutes.seerrDiscover
            : null,
        pageBuilder: (context, state) =>
            _discoverDetailPage(state, mediaType: 'movie'),
      ),
      GoRoute(
        path: 'tv/:id',
        redirect: (context, state) =>
            RouteUtils.safeIntParam(state, 'id') == null
            ? ServiceRoutes.seerrDiscover
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
            ? ServiceRoutes.seerrDiscover
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
            ? ServiceRoutes.seerrDiscover
            : null,
      ),
    ],
  ),
  // Both blocked, and on endpoints rather than on work. `SeerrService` calls
  // `/api/v1/discover/*`, `/api/v1/request`, `/api/v1/search` and
  // `/api/v1/service/{radarr,sonarr}` and nothing else: there is no
  // `/api/v1/issue` behind Issues and no `/api/v1/user` behind Users, so
  // neither tab has a client to ask.
  ServiceTab.issues || ServiceTab.users => _page(
    tab.segment,
    (state) => ServiceTabScaffold(
      service: ServiceKey.seerr,
      tab: tab,
      child: ServiceTabPlaceholder(service: ServiceKey.seerr, tab: tab),
    ),
  ),
  _ => throw UnsupportedError(
    'ServiceTab.${tab.name} is on seerr\'s bar with no branch root',
  ),
};

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
      fallbackLocation: ServiceRoutes.radarrLibrary,
    ),
    builder: (context, state) => const MoviesScreen(),
    routes: [
      GoRoute(
        path: ':id',
        redirect: (context, state) =>
            RouteUtils.safeIntParam(state, 'id') == null
            ? ServiceRoutes.radarrLibrary
            : null,
        pageBuilder: (context, state) => _libraryDetailPage<RadarrMovie>(
          state,
          heroPrefix: 'movie',
          fallbackLocation: ServiceRoutes.radarrLibrary,
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
          fallbackLocation: ServiceRoutes.radarrLibrary,
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
      fallbackLocation: ServiceRoutes.sonarrLibrary,
    ),
    builder: (context, state) => const SeriesScreen(),
    routes: [
      GoRoute(
        path: ':id',
        redirect: (context, state) =>
            RouteUtils.safeIntParam(state, 'id') == null
            ? ServiceRoutes.sonarrLibrary
            : null,
        pageBuilder: (context, state) => _libraryDetailPage<SonarrSeries>(
          state,
          heroPrefix: 'series',
          fallbackLocation: ServiceRoutes.sonarrLibrary,
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
  ServiceTab.overview => _page(
    tab.segment,
    (state) => const ServiceTabScaffold(
      service: ServiceKey.sonarr,
      tab: ServiceTab.overview,
      child: SonarrOverviewScreen(topPadding: _serviceTabTopPadding),
    ),
  ),
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
          fallbackLocation: ServiceRoutes.sonarrLibrary,
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
  // Calendar is not a missing screen but a missing call, and it is the one tab
  // Radarr could build and Sonarr cannot: a film's dates are on the film, so
  // Radarr's calendar is derivable from the library list it already holds,
  // while episodes are not in `GET /api/v3/series` at all. Sonarr's needs
  // `GET /api/v3/calendar`, which `SonarrService` has never called. Queue,
  // Wanted and History are the same shape as Radarr's and wait on the same
  // work.
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
      fallbackLocation: ServiceRoutes.lidarrLibrary,
    ),
    builder: (context, state) => const MusicScreen(),
    routes: [
      GoRoute(
        path: ':id',
        redirect: (context, state) =>
            RouteUtils.safeIntParam(state, 'id') == null
            ? ServiceRoutes.lidarrLibrary
            : null,
        pageBuilder: (context, state) => _libraryDetailPage<LidarrArtist>(
          state,
          heroPrefix: 'artist',
          fallbackLocation: ServiceRoutes.lidarrLibrary,
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
  ServiceTab.overview => _page(
    tab.segment,
    (state) => const ServiceTabScaffold(
      service: ServiceKey.lidarr,
      tab: ServiceTab.overview,
      child: LidarrOverviewScreen(topPadding: _serviceTabTopPadding),
    ),
  ),
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
          fallbackLocation: ServiceRoutes.lidarrLibrary,
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
  // Calendar is blocked the same way Sonarr's is, one level further down: a
  // release date belongs to an *album*, and `GET /api/v1/artist` does not carry
  // the albums. It needs `GET /api/v1/calendar`, which `LidarrService` has
  // never called.
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

/// qBittorrent: the first download client on one shell and one bar.
///
/// [_radarrRoutes] carries the reasoning for every structural choice and none of
/// it is Radarr's — the nesting inside the Dashboard branch, the redirect-only
/// node whose guard is on the full location, the childless compatibility tail.
///
/// Two things are qBittorrent's own. The torrent list was the *whole* service,
/// so what the four \*arr called Library this calls Queue and it is where the
/// detail now hangs. And the transfer controls stay on the band as a
/// `trailingAction`: they are alternative-speed-limit and add-torrent, which
/// belong to the connection rather than to any one tab, so the band carries them
/// on all three the way it carried them on the single page.
RouteBase _qbittorrentRoutes() {
  const service = ServiceKey.qbittorrent;
  final tabs = tabsFor(service)!;

  return GoRoute(
    path: service.routeParam,
    redirect: (context, state) => state.uri.path == ServiceRoutes.qbittorrent
        ? _preserveQuery(state.uri, ServiceRoutes.qbittorrentOverview)
        : null,
    routes: [
      // The tab-less tail, childless on purpose: the matcher treats a prefix
      // hit with no complete match as no match at all, so `torrent/:hash` here
      // cannot shadow `queue/torrent/:hash` inside the shell below. It is the
      // only shape qBittorrent ever shipped besides its root, and the second
      // hop of every `/services/qbittorrent/torrent/<hash>`.
      GoRoute(
        path: 'torrent/:hash',
        redirect: (context, state) => _preserveQuery(
          state.uri,
          '${ServiceRoutes.qbittorrentTorrentBase}/'
          '${state.pathParameters['hash']}',
        ),
      ),
      StatefulShellRoute(
        navigatorContainerBuilder: buildBranchTransition,
        pageBuilder: (context, state, navigationShell) =>
            RouteUtils.cupertinoPage(
              key: state.pageKey,
              child: ServiceHomeScreen(
                service: service,
                trailingAction: const QbittorrentActionsBar(),
                showAppBar: isServiceTabRoot(service, state.uri.path),
                child: navigationShell,
              ),
            ),
        branches: [
          for (final tab in tabs)
            StatefulShellBranch(
              navigatorKey: serviceBranchNavigatorKeyFor(service, tab),
              routes: [_qbittorrentBranchRoot(tab)],
            ),
        ],
      ),
    ],
  );
}

/// The route at the root of one qBittorrent tab.
///
/// Branch order is `tabsFor(ServiceKey.qbittorrent)` and nothing else, because
/// the bar is generated from the same list and taps it by index. The wildcard
/// throws rather than quietly rendering a placeholder: a fourth tab added to
/// that table with no case here is a bar and a router disagreeing.
GoRoute _qbittorrentBranchRoot(ServiceTab tab) => switch (tab) {
  ServiceTab.overview => _page(
    tab.segment,
    (state) => const ServiceTabScaffold(
      service: ServiceKey.qbittorrent,
      tab: ServiceTab.overview,
      child: QbittorrentOverviewScreen(topPadding: _serviceTabTopPadding),
    ),
  ),
  ServiceTab.queue => _page(
    tab.segment,
    (state) => const ServiceTabScaffold(
      service: ServiceKey.qbittorrent,
      tab: ServiceTab.queue,
      child: QbittorrentScreen(topPadding: _serviceTabTopPadding),
    ),
    routes: [
      // The torrent, now INSIDE the Queue branch. Pushing it keeps the branch,
      // so leaving qBittorrent for another app tab and coming back returns to
      // the torrent rather than to the top of the list.
      _page(
        'torrent/:hash',
        (state) =>
            TorrentDetailScreen(hash: state.pathParameters['hash'] ?? ''),
      ),
    ],
  ),
  // RSS is blocked, and on endpoints rather than on work: `QbittorrentService`
  // calls nothing under `/api/v2/rss/` at all, so the feed tree
  // (`GET /api/v2/rss/items`), the auto-download rules (`GET /api/v2/rss/rules`)
  // and everything that writes them have no client to call.
  ServiceTab.rss => _page(
    tab.segment,
    (state) => ServiceTabScaffold(
      service: ServiceKey.qbittorrent,
      tab: tab,
      child: ServiceTabPlaceholder(service: ServiceKey.qbittorrent, tab: tab),
    ),
  ),
  _ => throw UnsupportedError(
    'ServiceTab.${tab.name} is on qbittorrent\'s bar with no branch root',
  ),
};

/// Bazarr: one shell, one branch per tab.
///
/// [_radarrRoutes] carries the reasoning for every structural choice and none
/// of it is Radarr's — the nesting inside the Dashboard branch, the
/// redirect-only node whose guard is on the full location, the childless
/// compatibility tails, the wildcard that throws.
///
/// Two things are Bazarr's own. Its bar names the **record types** rather than
/// a Library — Series and Movies are two destinations (decision 22) — so the
/// two-tab `BazarrLibraryScreen` split in half and the detail spelling is
/// `<tab>/:id`, which is why the series detail did not have to move at all.
/// And what was the service home, `BazarrScreen`, is superseded by
/// `BazarrOverviewScreen`: the Overview tab is the one that carries the
/// identity block and the readouts.
RouteBase _bazarrRoutes() {
  const service = ServiceKey.bazarr;
  final tabs = tabsFor(service)!;

  return GoRoute(
    path: service.routeParam,
    redirect: (context, state) => state.uri.path == ServiceRoutes.bazarr
        ? _preserveQuery(state.uri, ServiceRoutes.bazarrOverview)
        : null,
    routes: [
      // The tab-less tails, childless on purpose: the matcher treats a prefix
      // hit with no complete match as no match at all, so `movie/:id` here
      // cannot shadow `movies/:id` inside the shell below.
      //
      // `library` was the combined Series/Movies page. It lands on Series
      // rather than on the service root: the list the link was asking for is
      // still there, one bar tap from the other half.
      GoRoute(
        path: 'library',
        redirect: (context, state) =>
            _preserveQuery(state.uri, ServiceRoutes.bazarrSeriesBase),
      ),
      // Singular `movie`, the pre-tab spelling. No id validation: the canonical
      // route inside the branch owns it, and doing it twice is two places to
      // get it wrong.
      GoRoute(
        path: 'movie/:id',
        redirect: (context, state) => _preserveQuery(
          state.uri,
          '${ServiceRoutes.bazarrMovieBase}/${state.pathParameters['id']}',
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
              routes: [_bazarrBranchRoot(tab)],
            ),
        ],
      ),
    ],
  );
}

/// The route at the root of one Bazarr tab.
///
/// Branch order is `tabsFor(ServiceKey.bazarr)` and nothing else, because the
/// bar is generated from the same list and taps it by index. The wildcard
/// throws rather than quietly rendering a placeholder: a seventh tab added to
/// that table with no case here is a bar and a router disagreeing.
GoRoute _bazarrBranchRoot(ServiceTab tab) => switch (tab) {
  ServiceTab.overview => _page(
    tab.segment,
    (state) => const ServiceTabScaffold(
      service: ServiceKey.bazarr,
      tab: ServiceTab.overview,
      child: BazarrOverviewScreen(topPadding: _serviceTabTopPadding),
    ),
  ),
  ServiceTab.wanted => _page(
    tab.segment,
    (state) => const ServiceTabScaffold(
      service: ServiceKey.bazarr,
      tab: ServiceTab.wanted,
      child: BazarrWantedScreen(
        showAppBar: false,
        topPadding: _serviceTabTopPadding,
      ),
    ),
  ),
  // The two halves of what was one screen, each with its own detail inside it.
  // Pushing the detail keeps the branch, so leaving Bazarr for another app tab
  // and coming back returns to the item rather than to the top of the list.
  //
  // No `heroTag` on either: the Bazarr lead is a figure plate, not a poster, so
  // there is no source counterpart on a Bazarr row to fly from and an orphan
  // flight would fade in from nothing. Both routes still accept the query
  // param — global search builds one for every service uniformly — and nothing
  // reads it.
  ServiceTab.series => _page(
    tab.segment,
    (state) => const ServiceTabScaffold(
      service: ServiceKey.bazarr,
      tab: ServiceTab.series,
      child: BazarrLibraryScreen.series(
        showAppBar: false,
        topPadding: _serviceTabTopPadding,
      ),
    ),
    routes: [
      _page(
        ':id',
        (state) => BazarrSeriesDetailScreen(
          sonarrSeriesId: RouteUtils.safeIntParam(state, 'id')!,
          initialWanted: RouteUtils.safeExtra<BazarrWantedItem>(state),
        ),
        redirect: (context, state) =>
            RouteUtils.safeIntParam(state, 'id') == null
            ? ServiceRoutes.bazarrSeriesBase
            : null,
      ),
    ],
  ),
  ServiceTab.movies => _page(
    tab.segment,
    (state) => const ServiceTabScaffold(
      service: ServiceKey.bazarr,
      tab: ServiceTab.movies,
      child: BazarrLibraryScreen.movies(
        showAppBar: false,
        topPadding: _serviceTabTopPadding,
      ),
    ),
    routes: [
      _page(
        ':id',
        (state) => BazarrMovieDetailScreen(
          radarrId: RouteUtils.safeIntParam(state, 'id')!,
          initialWanted: RouteUtils.safeExtra<BazarrWantedItem>(state),
        ),
        redirect: (context, state) =>
            RouteUtils.safeIntParam(state, 'id') == null
            ? ServiceRoutes.bazarrMovieBase
            : null,
      ),
    ],
  ),
  // History is a placeholder but **not blocked**: `BazarrService` already calls
  // `/api/episodes/history` and `/api/movies/history`, and the Overview reads
  // both. The tab is a screen away, and the Blacklist pill it is drawn with
  // (decision 22) is the part that still needs a client.
  //
  // **Providers is blocked**, and on an endpoint rather than on work: Bazarr's
  // `/api/providers` — the configured provider list, their status and the
  // reset action — is called nowhere in `BazarrService`, which speaks only
  // `badges`, `series`, `movies`, the two `wanted` lists and the two `history`
  // lists. There is nothing to draw.
  ServiceTab.history || ServiceTab.providers => _page(
    tab.segment,
    (state) => ServiceTabScaffold(
      service: ServiceKey.bazarr,
      tab: tab,
      child: ServiceTabPlaceholder(service: ServiceKey.bazarr, tab: tab),
    ),
  ),
  _ => throw UnsupportedError(
    'ServiceTab.${tab.name} is on bazarr\'s bar with no branch root',
  ),
};

/// Dockge: one shell, one branch per tab.
///
/// [_radarrRoutes] carries the reasoning for every structural choice and none
/// of it is Radarr's — the nesting inside the Dashboard branch, the
/// redirect-only node whose guard is on the full location, the childless
/// compatibility tails, the wildcard that throws.
///
/// Two things are Dockge's own.
///
/// **The agent lens is on the band, not on the bar** (decision 41). An agent is
/// not a *place*: it is which Dockge the rows on screen came off, which is what
/// the connection lens means everywhere else in the app. So it rides as the
/// band's `trailingAction` exactly as qBittorrent's transfer controls do —
/// above every tab, because it qualifies all of them. It also gets it drawn at
/// all: `DockgeScreen` put it in an app bar the service home has been hiding
/// since this service was hosted, so the control has been in the tree and
/// invisible.
///
/// **The stack tree moved inside Stacks.** The detail, its compose editor and
/// the New button's editor all hung off the service root, because a one-page
/// service had nowhere else to hang them; all three are reached from the Stacks
/// list and none from anywhere else. Each old spelling keeps a childless tail.
RouteBase _dockgeRoutes() {
  const service = ServiceKey.dockge;
  final tabs = tabsFor(service)!;

  return GoRoute(
    path: service.routeParam,
    redirect: (context, state) => state.uri.path == ServiceRoutes.dockge
        ? _preserveQuery(state.uri, ServiceRoutes.dockgeOverview)
        : null,
    routes: [
      // The tab-less tails, childless on purpose: the matcher treats a prefix
      // hit with no complete match as no match at all, so `stack/:name` here
      // cannot shadow `stacks/stack/:name` inside the shell below.
      //
      // The editor is declared before the detail it hangs under. Neither can
      // match the other's location — a childless route matches its own depth
      // and nothing longer — but the pair reads as one rule in that order, and
      // the order is free.
      GoRoute(
        path: 'stack/:name/edit',
        redirect: (context, state) => _preserveQuery(
          state.uri,
          ServiceRoutes.dockgeStackEdit(state.pathParameters['name']!),
        ),
      ),
      GoRoute(
        path: 'stack/:name',
        redirect: (context, state) => _preserveQuery(
          state.uri,
          ServiceRoutes.dockgeStack(state.pathParameters['name']!),
        ),
      ),
      GoRoute(
        path: 'new',
        redirect: (context, state) =>
            _preserveQuery(state.uri, ServiceRoutes.dockgeNewStack),
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
                trailingAction: const DockgeAgentLensButton(),
                showAppBar: isServiceTabRoot(service, state.uri.path),
                child: navigationShell,
              ),
            ),
        branches: [
          for (final tab in tabs)
            StatefulShellBranch(
              navigatorKey: serviceBranchNavigatorKeyFor(service, tab),
              routes: [_dockgeBranchRoot(tab)],
            ),
        ],
      ),
    ],
  );
}

/// The route at the root of one Dockge tab.
///
/// Branch order is `tabsFor(ServiceKey.dockge)` and nothing else, because the
/// bar is generated from the same list and taps it by index. The wildcard
/// throws rather than quietly rendering a placeholder: a fourth tab added to
/// that table with no case here is a bar and a router disagreeing.
///
/// **Terminal is a placeholder but not blocked.** `DockgeClient` already joins
/// a stack's combined terminal and streams `terminalWrite` back, so the wire is
/// there — what is missing is the screen, and a tab-level terminal has one
/// question this pass does not get to answer: which stack it is attached to
/// when no stack was named. `DockgeOverviewScreen` answers it sideways rather
/// than pretending to: every stack row it draws opens that stack's detail,
/// which already carries the live combined terminal for a stack the user has
/// just named by tapping it.
GoRoute _dockgeBranchRoot(ServiceTab tab) => switch (tab) {
  ServiceTab.overview => _page(
    tab.segment,
    (state) => const ServiceTabScaffold(
      service: ServiceKey.dockge,
      tab: ServiceTab.overview,
      child: DockgeOverviewScreen(topPadding: _serviceTabTopPadding),
    ),
  ),
  // The list that was the whole service. Its own app bar stays off: the band
  // above draws the title and the lens, and the tab bar sits under it.
  ServiceTab.stacks => _page(
    tab.segment,
    (state) => const ServiceTabScaffold(
      service: ServiceKey.dockge,
      tab: ServiceTab.stacks,
      child: DockgeScreen(showAppBar: false, topPadding: _serviceTabTopPadding),
    ),
    routes: [
      // `new` before `stack/:name`, though nothing here forces it: both are
      // literal-led, so neither can swallow the other. It is the New button's
      // destination and it reads first.
      _page('new', (state) => const DockgeStackEditScreen()),
      // Pushed INSIDE the branch, so leaving Dockge for another app tab and
      // coming back returns to the stack rather than to the top of the list.
      //
      // A blank name falls back to the tab this page was pushed from, not to
      // the app home: the branch is where the user still is. Dockge stack names
      // are free-form strings — a Compose project directory name — so there is
      // no `safeIntParam` to run, and emptiness is the whole of what can be
      // checked.
      _page(
        'stack/:name',
        (state) => DockgeStackDetailScreen(name: state.pathParameters['name']!),
        redirect: _rejectBlankDockgeStackName,
        routes: [
          // No guard of its own: a route-level redirect fires for every
          // match under it, descendants included, so the detail's guard has
          // already run by the time this builds.
          _page(
            'edit',
            (state) =>
                DockgeStackEditScreen(name: state.pathParameters['name']!),
          ),
        ],
      ),
    ],
  ),
  ServiceTab.terminal => _page(
    tab.segment,
    (state) => ServiceTabScaffold(
      service: ServiceKey.dockge,
      tab: tab,
      child: ServiceTabPlaceholder(service: ServiceKey.dockge, tab: tab),
    ),
  ),
  _ => throw UnsupportedError(
    'ServiceTab.${tab.name} is on dockge\'s bar with no branch root',
  ),
};

String? _rejectBlankDockgeStackName(
  BuildContext context,
  GoRouterState state,
) => (state.pathParameters['name']?.trim().isEmpty ?? true)
    ? ServiceRoutes.dockgeStacks
    : null;

/// Prowlarr: one shell, one branch per tab.
///
/// [_radarrRoutes] carries the reasoning for every structural choice and none
/// of it is Radarr's — the nesting inside the Dashboard branch, the
/// redirect-only node whose guard is on the full location, the childless
/// compatibility tails, the wildcard that throws.
///
/// What is Prowlarr's own is **Settings**, which is not a tab (decision 26) and
/// therefore not in the shell. It hangs off the service node beside the
/// `StatefulShellRoute`, exactly where it hung off the service page before:
/// four field-driven sections, an app-profiles page and a tags page that no one
/// tab owns, pushed on the Dashboard branch's navigator as they always were. It
/// keeps its children where a compatibility tail may not, and safely: `settings`
/// is not a tab segment, so there is nothing inside the shell for it to shadow.
RouteBase _prowlarrRoutes() {
  const service = ServiceKey.prowlarr;
  final tabs = tabsFor(service)!;

  return GoRoute(
    path: service.routeParam,
    redirect: (context, state) => state.uri.path == ServiceRoutes.prowlarr
        ? _preserveQuery(state.uri, ServiceRoutes.prowlarrOverview)
        : null,
    routes: [
      // The tab-less tails, childless on purpose: the matcher treats a prefix
      // hit with no complete match as no match at all, so `indexer/:id` here
      // cannot shadow `indexers/indexer/:id` inside the shell below.
      GoRoute(
        path: 'library',
        redirect: (context, state) =>
            _preserveQuery(state.uri, ServiceRoutes.prowlarrIndexers),
      ),
      // No id validation: the canonical route inside the branch owns it, and
      // doing it twice is two places to get it wrong.
      GoRoute(
        path: 'indexer/:id',
        redirect: (context, state) => _preserveQuery(
          state.uri,
          '${ServiceRoutes.prowlarrIndexerBase}/'
          '${state.pathParameters['id']}',
        ),
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
              routes: [_prowlarrBranchRoot(tab)],
            ),
        ],
      ),
    ],
  );
}

/// The route at the root of one Prowlarr tab.
///
/// Branch order is `tabsFor(ServiceKey.prowlarr)` and nothing else, because the
/// bar is generated from the same list and taps it by index. The wildcard
/// throws rather than quietly rendering a placeholder: a fifth tab added to
/// that table with no case here is a bar and a router disagreeing.
GoRoute _prowlarrBranchRoot(ServiceTab tab) => switch (tab) {
  ServiceTab.overview => _page(
    tab.segment,
    (state) => const ServiceTabScaffold(
      service: ServiceKey.prowlarr,
      tab: ServiceTab.overview,
      child: ProwlarrOverviewScreen(topPadding: _serviceTabTopPadding),
    ),
  ),
  ServiceTab.indexers => _page(
    tab.segment,
    (state) => const ServiceTabScaffold(
      service: ServiceKey.prowlarr,
      tab: ServiceTab.indexers,
      child: ProwlarrLibraryScreen(
        showAppBar: false,
        topPadding: _serviceTabTopPadding,
      ),
    ),
    routes: [
      // The indexer, now INSIDE the Indexers branch. Pushing it keeps the
      // branch, so leaving Prowlarr for another app tab and coming back returns
      // to the indexer rather than to the top of the list.
      _page(
        'indexer/:id',
        (state) => ProwlarrIndexerDetailScreen(
          indexerId: RouteUtils.safeIntParam(state, 'id')!,
        ),
        redirect: (context, state) =>
            RouteUtils.safeIntParam(state, 'id') == null
            ? ServiceRoutes.prowlarrIndexers
            : null,
      ),
    ],
  ),
  // Neither is blocked, and saying so matters: both tabs are a screen away, not
  // an endpoint away.
  //
  // History has `GET /api/v1/history` behind it — paged, sortable, filterable
  // by event type — and `prowlarrRecentHistoryProvider` already reads page one
  // for the Overview. A full tab needs paging and the event filter on top of
  // it, and nothing else.
  //
  // Stats has `GET /api/v1/indexerstats`, which `prowlarrIndexerStatsProvider`
  // already calls over a fixed 24-hour window: per-indexer queries, grabs and
  // failures, with the totals derived in `ProwlarrIndexerStats`. What the tab
  // adds over the Overview's three KPIs is the per-indexer table and a window
  // the user can choose — the client has accepted `startDate`/`endDate` all
  // along.
  ServiceTab.history || ServiceTab.stats => _page(
    tab.segment,
    (state) => ServiceTabScaffold(
      service: ServiceKey.prowlarr,
      tab: tab,
      child: ServiceTabPlaceholder(service: ServiceKey.prowlarr, tab: tab),
    ),
  ),
  _ => throw UnsupportedError(
    'ServiceTab.${tab.name} is on prowlarr\'s bar with no branch root',
  ),
};

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
/// Readarr's Overview is `ReadarrOverviewScreen`, the page written against the
/// board rather than the pre-tab-model home the model first borrowed — and that
/// home has since been retired, taking nothing with it: its author preview is
/// the Library tab in full, and the two regions the notes record as lost
/// (`Coming up`, `Recently added`) are the board's — that home never drew
/// either of them, at any point in its history. The
/// Overview draws only the regions the client can fill — the queue's faults,
/// the library's backlog, where the books are filed, what happened today — and
/// leaves out the two the board asks for and `ReadarrService` cannot answer.
GoRoute _readarrBranchRoot(ServiceTab tab) => switch (tab) {
  ServiceTab.overview => _page(
    tab.segment,
    (state) => const ServiceTabScaffold(
      service: ServiceKey.readarr,
      tab: ServiceTab.overview,
      child: ReadarrOverviewScreen(topPadding: _serviceTabTopPadding),
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

/// SABnzbd: one shell, one branch per tab.
///
/// [_radarrRoutes] carries the reasoning for the shape and [_qbittorrentRoutes]
/// for what a download client does with it. Like Transmission it needs no
/// compatibility tail: a queue slot and a history slot are each one row that
/// expands, so it never had a detail page and its bare root is the only path it
/// ever shipped.
RouteBase _sabnzbdRoutes() {
  const service = ServiceKey.sabnzbd;
  final tabs = tabsFor(service)!;

  return GoRoute(
    path: service.routeParam,
    redirect: (context, state) => state.uri.path == ServiceRoutes.sabnzbd
        ? _preserveQuery(state.uri, ServiceRoutes.sabnzbdOverview)
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
              routes: [_sabnzbdBranchRoot(tab)],
            ),
        ],
      ),
    ],
  );
}

/// The route at the root of one SABnzbd tab.
///
/// Branch order is `tabsFor(ServiceKey.sabnzbd)` and nothing else, and the
/// wildcard throws for the reason it throws everywhere else in this file.
GoRoute _sabnzbdBranchRoot(ServiceTab tab) => switch (tab) {
  ServiceTab.overview => _page(
    tab.segment,
    (state) => const ServiceTabScaffold(
      service: ServiceKey.sabnzbd,
      tab: ServiceTab.overview,
      child: SabnzbdOverviewScreen(topPadding: _serviceTabTopPadding),
    ),
  ),
  // `SabnzbdScreen` is still the whole queue page — the readouts above it now
  // have their own home on Overview — so Queue takes it unsplit.
  ServiceTab.queue => _page(
    tab.segment,
    (state) => const ServiceTabScaffold(
      service: ServiceKey.sabnzbd,
      tab: ServiceTab.queue,
      child: SabnzbdScreen(
        showAppBar: false,
        topPadding: _serviceTabTopPadding,
      ),
    ),
  ),
  // History is a placeholder but not blocked: `mode=history` is already called,
  // so the tab is a screen away.
  //
  // **Servers is blocked**, and on a narrower thing than a missing call.
  // `mode=server_stats` is called, but `SabnzbdServerStats.fromJson` keeps one
  // field of it — the all-time `total` — and throws away the per-server object
  // the tab exists to show. The live half has nothing at all behind it:
  // `mode=status`, which carries each server's connection count, its article
  // errors and whether it is active, is never called, and neither is
  // `mode=get_config&section=servers` for the configured list.
  ServiceTab.history || ServiceTab.servers => _page(
    tab.segment,
    (state) => ServiceTabScaffold(
      service: ServiceKey.sabnzbd,
      tab: tab,
      child: ServiceTabPlaceholder(service: ServiceKey.sabnzbd, tab: tab),
    ),
  ),
  _ => throw UnsupportedError(
    'ServiceTab.${tab.name} is on sabnzbd\'s bar with no branch root',
  ),
};

/// NZBGet: the last of the four download clients on one shell and one bar.
///
/// [_radarrRoutes] carries the reasoning for the shape and [_qbittorrentRoutes]
/// for what a download client does with it. Like Transmission and SABnzbd it
/// needs no compatibility tail — a group is an expanding row, never a pushed
/// page — and its five tabs are the widest bar of the four because the daemon
/// keeps feeds and a log as first-class things the others do not have.
RouteBase _nzbgetRoutes() {
  const service = ServiceKey.nzbget;
  final tabs = tabsFor(service)!;

  return GoRoute(
    path: service.routeParam,
    redirect: (context, state) => state.uri.path == ServiceRoutes.nzbget
        ? _preserveQuery(state.uri, ServiceRoutes.nzbgetOverview)
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
              routes: [_nzbgetBranchRoot(tab)],
            ),
        ],
      ),
    ],
  );
}

/// The route at the root of one NZBGet tab.
///
/// Branch order is `tabsFor(ServiceKey.nzbget)` and nothing else, and the
/// wildcard throws for the reason it throws everywhere else in this file — here
/// over five cases rather than three, which is exactly when a hand-kept list
/// starts drifting.
GoRoute _nzbgetBranchRoot(ServiceTab tab) => switch (tab) {
  ServiceTab.overview => _page(
    tab.segment,
    (state) => const ServiceTabScaffold(
      service: ServiceKey.nzbget,
      tab: ServiceTab.overview,
      child: NzbgetOverviewScreen(topPadding: _serviceTabTopPadding),
    ),
  ),
  // `NzbgetScreen` is still readouts and group list together, so Queue takes it
  // unsplit for the reason SABnzbd's does.
  ServiceTab.queue => _page(
    tab.segment,
    (state) => const ServiceTabScaffold(
      service: ServiceKey.nzbget,
      tab: ServiceTab.queue,
      child: NzbgetScreen(showAppBar: false, topPadding: _serviceTabTopPadding),
    ),
  ),
  // History is a screen away, not an endpoint away: `history` is already
  // called.
  //
  // **Feeds and Messages are blocked**, and on whole RPC methods rather than on
  // fields. `NzbgetClient` calls thirteen methods and none of them is a feed
  // one — no `listfeeds` for the configured feeds, no `viewfeed`/`fetchfeed`
  // for their contents — and none is a log one: `log` and `loadlog` are what
  // the Messages tab is, and neither has ever been sent.
  ServiceTab.history || ServiceTab.feeds || ServiceTab.messages => _page(
    tab.segment,
    (state) => ServiceTabScaffold(
      service: ServiceKey.nzbget,
      tab: tab,
      child: ServiceTabPlaceholder(service: ServiceKey.nzbget, tab: tab),
    ),
  ),
  _ => throw UnsupportedError(
    'ServiceTab.${tab.name} is on nzbget\'s bar with no branch root',
  ),
};

/// Unraid: one shell, one branch per tab.
///
/// [_radarrRoutes] carries the reasoning for every structural choice and none
/// of it is Radarr's — the nesting inside the Dashboard branch, the
/// redirect-only node whose guard is on the full location, the wildcard that
/// throws.
///
/// **No compatibility tail at all**, which is Unraid's own difference and the
/// same one Transmission has: the only path it ever shipped is its bare root,
/// because the whole service was one page with no detail to push. The root is
/// what this node redirects and there is nothing else to forward.
///
/// Two of the six tabs draw something, and both were already on that page: the
/// array's disks and the Docker containers, the two halves `UnraidScreen` split
/// into. The other four are **blocked on the read layer rather than on work** —
/// `UnraidClient` speaks exactly three documents (`info`, `array`, `docker`),
/// so there is no VM list, no notification feed and no share table to draw.
/// Nothing here is guessed: this is the one service in the stack that has never
/// been run against a real instance.
RouteBase _unraidRoutes() {
  const service = ServiceKey.unraid;
  final tabs = tabsFor(service)!;

  return GoRoute(
    path: service.routeParam,
    redirect: (context, state) => state.uri.path == ServiceRoutes.unraid
        ? _preserveQuery(state.uri, ServiceRoutes.unraidOverview)
        : null,
    routes: [
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
              routes: [_unraidBranchRoot(tab)],
            ),
        ],
      ),
    ],
  );
}

/// The route at the root of one Unraid tab.
///
/// Branch order is `tabsFor(ServiceKey.unraid)` and nothing else, because the
/// bar is generated from the same list and taps it by index. The wildcard
/// throws rather than quietly rendering a placeholder: a seventh tab added to
/// that table with no case here is a bar and a router disagreeing.
///
/// **VMs, Notifications and Shares stay placeholders, and are blocked rather
/// than unbuilt.** `UnraidClient` speaks three documents — `info`, `array`,
/// `dockerContainers` — and the committed SDL declares no `vms`, no
/// `notifications` and no `shares` query, so there is nothing for a screen to
/// read. `UnraidOverviewScreen` leaves those regions out for the same reason
/// instead of drawing them as zeroes.
GoRoute _unraidBranchRoot(ServiceTab tab) => switch (tab) {
  ServiceTab.overview => _page(
    tab.segment,
    (state) => const ServiceTabScaffold(
      service: ServiceKey.unraid,
      tab: ServiceTab.overview,
      child: UnraidOverviewScreen(topPadding: _serviceTabTopPadding),
    ),
  ),
  ServiceTab.array => _page(
    tab.segment,
    (state) => const ServiceTabScaffold(
      service: ServiceKey.unraid,
      tab: ServiceTab.array,
      child: UnraidScreen.array(
        showAppBar: false,
        topPadding: _serviceTabTopPadding,
      ),
    ),
  ),
  ServiceTab.docker => _page(
    tab.segment,
    (state) => const ServiceTabScaffold(
      service: ServiceKey.unraid,
      tab: ServiceTab.docker,
      child: UnraidScreen.docker(
        showAppBar: false,
        topPadding: _serviceTabTopPadding,
      ),
    ),
  ),
  ServiceTab.vms || ServiceTab.notifications || ServiceTab.shares => _page(
    tab.segment,
    (state) => ServiceTabScaffold(
      service: ServiceKey.unraid,
      tab: tab,
      child: ServiceTabPlaceholder(service: ServiceKey.unraid, tab: tab),
    ),
  ),
  _ => throw UnsupportedError(
    'ServiceTab.${tab.name} is on unraid\'s bar with no branch root',
  ),
};

/// Transmission: one shell, one branch per tab.
///
/// [_radarrRoutes] carries the reasoning for the shape and [_qbittorrentRoutes]
/// for what a download client does with it. Transmission's own difference is
/// that it needs **no compatibility tail at all**: the only path it ever
/// shipped is its bare root, because its torrent list expands rows in place and
/// never had a detail page to push. The root is what this node redirects, and
/// there is nothing else to forward.
RouteBase _transmissionRoutes() {
  const service = ServiceKey.transmission;
  final tabs = tabsFor(service)!;

  return GoRoute(
    path: service.routeParam,
    redirect: (context, state) => state.uri.path == ServiceRoutes.transmission
        ? _preserveQuery(state.uri, ServiceRoutes.transmissionOverview)
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
              routes: [_transmissionBranchRoot(tab)],
            ),
        ],
      ),
    ],
  );
}

/// The route at the root of one Transmission tab.
///
/// Branch order is `tabsFor(ServiceKey.transmission)` and nothing else. The
/// wildcard throws: a fifth tab on that table with no case here is a bar and a
/// router disagreeing, and that has to fail loudly rather than light a tab that
/// shows nothing.
GoRoute _transmissionBranchRoot(ServiceTab tab) => switch (tab) {
  ServiceTab.overview => _page(
    tab.segment,
    (state) => const ServiceTabScaffold(
      service: ServiceKey.transmission,
      tab: ServiceTab.overview,
      child: TransmissionOverviewScreen(topPadding: _serviceTabTopPadding),
    ),
  ),
  ServiceTab.queue => _page(
    tab.segment,
    (state) => const ServiceTabScaffold(
      service: ServiceKey.transmission,
      tab: ServiceTab.queue,
      child: TransmissionScreen(
        showAppBar: false,
        topPadding: _serviceTabTopPadding,
      ),
    ),
  ),
  // Two placeholders, and they are blocked different distances away — which is
  // why each is named rather than waved at as "not built".
  //
  // **Labels** can be *read* today — `labels` is parsed off every torrent by
  // `TransmissionTorrent.fromJson` — but a Labels tab that cannot assign one is
  // a filter, not a tab, and the write has no client method: `torrent-set` is
  // called in exactly one place, with the four speed keys, and never with
  // `labels`.
  //
  // **Session** is the furthest. `session-get` is called, but
  // `TransmissionSession` keeps eight fields of the sixty the daemon returns —
  // no peer port, encryption, port forwarding, peer limits, seed ratio,
  // incomplete directory, blocklist or queue sizes — and `session-set` is
  // called with `alt-speed-enabled` and nothing else. The tab needs both halves
  // widened, not a new RPC method.
  ServiceTab.labels || ServiceTab.session => _page(
    tab.segment,
    (state) => ServiceTabScaffold(
      service: ServiceKey.transmission,
      tab: tab,
      child: ServiceTabPlaceholder(service: ServiceKey.transmission, tab: tab),
    ),
  ),
  _ => throw UnsupportedError(
    'ServiceTab.${tab.name} is on transmission\'s bar with no branch root',
  ),
};

/// Nginx Proxy Manager: one shell, one branch per tab.
///
/// [_radarrRoutes] carries the reasoning for every structural choice and none
/// of it is Radarr's — the nesting inside the Dashboard branch, the
/// redirect-only node whose guard is on the full location, the wildcard that
/// throws. Like Unraid it needs **no compatibility tail**: the only path it
/// ever shipped is its bare root.
///
/// What is NPM's own is that **becoming a tab changes nothing about who may
/// write.** The per-control gate in `npm_write_gate.dart` travels with each
/// control, and the permission band that explains it is drawn on *both* halves
/// of the split rather than on the tab that has the most controls: Proxy hosts
/// carries the host menu's Enable/Disable, Certificates carries Renew, and
/// splitting a page across a bar must not leave a control on one tab and the
/// sentence explaining why it is attenuated on another.
///
/// Two of the five tabs draw something and both were sections of that one page.
/// **Access lists and Audit log are blocked on endpoints rather than on work**:
/// `NpmClient` calls `/nginx/proxy-hosts`, `/nginx/redirection-hosts`,
/// `/nginx/dead-hosts`, `/nginx/streams`, `/nginx/certificates`, `/tokens` and
/// `/users/me`, and neither `/nginx/access-lists` nor `/audit-log` is among
/// them, so neither tab has a client to ask.
RouteBase _npmRoutes() {
  const service = ServiceKey.nginxProxyManager;
  final tabs = tabsFor(service)!;

  return GoRoute(
    path: service.routeParam,
    redirect: (context, state) =>
        state.uri.path == ServiceRoutes.nginxProxyManager
        ? _preserveQuery(state.uri, ServiceRoutes.npmOverview)
        : null,
    routes: [
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
              routes: [_npmBranchRoot(tab)],
            ),
        ],
      ),
    ],
  );
}

/// The route at the root of one NPM tab.
///
/// Branch order is `tabsFor(ServiceKey.nginxProxyManager)` and nothing else,
/// because the bar is generated from the same list and taps it by index. The
/// wildcard throws rather than quietly rendering a placeholder: a sixth tab
/// added to that table with no case here is a bar and a router disagreeing.
///
/// **Access lists and Audit log stay placeholders, and both are blocked on an
/// endpoint rather than on work**: `NpmClient` calls neither
/// `GET /api/nginx/access-lists` nor `GET /api/audit-log`.
/// `NpmOverviewScreen` omits the two regions the board draws from them for that
/// same reason — the tabs are where the work belongs the day the client can
/// read them.
GoRoute _npmBranchRoot(ServiceTab tab) => switch (tab) {
  ServiceTab.overview => _page(
    tab.segment,
    (state) => const ServiceTabScaffold(
      service: ServiceKey.nginxProxyManager,
      tab: ServiceTab.overview,
      child: NpmOverviewScreen(topPadding: _serviceTabTopPadding),
    ),
  ),
  ServiceTab.proxyHosts => _page(
    tab.segment,
    (state) => const ServiceTabScaffold(
      service: ServiceKey.nginxProxyManager,
      tab: ServiceTab.proxyHosts,
      child: NpmScreen.proxyHosts(
        showAppBar: false,
        topPadding: _serviceTabTopPadding,
      ),
    ),
  ),
  ServiceTab.certificates => _page(
    tab.segment,
    (state) => const ServiceTabScaffold(
      service: ServiceKey.nginxProxyManager,
      tab: ServiceTab.certificates,
      child: NpmScreen.certificates(
        showAppBar: false,
        topPadding: _serviceTabTopPadding,
      ),
    ),
  ),
  ServiceTab.accessLists || ServiceTab.auditLog => _page(
    tab.segment,
    (state) => ServiceTabScaffold(
      service: ServiceKey.nginxProxyManager,
      tab: tab,
      child: ServiceTabPlaceholder(
        service: ServiceKey.nginxProxyManager,
        tab: tab,
      ),
    ),
  ),
  _ => throw UnsupportedError(
    'ServiceTab.${tab.name} is on npm\'s bar with no branch root',
  ),
};

/// The route spellings of one media server, by key.
///
/// A switch returning the four constants rather than interpolating them from
/// [ServiceKey.routeParam] and [ServiceTab.segment]: the constants have to stay
/// `const` — an enum instance's field is not a compile-time constant in Dart —
/// and an earlier attempt at composing a path here shipped one containing a
/// literal dollar sign that no analyzer could see. The wildcard throws because
/// this file has exactly two media servers and a third arriving silently is
/// worse than a build that stops.
({String root, String overview, String libraries, String itemBase})
_streamPaths(ServiceKey service) => switch (service) {
  ServiceKey.jellyfin => (
    root: ServiceRoutes.jellyfin,
    overview: ServiceRoutes.jellyfinOverview,
    libraries: ServiceRoutes.jellyfinLibraries,
    itemBase: ServiceRoutes.jellyfinItemBase,
  ),
  ServiceKey.plex => (
    root: ServiceRoutes.plex,
    overview: ServiceRoutes.plexOverview,
    libraries: ServiceRoutes.plexLibraries,
    itemBase: ServiceRoutes.plexItemBase,
  ),
  _ => throw UnsupportedError('${service.name} is not a media server'),
};

/// Jellyfin and Plex: one shell each, one branch per tab, one builder for both.
///
/// [_radarrRoutes] carries the reasoning for every structural choice and none of
/// it is Radarr's — the nesting inside the Dashboard branch, the redirect-only
/// node whose guard is on the full location, the childless compatibility tails,
/// the wildcard that throws.
///
/// **One function for two services, because the screens are one family.** Every
/// Stream surface is written against `StreamServerClient` and takes the service
/// as a parameter, so there is nothing per-service to fork here. The two bars
/// are genuinely different — Jellyfin has Users, Devices, Tasks and Activity;
/// Plex has On deck, Activities, Devices and Playlists — and that difference
/// lives in `tabsFor`, which this reads. Forking the routes to express it would
/// put the same list in two places and let them drift.
///
/// **What the single page became.** Until now the whole service was
/// `StreamDashboardScreen`: the sessions at the top, the libraries at its foot,
/// and `library/:id` and `item/:id` hanging off the service root because a
/// one-page service had nowhere else to hang them. The libraries are the
/// Libraries tab, the sessions belong to the Overview the next pass builds, and
/// both details moved **inside** the Libraries branch — the move Radarr's film
/// made into Library, for the same two reasons: leaving the service for another
/// app tab and coming back returns to the item, and the poster's Hero still
/// flies because the grid it left and the page it lands on share one Navigator.
RouteBase _streamRoutes(ServiceKey service) {
  final tabs = tabsFor(service)!;
  final paths = _streamPaths(service);

  return GoRoute(
    path: service.routeParam,
    redirect: (context, state) => state.uri.path == paths.root
        ? _preserveQuery(state.uri, paths.overview)
        : null,
    routes: [
      // The two tab-less tails, childless on purpose: the matcher treats a
      // prefix hit with no complete match as no match at all, so `item/:id`
      // here cannot shadow `libraries/item/:id` inside the shell below.
      //
      // Both are spellings the app shipped — `ServiceRoutes.jellyfinItem` built
      // `/dashboard/jellyfin/item/<guid>` for every poster tile, every search
      // result and the availability slot on a Radarr or Sonarr detail — and
      // both are also the second hop of the `/services/...` rewrite. No id
      // validation: the canonical routes inside the branch own it, and doing it
      // twice is two places to get it wrong.
      GoRoute(
        path: 'library/:id',
        redirect: (context, state) => _preserveQuery(
          state.uri,
          '${paths.libraries}/${state.pathParameters['id']}',
        ),
      ),
      GoRoute(
        path: 'item/:id',
        redirect: (context, state) => _preserveQuery(
          state.uri,
          '${paths.itemBase}/${state.pathParameters['id']}',
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
              routes: [_streamBranchRoot(service, tab)],
            ),
        ],
      ),
    ],
  );
}

/// The route at the root of one media server tab.
///
/// Branch order is `tabsFor(service)` and nothing else, because the bar is
/// generated from the same list and taps it by index. The wildcard throws
/// rather than quietly rendering a placeholder: a seventh tab added to that
/// table with no case here is a bar and a router disagreeing.
///
/// Overview and Libraries are real on both servers, and `StreamOverviewScreen`
/// is mounted twice from one class — the same shape every other screen in that
/// folder has, where the only per-service input is the [ServiceKey] and the
/// difference between the two servers lives in what their clients can answer.
///
/// The rest are placeholders, and the two services are placeholders for
/// different reasons — which is the honest split given that Jellyfin has been
/// run against a live server and Plex has not:
///
///  * **Jellyfin.** Users is unbuilt rather than blocked: `getViewers()` already
///    reads `/Users` for the settings viewer picker, so the tab has a client the
///    day someone draws it. Devices (`/Devices`), Tasks (`/ScheduledTasks`) and
///    Activity (`/System/ActivityLog/Entries`) are blocked — `JellyfinClient`
///    calls none of the three.
///  * **Plex.** On deck is unbuilt rather than blocked: `getContinueWatching()`
///    already reads `/hubs/continueWatching`. Activities (`/activities`),
///    Devices (`/devices`) and Playlists (`/playlists`) are blocked, and on a
///    server nobody here has ever run — so nothing is guessed about what those
///    endpoints return.
GoRoute _streamBranchRoot(ServiceKey service, ServiceTab tab) {
  final paths = _streamPaths(service);

  /// Where a malformed id falls back to: the tab the page would have been
  /// pushed from, not the app home. The branch is where the user still is, and
  /// sending them out of the service would be a bigger move than the mistake.
  String? rejectBlankId(BuildContext context, GoRouterState state) =>
      (state.pathParameters['id']?.trim().isEmpty ?? true)
      ? paths.libraries
      : null;

  return switch (tab) {
    ServiceTab.libraries => _page(
      tab.segment,
      (state) => ServiceTabScaffold(
        service: service,
        tab: ServiceTab.libraries,
        child: StreamLibrariesScreen(
          service: service,
          showAppBar: false,
          topPadding: _serviceTabTopPadding,
        ),
      ),
      routes: [
        // `item/:id` BEFORE `:id`, and the order is load-bearing: routes match
        // in declaration order, so the other way round
        // `/dashboard/plex/libraries/item/9` would resolve as a library browse
        // whose id is the word `item`.
        //
        // Ids travel as path segments rather than through `_libraryDetailPage`,
        // whose `RouteUtils.safeIntParam` cannot represent a Jellyfin GUID or a
        // Plex `ratingKey` — both opaque strings that only often look numeric.
        // They are guarded for emptiness rather than dereferenced with `!` or
        // defaulted to `''`.
        _page(
          'item/:id',
          (state) => StreamItemScreen(
            service: service,
            itemId: state.pathParameters['id']!,
          ),
          redirect: rejectBlankId,
        ),
        // One library, browsed. The display name rides in `?title=` so a caller
        // that already knows it spares the destination a fetch, but a cold deep
        // link resolves from the path alone.
        _page(
          ':id',
          (state) => StreamLibraryScreen(
            service: service,
            libraryId: state.pathParameters['id']!,
            libraryTitle: state.uri.queryParameters['title'],
          ),
          redirect: rejectBlankId,
        ),
      ],
    ),
    ServiceTab.overview => _page(
      tab.segment,
      (state) => ServiceTabScaffold(
        service: service,
        tab: ServiceTab.overview,
        child: StreamOverviewScreen(
          service: service,
          topPadding: _serviceTabTopPadding,
        ),
      ),
    ),
    ServiceTab.users ||
    ServiceTab.devices ||
    ServiceTab.tasks ||
    ServiceTab.activity ||
    ServiceTab.onDeck ||
    ServiceTab.activities ||
    ServiceTab.playlists => _page(
      tab.segment,
      (state) => ServiceTabScaffold(
        service: service,
        tab: tab,
        child: ServiceTabPlaceholder(service: service, tab: tab),
      ),
    ),
    _ => throw UnsupportedError(
      'ServiceTab.${tab.name} is on ${service.name}\'s bar with no branch root',
    ),
  };
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
  required String fallbackLocation,
}) {
  final path = state.uri.path;
  if (path == legacyBase) return fallbackLocation;

  final prefix = '$legacyBase/';
  if (!path.startsWith(prefix)) return null;

  final id = path.substring(prefix.length);
  if (id.isEmpty || id.contains('/')) return fallbackLocation;
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
      _seerrRoutes(),
      _radarrRoutes(),
      _sonarrRoutes(),
      _lidarrRoutes(),
      _qbittorrentRoutes(),
      _bazarrRoutes(),
      _truenasRoutes(path: ServiceKey.truenas.routeParam),
      _dockgeRoutes(),
      _prowlarrRoutes(),
      _readarrRoutes(),
      _sabnzbdRoutes(),
      _nzbgetRoutes(),
      _unraidRoutes(),
      _transmissionRoutes(),
      _npmRoutes(),
      _streamRoutes(ServiceKey.jellyfin),
      _streamRoutes(ServiceKey.plex),
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
      _legacyDiscoverRoutes(path: '/discover'),
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
