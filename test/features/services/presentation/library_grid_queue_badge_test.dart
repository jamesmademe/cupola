import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/movies/presentation/movies_screen.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';
import 'package:cupola/features/music/presentation/music_screen.dart';
import 'package:cupola/features/series/domain/models/sonarr_series.dart';
import 'package:cupola/features/series/presentation/series_screen.dart';

import '../../../test_helpers/model_builders.dart';
import '../../../test_helpers/profiles/profiles.dart';

/// Sprite Fright as Radarr lists it: no file yet, and on its way.
final _spriteFright = RadarrMovie.fromJson(const {
  'id': 1,
  'title': 'Sprite Fright',
  'year': 2021,
  'hasFile': false,
  'monitored': true,
  'isAvailable': true,
  'status': 'released',
});

/// A film Radarr tracks with no file and nothing in the queue for it.
final _notInQueue = RadarrMovie.fromJson(const {
  'id': 77,
  'title': 'Glass Half',
  'year': 2015,
  'hasFile': false,
  'monitored': true,
  'isAvailable': true,
  'status': 'released',
});

/// A series with nothing on disk and nothing in the queue.
final _emptySeries = SonarrSeries.fromJson(const {
  'id': 77,
  'title': 'Hero',
  'year': 2018,
  'monitored': true,
  'status': 'continuing',
  'statistics': {'episodeFileCount': 0, 'episodeCount': 8},
});

/// An artist with nothing on disk and nothing in the queue.
final LidarrArtist _emptyArtist = buildArtist(
  id: 77,
  artistName: 'Nobody Yet',
  statistics: const {'trackCount': 10, 'trackFileCount': 0},
);

MediaStatusInfo _statusOf<T>(WidgetTester tester, T item) => tester
    .widget<MediaBrowseScaffold<T>>(find.byType(MediaBrowseScaffold<T>))
    .statusExtractor!(item)!;

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

NetworkReply _boom(NetworkRequest _) =>
    NetworkReply.json({'message': 'boom'}, status: 500);

void main() {
  group('the Radarr grid', () {
    testWidgets('a queue that answered names what it holds, and Missing '
        'only for what it does not', (tester) async {
      final harness = await _pump(tester, Profiles.p1, const MoviesScreen());

      expect(_statusOf(tester, _spriteFright).label, 'Downloading');
      expect(_statusOf(tester, _notInQueue).label, 'Missing');

      await harness.unmount(tester);
    });

    testWidgets('a queue that answered with an error leaves a film with no '
        'file unknown', (tester) async {
      final harness = await _pump(
        tester,
        Profiles.p7,
        const MoviesScreen(),
        routes: (network) =>
            network.on(WorldIds.radarr, 'GET', '/api/v3/queue', _boom),
      );

      // It used to read the failure as an empty queue: every film on its way
      // read "Missing" on its poster.
      expect(_statusOf(tester, _spriteFright).label, 'Unknown');
      expect(_statusOf(tester, _notInQueue).label, 'Unknown');

      await harness.unmount(tester);
    });
  });

  group('the Sonarr grid', () {
    testWidgets('Missing over a queue that answered, unknown over one that '
        'did not', (tester) async {
      final harness = await _pump(tester, Profiles.p1, const SeriesScreen());
      expect(_statusOf(tester, _emptySeries).label, 'Missing');
      await harness.unmount(tester);

      final down = await _pump(
        tester,
        Profiles.p7,
        const SeriesScreen(),
        routes: (network) =>
            network.on(WorldIds.sonarr, 'GET', '/api/v3/queue', _boom),
      );
      expect(_statusOf(tester, _emptySeries).label, 'Unknown');
      await down.unmount(tester);
    });
  });

  group('the Lidarr grid', () {
    testWidgets('Missing over a queue that answered', (tester) async {
      final harness = await _pump(tester, Profiles.p1, const MusicScreen());

      expect(_statusOf(tester, _emptyArtist).label, 'Missing');

      await harness.unmount(tester);
    });

    testWidgets('unknown over a Lidarr that did not answer', (tester) async {
      // P7 is away from home, and its Lidarr answers only at home.
      final harness = await _pump(tester, Profiles.p7, const MusicScreen());

      expect(_statusOf(tester, _emptyArtist).label, 'Unknown');

      await harness.unmount(tester);
    });
  });
}
