import 'package:flutter_test/flutter_test.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

void main() {
  group('ServiceRoutes', () {
    test('every registered service has a home route, and it interpolates', () {
      // Exhaustive over the registry, so a service added later cannot ship
      // without one. It also catches the specific way this helper can be
      // broken and still analyses clean: an escaped dollar in the literal
      // makes the helper return the interpolation as text, which no type
      // checks and no analyzer rule sees.
      for (final service in ServiceKey.values) {
        final route = ServiceRoutes.forService(service);
        expect(route, startsWith('${ServiceRoutes.dashboard}/'));
        expect(route, isNot(contains(r'$')));
        expect(route, isNot(contains('{')));
        expect(route, endsWith('/${service.routeParam}'));
      }
    });

    test('the two that used to be built by hand are constants now', () {
      expect(
        ServiceRoutes.transmission,
        ServiceRoutes.forService(ServiceKey.transmission),
      );
      // The one segment that is not the enum name.
      expect(ServiceRoutes.nginxProxyManager, '/dashboard/npm');
      expect(
        ServiceRoutes.nginxProxyManager,
        ServiceRoutes.forService(ServiceKey.nginxProxyManager),
      );
    });

    test('builds Radarr detail routes with optional hero tag', () {
      // The film moved under `library/`: it is a page inside the Library tab's
      // branch now, not a sibling of the tabs. Every link in the app is built
      // here, so this constant is what put it there.
      expect(
        ServiceRoutes.radarrMovie(42),
        '/dashboard/radarr/library/movie/42',
      );
      expect(
        ServiceRoutes.radarrMovie(42, heroTag: 'movie hero'),
        '/dashboard/radarr/library/movie/42?heroTag=movie+hero',
      );
    });

    test('the Radarr tab roots are spelled by the tabs they mount', () {
      // Both are written as literals in `ServiceRoutes` because an enum
      // instance's field is not a compile-time constant in Dart and these have
      // to stay `const` — so nothing the analyzer sees ties the URL spelling to
      // the tab. This does, and the film hangs off the second one, which means
      // a drift there moves every detail link in the app with it.
      expect(
        ServiceRoutes.radarrOverview,
        '${ServiceRoutes.radarr}/${ServiceTab.overview.segment}',
      );
      expect(
        ServiceRoutes.radarrLibrary,
        '${ServiceRoutes.radarr}/${ServiceTab.library.segment}',
      );
      expect(
        ServiceRoutes.radarrMovieBase,
        startsWith('${ServiceRoutes.radarrLibrary}/'),
      );
    });

    test('builds Sonarr and Lidarr detail routes', () {
      expect(
        ServiceRoutes.sonarrSeries(7, heroTag: 'series_7'),
        '/dashboard/sonarr/series/7?heroTag=series_7',
      );
      expect(
        ServiceRoutes.lidarrArtist(9, heroTag: 'artist_9'),
        '/dashboard/lidarr/artist/9?heroTag=artist_9',
      );
    });

    test('encodes Seerr detail query values once', () {
      expect(
        ServiceRoutes.seerrDetail(
          mediaType: 'tv',
          id: 123,
          heroTag: 'hero tag',
          posterUrl: 'https://image.tmdb.org/t/p/w500/a/b.jpg',
        ),
        '/dashboard/seerr/tv/123?heroTag=hero+tag&posterUrl=https%3A%2F%2Fimage.tmdb.org%2Ft%2Fp%2Fw500%2Fa%2Fb.jpg',
      );
    });

    test('normalizes non-tv Seerr media types to movie', () {
      expect(
        ServiceRoutes.seerrDetail(mediaType: 'movie', id: 1),
        '/dashboard/seerr/movie/1',
      );
      expect(
        ServiceRoutes.seerrDetail(mediaType: 'person', id: 1),
        '/dashboard/seerr/movie/1',
      );
    });

    test('exposes the Bazarr service root', () {
      expect(ServiceRoutes.bazarr, '/dashboard/bazarr');
    });

    test('builds Prowlarr library and indexer detail routes', () {
      expect(ServiceRoutes.prowlarr, '/dashboard/prowlarr');
      expect(ServiceRoutes.prowlarrLibrary, '/dashboard/prowlarr/library');
      expect(ServiceRoutes.prowlarrIndexer(3), '/dashboard/prowlarr/indexer/3');
    });
  });
}
