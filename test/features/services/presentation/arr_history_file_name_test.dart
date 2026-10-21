/// The file an import record landed, as the history entry names it.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/services/domain/arr_import.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/profiles/profiles.dart';

/// The moment the week is read from: the harness's own clock.
DateTime _now(ProfileHarness harness) => harness.network.now;

ProviderContainer _container(ProfileHarness harness) {
  final container = ProviderContainer(
    overrides: [
      ...harness.overrides,
      arrivalsClockProvider.overrideWith(
        (ref) =>
            () => _now(harness),
      ),
    ],
    retry: (_, _) => null,
  );
  addTearDown(container.dispose);
  return container;
}

Future<ArrHistory> _arrivals(ProviderContainer container) {
  container.listen(servicesArrivalsProvider, (_, _) {});
  return container.read(servicesArrivalsProvider.future);
}

String _stamp(ProfileHarness harness, Duration ago) =>
    _now(harness).subtract(ago).toUtc().toIso8601String();

/// One history record as an arr sends it, with the media it embeds.
Map<String, Object?> _record(
  ProfileHarness harness, {
  required int id,
  required String eventType,
  Duration ago = const Duration(hours: 2),
  String? sourceTitle,
  Map<String, Object?>? data,
  String? media,
}) => {
  'id': id,
  'eventType': eventType,
  'date': _stamp(harness, ago),
  'sourceTitle': ?sourceTitle,
  'data': data ?? const <String, Object?>{},
  if (media == 'movie') ...{
    'movieId': id,
    'movie': {'id': id, 'title': 'Movie $id', 'year': 2024, 'tmdbId': 100 + id},
  },
  if (media == 'series') ...{
    'seriesId': id,
    'series': {'id': id, 'title': 'Series $id', 'tmdbId': 100 + id},
  },
  if (media == 'artist') ...{
    'artistId': id,
    'artist': {'artistName': 'Artist $id'},
    'album': {'id': id, 'title': 'Album $id'},
  },
};

void main() {
  group('the file an import landed', () {
    test(
      'P1: Radarr names it by the last segment of the imported path',
      () async {
        final harness = await ProfileHarness.start(Profiles.p1);
        final week = await _arrivals(_container(harness));

        final spring = week.entries.firstWhere(
          (entry) => entry.title == 'Spring',
        );
        expect(spring.outcome, ArrImportOutcome.imported);
        expect(spring.fileName, 'Spring (${WorldTitles.spring.year}).mkv');
      },
    );

    test('P1: Sonarr, whose record names no path, falls back to the release '
        'it came from', () async {
      final harness = await ProfileHarness.start(Profiles.p1);
      final week = await _arrivals(_container(harness));

      final cosmos = week.entries.firstWhere(
        (entry) => entry.service == ServiceKey.sonarr,
      );
      expect(cosmos.fileName, 'Cosmos.Laundromat.S02E03.1080p.WEB');
    });

    test('a path reads on either separator, and a trailing one is ignored, '
        'in every arr', () async {
      final harness = await ProfileHarness.start(Profiles.p1);
      harness.network
        ..on(
          WorldIds.sonarr,
          'GET',
          '/api/v3/history/since',
          (r) => NetworkReply.json([
            _record(
              harness,
              id: 1,
              eventType: 'downloadFolderImported',
              media: 'series',
              data: {
                'importedPath':
                    r'D:\TV\Series 1\Season 2\Series.1.S02E04.1080p.mkv',
              },
            ),
          ]),
        )
        ..on(
          WorldIds.lidarr,
          'GET',
          '/api/v1/history/since',
          (r) => NetworkReply.json([
            _record(
              harness,
              id: 2,
              eventType: 'trackFileImported',
              media: 'artist',
              data: {
                'importedPath': '/music/Artist 2/Album 2/01 - Opening.flac',
              },
            ),
            _record(
              harness,
              id: 3,
              eventType: 'trackFileImported',
              media: 'artist',
              data: {'importedPath': '/music/Artist 3/Album 3/'},
            ),
          ]),
        );

      final week = await _arrivals(_container(harness));

      String? fileOf(ServiceKey service, String title) => week.entries
          .firstWhere(
            (entry) => entry.service == service && entry.title == title,
          )
          .fileName;
      expect(
        fileOf(ServiceKey.sonarr, 'Series 1'),
        'Series.1.S02E04.1080p.mkv',
      );
      expect(fileOf(ServiceKey.lidarr, 'Album 2'), '01 - Opening.flac');
      expect(fileOf(ServiceKey.lidarr, 'Album 3'), 'Album 3');
    });

    test('an import with neither a path nor a release has no name', () async {
      final harness = await ProfileHarness.start(Profiles.p1);
      harness.network.on(
        WorldIds.sonarr,
        'GET',
        '/api/v3/history/since',
        (r) => NetworkReply.json([
          _record(
            harness,
            id: 1,
            eventType: 'downloadFolderImported',
            media: 'series',
          ),
        ]),
      );

      final week = await _arrivals(_container(harness));

      expect(
        week.entries
            .singleWhere((entry) => entry.service == ServiceKey.sonarr)
            .fileName,
        isNull,
      );
    });
  });
}
