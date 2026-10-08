import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/features/bazarr/data/bazarr_service.dart';
import 'package:cupola/features/bazarr/domain/models/bazarr_models.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_library_screen.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_movie_detail_screen.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_provider.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_series_detail_screen.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_wanted_screen.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';

import '../../../test_helpers/fake_bazarr_service.dart';

import '../../../test_helpers/settings_scope.dart';

final _settings = settingsWith(
  bazarrUrl: 'http://bazarr.local',
  bazarrApiKey: 'key',
);

Widget _wrap({required Widget child, required BazarrService service}) {
  return ProviderScope(
    overrides: [
      currentSettingsProvider.overrideWith((ref) => _settings),
      bazarrServiceProvider.overrideWith((ref) => service),
    ],
    child: MaterialApp(home: child),
  );
}

void main() {
  testWidgets('BazarrWantedScreen shows tabs and renders wanted items', (
    tester,
  ) async {
    final fake = FakeBazarrService()
      ..wantedEpisodesResult = const BazarrPagedResult(
        data: [
          BazarrWantedItem(
            seriesTitle: 'Foundation',
            episodeTitle: 'The Emperor',
            episodeNumber: '1x01',
            sonarrSeriesId: 7,
            missingLanguages: [BazarrSubtitleLanguage(code2: 'en')],
          ),
        ],
        total: 1,
      );

    await tester.pumpWidget(
      _wrap(child: const BazarrWantedScreen(), service: fake),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Wanted subtitles'), findsOneWidget);
    expect(find.text('Episodes'), findsOneWidget);
    expect(find.text('Movies'), findsOneWidget);
    expect(find.text('Foundation'), findsOneWidget);
    expect(find.textContaining('The Emperor'), findsOneWidget);
  });

  testWidgets('BazarrWantedScreen shows empty state when nothing is wanted', (
    tester,
  ) async {
    final fake = FakeBazarrService();
    await tester.pumpWidget(
      _wrap(child: const BazarrWantedScreen(), service: fake),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('No wanted subtitles'), findsOneWidget);
  });

  testWidgets('BazarrWantedScreen shows retryable error when the call fails', (
    tester,
  ) async {
    final fake = FakeBazarrService()..throwOnCall = Exception('boom');
    await tester.pumpWidget(
      _wrap(child: const BazarrWantedScreen(), service: fake),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('The request to Bazarr did not complete'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  // The screen lists ONE half now. Series and Movies are two entries on
  // Bazarr's own bar, so the inner `TabBar` this case used to assert is gone:
  // two bars answering the same question is what the split removed.
  testWidgets('BazarrLibraryScreen.series renders series entries', (
    tester,
  ) async {
    final fake = FakeBazarrService()
      ..seriesResult = const BazarrPagedResult(
        data: [
          BazarrSeries(
            sonarrSeriesId: 1,
            title: 'Foundation',
            year: 2021,
            monitored: true,
          ),
        ],
        total: 1,
      );

    await tester.pumpWidget(
      _wrap(child: const BazarrLibraryScreen.series(), service: fake),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // The app bar names the half, and nothing on the page offers the other
    // one: switching is the service bar's job.
    expect(find.text('Series'), findsOneWidget);
    expect(find.text('Movies'), findsNothing);
    expect(find.text('Foundation'), findsOneWidget);
  });

  testWidgets(
    'BazarrLibraryScreen.series shows empty state when no items are present',
    (tester) async {
      final fake = FakeBazarrService();
      await tester.pumpWidget(
        _wrap(child: const BazarrLibraryScreen.series(), service: fake),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('No items found'), findsOneWidget);
    },
  );

  testWidgets(
    'BazarrLibraryScreen.series shows retryable error when the call fails',
    (tester) async {
      final fake = FakeBazarrService()..throwOnCall = Exception('boom');
      await tester.pumpWidget(
        _wrap(child: const BazarrLibraryScreen.series(), service: fake),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.text('The request to Bazarr did not complete'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
    },
  );

  testWidgets(
    'BazarrLibraryScreen.series tapping a row navigates to the series detail',
    (tester) async {
      const series = BazarrSeries(
        sonarrSeriesId: 7,
        title: 'Foundation',
        year: 2021,
        monitored: true,
      );
      final fake = FakeBazarrService()
        ..seriesResult = const BazarrPagedResult(data: [series], total: 1)
        ..seriesByIdOverride = series;

      // The addresses the app builds through `ServiceRoutes`, spelled out: the
      // Series tab's root doubles as the detail's base, which is why the
      // series link did not move when the tab model landed.
      final router = GoRouter(
        initialLocation: ServiceRoutes.bazarrSeriesBase,
        routes: [
          GoRoute(
            path: ServiceRoutes.bazarrSeriesBase,
            builder: (context, state) => const BazarrLibraryScreen.series(),
          ),
          GoRoute(
            path: '${ServiceRoutes.bazarrSeriesBase}/:id',
            builder: (context, state) => BazarrSeriesDetailScreen(
              sonarrSeriesId: int.parse(state.pathParameters['id']!),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentSettingsProvider.overrideWith((ref) => _settings),
            bazarrServiceProvider.overrideWith((ref) => fake),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await tester.pumpAndSettle();

      // Tap the series row.
      await tester.tap(find.text('Foundation'));
      await tester.pumpAndSettle();

      expect(find.byType(BazarrSeriesDetailScreen), findsOneWidget);
      expect(router.state.uri.path, '/stack/bazarr/series/7');
    },
  );

  testWidgets(
    'BazarrLibraryScreen.movies tapping a row navigates to the movie detail',
    (tester) async {
      const movie = BazarrMovie(
        radarrId: 12,
        title: 'Inception',
        year: 2010,
        monitored: true,
      );
      final fake = FakeBazarrService()
        ..moviesResult = const BazarrPagedResult(data: [movie], total: 1)
        ..movieByIdOverride = movie;

      // `movies`, plural: the film detail moved under the Movies tab with the
      // tab model, and this is the address `ServiceRoutes.bazarrMovie` now
      // builds. The pre-tab `movie/:id` still resolves, as a redirect tail in
      // the real router.
      final router = GoRouter(
        initialLocation: ServiceRoutes.bazarrMovieBase,
        routes: [
          GoRoute(
            path: ServiceRoutes.bazarrMovieBase,
            builder: (context, state) => const BazarrLibraryScreen.movies(),
          ),
          GoRoute(
            path: '${ServiceRoutes.bazarrMovieBase}/:id',
            builder: (context, state) => BazarrMovieDetailScreen(
              radarrId: int.parse(state.pathParameters['id']!),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentSettingsProvider.overrideWith((ref) => _settings),
            bazarrServiceProvider.overrideWith((ref) => fake),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await tester.pumpAndSettle();

      // No tab to switch to: the page IS the Movies half.
      await tester.tap(find.textContaining('Inception'));
      await tester.pumpAndSettle();

      expect(find.byType(BazarrMovieDetailScreen), findsOneWidget);
      expect(router.state.uri.path, '/stack/bazarr/movies/12');
    },
  );
}
