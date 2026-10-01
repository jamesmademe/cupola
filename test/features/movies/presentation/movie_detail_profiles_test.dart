import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/movies/presentation/movie_detail_provider.dart';
import 'package:cupola/features/movies/presentation/movie_detail_screen.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/profiles/profiles.dart';

/// The container the page under test reads from.
ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(MovieDetailScreen)));

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
}
