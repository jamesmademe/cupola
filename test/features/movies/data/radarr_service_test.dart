import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/api/base_arr_service.dart';
import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';

import '../../../test_helpers/fake_api_client.dart';

void main() {
  group('RadarrService', () {
    test('getQueue requests embedded movie data', () async {
      final client = FakeApiClient()
        ..getResponseData = {
          'records': [
            {'id': 1, 'title': 'Queued'},
          ],
        };
      final service = RadarrService(client);

      final items = await service.getQueue();

      expect(items, hasLength(1));
      expect(
        client.lastGetPath,
        '/api/${ArrServiceConfig.radarr.apiVersion}/queue',
      );
      expect(client.lastGetQueryParameters, const {
        'page': 1,
        'pageSize': 200,
        'includeMovie': true,
      });
    });

    test('getHistory requests embedded movie data', () async {
      final client = FakeApiClient()
        ..getResponseData = {
          'records': [
            {'id': 1, 'sourceTitle': 'Imported.Release'},
          ],
        };
      final service = RadarrService(client);

      final items = await service.getHistory();

      expect(items, hasLength(1));
      expect(
        client.lastGetPath,
        '/api/${ArrServiceConfig.radarr.apiVersion}/history',
      );
      expect(client.lastGetQueryParameters, {
        'page': 1,
        'pageSize': 20,
        'sortKey': 'date',
        'sortDirection': 'descending',
        'includeMovie': true,
      });
    });

    // The override lives on the PAGE primitive, and this is the test that says
    // why it has to. `getHistoryPage` is the only variant that carries the
    // envelope's `totalRecords`, so it is the only one a count may be derived
    // from — and while the parameter hung off `getHistory` instead, a caller
    // that reached for the count got records with no embedded `movie`. The
    // embedded movie is the row: title, poster, year. The count and the content
    // could not both be right at once.
    test('getHistoryPage asks for the embedded movie too', () async {
      final client = FakeApiClient()
        ..getResponseData = {
          'totalRecords': 340,
          'records': [
            {'id': 1, 'sourceTitle': 'Imported.Release'},
          ],
        };
      final service = RadarrService(client);

      final page = await service.getHistoryPage();

      expect(client.lastGetQueryParameters, {
        'page': 1,
        'pageSize': 20,
        'sortKey': 'date',
        'sortDirection': 'descending',
        'includeMovie': true,
      });
      // And the total survives: how many there ARE, not how many we fetched.
      expect(page.records, hasLength(1));
      expect(page.total, 340);
    });

    test('getReleases forwards the cancel token to ApiClient', () async {
      final client = FakeApiClient()..getResponseData = const [];
      final service = RadarrService(client);
      final cancelToken = CancelToken();

      await service.getReleases(42, cancelToken: cancelToken);

      expect(client.lastGetPath, '/api/v3/release');
      expect(client.lastGetQueryParameters, {'movieId': 42});
      expect(client.lastGetCancelToken, same(cancelToken));
    });

    test('lookupMovies asks nothing for an empty term', () async {
      final client = FakeApiClient();
      final service = RadarrService(client);

      expect(await service.lookupMovies(''), isEmpty);
      expect(client.getCallCount, 0);
    });

    test('lookupMovies encodes the term and maps results', () async {
      final client = FakeApiClient()
        ..getResponseData = [
          {'id': 7, 'title': 'Dune', 'year': 2021},
        ];
      final service = RadarrService(client);

      final movies = await service.lookupMovies('dune & friends');

      expect(client.lastGetPath, '/api/v3/movie/lookup');
      expect(client.lastGetQueryParameters, {'term': 'dune%20%26%20friends'});
      expect(movies.single.title, 'Dune');
    });

    test('lookupMovies forwards the cancel token to ApiClient', () async {
      final client = FakeApiClient()..getResponseData = const [];
      final service = RadarrService(client);
      final cancelToken = CancelToken();

      await service.lookupMovies('dune', cancelToken: cancelToken);

      // Global search re-runs this leg on every debounced keystroke; without a
      // token the superseded request runs to completion.
      expect(client.lastGetCancelToken, same(cancelToken));
    });

    group('getMovieByTmdbId', () {
      test('finds movie when TMDB ID matches', () async {
        final service = _TestRadarrService([
          _movie(
            id: 1,
            title: 'Movie 1',
            tmdbId: 12345,
            year: 2023,
            runtime: 120,
          ),
          _movie(
            id: 2,
            title: 'Movie 2',
            tmdbId: 67890,
            year: 2024,
            runtime: 90,
          ),
        ]);

        final found = await service.getMovieByTmdbId(12345);

        expect(found, isNotNull);
        expect(found?.id, 1);
        expect(found?.title, 'Movie 1');
      });

      test('returns null when TMDB ID not found', () async {
        final service = _TestRadarrService([
          _movie(
            id: 1,
            title: 'Movie 1',
            tmdbId: 12345,
            year: 2023,
            runtime: 120,
          ),
        ]);

        final found = await service.getMovieByTmdbId(99999);
        expect(found, isNull);
      });

      test('handles empty library', () async {
        final service = _TestRadarrService(const []);

        final found = await service.getMovieByTmdbId(12345);
        expect(found, isNull);
      });
    });

    group('addMovie', () {
      RadarrMovie lookupHit() => RadarrMovie(
        // What `movie/lookup` sends for a title the server does NOT have: no
        // library id, and the metadata it proxied from TMDB.
        id: 0,
        title: 'Dune',
        sortTitle: 'dune',
        titleSlug: 'dune-438631',
        sizeOnDisk: 0,
        status: 'released',
        hasFile: false,
        monitored: false,
        year: 2021,
        images: const [
          {'coverType': 'poster', 'url': '/MediaCover/0/poster.jpg'},
        ],
        tmdbId: 438631,
        runtime: 155,
        genres: const [],
        minimumAvailability: 'announced',
      );

      test('posts the lookup payload with the chosen options', () async {
        final client = FakeApiClient()
          ..postResponseData = {'id': 77, 'title': 'Dune', 'tmdbId': 438631};
        final service = RadarrService(client);

        final added = await service.addMovie(
          lookupHit(),
          qualityProfileId: 4,
          rootFolderPath: '/data/movies',
          monitored: true,
          searchForMovie: true,
        );

        expect(client.lastPostPath, '/api/v3/movie');
        final body = client.lastPostData as Map<String, dynamic>;
        expect(body['tmdbId'], 438631);
        // Radarr keys the library entry on the slug, and the lookup row is the
        // only place it comes from.
        expect(body['titleSlug'], 'dune-438631');
        expect(body['title'], 'Dune');
        expect(body['year'], 2021);
        expect(body['images'], hasLength(1));
        expect(body['qualityProfileId'], 4);
        expect(body['rootFolderPath'], '/data/movies');
        expect(body['monitored'], isTrue);
        expect(body['minimumAvailability'], 'announced');
        // The half that makes this an add rather than a bookmark.
        expect(body['addOptions'], {'searchForMovie': true});
        // The created resource comes back with the library id it was given.
        expect(added.id, 77);
      });

      test('an unmonitored, unsearched add says so', () async {
        final client = FakeApiClient()..postResponseData = {'id': 78};
        final service = RadarrService(client);

        await service.addMovie(
          lookupHit(),
          qualityProfileId: 4,
          rootFolderPath: '/data/movies',
          monitored: false,
          searchForMovie: false,
        );

        final body = client.lastPostData as Map<String, dynamic>;
        expect(body['monitored'], isFalse);
        expect(body['addOptions'], {'searchForMovie': false});
      });

      test('a rejected add is not swallowed', () async {
        // Radarr answers 400 for a movie it already holds. Returning normally
        // here would leave the sheet reporting a success that never happened.
        final client = FakeApiClient()
          ..postException = Exception('400 MovieExistsValidator');
        final service = RadarrService(client);

        expect(
          service.addMovie(
            lookupHit(),
            qualityProfileId: 4,
            rootFolderPath: '/data/movies',
          ),
          throwsA(isA<Exception>()),
        );
      });
    });
  });
}

class _TestRadarrService extends RadarrService {
  _TestRadarrService(this._movies) : super(ApiClient(baseUrl: '', apiKey: ''));

  final List<RadarrMovie> _movies;

  @override
  Future<List<RadarrMovie>> getMovies() async => _movies;
}

RadarrMovie _movie({
  required int id,
  required String title,
  required int tmdbId,
  required int year,
  required int runtime,
}) {
  return RadarrMovie(
    id: id,
    title: title,
    sortTitle: title.toLowerCase(),
    sizeOnDisk: 0,
    status: 'released',
    hasFile: true,
    monitored: true,
    year: year,
    images: const [],
    tmdbId: tmdbId,
    runtime: runtime,
    genres: const [],
  );
}
