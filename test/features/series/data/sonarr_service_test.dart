import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/api/base_arr_service.dart';
import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/series/domain/models/sonarr_series.dart';

import '../../../test_helpers/fake_api_client.dart';

void main() {
  group('SonarrService', () {
    test('getSeries answers [] when the library cannot be read', () async {
      final client = FakeApiClient()..getException = Exception('unreachable');

      expect(await SonarrService(client).getSeries(), isEmpty);
    });

    test('getSeriesOrThrow lets that same failure through', () async {
      // The pair is the point. An empty library and an unreachable server are
      // the same `[]` out of `getSeries`, so any figure derived from it prints
      // a confident zero for a question nobody answered. Callers that count
      // read this one instead.
      final client = FakeApiClient()..getException = Exception('unreachable');

      expect(
        SonarrService(client).getSeriesOrThrow(),
        throwsA(isA<Exception>()),
      );
    });

    test('getSeriesOrThrow reads the same endpoint and maps it', () async {
      final client = FakeApiClient()
        ..getResponseData = [
          {'id': 7, 'title': 'Severance'},
        ];

      final series = await SonarrService(client).getSeriesOrThrow();

      expect(
        client.lastGetPath,
        '/api/${ArrServiceConfig.sonarr.apiVersion}/series',
      );
      expect(series.single.title, 'Severance');
    });

    test('getQueue requests embedded series and episode data', () async {
      final client = FakeApiClient()
        ..getResponseData = {
          'records': [
            {'id': 1, 'title': 'Queued'},
          ],
        };
      final service = SonarrService(client);

      final items = await service.getQueue();

      expect(items, hasLength(1));
      expect(
        client.lastGetPath,
        '/api/${ArrServiceConfig.sonarr.apiVersion}/queue',
      );
      expect(client.lastGetQueryParameters, const {
        'page': 1,
        'pageSize': 200,
        'includeSeries': true,
        'includeEpisode': true,
        'includeUnknownSeriesItems': true,
      });
    });

    test('getHistory requests embedded series and episode data', () async {
      final client = FakeApiClient()
        ..getResponseData = {
          'records': [
            {'id': 1, 'sourceTitle': 'Imported.Release'},
          ],
        };
      final service = SonarrService(client);

      final items = await service.getHistory();

      expect(items, hasLength(1));
      expect(
        client.lastGetPath,
        '/api/${ArrServiceConfig.sonarr.apiVersion}/history',
      );
      expect(client.lastGetQueryParameters, {
        'page': 1,
        'pageSize': 20,
        'includeSeries': true,
        'includeEpisode': true,
      });
    });

    // The override lives on the PAGE primitive, and this is the test that says
    // why it has to. `getHistoryPage` is the only variant carrying the
    // envelope's `totalRecords`, so it is the only one a count may come from —
    // and while the parameters hung off `getHistory` instead, a caller that
    // reached for the count got records with neither the series nor the
    // episode embedded. On Sonarr that is the whole row: a bare history record
    // names a season and an episode number against a series id, and without
    // them there is nothing to print but the id.
    test(
      'getHistoryPage asks for the embedded series and episode too',
      () async {
        final client = FakeApiClient()
          ..getResponseData = {
            'totalRecords': 512,
            'records': [
              {'id': 1, 'sourceTitle': 'Imported.Release'},
            ],
          };
        final service = SonarrService(client);

        final page = await service.getHistoryPage();

        expect(client.lastGetQueryParameters, {
          'page': 1,
          'pageSize': 20,
          'includeSeries': true,
          'includeEpisode': true,
        });
        expect(page.records, hasLength(1));
        expect(page.total, 512);
      },
    );

    test('getReleases forwards the cancel token to ApiClient', () async {
      final client = FakeApiClient()..getResponseData = const [];
      final service = SonarrService(client);
      final cancelToken = CancelToken();

      await service.getReleases(
        seriesId: 7,
        seasonNumber: 2,
        cancelToken: cancelToken,
      );

      expect(client.lastGetPath, '/api/v3/release');
      expect(client.lastGetQueryParameters, {'seriesId': 7, 'seasonNumber': 2});
      expect(client.lastGetCancelToken, same(cancelToken));
    });

    test('lookupSeries asks nothing for an empty term', () async {
      final client = FakeApiClient();
      final service = SonarrService(client);

      expect(await service.lookupSeries(''), isEmpty);
      expect(client.getCallCount, 0);
    });

    test('lookupSeries encodes the term and maps results', () async {
      final client = FakeApiClient()
        ..getResponseData = [
          {'id': 9, 'title': 'The Boys', 'year': 2019},
        ];
      final service = SonarrService(client);

      final series = await service.lookupSeries('the boys & co');

      expect(client.lastGetPath, '/api/v3/series/lookup');
      expect(client.lastGetQueryParameters, {'term': 'the%20boys%20%26%20co'});
      expect(series.single.title, 'The Boys');
    });

    test('lookupSeries forwards the cancel token to ApiClient', () async {
      final client = FakeApiClient()..getResponseData = const [];
      final service = SonarrService(client);
      final cancelToken = CancelToken();

      await service.lookupSeries('the boys', cancelToken: cancelToken);

      // Global search re-runs this leg on every debounced keystroke; without a
      // token the superseded request runs to completion.
      expect(client.lastGetCancelToken, same(cancelToken));
    });

    group('getSeriesByTvdbId', () {
      test('finds series when TVDB ID matches', () async {
        final service = _TestSonarrService([
          _series(
            id: 1,
            title: 'Series 1',
            tvdbId: 11111,
            year: 2023,
            runtime: 45,
            genres: const ['Drama'],
          ),
          _series(
            id: 2,
            title: 'Series 2',
            tvdbId: 22222,
            year: 2020,
            runtime: 60,
            genres: const ['Comedy'],
          ),
        ]);

        final found = await service.getSeriesByTvdbId(11111);
        expect(found, isNotNull);
        expect(found!.id, 1);
        expect(found.title, 'Series 1');
      });

      test('returns null when TVDB ID not found', () async {
        final service = _TestSonarrService([
          _series(
            id: 1,
            title: 'Series 1',
            tvdbId: 11111,
            year: 2023,
            runtime: 45,
            genres: const ['Drama'],
          ),
        ]);

        final found = await service.getSeriesByTvdbId(99999);
        expect(found, isNull);
      });

      test('handles empty library', () async {
        final service = _TestSonarrService(const []);

        final found = await service.getSeriesByTvdbId(11111);
        expect(found, isNull);
      });
    });

    group('addSeries', () {
      SonarrSeries lookupHit() => const SonarrSeries(
        // What `series/lookup` sends for a series the server does NOT have.
        id: 0,
        title: 'Severance',
        sortTitle: 'severance',
        titleSlug: 'severance',
        status: 'continuing',
        monitored: false,
        year: 2022,
        images: [
          {'coverType': 'poster', 'url': '/MediaCover/0/poster.jpg'},
        ],
        tvdbId: 371980,
        runtime: 50,
        genres: [],
        seasons: [
          {'seasonNumber': 1, 'monitored': true},
          {'seasonNumber': 2, 'monitored': true},
        ],
        seriesType: 'standard',
      );

      test('posts the lookup payload with the chosen options', () async {
        final client = FakeApiClient()
          ..postResponseData = {'id': 91, 'title': 'Severance'};
        final service = SonarrService(client);

        final added = await service.addSeries(
          lookupHit(),
          qualityProfileId: 6,
          rootFolderPath: '/data/tv',
          monitored: true,
          searchForMissingEpisodes: true,
        );

        expect(client.lastPostPath, '/api/v3/series');
        final body = client.lastPostData as Map<String, dynamic>;
        expect(body['tvdbId'], 371980);
        expect(body['titleSlug'], 'severance');
        expect(body['title'], 'Severance');
        // The seasons travel back untouched: Sonarr builds the library entry
        // from them, and an add without them lands a series with no seasons.
        expect(body['seasons'], hasLength(2));
        expect(body['qualityProfileId'], 6);
        expect(body['rootFolderPath'], '/data/tv');
        expect(body['monitored'], isTrue);
        expect(body['seasonFolder'], isTrue);
        expect(body['addOptions'], {
          'monitor': 'all',
          'searchForMissingEpisodes': true,
          'searchForCutoffUnmetEpisodes': false,
        });
        expect(added.id, 91);
      });

      test('an unmonitored add monitors no episodes either', () async {
        final client = FakeApiClient()..postResponseData = {'id': 92};
        final service = SonarrService(client);

        await service.addSeries(
          lookupHit(),
          qualityProfileId: 6,
          rootFolderPath: '/data/tv',
          monitored: false,
          searchForMissingEpisodes: false,
        );

        final body = client.lastPostData as Map<String, dynamic>;
        expect(body['monitored'], isFalse);
        // Not `all`: a series that is not monitored with every episode
        // monitored is a contradiction Sonarr resolves by grabbing nothing —
        // and it would still queue a search sweep.
        expect(body['addOptions'], {
          'monitor': 'none',
          'searchForMissingEpisodes': false,
          'searchForCutoffUnmetEpisodes': false,
        });
      });

      test('a rejected add is not swallowed', () async {
        final client = FakeApiClient()
          ..postException = Exception('400 SeriesExistsValidator');
        final service = SonarrService(client);

        expect(
          service.addSeries(
            lookupHit(),
            qualityProfileId: 6,
            rootFolderPath: '/data/tv',
          ),
          throwsA(isA<Exception>()),
        );
      });
    });

    group('updateSeriesType', () {
      test(
        'sends back the whole series record with only seriesType changed',
        () async {
          // The rule, not the route: Sonarr's series PUT replaces the resource
          // and silently resets anything the body leaves out, so a write that
          // posts `{seriesType: anime}` alone unmonitors the show and drops its
          // quality profile. The body has to be what the GET just returned.
          final client = FakeApiClient()
            ..getResponseData = {
              'id': 7,
              'title': 'Frieren',
              'monitored': true,
              'qualityProfileId': 4,
              'seriesType': 'standard',
              'seasons': [
                {'seasonNumber': 1, 'monitored': true},
              ],
            };
          final service = SonarrService(client);

          await service.updateSeriesType(7, 'anime');

          expect(client.lastGetPath, '/api/v3/series/7');
          expect(client.lastPutPath, '/api/v3/series/7');
          final body = client.lastPutData as Map<String, dynamic>;
          expect(body['seriesType'], 'anime');
          expect(body['monitored'], isTrue);
          expect(body['qualityProfileId'], 4);
          expect(body['title'], 'Frieren');
          expect(body['seasons'], hasLength(1));
        },
      );

      test('surfaces a failure instead of degrading', () async {
        // This write changes what imports. A swallowed error would leave the
        // row showing the old value as though the change had landed.
        final client = FakeApiClient()
          ..getResponseData = {'id': 7, 'seriesType': 'standard'}
          ..putException = Exception('403');
        final service = SonarrService(client);

        expect(() => service.updateSeriesType(7, 'daily'), throwsException);
      });
    });
  });
}

class _TestSonarrService extends SonarrService {
  _TestSonarrService(this._series) : super(ApiClient(baseUrl: '', apiKey: ''));

  final List<SonarrSeries> _series;

  @override
  Future<List<SonarrSeries>> getSeries() async => _series;
}

SonarrSeries _series({
  required int id,
  required String title,
  required int tvdbId,
  required int year,
  required int runtime,
  required List<String> genres,
}) {
  return SonarrSeries(
    id: id,
    title: title,
    sortTitle: title.toLowerCase(),
    status: 'continuing',
    overview: 'A test series',
    path: '/tv/${title.toLowerCase()}',
    monitored: true,
    year: year,
    images: const [],
    tvdbId: tvdbId,
    runtime: runtime,
    genres: genres,
    seasons: const [],
  );
}
