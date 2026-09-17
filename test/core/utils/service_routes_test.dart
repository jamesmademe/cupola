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

    test('the Seerr tab roots are spelled by the tabs they mount', () {
      // The same tie the four \*arr and the four download clients carry, and it
      // has to be its own case for the same reason: these are `const` literals
      // precisely because an enum instance's field is not a compile-time
      // constant, so there is nothing to iterate that would not defeat the
      // point.
      expect(
        ServiceRoutes.seerrOverview,
        '${ServiceRoutes.seerr}/${ServiceTab.overview.segment}',
      );
      expect(
        ServiceRoutes.seerrRequests,
        '${ServiceRoutes.seerr}/${ServiceTab.requests.segment}',
      );
      expect(
        ServiceRoutes.seerrIssues,
        '${ServiceRoutes.seerr}/${ServiceTab.issues.segment}',
      );
      expect(
        ServiceRoutes.seerrDiscover,
        '${ServiceRoutes.seerr}/${ServiceTab.discover.segment}',
      );
      expect(
        ServiceRoutes.seerrUsers,
        '${ServiceRoutes.seerr}/${ServiceTab.users.segment}',
      );
      // Requests did not move, and that is the assertion: the all-requests list
      // was already at this address as a pushed page, so every link that ever
      // pointed at it still resolves — now to a tab.
      expect(ServiceRoutes.seerrRequests, '/dashboard/seerr/requests');
    });

    test('every Seerr see-all and detail hangs off the Discover tab', () {
      // Eight link shapes moved at once, and they moved because one constant
      // each says so: nothing in the app builds a Seerr path by hand. A drift
      // here silently retargets every poster tap in Discover.
      for (final base in [
        ServiceRoutes.seerrMoviesAll,
        ServiceRoutes.seerrTvAll,
        ServiceRoutes.seerrTrendingAll,
        ServiceRoutes.seerrGenreBase,
        ServiceRoutes.seerrPersonBase,
        ServiceRoutes.seerrCollectionBase,
      ]) {
        expect(base, startsWith('${ServiceRoutes.seerrDiscover}/'));
      }
      expect(
        ServiceRoutes.seerrDetail(mediaType: 'movie', id: 7),
        startsWith('${ServiceRoutes.seerrDiscover}/'),
      );
      expect(
        ServiceRoutes.seerrPerson(287),
        '/dashboard/seerr/discover/person/287',
      );
      expect(
        ServiceRoutes.seerrCollection(10),
        '/dashboard/seerr/discover/collection/10',
      );
      expect(
        ServiceRoutes.seerrGenre(mediaType: 'tv', genreId: 28, title: 'Action'),
        '/dashboard/seerr/discover/genre/tv/28?title=Action',
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
        '/dashboard/seerr/discover/tv/123?heroTag=hero+tag&posterUrl=https%3A%2F%2Fimage.tmdb.org%2Ft%2Fp%2Fw500%2Fa%2Fb.jpg',
      );
    });

    test('normalizes non-tv Seerr media types to movie', () {
      expect(
        ServiceRoutes.seerrDetail(mediaType: 'movie', id: 1),
        '/dashboard/seerr/discover/movie/1',
      );
      expect(
        ServiceRoutes.seerrDetail(mediaType: 'person', id: 1),
        '/dashboard/seerr/discover/movie/1',
      );
    });

    test('exposes the Bazarr service root', () {
      expect(ServiceRoutes.bazarr, '/dashboard/bazarr');
    });

    test('the Bazarr tab roots are spelled by the tabs they mount', () {
      // Six literals, the widest bar in the app, tied one by one for the reason
      // every other service's are: an enum instance's field is not a
      // compile-time constant, so nothing the analyzer sees holds these to the
      // table that draws them.
      expect(
        ServiceRoutes.bazarrOverview,
        '${ServiceRoutes.bazarr}/${ServiceTab.overview.segment}',
      );
      expect(
        ServiceRoutes.bazarrWanted,
        '${ServiceRoutes.bazarr}/${ServiceTab.wanted.segment}',
      );
      expect(
        ServiceRoutes.bazarrSeriesBase,
        '${ServiceRoutes.bazarr}/${ServiceTab.series.segment}',
      );
      expect(
        ServiceRoutes.bazarrMovieBase,
        '${ServiceRoutes.bazarr}/${ServiceTab.movies.segment}',
      );
      expect(
        ServiceRoutes.bazarrHistory,
        '${ServiceRoutes.bazarr}/${ServiceTab.history.segment}',
      );
      expect(
        ServiceRoutes.bazarrProviders,
        '${ServiceRoutes.bazarr}/${ServiceTab.providers.segment}',
      );
    });

    test('the Bazarr details hang off the tabs that own them', () {
      // Bazarr is the one service whose bar names the record types, so the
      // detail is `<tab>/:id` rather than `<tab>/<record>/:id`. The series link
      // is byte-for-byte what it always was; the film's moved from the singular
      // `movie/`, and every link to one in the app is built here.
      expect(ServiceRoutes.bazarrSeries(7), '/dashboard/bazarr/series/7');
      expect(
        ServiceRoutes.bazarrSeries(7, heroTag: 'ignored'),
        '/dashboard/bazarr/series/7?heroTag=ignored',
      );
      expect(ServiceRoutes.bazarrMovie(12), '/dashboard/bazarr/movies/12');
    });

    test('the Prowlarr tab roots are spelled by the tabs they mount', () {
      // `library` became `indexers` — the word the bar uses and the word the
      // page always meant. The literal is tied to the tab here because nothing
      // the analyzer sees ties them.
      expect(ServiceRoutes.prowlarr, '/dashboard/prowlarr');
      expect(
        ServiceRoutes.prowlarrOverview,
        '${ServiceRoutes.prowlarr}/${ServiceTab.overview.segment}',
      );
      expect(
        ServiceRoutes.prowlarrIndexers,
        '${ServiceRoutes.prowlarr}/${ServiceTab.indexers.segment}',
      );
      expect(
        ServiceRoutes.prowlarrHistory,
        '${ServiceRoutes.prowlarr}/${ServiceTab.history.segment}',
      );
      expect(
        ServiceRoutes.prowlarrStats,
        '${ServiceRoutes.prowlarr}/${ServiceTab.stats.segment}',
      );
    });

    test('the indexer detail hangs off the Indexers tab', () {
      // Every link to an indexer in the app is built by this helper, so this
      // constant is what moved them all inside the branch at once.
      expect(
        ServiceRoutes.prowlarrIndexerBase,
        startsWith('${ServiceRoutes.prowlarrIndexers}/'),
      );
      expect(
        ServiceRoutes.prowlarrIndexer(3),
        '/dashboard/prowlarr/indexers/indexer/3',
      );
    });

    test('the Jellyfin tab roots are spelled by the tabs they mount', () {
      // Six literals tied to the six tabs the bar draws. Jellyfin and Plex
      // share a screen family and not a bar, so the two services need two
      // cases: a loop over both would assert a shape that is only accidentally
      // the same and would keep passing if one bar changed.
      expect(
        ServiceRoutes.jellyfinOverview,
        '${ServiceRoutes.jellyfin}/${ServiceTab.overview.segment}',
      );
      expect(
        ServiceRoutes.jellyfinLibraries,
        '${ServiceRoutes.jellyfin}/${ServiceTab.libraries.segment}',
      );
      expect(
        ServiceRoutes.jellyfinUsers,
        '${ServiceRoutes.jellyfin}/${ServiceTab.users.segment}',
      );
      expect(
        ServiceRoutes.jellyfinDevices,
        '${ServiceRoutes.jellyfin}/${ServiceTab.devices.segment}',
      );
      expect(
        ServiceRoutes.jellyfinTasks,
        '${ServiceRoutes.jellyfin}/${ServiceTab.tasks.segment}',
      );
      expect(
        ServiceRoutes.jellyfinActivity,
        '${ServiceRoutes.jellyfin}/${ServiceTab.activity.segment}',
      );
    });

    test('the Plex tab roots are spelled by the tabs they mount', () {
      expect(
        ServiceRoutes.plexOverview,
        '${ServiceRoutes.plex}/${ServiceTab.overview.segment}',
      );
      expect(
        ServiceRoutes.plexLibraries,
        '${ServiceRoutes.plex}/${ServiceTab.libraries.segment}',
      );
      // The one tab segment that is not simply its enum name: Plex writes it
      // "On Deck", so the URL is hyphenated rather than camel-cased away.
      expect(ServiceRoutes.plexOnDeck, '/dashboard/plex/on-deck');
      expect(
        ServiceRoutes.plexOnDeck,
        '${ServiceRoutes.plex}/${ServiceTab.onDeck.segment}',
      );
      expect(
        ServiceRoutes.plexActivities,
        '${ServiceRoutes.plex}/${ServiceTab.activities.segment}',
      );
      expect(
        ServiceRoutes.plexDevices,
        '${ServiceRoutes.plex}/${ServiceTab.devices.segment}',
      );
      expect(
        ServiceRoutes.plexPlaylists,
        '${ServiceRoutes.plex}/${ServiceTab.playlists.segment}',
      );
    });

    test('both media server details hang off the Libraries tab', () {
      // Every link to a library or an item is built by these four helpers — the
      // library row, the poster tile, the global search result and the
      // availability slot on a Radarr or Sonarr detail — so these constants are
      // what moved them all inside the branch at once. The browse's own base
      // *is* the tab root, the way Bazarr's Series tab is also its series base.
      expect(
        ServiceRoutes.jellyfinLibrary('f137a2dd'),
        '/dashboard/jellyfin/libraries/f137a2dd',
      );
      expect(
        ServiceRoutes.jellyfinLibrary('f137a2dd', title: 'Films'),
        '/dashboard/jellyfin/libraries/f137a2dd?title=Films',
      );
      expect(
        ServiceRoutes.jellyfinItemBase,
        startsWith('${ServiceRoutes.jellyfinLibraries}/'),
      );
      expect(
        ServiceRoutes.jellyfinItem('abc-123'),
        '/dashboard/jellyfin/libraries/item/abc-123',
      );

      expect(
        ServiceRoutes.plexLibrary('3', title: 'TV Shows'),
        '/dashboard/plex/libraries/3?title=TV+Shows',
      );
      expect(
        ServiceRoutes.plexItemBase,
        startsWith('${ServiceRoutes.plexLibraries}/'),
      );
      expect(
        ServiceRoutes.plexItem('9421'),
        '/dashboard/plex/libraries/item/9421',
      );
    });

    test('the Dockge tab roots are spelled by the tabs they mount', () {
      // The same tie every other service carries, and it has to be its own
      // case for the same reason: these are `const` literals precisely because
      // an enum instance's field is not a compile-time constant, so there is
      // nothing to iterate that would not defeat the point.
      expect(
        ServiceRoutes.dockgeOverview,
        '${ServiceRoutes.dockge}/${ServiceTab.overview.segment}',
      );
      expect(
        ServiceRoutes.dockgeStacks,
        '${ServiceRoutes.dockge}/${ServiceTab.stacks.segment}',
      );
      expect(
        ServiceRoutes.dockgeTerminal,
        '${ServiceRoutes.dockge}/${ServiceTab.terminal.segment}',
      );
    });

    test('the whole stack tree hangs off the Stacks tab', () {
      // Three routes that used to hang off the service root, because a
      // one-page service had nowhere else to hang them. All three are reached
      // from the Stacks list and nowhere else, so a drift here moves every
      // stack link in the app out of the branch that owns it.
      expect(
        ServiceRoutes.dockgeStackBase,
        startsWith('${ServiceRoutes.dockgeStacks}/'),
      );
      expect(
        ServiceRoutes.dockgeStack('immich'),
        '/dashboard/dockge/stacks/stack/immich',
      );
      expect(
        ServiceRoutes.dockgeStackEdit('immich'),
        '/dashboard/dockge/stacks/stack/immich/edit',
      );
      expect(ServiceRoutes.dockgeNewStack, '${ServiceRoutes.dockgeStacks}/new');
    });

    test('the Unraid tab roots are spelled by the tabs they mount', () {
      // Six, and not one of them moved: the service shipped exactly one path —
      // its bare root — so this table is the whole of Unraid's URL surface.
      expect(
        ServiceRoutes.unraidOverview,
        '${ServiceRoutes.unraid}/${ServiceTab.overview.segment}',
      );
      expect(
        ServiceRoutes.unraidArray,
        '${ServiceRoutes.unraid}/${ServiceTab.array.segment}',
      );
      expect(
        ServiceRoutes.unraidDocker,
        '${ServiceRoutes.unraid}/${ServiceTab.docker.segment}',
      );
      expect(
        ServiceRoutes.unraidVms,
        '${ServiceRoutes.unraid}/${ServiceTab.vms.segment}',
      );
      expect(
        ServiceRoutes.unraidNotifications,
        '${ServiceRoutes.unraid}/${ServiceTab.notifications.segment}',
      );
      expect(
        ServiceRoutes.unraidShares,
        '${ServiceRoutes.unraid}/${ServiceTab.shares.segment}',
      );
      // `vms` and not `vMs`: the segment is the tab's, and the breadcrumb that
      // title-cased whatever it found is exactly what `ServiceTab` exists to
      // stop.
      expect(ServiceRoutes.unraidVms, '/dashboard/unraid/vms');
    });

    test('the NPM tab roots are spelled by the tabs they mount', () {
      // Five, three of them hyphenated where the label has a space. The
      // spelling is `ServiceTab.segment`'s and not one invented here, which is
      // the half of this case that a hand-written literal can silently lose:
      // `proxyHosts` would resolve to nothing and read as a 404 on a tab the
      // bar still draws.
      expect(
        ServiceRoutes.npmOverview,
        '${ServiceRoutes.nginxProxyManager}/${ServiceTab.overview.segment}',
      );
      expect(
        ServiceRoutes.npmProxyHosts,
        '${ServiceRoutes.nginxProxyManager}/${ServiceTab.proxyHosts.segment}',
      );
      expect(
        ServiceRoutes.npmCertificates,
        '${ServiceRoutes.nginxProxyManager}/${ServiceTab.certificates.segment}',
      );
      expect(
        ServiceRoutes.npmAccessLists,
        '${ServiceRoutes.nginxProxyManager}/${ServiceTab.accessLists.segment}',
      );
      expect(
        ServiceRoutes.npmAuditLog,
        '${ServiceRoutes.nginxProxyManager}/${ServiceTab.auditLog.segment}',
      );
      // Written out once, because two irregularities meet here: the service
      // segment is `npm` rather than the enum name, and three tab segments are
      // hyphenated.
      expect(ServiceRoutes.npmProxyHosts, '/dashboard/npm/proxy-hosts');
      expect(ServiceRoutes.npmAccessLists, '/dashboard/npm/access-lists');
      expect(ServiceRoutes.npmAuditLog, '/dashboard/npm/audit-log');
    });

    test('every tab of the three infrastructure services has a constant', () {
      // The other half of the tie above: those cases prove each constant is
      // spelled by a tab, this one proves no tab was left without one. A bar
      // entry with no route constant is a link nobody can build.
      const routes = {
        ServiceKey.dockge: [
          ServiceRoutes.dockgeOverview,
          ServiceRoutes.dockgeStacks,
          ServiceRoutes.dockgeTerminal,
        ],
        ServiceKey.unraid: [
          ServiceRoutes.unraidOverview,
          ServiceRoutes.unraidArray,
          ServiceRoutes.unraidDocker,
          ServiceRoutes.unraidVms,
          ServiceRoutes.unraidNotifications,
          ServiceRoutes.unraidShares,
        ],
        ServiceKey.nginxProxyManager: [
          ServiceRoutes.npmOverview,
          ServiceRoutes.npmProxyHosts,
          ServiceRoutes.npmCertificates,
          ServiceRoutes.npmAccessLists,
          ServiceRoutes.npmAuditLog,
        ],
      };

      for (final entry in routes.entries) {
        final tabs = tabsFor(entry.key)!;
        expect(entry.value, hasLength(tabs.length), reason: entry.key.name);
        for (var i = 0; i < tabs.length; i++) {
          expect(
            entry.value[i],
            '${ServiceRoutes.forService(entry.key)}/${tabs[i].segment}',
            reason: '${entry.key.name} tab ${tabs[i].name}',
          );
        }
      }
    });

    test('Prowlarr settings is not a tab and did not move', () {
      // Decision 26: the four field-driven sections are one page, not a fifth
      // bar entry. It stays a page pushed from the service, at the address it
      // always had, so every link into it still resolves.
      expect(ServiceRoutes.prowlarrSettings, '/dashboard/prowlarr/settings');
      expect(
        ServiceTab.fromSegment('settings'),
        isNull,
        reason: 'settings must not become a tab segment by accident',
      );
    });
  });
}
