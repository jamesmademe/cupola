import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/movies/presentation/movie_detail_provider.dart';
import 'package:cupola/features/movies/presentation/movie_detail_screen.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/profiles/profiles.dart';

/// The container the page under test reads from.
ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(MovieDetailScreen)));

/// What the list a film page is pushed from hands it: the record Radarr gave
/// the list, a while ago.
final _preload = RadarrMovie.fromJson(const {
  'id': 1,
  'title': 'Sprite Fright',
  'year': 2021,
  'hasFile': false,
  'monitored': true,
  'isAvailable': true,
  'status': 'released',
  'qualityProfileId': 1,
  'path': '/mnt/tank/media/movies/Sprite Fright (2021)',
});

final _radarrDown = Profiles.p7.withBehaviour(
  WorldIds.radarr,
  ConnectionBehaviour.didNotAnswer,
);

int _movieReads(ProfileHarness harness) => harness.network
    .requestsTo(WorldIds.radarr)
    .where((r) => r.uri.path == '/api/v3/movie/1')
    .length;

void main() {
  group('a Radarr that is not set up', () {
    testWidgets('says so on the first frame and asks Radarr nothing', (
      tester,
    ) async {
      final harness = await pumpWithProfile(
        tester,
        Profiles.p3.without(ServiceKey.radarr),
        child: const MovieDetailScreen(movieId: 1, heroTag: 'movie-1'),
        settle: false,
      );
      await tester.pump();

      // Not a skeleton waiting out a retry schedule: the settings already
      // knew, so the page says it at once.
      expect(find.byType(NotConfiguredPlaceholder), findsOneWidget);
      expect(find.byType(MediaDetailLoadingView), findsNothing);
      expect(
        _container(
          tester,
        ).exists(movieDetailForProvider((instanceId: '', id: 1))),
        isFalse,
      );

      await harness.unmount(tester);
    });

    testWidgets('a preloaded movie does not stand in for a Radarr', (
      tester,
    ) async {
      final harness = await pumpWithProfile(
        tester,
        Profiles.p3.without(ServiceKey.radarr),
        child: MovieDetailScreen(
          movieId: 1,
          heroTag: 'movie-1',
          initialMovie: RadarrMovie.fromJson(const {
            'id': 1,
            'title': 'Sprite Fright',
            'year': 2021,
            'path': '/movies/Sprite Fright (2021)',
          }),
        ),
        settle: false,
      );
      await tester.pump();

      expect(find.byType(NotConfiguredPlaceholder), findsOneWidget);
      expect(find.text('Sprite Fright'), findsNothing);

      await harness.unmount(tester);
    });

    testWidgets('a link naming a connection that is gone is not set up', (
      tester,
    ) async {
      final harness = await pumpWithProfile(
        tester,
        Profiles.p3,
        child: const MovieDetailScreen(
          movieId: 1,
          heroTag: 'movie-1',
          instanceId: 'radarr-removed',
        ),
        settle: false,
      );
      await tester.pump();

      // Gated on the connection the page would read, not on the service: this
      // household has a Radarr, just not the one the link names.
      expect(find.byType(NotConfiguredPlaceholder), findsOneWidget);
      expect(
        _container(
          tester,
        ).exists(movieDetailForProvider((instanceId: 'radarr-removed', id: 1))),
        isFalse,
      );

      await harness.unmount(tester);
    });
  });

  group('a Radarr that does not answer', () {
    testWidgets('a preloaded film stays, under a red band that says so', (
      tester,
    ) async {
      final harness = await _pump(
        tester,
        _radarrDown,
        MovieDetailScreen(
          movieId: 1,
          heroTag: 'movie-1',
          initialMovie: _preload,
        ),
      );

      expect(find.text('Sprite Fright'), findsWidgets);
      final band = tester.widget<FaultBand>(find.byType(FaultBand));
      expect(band.tone, StatusTone.error);
      expect(
        band.message,
        'Radarr did not answer. Everything below is what it said last.',
      );

      final asked = _movieReads(harness);
      await tester.tap(
        find.descendant(
          of: find.byType(FaultBand),
          matching: find.text('Retry'),
        ),
      );
      await harness.settle(tester);
      expect(_movieReads(harness), greaterThan(asked));

      await harness.unmount(tester);
    });

    testWidgets('a cold open says it did not answer, at once', (tester) async {
      final harness = await _pump(
        tester,
        _radarrDown,
        const MovieDetailScreen(movieId: 1, heroTag: 'movie-1'),
      );

      // It used to read "The request to Radarr did not complete": the read
      // swallowed the silence into "no such movie", which nobody could tell
      // apart from a fault.
      expect(find.text('Radarr did not answer'), findsOneWidget);
      // Asked once. The page offers Retry; it does not wait out a retry
      // schedule on its own first.
      expect(_movieReads(harness), 1);

      await harness.unmount(tester);
    });
  });

  group('a Radarr that answers with a fault', () {
    testWidgets('the band is amber, and Retry brings the answer back', (
      tester,
    ) async {
      var failing = true;
      final harness = await _pump(
        tester,
        Profiles.p7,
        MovieDetailScreen(
          movieId: 1,
          heroTag: 'movie-1',
          initialMovie: _preload,
        ),
        routes: (network) => network.on(
          WorldIds.radarr,
          'GET',
          '/api/v3/movie/1',
          (_) => failing
              ? NetworkReply.json({'message': 'boom'}, status: 500)
              : null,
        ),
      );

      final band = tester.widget<FaultBand>(find.byType(FaultBand));
      expect(band.tone, StatusTone.warning);
      expect(
        band.message,
        'Radarr answered with an error. Everything below is what it said '
        'last.',
      );

      failing = false;
      await tester.tap(
        find.descendant(
          of: find.byType(FaultBand),
          matching: find.text('Retry'),
        ),
      );
      await harness.settle(tester);

      expect(find.byType(FaultBand), findsNothing);
      expect(find.text('Sprite Fright'), findsWidgets);

      await harness.unmount(tester);
    });

    testWidgets('a film Radarr does not have is not a failed request', (
      tester,
    ) async {
      final harness = await _pump(
        tester,
        Profiles.p7,
        const MovieDetailScreen(movieId: 99, heroTag: 'movie-99'),
      );

      expect(find.text('Radarr has no record of this movie'), findsOneWidget);
      expect(find.byType(AppErrorState), findsNothing);

      await harness.unmount(tester);
    });
  });

  group('the quality profile row', () {
    testWidgets('comes back once a later read answers', (tester) async {
      // Tall enough that the Details card is built without scrolling.
      await tester.binding.setSurfaceSize(const Size(800, 3000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var profilesAnswer = false;
      final harness = await _pump(
        tester,
        Profiles.p7,
        const MovieDetailScreen(movieId: 1, heroTag: 'movie-1'),
        routes: (network) => network.on(
          WorldIds.radarr,
          'GET',
          '/api/v3/qualityprofile',
          (_) => profilesAnswer
              ? null
              : NetworkReply.json({'message': 'boom'}, status: 500),
        ),
      );

      // Omitted while the profiles are unknown: never a value nobody read.
      expect(find.text('Details'), findsOneWidget);
      expect(find.text('Quality profile'), findsNothing);
      // Asked once, not on every rebuild that followed the failure.
      expect(
        harness.network
            .requestsTo(WorldIds.radarr)
            .where((r) => r.uri.path == '/api/v3/qualityprofile'),
        hasLength(1),
      );

      profilesAnswer = true;
      await tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      await harness.settle(tester);
      // The profiles are asked for after the frame that drew the fresh film,
      // and that frame leaves nothing scheduled for `settle` to wait on.
      await tester.pump(const Duration(milliseconds: 100));
      await harness.settle(tester);

      // It used to be asked for once per page, so this row stayed gone until
      // the user left and came back.
      expect(find.text('Quality profile'), findsOneWidget);
      expect(find.text('HD-1080p'), findsOneWidget);

      await harness.unmount(tester);
    });
  });
}

/// Pumps [child] under [profile] with [routes] answering ahead of the world
/// from the first request on, which `pumpWithProfile` cannot do: its first
/// frame has already asked by the time it hands the harness back.
Future<ProfileHarness> _pump(
  WidgetTester tester,
  ConfigProfile profile,
  Widget child, {
  void Function(ProfileNetwork network)? routes,
}) async {
  final harness = await ProfileHarness.start(profile);
  routes?.call(harness.network);
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: MaterialApp(theme: AppTheme.darkTheme(), home: child),
    ),
  );
  await harness.settle(tester);
  return harness;
}
