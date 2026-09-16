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
      // The show moved under `library/` with the film, and for the same
      // reason: it is a page inside the Library tab's branch now, not a
      // sibling of the tabs.
      expect(
        ServiceRoutes.sonarrSeries(7, heroTag: 'series_7'),
        '/dashboard/sonarr/library/series/7?heroTag=series_7',
      );
      expect(
        ServiceRoutes.lidarrArtist(9, heroTag: 'artist_9'),
        '/dashboard/lidarr/library/artist/9?heroTag=artist_9',
      );
    });

    test('the Sonarr tab roots are spelled by the tabs they mount', () {
      // Same tie as Radarr's, and it has to be its own case rather than a loop
      // over the four: these are `const` literals precisely because an enum
      // instance's field is not a compile-time constant, so there is nothing
      // to iterate that would not defeat the point.
      expect(
        ServiceRoutes.sonarrOverview,
        '${ServiceRoutes.sonarr}/${ServiceTab.overview.segment}',
      );
      expect(
        ServiceRoutes.sonarrLibrary,
        '${ServiceRoutes.sonarr}/${ServiceTab.library.segment}',
      );
      expect(
        ServiceRoutes.sonarrSeriesBase,
        startsWith('${ServiceRoutes.sonarrLibrary}/'),
      );
    });

    test('the Lidarr tab roots are spelled by the tabs they mount', () {
      expect(
        ServiceRoutes.lidarrOverview,
        '${ServiceRoutes.lidarr}/${ServiceTab.overview.segment}',
      );
      expect(
        ServiceRoutes.lidarrLibrary,
        '${ServiceRoutes.lidarr}/${ServiceTab.library.segment}',
      );
      expect(
        ServiceRoutes.lidarrArtistBase,
        startsWith('${ServiceRoutes.lidarrLibrary}/'),
      );
    });

    test('the Readarr tab roots are spelled by the tabs they mount', () {
      expect(
        ServiceRoutes.readarrOverview,
        '${ServiceRoutes.readarr}/${ServiceTab.overview.segment}',
      );
      // Unchanged by the migration, and that is the assertion: the author list
      // was already at this address as a pushed page, so every link that ever
      // pointed at it still resolves — now to the Library tab.
      expect(ServiceRoutes.readarrLibrary, '/dashboard/readarr/library');
      expect(
        ServiceRoutes.readarrLibrary,
        '${ServiceRoutes.readarr}/${ServiceTab.library.segment}',
      );
    });

    test('the qBittorrent tab roots are spelled by the tabs they mount', () {
      // Same tie as the four \*arr, and it has to be its own case for the same
      // reason: these are `const` literals precisely because an enum instance's
      // field is not a compile-time constant, so there is nothing to iterate
      // that would not defeat the point.
      expect(
        ServiceRoutes.qbittorrentOverview,
        '${ServiceRoutes.qbittorrent}/${ServiceTab.overview.segment}',
      );
      expect(
        ServiceRoutes.qbittorrentQueue,
        '${ServiceRoutes.qbittorrent}/${ServiceTab.queue.segment}',
      );
      expect(
        ServiceRoutes.qbittorrentRss,
        '${ServiceRoutes.qbittorrent}/${ServiceTab.rss.segment}',
      );
    });

    test('the torrent detail hangs off the Queue tab', () {
      // It used to be `/dashboard/qbittorrent/torrent/<hash>`, a sibling of
      // nothing. Every link to a torrent in the app is built by this helper —
      // the list row and the Dashboard's activity readout — so this constant is
      // what moved them all inside the branch at once.
      expect(
        ServiceRoutes.qbittorrentTorrentBase,
        startsWith('${ServiceRoutes.qbittorrentQueue}/'),
      );
      expect(
        ServiceRoutes.qbittorrentTorrent('abc123'),
        '/dashboard/qbittorrent/queue/torrent/abc123',
      );
    });

    test('the Transmission tab roots are spelled by the tabs they mount', () {
      // Four literals, and no detail constant under any of them: the torrent
      // list expands rows in place, so Queue is a leaf and there has never been
      // a page to push from it.
      expect(
        ServiceRoutes.transmissionOverview,
        '${ServiceRoutes.transmission}/${ServiceTab.overview.segment}',
      );
      expect(
        ServiceRoutes.transmissionQueue,
        '${ServiceRoutes.transmission}/${ServiceTab.queue.segment}',
      );
      expect(
        ServiceRoutes.transmissionLabels,
        '${ServiceRoutes.transmission}/${ServiceTab.labels.segment}',
      );
      expect(
        ServiceRoutes.transmissionSession,
        '${ServiceRoutes.transmission}/${ServiceTab.session.segment}',
      );
    });

    test('the SABnzbd tab roots are spelled by the tabs they mount', () {
      expect(
        ServiceRoutes.sabnzbdOverview,
        '${ServiceRoutes.sabnzbd}/${ServiceTab.overview.segment}',
      );
      expect(
        ServiceRoutes.sabnzbdQueue,
        '${ServiceRoutes.sabnzbd}/${ServiceTab.queue.segment}',
      );
      expect(
        ServiceRoutes.sabnzbdHistory,
        '${ServiceRoutes.sabnzbd}/${ServiceTab.history.segment}',
      );
      expect(
        ServiceRoutes.sabnzbdServers,
        '${ServiceRoutes.sabnzbd}/${ServiceTab.servers.segment}',
      );
    });

    test('the NZBGet tab roots are spelled by the tabs they mount', () {
      // Five, the widest bar of the four download clients, and the one where a
      // hand-kept list is most likely to drift from the table that draws it.
      expect(
        ServiceRoutes.nzbgetOverview,
        '${ServiceRoutes.nzbget}/${ServiceTab.overview.segment}',
      );
      expect(
        ServiceRoutes.nzbgetQueue,
        '${ServiceRoutes.nzbget}/${ServiceTab.queue.segment}',
      );
      expect(
        ServiceRoutes.nzbgetHistory,
        '${ServiceRoutes.nzbget}/${ServiceTab.history.segment}',
      );
      expect(
        ServiceRoutes.nzbgetFeeds,
        '${ServiceRoutes.nzbget}/${ServiceTab.feeds.segment}',
      );
      expect(
        ServiceRoutes.nzbgetMessages,
        '${ServiceRoutes.nzbget}/${ServiceTab.messages.segment}',
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
