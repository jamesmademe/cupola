import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/router.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/presentation/discover_detail_screen.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/movies/presentation/movie_detail_screen.dart';
import 'package:cupola/features/movies/presentation/movies_screen.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/music/presentation/music_detail_screen.dart';
import 'package:cupola/features/onboarding/data/onboarding_provider.dart';
import 'package:cupola/features/prowlarr/data/prowlarr_service.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_provider.dart';
import 'package:cupola/features/onboarding/presentation/onboarding_screen.dart';
import 'package:cupola/features/search/presentation/search_screen.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/series/presentation/series_detail_screen.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/services/presentation/service_all_screens.dart';
import 'package:cupola/features/services/presentation/dashboard_screen.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/settings/presentation/settings_appearance_screen.dart';
import 'package:cupola/features/settings/presentation/settings_connections_screen.dart';
import 'package:cupola/features/settings/presentation/service_settings_screen.dart';

import '../test_helpers/fake_api_client.dart';
import '../test_helpers/fake_services.dart';
import '../test_helpers/model_builders.dart';

void main() {
  group('routerProvider', () {
    testWidgets('starts on services', (tester) async {
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      expect(router.state.uri.toString(), '/dashboard');
      expect(find.byType(DashboardScreen), findsOneWidget);
    });

    testWidgets('starts on onboarding when onboarding is incomplete', (
      tester,
    ) async {
      final container = await _pumpRouter(tester, onboardingCompleted: false);
      final router = container.read(routerProvider);

      expect(router.state.uri.toString(), '/onboarding');
      expect(find.byType(OnboardingScreen), findsOneWidget);
    });

    testWidgets(
      'redirects protected routes to onboarding when onboarding is incomplete',
      (tester) async {
        final container = await _pumpRouter(tester, onboardingCompleted: false);
        final router = container.read(routerProvider);

        router.go('/search');
        await tester.pumpAndSettle();

        expect(router.state.uri.toString(), '/onboarding');
        expect(find.byType(OnboardingScreen), findsOneWidget);
        expect(find.byType(SearchScreen), findsNothing);
      },
    );

    testWidgets('redirects to services when onboarding completes', (
      tester,
    ) async {
      final container = await _pumpRouter(tester, onboardingCompleted: false);
      final router = container.read(routerProvider);

      container.read(onboardingCompletedProvider.notifier).state = true;
      await tester.pumpAndSettle();

      expect(router.state.uri.toString(), '/dashboard');
      expect(find.byType(DashboardScreen), findsOneWidget);
      expect(find.byType(OnboardingScreen), findsNothing);
    });

    testWidgets('redirects invalid discover detail ids back to Discover', (
      tester,
    ) async {
      // Two hops now, and both are the point: the pre-tab spelling rewrites to
      // the detail inside the Discover branch, and *that* route rejects the id.
      // It falls back to the tab the page would have been pushed from rather
      // than to the app home — the branch is where the user still is, and
      // sending them out of the service is a bigger move than the mistake.
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      router.go('/dashboard/seerr/movie/not-a-number');
      await tester.pumpAndSettle();

      expect(router.state.uri.toString(), ServiceRoutes.seerrDiscover);
      expect(find.byType(DiscoverDetailScreen), findsNothing);
    });

    testWidgets(
      'preserves discover detail default hero tag and posterUrl decoding',
      (tester) async {
        final container = await _pumpRouter(tester);
        final router = container.read(routerProvider);
        const encodedPosterUrl =
            'https%3A%2F%2Fcdn.example.com%2Fposter%20image.jpg';

        router.go(
          '/dashboard/seerr/discover/movie/123?posterUrl=$encodedPosterUrl',
        );
        await tester.pumpAndSettle();

        final screen = tester.widget<DiscoverDetailScreen>(
          find.byType(DiscoverDetailScreen),
        );

        expect(
          router.state.uri.toString(),
          '/dashboard/seerr/discover/movie/123?posterUrl=$encodedPosterUrl',
        );
        expect(screen.mediaId, 123);
        expect(screen.mediaType, 'movie');
        expect(screen.heroTag, 'discover_movie_123');
        expect(
          screen.initialPosterUrl,
          'https://cdn.example.com/poster image.jpg',
        );
      },
    );

    testWidgets(
      'supports deep-linked library detail routes without extras and preserves default hero tags',
      (tester) async {
        final container = await _pumpRouter(tester);
        final router = container.read(routerProvider);

        router.go('/dashboard/radarr/movie/42');
        await tester.pumpAndSettle();

        final movieScreen = tester.widget<MovieDetailScreen>(
          find.byType(MovieDetailScreen),
        );
        expect(movieScreen.heroTag, 'movie_42');
        expect(movieScreen.movieId, 42);
        expect(movieScreen.initialMovie, isNull);

        router.go('${ServiceRoutes.sonarrSeriesBase}/55');
        await tester.pumpAndSettle();

        final seriesScreen = tester.widget<SeriesDetailScreen>(
          find.byType(SeriesDetailScreen),
        );
        expect(seriesScreen.heroTag, 'series_55');
        expect(seriesScreen.seriesId, 55);
        expect(seriesScreen.initialSeries, isNull);

        router.go('${ServiceRoutes.lidarrArtistBase}/9');
        await tester.pumpAndSettle();

        final musicScreen = tester.widget<MusicDetailScreen>(
          find.byType(MusicDetailScreen),
        );
        expect(musicScreen.heroTag, 'artist_9');
        expect(musicScreen.artistId, 9);
        expect(musicScreen.initialArtist, isNull);
      },
    );

    testWidgets('redirects invalid library detail ids back to the library', (
      tester,
    ) async {
      // The fallback moved with the film. A bad id used to drop the user at
      // the app home, which was the only place a detail route could name
      // before it had a tab around it; now the film is a page inside Library,
      // so the nearest place that exists is the list it was pushed from.
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      router.go(
        '/dashboard/radarr/movie/not-a-number',
        extra: buildMovie(id: 42),
      );
      await tester.pumpAndSettle();

      expect(router.state.uri.toString(), ServiceRoutes.radarrLibrary);
      expect(find.byType(MoviesScreen), findsOneWidget);
      expect(find.byType(MovieDetailScreen), findsNothing);
    });

    testWidgets(
      'library detail routes ignore wrong-type and mismatched extras instead of redirecting',
      (tester) async {
        final container = await _pumpRouter(tester);
        final router = container.read(routerProvider);

        // Aimed at the canonical path — the one `ServiceRoutes.radarrMovie`
        // builds and every in-app caller emits — rather than at the pre-tab
        // `radarr/movie/:id` tail. That tail still resolves, but only by
        // redirecting, and go_router re-matches a redirect with
        // `findMatch(uri)` and no extra: the preload would arrive as null and
        // the second half of this case would assert nothing.
        router.go(ServiceRoutes.radarrMovie(42), extra: buildArtist(id: 9));
        await tester.pumpAndSettle();

        expect(router.state.uri.toString(), ServiceRoutes.radarrMovie(42));
        var movieScreen = tester.widget<MovieDetailScreen>(
          find.byType(MovieDetailScreen),
        );
        expect(movieScreen.movieId, 42);
        expect(movieScreen.initialMovie, isNull);

        router.go(ServiceRoutes.radarrMovie(42), extra: buildMovie(id: 7));
        await tester.pumpAndSettle();

        expect(router.state.uri.toString(), ServiceRoutes.radarrMovie(42));
        movieScreen = tester.widget<MovieDetailScreen>(
          find.byType(MovieDetailScreen),
        );
        expect(movieScreen.movieId, 42);
        expect(movieScreen.initialMovie?.id, 7);
      },
    );

    testWidgets('unknown service settings routes fall back to seerr', (
      tester,
    ) async {
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      router.go('/settings/service/not-a-service');
      await tester.pumpAndSettle();

      final screen = tester.widget<ServiceSettingsScreen>(
        find.byType(ServiceSettingsScreen),
      );

      expect(screen.service, ServiceKey.seerr);
      // The page prints the service's name alone: "Seerr Settings" is the name
      // of Seerr's own configuration, which is a different page from the form
      // that tells Cupola how to reach it.
      expect(find.text(ServiceKey.seerr.title), findsWidgets);
    });

    testWidgets('supports appearance and connections settings subroutes', (
      tester,
    ) async {
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      router.go('/settings/appearance');
      await tester.pumpAndSettle();

      expect(find.byType(SettingsAppearanceScreen), findsOneWidget);

      router.go('/settings/connections');
      await tester.pumpAndSettle();

      expect(find.byType(SettingsConnectionsScreen), findsOneWidget);
    });

    testWidgets('the old services settings path redirects to connections', (
      tester,
    ) async {
      // '/settings/services' was the route before the two service lists were
      // merged; a saved deep link should land on the screen that replaced it
      // rather than 404.
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      router.go('/settings/services');
      await tester.pumpAndSettle();

      expect(find.byType(SettingsConnectionsScreen), findsOneWidget);
      expect(router.state.uri.toString(), '/settings/connections');
    });

    testWidgets('supports global search route', (tester) async {
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      router.go('/search');
      await tester.pumpAndSettle();

      expect(router.state.uri.toString(), '/search');
      expect(find.byType(SearchScreen), findsOneWidget);
    });

    testWidgets('supports service dashboard routes', (tester) async {
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      // A service on the tab model has a redirect-only prefix for a root: the
      // service home is a tab now, so the bare path names a place that draws
      // nothing and hands off to Overview.
      for (final entry in {
        ServiceRoutes.seerr: ServiceRoutes.seerrOverview,
        ServiceRoutes.radarr: ServiceRoutes.radarrOverview,
        ServiceRoutes.sonarr: ServiceRoutes.sonarrOverview,
        ServiceRoutes.lidarr: ServiceRoutes.lidarrOverview,
        ServiceRoutes.readarr: ServiceRoutes.readarrOverview,
        ServiceRoutes.qbittorrent: ServiceRoutes.qbittorrentOverview,
        ServiceRoutes.transmission: ServiceRoutes.transmissionOverview,
        ServiceRoutes.sabnzbd: ServiceRoutes.sabnzbdOverview,
        ServiceRoutes.nzbget: ServiceRoutes.nzbgetOverview,
      }.entries) {
        router.go(entry.key);
        await tester.pumpAndSettle();

        expect(router.state.uri.toString(), entry.value, reason: entry.key);
      }
    });

    testWidgets('every tab on an arr\'s bar resolves to its own location', (
      tester,
    ) async {
      // The bar draws one label per entry in `tabsFor`, so a tab the table
      // names with no branch behind it would 404 on tap rather than fail
      // anywhere a reader would look. Three of the four are faked by this
      // harness; the fourth, Readarr, needs no fake because every one of its
      // tabs checks `isServiceConfigured` before it reads anything — an
      // unconfigured service is answered without a request, so there is no
      // retry timer to leave pending.
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      for (final service in [
        ServiceKey.radarr,
        ServiceKey.sonarr,
        ServiceKey.lidarr,
        ServiceKey.readarr,
      ]) {
        for (final tab in tabsFor(service)!) {
          final location = '/dashboard/${service.routeParam}/${tab.segment}';
          router.go(location);
          await tester.pumpAndSettle();

          expect(
            router.state.uri.toString(),
            location,
            reason: '${service.name}.${tab.name}',
          );
        }
      }
    });

    testWidgets('every tab on Seerr\'s bar resolves to its own location', (
      tester,
    ) async {
      // The bar draws one label per entry in `tabsFor`, so a tab the table
      // names with no branch behind it would 404 on tap rather than fail
      // anywhere a reader would look. Seerr is faked by this harness, so
      // Overview, Requests and Discover all reach a service; Issues and Users
      // answer without a request.
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      for (final tab in tabsFor(ServiceKey.seerr)!) {
        final location = '/dashboard/seerr/${tab.segment}';
        router.go(location);
        await tester.pumpAndSettle();

        expect(router.state.uri.toString(), location, reason: tab.name);
      }
    });

    testWidgets('every pre-tab Seerr path still resolves', (tester) async {
      // Seerr shipped more link shapes than any other service, all of them
      // hanging off the service root because the service root *was* Discover.
      // Every one of them moved under the Discover tab, so every one needs a
      // tail — and the two `.../all` literals need to be matched before the
      // `:id` details, or `/dashboard/seerr/tv/all` becomes a media detail
      // whose id is the word `all`. Both spellings of the prefix, because the
      // `/services` rewrite chains into these rather than duplicating them.
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      for (final prefix in ['/dashboard/seerr', '/services/seerr']) {
        for (final entry in {
          '': ServiceRoutes.seerrOverview,
          '/requests': ServiceRoutes.seerrRequests,
          '/movies/all': ServiceRoutes.seerrMoviesAll,
          '/tv/all': ServiceRoutes.seerrTvAll,
          '/trending/all': ServiceRoutes.seerrTrendingAll,
          '/genre/tv/28?title=Action': ServiceRoutes.seerrGenre(
            mediaType: 'tv',
            genreId: 28,
            title: 'Action',
          ),
          '/movie/42': '${ServiceRoutes.seerrDiscover}/movie/42',
          '/tv/55': '${ServiceRoutes.seerrDiscover}/tv/55',
          '/person/287?heroTag=cast_287': ServiceRoutes.seerrPerson(
            287,
            heroTag: 'cast_287',
          ),
          '/collection/10': ServiceRoutes.seerrCollection(10),
        }.entries) {
          final from = '$prefix${entry.key}';
          router.go(from);
          await tester.pumpAndSettle();

          expect(router.state.uri.toString(), entry.value, reason: from);
        }
      }
    });

    testWidgets(
      'every tab on a download client\'s bar resolves to its own location',
      (tester) async {
        // The same rule the \*arr case asserts, on the services whose bars do
        // not match each other: qBittorrent has RSS where Transmission has
        // Labels and Session, so there is no shared list and every one of them
        // has to be walked.
        //
        // No fakes: every tab of these services answers an unconfigured
        // connection without a request — the placeholder asks
        // `isServiceConfigured` first and the queues gate on it too — so there
        // is no retry timer left pending by the time the case ends.
        final container = await _pumpRouter(tester);
        final router = container.read(routerProvider);

        for (final service in [
          ServiceKey.qbittorrent,
          ServiceKey.transmission,
          ServiceKey.sabnzbd,
          ServiceKey.nzbget,
        ]) {
          for (final tab in tabsFor(service)!) {
            final location = '/dashboard/${service.routeParam}/${tab.segment}';
            router.go(location);
            await tester.pumpAndSettle();

            expect(
              router.state.uri.toString(),
              location,
              reason: '${service.name}.${tab.name}',
            );
          }
        }
      },
    );

    testWidgets('every tab on Bazarr\'s bar resolves to its own location', (
      tester,
    ) async {
      // Six tabs, the widest bar in the app. No fake: every Bazarr surface
      // checks `isServiceConfigured` before it reads anything, so an
      // unconfigured connection is answered without a request and there is no
      // retry timer left pending.
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      for (final tab in tabsFor(ServiceKey.bazarr)!) {
        final location = '/dashboard/bazarr/${tab.segment}';
        router.go(location);
        await tester.pumpAndSettle();

        expect(router.state.uri.toString(), location, reason: tab.name);
      }
    });

    testWidgets('every pre-tab Bazarr path still resolves', (tester) async {
      // Three shapes moved and one did not, which is the whole point of the
      // table: `library` was the combined Series/Movies page and lands on
      // Series, the singular `movie/:id` lands on the film inside Movies, and
      // `series/:id` is unchanged because the Series tab's root IS its base.
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      for (final prefix in ['/dashboard/bazarr', '/services/bazarr']) {
        for (final entry in {
          '': ServiceRoutes.bazarrOverview,
          '/library': ServiceRoutes.bazarrSeriesBase,
          '/wanted': ServiceRoutes.bazarrWanted,
          '/series/7': ServiceRoutes.bazarrSeries(7),
          '/movie/12': ServiceRoutes.bazarrMovie(12),
        }.entries) {
          final from = '$prefix${entry.key}';
          router.go(from);
          await tester.pumpAndSettle();

          expect(router.state.uri.toString(), entry.value, reason: from);
        }
      }
    });

    testWidgets('every tab on Prowlarr\'s bar resolves to its own location', (
      tester,
    ) async {
      // No fake: every Prowlarr surface checks `isServiceConfigured` before it
      // reads anything, so an unconfigured connection is answered without a
      // request and there is no retry timer left pending.
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      for (final tab in tabsFor(ServiceKey.prowlarr)!) {
        final location = '/dashboard/prowlarr/${tab.segment}';
        router.go(location);
        await tester.pumpAndSettle();

        expect(router.state.uri.toString(), location, reason: tab.name);
      }
    });

    testWidgets('every pre-tab Prowlarr path still resolves', (tester) async {
      // Settings is in this table for the opposite reason to the others: it is
      // NOT a tab (decision 26) and must not have moved. It hangs off the
      // service node beside the shell, so a link into any of its sections has
      // to keep landing exactly where it did.
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      for (final prefix in ['/dashboard/prowlarr', '/services/prowlarr']) {
        for (final entry in {
          '': ServiceRoutes.prowlarrOverview,
          '/library': ServiceRoutes.prowlarrIndexers,
          '/indexer/3': ServiceRoutes.prowlarrIndexer(3),
          '/settings': ServiceRoutes.prowlarrSettings,
          '/settings/tags': ServiceRoutes.prowlarrTags,
          '/settings/sync-profiles': ServiceRoutes.prowlarrSyncProfiles,
        }.entries) {
          final from = '$prefix${entry.key}';
          router.go(from);
          await tester.pumpAndSettle();

          expect(router.state.uri.toString(), entry.value, reason: from);
        }
      }
    });

    testWidgets('the pre-tab download client paths still resolve', (
      tester,
    ) async {
      // Every path shape these services ever shipped, in both spellings: the
      // bare root, the tab-less detail, and the same two under the pre-rename
      // `/services` prefix. The prefix rewrite chains into the per-service
      // redirects rather than duplicating them, so what this asserts is that
      // the chain finishes — a rewrite that stopped at the first hop would
      // leave the user on a path that draws nothing.
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      for (final entry in {
        ServiceRoutes.qbittorrent: ServiceRoutes.qbittorrentOverview,
        '/services/qbittorrent': ServiceRoutes.qbittorrentOverview,
        '/dashboard/qbittorrent/torrent/abc123':
            ServiceRoutes.qbittorrentTorrent('abc123'),
        '/services/qbittorrent/torrent/abc123':
            ServiceRoutes.qbittorrentTorrent('abc123'),
        // Transmission carries only its root, in both spellings: it never had
        // a detail path to keep resolving.
        ServiceRoutes.transmission: ServiceRoutes.transmissionOverview,
        '/services/transmission': ServiceRoutes.transmissionOverview,
        // SABnzbd likewise: a job is an expanding row, never a pushed page.
        ServiceRoutes.sabnzbd: ServiceRoutes.sabnzbdOverview,
        '/services/sabnzbd': ServiceRoutes.sabnzbdOverview,
        // NZBGet, the same: a group is an expanding row, never a pushed page.
        ServiceRoutes.nzbget: ServiceRoutes.nzbgetOverview,
        '/services/nzbget': ServiceRoutes.nzbgetOverview,
      }.entries) {
        router.go(entry.key);
        await tester.pumpAndSettle();

        expect(router.state.uri.toString(), entry.value, reason: entry.key);
      }
    });

    testWidgets('supports service all-list routes', (tester) async {
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      router.go('/dashboard/seerr/requests');
      await tester.pumpAndSettle();

      expect(router.state.uri.toString(), '/dashboard/seerr/requests');
      expect(find.byType(ServiceAllRequestsScreen), findsOneWidget);

      // Readarr never had a `media` tail and does not grow one here: its
      // author list always lived at `library`, which is now the tab.
      // `media` was the all-list tail the other three arrs carried. On the tab model it
      // lands on the Library tab rather than on the service root, because the
      // whole library IS a tab now; a service still off the model has nowhere
      // but its root to go.
      for (final entry in {
        '/dashboard/radarr/media': ServiceRoutes.radarrLibrary,
        '/dashboard/sonarr/media': ServiceRoutes.sonarrLibrary,
        '/dashboard/lidarr/media': ServiceRoutes.lidarrLibrary,
      }.entries) {
        router.go(entry.key);
        await tester.pumpAndSettle();

        expect(router.state.uri.toString(), entry.value, reason: entry.key);
        expect(find.byType(ServiceAllRequestsScreen), findsNothing);
      }
    });

    testWidgets('every pre-rename /services path still resolves', (
      tester,
    ) async {
      // The rename moved thirty-four routes and every detail tail under them.
      // A bookmark, a restored session or a shared deep link from before it
      // must not 404, and the rewrite is a prefix swap rather than a shadow
      // copy of the tree — so what this asserts is that the swap reaches the
      // *descendants*, not just the root.
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      // Only services this harness fakes: an unfaked one leaves a provider
      // retry timer pending and the failure would be about the fixture rather
      // than about the rewrite.
      // `/services/radarr` takes two hops now: the prefix rewrite lands it on
      // `/dashboard/radarr`, which is redirect-only and hands off to Overview.
      // That chaining is the property — a rewrite that stopped at the first
      // hop would leave the user on a path that draws nothing.
      const cases = {
        '/services': '/dashboard',
        '/services/radarr': ServiceRoutes.radarrOverview,
        '/services/sonarr': ServiceRoutes.sonarrOverview,
        '/services/lidarr': ServiceRoutes.lidarrOverview,
        '/services/readarr': ServiceRoutes.readarrOverview,
        '/services/seerr/requests': '/dashboard/seerr/requests',
      };

      for (final entry in cases.entries) {
        router.go(entry.key);
        await tester.pumpAndSettle();
        expect(router.state.uri.toString(), entry.value, reason: entry.key);
      }
    });

    testWidgets('the legacy rewrite keeps the query, lens included', (
      tester,
    ) async {
      // The instance lens travels as `?i=`, so a rewrite that dropped the
      // query would silently retarget a deep link at whichever connection the
      // lens happens to point at — the one failure mode of this change that
      // moves a user's files rather than just their view.
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      // `heroTag` stands in for the lens here only because pointing `i=` at a
      // connection this harness does not define leaves a provider retrying;
      // the property under test is the whole query surviving the swap, and
      // that is what `i=` rides on in production.
      // Three hops, and the query survives all of them: the prefix rewrite,
      // then the pre-tab `radarr/movie/:id` tail, then the film inside the
      // Library branch where it lives now.
      router.go('/services/radarr/movie/42?heroTag=legacy_movie');
      await tester.pumpAndSettle();

      expect(
        router.state.uri.toString(),
        '${ServiceRoutes.radarrMovieBase}/42?heroTag=legacy_movie',
      );
      expect(find.byType(MovieDetailScreen), findsOneWidget);
    });

    testWidgets('a path that merely starts with the old prefix is not moved', (
      tester,
    ) async {
      // `startsWith('/services')` would rewrite `/services-of-mine` too. The
      // rewrite matches on the segment boundary, so an unknown path stays
      // unknown and falls through to the router's own handling.
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      router.go('/servicesfoo');
      await tester.pumpAndSettle();

      // Asserted on what rendered rather than on `router.state`: an unmatched
      // location leaves the match list empty and reading `state` throws, which
      // would pass this test for entirely the wrong reason.
      expect(find.byType(DashboardScreen), findsNothing);
    });

    testWidgets('legacy top-level routes redirect to services', (tester) async {
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      for (final route in ['/discover', '/movies', '/series', '/music']) {
        router.go(route);
        await tester.pumpAndSettle();

        expect(router.state.uri.toString(), '/dashboard');
        expect(find.byType(DashboardScreen), findsOneWidget);
      }
    });

    testWidgets('legacy detail routes redirect to equivalent services routes', (
      tester,
    ) async {
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      const encodedPosterUrl =
          'https%3A%2F%2Fcdn.example.com%2Fposter%20image.jpg';
      router.go('/discover/movie/123?posterUrl=$encodedPosterUrl');
      await tester.pumpAndSettle();

      // Two hops: the `/discover` tree rewrites onto the pre-tab Seerr
      // spelling, which rewrites again onto the detail inside the Discover
      // branch. What this asserts is that the chain finishes — a rewrite that
      // stopped at the first hop would leave the user on a path that draws
      // nothing.
      expect(
        router.state.uri.toString(),
        '/dashboard/seerr/discover/movie/123?posterUrl=$encodedPosterUrl',
      );
      expect(find.byType(DiscoverDetailScreen), findsOneWidget);

      // `/movies/:id` still crosses in one hop, but its destination moved
      // inside the Library branch with the film.
      router.go('/movies/42?heroTag=legacy_movie');
      await tester.pumpAndSettle();

      expect(
        router.state.uri.toString(),
        '${ServiceRoutes.radarrMovieBase}/42?heroTag=legacy_movie',
      );
      expect(find.byType(MovieDetailScreen), findsOneWidget);

      router.go('/series/55?heroTag=legacy_series');
      await tester.pumpAndSettle();

      expect(
        router.state.uri.toString(),
        '${ServiceRoutes.sonarrSeriesBase}/55?heroTag=legacy_series',
      );
      expect(find.byType(SeriesDetailScreen), findsOneWidget);

      router.go('/music/9?heroTag=legacy_artist');
      await tester.pumpAndSettle();

      expect(
        router.state.uri.toString(),
        '${ServiceRoutes.lidarrArtistBase}/9?heroTag=legacy_artist',
      );
      expect(find.byType(MusicDetailScreen), findsOneWidget);
    });
  });
}

Future<ProviderContainer> _pumpRouter(
  WidgetTester tester, {
  SettingsModel settings = const SettingsModel(),
  bool onboardingCompleted = true,
}) async {
  final container = ProviderContainer(
    overrides: [
      initialOnboardingCompletedProvider.overrideWith(
        (ref) => onboardingCompleted,
      ),
      currentSettingsProvider.overrideWith((ref) => settings),
      seerrServiceProvider.overrideWith((ref) => FakeSeerrService()),
      radarrServiceProvider.overrideWith((ref) => FakeRadarrService()),
      sonarrServiceProvider.overrideWith((ref) => FakeSonarrService()),
      lidarrServiceProvider.overrideWith((ref) => FakeLidarrService()),
      // Prowlarr has no hand-written fake, and does not need one: every call
      // its screens make is a GET whose envelope is an array or an object that
      // degrades to `{}`, so one canned empty array answers all of them. What
      // it buys is a *quiet* teardown — an unconfigured `ProwlarrService`
      // throws, and Riverpod retries the throw on a timer that outlives the
      // widget tree. Prowlarr's Settings pages and its indexer detail are
      // reachable from this file's tables, and neither gates on configuration.
      prowlarrServiceProvider.overrideWith(
        (ref) => ProwlarrService(FakeApiClient()..getResponseData = const []),
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      // Reduce Motion, because these cases are about *where* the router lands
      // and one of the destinations owns a continuous animation: the onboarding
      // ring sweeps forever by design, so with motion on `pumpAndSettle` waits
      // for a frame that never stops coming.
      child: MaterialApp.router(
        routerConfig: container.read(routerProvider),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  return container;
}
