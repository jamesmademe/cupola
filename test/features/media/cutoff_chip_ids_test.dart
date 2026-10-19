import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/music/presentation/music_screen.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/series/presentation/series_screen.dart';

import '../../test_helpers/fake_api_client.dart';

/// The "Cutoff unmet" chips read `wanted/cutoff` for a set of ids and nothing
/// else, so what they ask the server to embed in every record is pure weight:
/// Sonarr's series and episode file in each episode, Lidarr's artist in each
/// album.
void main() {
  late FakeApiClient client;

  setUp(() => client = FakeApiClient());

  test('the Sonarr chip folds the episodes into series ids and asks for no '
      'embed', () async {
    client.getResponseData = {
      'records': [
        {'id': 1, 'seriesId': 7},
        {'id': 2, 'seriesId': 7},
        {'id': 3, 'seriesId': 9},
      ],
      'totalRecords': 3,
    };
    final container = ProviderContainer(
      overrides: [
        sonarrServiceProvider.overrideWith((_) => SonarrService(client)),
      ],
    );
    addTearDown(container.dispose);
    container.listen(sonarrCutoffUnmetSeriesIdsProvider, (_, _) {});

    final ids = await container.read(sonarrCutoffUnmetSeriesIdsProvider.future);

    expect(ids, {7, 9});
    expect(client.lastGetPath, '/api/v3/wanted/cutoff');
    expect(client.lastGetQueryParameters, containsPair('includeSeries', false));
    expect(
      client.lastGetQueryParameters,
      containsPair('includeEpisodeFile', false),
    );
  });

  test('the Lidarr chip folds the albums into artist ids and asks for no '
      'embed', () async {
    client.getResponseData = {
      'records': [
        {'id': 1, 'artistId': 4},
        {'id': 2, 'artistId': 4},
        {'id': 3, 'artistId': 5},
      ],
      'totalRecords': 3,
    };
    final container = ProviderContainer(
      overrides: [
        lidarrServiceProvider.overrideWith((_) => LidarrService(client)),
      ],
    );
    addTearDown(container.dispose);
    container.listen(lidarrCutoffUnmetArtistIdsProvider, (_, _) {});

    final ids = await container.read(lidarrCutoffUnmetArtistIdsProvider.future);

    expect(ids, {4, 5});
    expect(client.lastGetPath, '/api/v1/wanted/cutoff');
    expect(client.lastGetQueryParameters, containsPair('includeArtist', false));
  });

  test(
    'Activity\'s Wanted list still gets its embeds from the same walk',
    () async {
      // The chips override the embeds per call. The service defaults, which the
      // Wanted tab reads its rows by, stay as they were.
      client.getResponseData = {'records': const [], 'totalRecords': 0};

      await SonarrService(client).getAllCutoff();
      expect(
        client.lastGetQueryParameters,
        containsPair('includeSeries', true),
      );
      expect(
        client.lastGetQueryParameters,
        containsPair('includeEpisodeFile', true),
      );

      await LidarrService(client).getAllCutoff();
      expect(
        client.lastGetQueryParameters,
        containsPair('includeArtist', true),
      );
    },
  );
}
