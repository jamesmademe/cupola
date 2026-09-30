import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/movies/presentation/movies_provider.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/music/presentation/music_provider.dart';
import 'package:cupola/features/readarr/data/readarr_service.dart';
import 'package:cupola/features/readarr/presentation/readarr_provider.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/series/presentation/series_provider.dart';

import '../../../test_helpers/fake_api_client.dart';

FakeApiClient _dark() =>
    FakeApiClient()
      ..getException = DioException.connectionError(
        requestOptions: RequestOptions(path: '/api'),
        reason: 'Connection refused',
      );

/// The library walls — Radarr, Sonarr, Lidarr, and Readarr's author list.
///
/// Each read went through `fetchAllItems`, which swallows every failure into
/// `[]`, so a server that was down resolved the wall *successfully* and it said
/// "No items found": a library that exists and is empty, the opposite of what
/// happened. A wall is the whole library in one request — there is no partial
/// answer to show beside the failure — so the failure has to reach it.
void main() {
  final walls =
      <
        ({
          String name,
          Override Function(FakeApiClient api) service,
          Future<Object?> Function(ProviderContainer c) read,
        })
      >[
        (
          name: 'Radarr',
          service: (api) =>
              radarrServiceProvider.overrideWith((ref) => RadarrService(api)),
          read: (c) => c.read(moviesProvider.future),
        ),
        (
          name: 'Sonarr',
          service: (api) =>
              sonarrServiceProvider.overrideWith((ref) => SonarrService(api)),
          read: (c) => c.read(seriesProvider.future),
        ),
        (
          name: 'Lidarr',
          service: (api) =>
              lidarrServiceProvider.overrideWith((ref) => LidarrService(api)),
          read: (c) => c.read(musicProvider.future),
        ),
        (
          name: 'Readarr',
          service: (api) =>
              readarrServiceProvider.overrideWith((ref) => ReadarrService(api)),
          read: (c) => c.read(readarrAuthorsProvider.future),
        ),
      ];

  for (final wall in walls) {
    test('a dark ${wall.name} fails its library wall once, never as an empty '
        'library', () async {
      final api = _dark();
      final container = ProviderContainer(overrides: [wall.service(api)]);
      addTearDown(container.dispose);

      await expectLater(
        // Settles at once: under the default retry the wall sat on a spinner
        // for the better part of a minute while the KPI peek above it — which
        // reads the same library with `noProviderRetry` — already said "—".
        wall.read(container).timeout(const Duration(milliseconds: 300)),
        throwsA(isA<DioException>()),
      );
      expect(
        api.getCallCount,
        1,
        reason: 'retrying is the Retry button\'s call, not the provider\'s',
      );
    });

    test('an empty ${wall.name} library is still an empty list', () async {
      final api = FakeApiClient()..getResponseData = <dynamic>[];
      final container = ProviderContainer(overrides: [wall.service(api)]);
      addTearDown(container.dispose);

      expect(await wall.read(container), isEmpty);
    });
  }
}
