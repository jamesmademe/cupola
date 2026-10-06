import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/features/activity/domain/service_type.dart';
import 'package:cupola/features/activity/presentation/activity_provider.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_item_tiles.dart';
import 'package:cupola/features/import/presentation/manual_import_routes.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/media/domain/media_copies.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/media/domain/media_reading.dart';
import 'package:cupola/features/media/domain/media_rows.dart';
import 'package:cupola/features/media/presentation/media_page.dart';
import 'package:cupola/features/media/presentation/media_sources_provider.dart';
import 'package:cupola/features/music/domain/lidarr_queue_snapshots.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';
import 'package:cupola/features/music/presentation/artist_page.dart';
import 'package:cupola/features/music/presentation/artist_page_providers.dart';
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

void main() {
  // The one bug in this flow that moves files into the wrong library: a page
  // belonging to the second server opened a wizard bound to whichever server
  // the lens was on, carrying an item id that names something else there.
  group('a detail page binds the wizard to its own connection', () {
    testWidgets('Radarr, from the film\'s own page', (tester) async {
      // The 4K Radarr's copy is the one whose import is blocked: its panel
      // leads, and its Finish import opens the wizard on that server.
      const record = {
        'id': 7,
        'movieId': 42,
        'title': 'Sprite.Fright.2021.2160p.WEB',
        'downloadClient': 'qBittorrent',
        'outputPath': '/downloads/complete/Sprite.Fright.2021.2160p.WEB',
        'size': 9000000000,
        'sizeleft': 0,
        'status': 'completed',
        'trackedDownloadStatus': 'warning',
        'trackedDownloadState': 'importBlocked',
      };
      final copy = MediaRadarrCopy(
        movie: RadarrMovie.fromJson({
          'id': 42,
          'tmdbId': 811631,
          'title': 'Sprite Fright',
          'year': 2021,
          'monitored': true,
          'hasFile': false,
          'path': '/movies/Sprite Fright (2021)',
        }),
        queue: ArrQueueSnapshot.fromQueueItems([
          record,
        ], idsFor: (item) => [item['movieId'] as int]),
      );
      await _pump(
        tester,
        const MediaPage(mediaKey: MediaKey.movie(811631), focus: 'radarr-4k'),
        overrides: [
          mediaRowsProvider.overrideWith(
            (ref, key) => [
              MediaConnectionRow<MediaRadarrCopy>(
                _instances[1],
                MediaReadingAnswered(MediaAnswer(copy, DateTime(2026, 10, 4))),
              ),
            ],
          ),
          mediaRadarrQueueProvider.overrideWith((ref, copy) async => [record]),
          mediaRadarrSearchProvider.overrideWith((ref, copy) async => null),
        ],
      );

      await tester.scrollUntilVisible(
        find.text('Finish import'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Finish import'));
      await tester.pumpAndSettle();

      expect(_opened?.queryParameters, containsPair('service', 'radarr'));
      expect(_opened?.queryParameters, containsPair('targetId', '42'));
      expect(_opened?.queryParameters, containsPair('i', 'radarr-4k'));
    });

    testWidgets('Lidarr, from the artist\'s actions', (tester) async {
      await _pump(
        tester,
        const ArtistPage(artistId: 9, instanceId: 'lidarr-vinyl'),
        overrides: [
          lidarrArtistProvider.overrideWith(
            (ref, item) async => LidarrArtist.fromJson({
              'id': 9,
              'artistName': 'Tears of Steel',
              'path': '/music/Tears of Steel',
            }),
          ),
          lidarrArtistAlbumsProvider.overrideWith((ref, item) async => []),
          lidarrQueueSnapshotsForProvider.overrideWith(
            (ref, instanceId) async => LidarrQueueSnapshots.empty,
          ),
        ],
      );

      await tester.tap(
        find.bySemanticsLabel('More actions for Tears of Steel'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import files'));
      await tester.pumpAndSettle();

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
