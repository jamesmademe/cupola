import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/core/widgets/library_detail_actions.dart';
import 'package:cupola/features/activity/domain/service_type.dart';
import 'package:cupola/features/activity/presentation/activity_provider.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_item_tiles.dart';
import 'package:cupola/features/import/presentation/manual_import_routes.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/movies/presentation/movie_detail_provider.dart';
import 'package:cupola/features/movies/presentation/movie_detail_screen.dart';
import 'package:cupola/features/music/domain/lidarr_queue_snapshots.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';
import 'package:cupola/features/music/presentation/music_detail_provider.dart';
import 'package:cupola/features/music/presentation/music_detail_screen.dart';
import 'package:cupola/features/series/domain/models/sonarr_series.dart';
import 'package:cupola/features/series/presentation/series_detail_provider.dart';
import 'package:cupola/features/series/presentation/series_detail_screen.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

/// Two connections per service. The first of each is where the lens rests
/// when nothing moved it; every page below belongs to the second.
ServiceInstance _instance(ServiceKey service, String id, String label) =>
    ServiceInstance(
      id: id,
      service: service,
      label: label,
      url: 'https://$id.lan',
      credential: 'key-$id',
    );

final _instances = [
  _instance(ServiceKey.radarr, 'radarr', 'HD'),
  _instance(ServiceKey.radarr, 'radarr-4k', '4K'),
  _instance(ServiceKey.sonarr, 'sonarr', 'TV'),
  _instance(ServiceKey.sonarr, 'sonarr-anime', 'Anime'),
  _instance(ServiceKey.lidarr, 'lidarr', 'Music'),
  _instance(ServiceKey.lidarr, 'lidarr-vinyl', 'Vinyl'),
];

/// Where the wizard was asked to open, as the router received it.
Uri? _opened;

GoRouter _router(Widget page) => GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => Scaffold(body: page),
    ),
    GoRoute(
      path: manualImportBrowsePath,
      builder: (context, state) {
        _opened = state.uri;
        return const SizedBox.shrink();
      },
    ),
  ],
);

Future<void> _pump(
  WidgetTester tester,
  Widget page, {
  List<Override> overrides = const [],
}) async {
  _opened = null;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentSettingsProvider.overrideWith(
          (ref) => SettingsModel(instances: _instances),
        ),
        ...overrides,
      ],
      child: MaterialApp.router(routerConfig: _router(page)),
    ),
  );
  await tester.pumpAndSettle();
}

/// Runs the page's Manual import exactly as the action band would.
Future<void> _import(WidgetTester tester) async {
  // The band sits below the hero, past the first screen of a phone.
  await tester.scrollUntilVisible(
    find.byType(LibraryDetailActions),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  final actions = tester.widget<LibraryDetailActions>(
    find.byType(LibraryDetailActions),
  );
  expect(actions.onImport, isNotNull);
  actions.onImport!();
  await tester.pumpAndSettle();
}

void main() {
  // The one bug in this flow that moves files into the wrong library: a page
  // belonging to the second server opened a wizard bound to whichever server
  // the lens was on, carrying an item id that names something else there.
  group('a detail page binds the wizard to its own connection', () {
    testWidgets('Radarr', (tester) async {
      await _pump(
        tester,
        const MovieDetailScreen(
          movieId: 42,
          heroTag: 'movie-42',
          instanceId: 'radarr-4k',
        ),
        overrides: [
          movieDetailForProvider.overrideWith(
            (ref, item) async => RadarrMovie.fromJson({
              'id': 42,
              'title': 'Sprite Fright',
              'year': 2021,
              // A path is what makes it a library item, and only a library
              // item has an action band.
              'path': '/movies/Sprite Fright (2021)',
            }),
          ),
          radarrQueueSnapshotForProvider.overrideWith(
            (ref, id) => ArrQueueSnapshot.empty,
          ),
        ],
      );

      await _import(tester);

      expect(_opened?.queryParameters, {
        'service': 'radarr',
        'targetId': '42',
        'i': 'radarr-4k',
      });
    });

    testWidgets('Sonarr', (tester) async {
      await _pump(
        tester,
        const SeriesDetailScreen(
          seriesId: 7,
          heroTag: 'series-7',
          instanceId: 'sonarr-anime',
        ),
        overrides: [
          seriesDetailForProvider.overrideWith(
            (ref, item) async => SonarrSeries.fromJson({
              'id': 7,
              'title': 'Cosmos Laundromat',
              'path': '/tv/Cosmos Laundromat',
            }),
          ),
          seriesEpisodesForProvider.overrideWith((ref, item) async => []),
          sonarrQueueSnapshotForProvider.overrideWith(
            (ref, id) => ArrQueueSnapshot.empty,
          ),
        ],
      );

      await _import(tester);

      expect(_opened?.queryParameters['service'], 'sonarr');
      expect(_opened?.queryParameters['targetId'], '7');
      expect(_opened?.queryParameters['i'], 'sonarr-anime');
    });

    testWidgets('Lidarr', (tester) async {
      await _pump(
        tester,
        const MusicDetailScreen(
          artistId: 9,
          heroTag: 'artist-9',
          instanceId: 'lidarr-vinyl',
        ),
        overrides: [
          musicDetailForProvider.overrideWith(
            (ref, item) async => LidarrArtist.fromJson({
              'id': 9,
              'artistName': 'Tears of Steel',
              'path': '/music/Tears of Steel',
            }),
          ),
          musicAlbumsForProvider.overrideWith((ref, item) async => []),
          lidarrQueueSnapshotsForProvider.overrideWith(
            (ref, instanceId) async => LidarrQueueSnapshots.empty,
          ),
        ],
      );

      await _import(tester);

      expect(_opened?.queryParameters['service'], 'lidarr');
      expect(_opened?.queryParameters['targetId'], '9');
      expect(_opened?.queryParameters['i'], 'lidarr-vinyl');
    });
  });

  group('an Activity row hands the wizard the connection it came off', () {
    GlobalActivityItem queueRow({String instanceId = ''}) => GlobalActivityItem(
      kind: GlobalActivityKind.queue,
      service: ServiceKey.radarr,
      serviceType: ServiceType.movies,
      title: 'Elephants Dream',
      subtitle: '',
      status: const MediaStatusInfo(labelOverride: 'Import blocked'),
      instanceId: instanceId,
      raw: const {'id': 3, 'outputPath': '/downloads/complete/Elephants Dream'},
    );

    test('a row off the other server still offers the import', () {
      // Withheld until the wizard could be told which server to open on.
      expect(canManualImportFrom(queueRow(instanceId: 'radarr-4k')), isTrue);
    });

    testWidgets('and the wizard opens on that server', (tester) async {
      final row = queueRow(instanceId: 'radarr-4k');
      await _pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => openManualImportFrom(context, row),
            child: const Text('Manual import'),
          ),
        ),
      );

      await tester.tap(find.text('Manual import'));
      await tester.pumpAndSettle();

      expect(_opened?.queryParameters, {
        'service': 'radarr',
        'path': '/downloads/complete/Elephants Dream',
        'i': 'radarr-4k',
      });
    });

    testWidgets('a row that names no connection stays on the lens', (
      tester,
    ) async {
      final row = queueRow();
      await _pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => openManualImportFrom(context, row),
            child: const Text('Manual import'),
          ),
        ),
      );

      await tester.tap(find.text('Manual import'));
      await tester.pumpAndSettle();

      expect(_opened?.queryParameters.containsKey('i'), isFalse);
    });
  });
}
