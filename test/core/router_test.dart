import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/router.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/presentation/discover_detail_screen.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/movies/presentation/movie_detail_screen.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/music/presentation/music_detail_screen.dart';
import 'package:cupola/features/onboarding/data/onboarding_provider.dart';
import 'package:cupola/features/onboarding/presentation/onboarding_screen.dart';
import 'package:cupola/features/search/presentation/search_screen.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/series/presentation/series_detail_screen.dart';
import 'package:cupola/features/services/presentation/service_all_screens.dart';
import 'package:cupola/features/services/presentation/services_screen.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/settings/presentation/settings_appearance_screen.dart';
import 'package:cupola/features/settings/presentation/settings_connections_screen.dart';
import 'package:cupola/features/settings/presentation/service_settings_screen.dart';

import '../test_helpers/fake_services.dart';
import '../test_helpers/model_builders.dart';

void main() {
  group('routerProvider', () {
    testWidgets('starts on services', (tester) async {
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      expect(router.state.uri.toString(), '/dashboard');
      expect(find.byType(ServicesScreen), findsOneWidget);
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
      expect(find.byType(ServicesScreen), findsOneWidget);
      expect(find.byType(OnboardingScreen), findsNothing);
    });

    testWidgets('redirects invalid discover detail ids back to services', (
      tester,
    ) async {
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      router.go('/dashboard/seerr/movie/not-a-number');
      await tester.pumpAndSettle();

      expect(router.state.uri.toString(), '/dashboard');
      expect(find.byType(ServicesScreen), findsOneWidget);
      expect(find.byType(DiscoverDetailScreen), findsNothing);
    });

    testWidgets(
      'preserves discover detail default hero tag and posterUrl decoding',
      (tester) async {
        final container = await _pumpRouter(tester);
        final router = container.read(routerProvider);
        const encodedPosterUrl =
            'https%3A%2F%2Fcdn.example.com%2Fposter%20image.jpg';

        router.go('/dashboard/seerr/movie/123?posterUrl=$encodedPosterUrl');
        await tester.pumpAndSettle();

        final screen = tester.widget<DiscoverDetailScreen>(
          find.byType(DiscoverDetailScreen),
        );

        expect(
          router.state.uri.toString(),
          '/dashboard/seerr/movie/123?posterUrl=$encodedPosterUrl',
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

        router.go('/dashboard/sonarr/series/55');
        await tester.pumpAndSettle();

        final seriesScreen = tester.widget<SeriesDetailScreen>(
          find.byType(SeriesDetailScreen),
        );
        expect(seriesScreen.heroTag, 'series_55');
        expect(seriesScreen.seriesId, 55);
        expect(seriesScreen.initialSeries, isNull);

        router.go('/dashboard/lidarr/artist/9');
        await tester.pumpAndSettle();

        final musicScreen = tester.widget<MusicDetailScreen>(
          find.byType(MusicDetailScreen),
        );
        expect(musicScreen.heroTag, 'artist_9');
        expect(musicScreen.artistId, 9);
        expect(musicScreen.initialArtist, isNull);
      },
    );

    testWidgets('redirects invalid library detail ids back to services', (
      tester,
    ) async {
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      router.go(
        '/dashboard/radarr/movie/not-a-number',
        extra: buildMovie(id: 42),
      );
      await tester.pumpAndSettle();

      expect(router.state.uri.toString(), '/dashboard');
      expect(find.byType(ServicesScreen), findsOneWidget);
      expect(find.byType(MovieDetailScreen), findsNothing);
    });

    testWidgets(
      'library detail routes ignore wrong-type and mismatched extras instead of redirecting',
      (tester) async {
        final container = await _pumpRouter(tester);
        final router = container.read(routerProvider);

        router.go('/dashboard/radarr/movie/42', extra: buildArtist(id: 9));
        await tester.pumpAndSettle();

        expect(router.state.uri.toString(), '/dashboard/radarr/movie/42');
        var movieScreen = tester.widget<MovieDetailScreen>(
          find.byType(MovieDetailScreen),
        );
        expect(movieScreen.movieId, 42);
        expect(movieScreen.initialMovie, isNull);

        router.go('/dashboard/radarr/movie/42', extra: buildMovie(id: 7));
        await tester.pumpAndSettle();

        expect(router.state.uri.toString(), '/dashboard/radarr/movie/42');
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
      expect(find.text('Seerr Settings'), findsOneWidget);
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

      for (final route in [
        '/dashboard/seerr',
        '/dashboard/radarr',
        '/dashboard/sonarr',
        '/dashboard/lidarr',
      ]) {
        router.go(route);
        await tester.pumpAndSettle();

        expect(router.state.uri.toString(), route);
      }
    });

    testWidgets('supports service all-list routes', (tester) async {
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      router.go('/dashboard/seerr/requests');
      await tester.pumpAndSettle();

      expect(router.state.uri.toString(), '/dashboard/seerr/requests');
      expect(find.byType(ServiceAllRequestsScreen), findsOneWidget);

      for (final entry in {
        '/dashboard/radarr/media': ServiceKey.radarr,
        '/dashboard/sonarr/media': ServiceKey.sonarr,
        '/dashboard/lidarr/media': ServiceKey.lidarr,
      }.entries) {
        router.go(entry.key);
        await tester.pumpAndSettle();

        expect(
          router.state.uri.toString(),
          '/dashboard/${entry.value.routeParam}',
        );
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
      const cases = {
        '/services': '/dashboard',
        '/services/radarr': '/dashboard/radarr',
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
      router.go('/services/radarr/movie/42?heroTag=legacy_movie');
      await tester.pumpAndSettle();

      expect(
        router.state.uri.toString(),
        '/dashboard/radarr/movie/42?heroTag=legacy_movie',
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
      expect(find.byType(ServicesScreen), findsNothing);
    });

    testWidgets('legacy top-level routes redirect to services', (tester) async {
      final container = await _pumpRouter(tester);
      final router = container.read(routerProvider);

      for (final route in ['/discover', '/movies', '/series', '/music']) {
        router.go(route);
        await tester.pumpAndSettle();

        expect(router.state.uri.toString(), '/dashboard');
        expect(find.byType(ServicesScreen), findsOneWidget);
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

      expect(
        router.state.uri.toString(),
        '/dashboard/seerr/movie/123?posterUrl=$encodedPosterUrl',
      );
      expect(find.byType(DiscoverDetailScreen), findsOneWidget);

      router.go('/movies/42?heroTag=legacy_movie');
      await tester.pumpAndSettle();

      expect(
        router.state.uri.toString(),
        '/dashboard/radarr/movie/42?heroTag=legacy_movie',
      );
      expect(find.byType(MovieDetailScreen), findsOneWidget);

      router.go('/series/55?heroTag=legacy_series');
      await tester.pumpAndSettle();

      expect(
        router.state.uri.toString(),
        '/dashboard/sonarr/series/55?heroTag=legacy_series',
      );
      expect(find.byType(SeriesDetailScreen), findsOneWidget);

      router.go('/music/9?heroTag=legacy_artist');
      await tester.pumpAndSettle();

      expect(
        router.state.uri.toString(),
        '/dashboard/lidarr/artist/9?heroTag=legacy_artist',
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
