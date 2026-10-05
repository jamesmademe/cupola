import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/domain/models/person_credits.dart';
import 'package:cupola/features/discover/domain/models/seerr_admin_models.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';

import '../../../test_helpers/fake_api_client.dart';
import '../../../test_helpers/fixtures.dart';

void main() {
  late FakeApiClient client;
  late SeerrService service;

  setUp(() {
    client = FakeApiClient();
    // Known up front, so the scripted GETs below answer the reads they are
    // written for; the read of `/api/v1/status` has its own group.
    service = SeerrService(client, numbering: SeerrNumbering.seerr);
  });

  group('createRequest', () {
    test('movie body contains required fields without seasons', () async {
      await service.createRequest(
        mediaType: 'movie',
        mediaId: 12345,
        profileId: 1,
        rootFolder: '/movies',
      );

      expect(client.lastPostPath, '/api/v1/request');
      final body = client.lastPostData as Map<String, dynamic>;
      expect(body, {
        'mediaType': 'movie',
        'mediaId': 12345,
        'is4k': false,
        'profileId': 1,
        'rootFolder': '/movies',
      });
      expect(body.containsKey('seasons'), isFalse);
    });

    test('tv body defaults seasons to "all" when not specified', () async {
      await service.createRequest(mediaType: 'tv', mediaId: 67890);
      expect((client.lastPostData as Map)['seasons'], 'all');
    });

    test('tv body uses specific seasons when provided', () async {
      await service.createRequest(
        mediaType: 'tv',
        mediaId: 67890,
        seasons: const [1, 2, 3],
      );
      expect((client.lastPostData as Map)['seasons'], [1, 2, 3]);
    });

    test('is4k flag is forwarded', () async {
      await service.createRequest(
        mediaType: 'movie',
        mediaId: 12345,
        is4k: true,
      );
      expect((client.lastPostData as Map)['is4k'], isTrue);
    });

    test('serverId is forwarded when provided', () async {
      await service.createRequest(mediaType: 'movie', mediaId: 1, serverId: 42);
      expect((client.lastPostData as Map)['serverId'], 42);
    });
  });

  group('search', () {
    test('returns empty list when query is empty (no network call)', () async {
      final results = await service.search('');
      expect(results, isEmpty);
      expect(client.getCallCount, 0);
    });

    test('filters out person results and keeps movies & tv', () async {
      client.getResponseData = {
        'results': [
          {'id': 1, 'mediaType': 'movie', 'title': 'Movie'},
          {'id': 2, 'mediaType': 'person', 'name': 'Actor'},
          {'id': 3, 'mediaType': 'tv', 'name': 'Show'},
          {'id': 4, 'media_type': 'person', 'name': 'Another Actor'},
          {'id': 5, 'media_type': 'movie', 'title': 'Snake Case Movie'},
        ],
      };

      final results = await service.search('test');

      expect(results.length, 3);
      expect(results.any((r) => r.mediaType == 'person'), isFalse);
      expect(client.lastGetPath, '/api/v1/search');
    });

    test('url-encodes the query', () async {
      client.getResponseData = {'results': const []};
      await service.search('star wars & friends');
      final q = client.lastGetQueryParameters!['query'] as String;
      expect(q, Uri.encodeComponent('star wars & friends'));
    });

    test('names a series by TVDB through `tvdb:`, encoded once', () async {
      client.getResponseData = {
        'results': [
          {'id': 2, 'mediaType': 'person', 'name': 'Someone'},
          {'id': 1399, 'mediaType': 'tv', 'name': 'Game of Thrones'},
        ],
      };

      expect(await service.findTvByTvdbId(121361), 1399);
      expect(client.lastGetPath, '/api/v1/search');
      // As typed: Seerr reads the prefix before it decodes a second time.
      expect(client.lastGetQueryParameters!['query'], 'tvdb:121361');
    });

    test('a TVDB id Seerr finds no series for names none', () async {
      client.getResponseData = {'results': const []};
      expect(await service.findTvByTvdbId(1), isNull);
    });

    test('forwards the cancel token to ApiClient', () async {
      // The other three global-search legs pin this at service level; Seerr's
      // only cover was a fake that overrode `search` outright, so dropping the
      // forwarding here left the whole suite green.
      client.getResponseData = {'results': const []};
      final cancelToken = CancelToken();

      await service.search('dune', cancelToken: cancelToken);

      expect(client.lastGetCancelToken, same(cancelToken));
    });

    test('returns empty list on network error', () async {
      client.getException = Exception('network down');
      expect(await service.search('anything'), isEmpty);
    });
  });

  group('discover endpoints', () {
    test('getDiscoverMovies hits the correct path', () async {
      client.getResponseData = {'results': const []};
      await service.getDiscoverMovies(page: 2);
      expect(client.lastGetPath, '/api/v1/discover/movies');
      expect(client.lastGetQueryParameters, {'page': 2});
    });

    test('getDiscoverTV hits the correct path', () async {
      client.getResponseData = {'results': const []};
      await service.getDiscoverTV();
      expect(client.lastGetPath, '/api/v1/discover/tv');
    });

    test('getDiscoverTrending hits the correct path', () async {
      client.getResponseData = {'results': const []};
      await service.getDiscoverTrending();
      expect(client.lastGetPath, '/api/v1/discover/trending');
    });

    test('a discover rail that failed throws, never reads as empty', () async {
      // `[]` is Seerr answering with nothing. A failure used to be `[]` too,
      // so a dark Seerr's rails vanished as if there were nothing to show.
      client.getException = Exception('boom');
      await expectLater(service.getDiscoverMovies(), throwsException);
      await expectLater(service.getDiscoverTV(), throwsException);
      await expectLater(service.getDiscoverTrending(), throwsException);
      await expectLater(service.getMovieGenres(), throwsException);
    });

    test('a discover rail Seerr answered with nothing is empty', () async {
      client.getResponseData = {'results': const []};
      expect(await service.getDiscoverMovies(), isEmpty);
    });

    test('a body that is not a results list is an unreadable answer', () async {
      client.getResponseData = '<html>proxy</html>';
      await expectLater(
        service.getDiscoverTrending(),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('getRequests', () {
    test('parses results and skips malformed entries', () async {
      client.getResponseQueue.addAll([
        {
          'results': [
            {
              'id': 7,
              'status': 2,
              'createdAt': '2024-01-02T00:00:00.000Z',
              'type': 'movie',
              'is4k': false,
              'requestedBy': {'id': 1, 'displayName': 'Matt'},
              'media': {
                'id': 101,
                'tmdbId': 111,
                'status': 5,
                'mediaType': 'movie',
                'title': 'Hydrated Movie',
                'posterPath': '/poster.jpg',
              },
            },
            'bad',
          ],
        },
      ]);

      final requests = await service.getRequests();

      expect(requests, hasLength(1));
      expect(requests.single.id, 7);
      expect(client.lastGetPath, '/api/v1/request');
      expect(client.lastGetQueryParameters, {
        'take': 50,
        'skip': 0,
        'sort': 'added',
        'filter': 'all',
      });
    });

    test('pages through every request page in parallel', () async {
      client.getResponseQueue.addAll([
        {
          'pageInfo': {'results': 60},
          'results': [
            for (var id = 1; id <= 50; id++)
              {
                'id': id,
                'status': 2,
                'createdAt': '2024-01-01T00:00:00.000Z',
                'type': 'movie',
                'is4k': false,
                'media': {
                  'id': id,
                  'tmdbId': id,
                  'status': 5,
                  'mediaType': 'movie',
                  'title': 'Title $id',
                  'posterPath': '/p$id.jpg',
                },
              },
          ],
        },
        {
          'pageInfo': {'results': 60},
          'results': [
            for (var id = 51; id <= 60; id++)
              {
                'id': id,
                'status': 2,
                'createdAt': '2024-01-01T00:00:00.000Z',
                'type': 'movie',
                'is4k': false,
                'media': {
                  'id': id,
                  'tmdbId': id,
                  'status': 5,
                  'mediaType': 'movie',
                  'title': 'Title $id',
                  'posterPath': '/p$id.jpg',
                },
              },
          ],
        },
      ]);

      final requests = await service.getRequests();

      expect(requests, hasLength(60));
      expect(requests.first.id, 1);
      expect(requests.last.id, 60);
      // Seerr's own count travels with the rows, and every page arrived.
      expect(
        requests,
        isA<SeerrRequestList>()
            .having((list) => list.total, 'total', 60)
            .having((list) => list.isPartial, 'isPartial', isFalse),
      );
    });

    test('a failing later page keeps the pages that did arrive', () async {
      client.getResponseQueue.addAll([
        {
          'pageInfo': {'results': 60},
          'results': [
            for (var id = 1; id <= 50; id++)
              {
                'id': id,
                'status': 2,
                'createdAt': '2024-01-01T00:00:00.000Z',
                'type': 'movie',
                'is4k': false,
                'media': {
                  'id': id,
                  'tmdbId': id,
                  'status': 5,
                  'mediaType': 'movie',
                  'title': 'Title $id',
                  'posterPath': '/p$id.jpg',
                },
              },
          ],
        },
      ]);
      // The queue holds one response; the second page falls back to
      // getResponseData, which is null and cannot be parsed as a page.

      final requests = await service.getRequests();

      // The second page answered nothing, but the first page's requests are
      // still reported — truncation beats blanking the whole list.
      expect(requests, hasLength(50));
      // And the list says so. The total is still the server's 60, not the 50
      // that arrived: a count taken from the length was short by the lost
      // page and read as the whole history.
      expect(
        requests,
        isA<SeerrRequestList>()
            .having((list) => list.total, 'total', 60)
            .having((list) => list.isPartial, 'isPartial', isTrue),
      );
    });

    test('an answer with no page info names no total', () async {
      client.getResponseQueue.addAll([
        {'results': const []},
      ]);

      final requests = await service.getRequests();

      // Not 0: the server did not say, and a zero here would be a count
      // nobody gave.
      expect(
        requests,
        isA<SeerrRequestList>().having((list) => list.total, 'total', isNull),
      );
    });

    test('hydration results are cached across refreshes', () async {
      client.getResponseQueue.addAll([
        {
          'results': [
            {
              'id': 7,
              'status': 2,
              'createdAt': '2024-01-02T00:00:00.000Z',
              'type': 'movie',
              'is4k': false,
              'media': {
                'id': 101,
                'tmdbId': 111,
                'status': 5,
                'mediaType': 'movie',
                'title': 'Unknown Media',
              },
            },
          ],
        },
        {
          'title': 'Hydrated Movie',
          'releaseDate': '2022-05-01',
          'posterPath': '/hydrated.jpg',
        },
        // Second refresh: same request page again, but the details call below
        // is never made — the response queue would run dry and the fake would
        // fall back to getResponseData, which is null.
        {
          'results': [
            {
              'id': 7,
              'status': 2,
              'createdAt': '2024-01-02T00:00:00.000Z',
              'type': 'movie',
              'is4k': false,
              'media': {
                'id': 101,
                'tmdbId': 111,
                'status': 5,
                'mediaType': 'movie',
                'title': 'Unknown Media',
              },
            },
          ],
        },
      ]);

      final first = await service.getRequests();
      expect(first.single.media?.title, 'Hydrated Movie');
      expect(first.single.media?.year, '2022');
      expect(first.single.media?.posterPath, '/hydrated.jpg');

      final second = await service.getRequests();
      expect(second.single.media?.title, 'Hydrated Movie');
      // The queue held exactly three responses: two request pages and one
      // details call. A second hydration would have consumed a fourth.
      expect(client.getCallCount, 3);
    });

    test('hydrates media when title is Unknown via movie detail', () async {
      client.getResponseQueue.addAll([
        {
          'results': [
            {
              'id': 7,
              'status': 2,
              'createdAt': '2024-01-02T00:00:00.000Z',
              'type': 'movie',
              'is4k': false,
              'requestedBy': {'id': 1, 'displayName': 'Matt'},
              'media': {
                'id': 101,
                'tmdbId': 111,
                'status': 5,
                'mediaType': 'movie',
                'title': 'Unknown Media',
              },
            },
          ],
        },
        {
          'title': 'Hydrated Movie',
          'releaseDate': '2022-05-01',
          'posterPath': '/hydrated.jpg',
        },
      ]);

      final requests = await service.getRequests();

      expect(requests.single.media?.title, 'Hydrated Movie');
      expect(requests.single.media?.year, '2022');
      expect(requests.single.media?.posterPath, '/hydrated.jpg');
    });

    // Deliberately the opposite of what this asserted before. Swallowing the
    // failure into `[]` made "this Seerr is unreachable" and "this Seerr has no
    // requests" the same answer, and /activity now shows several Seerrs at once
    // — it has to be able to say which one did not answer, and to leave the
    // others' lists alone while it does.
    test('throws when the first page does not come back', () async {
      client.getException = Exception('offline');
      expect(service.getRequests(), throwsA(isA<Exception>()));
    });
  });

  group('admin endpoints', () {
    test('gets open issues with the documented query contract', () async {
      client.getResponseData = {
        'pageInfo': {'results': 1},
        'results': [
          {
            'id': 21,
            'issueType': 2,
            'media': {'title': 'Fight Club'},
            'createdBy': {'username': 'matt'},
          },
        ],
      };

      final issues = (await service.getIssuesResult()).items;

      expect(issues.single.media?.title, 'Fight Club');
      expect(client.lastGetPath, '/api/v1/issue');
      expect(client.lastGetQueryParameters, {
        'take': 50,
        'skip': 0,
        'sort': 'modified',
        'filter': 'open',
      });
    });

    test(
      'gets users and resolves an issue through verified endpoints',
      () async {
        client.getResponseData = {
          'pageInfo': {'results': 1},
          'results': [
            {'id': 4, 'email': 'matt@example.com', 'requestCount': 3},
          ],
        };

        final users = (await service.getUsersResult()).items;
        await service.resolveIssue(21);

        expect(users.single.id, 4);
        expect(client.lastGetPath, '/api/v1/user');
        expect(client.lastPostPath, '/api/v1/issue/21/resolved');
      },
    );

    test(
      'does not fail on a bare list response from older instances',
      () async {
        client.getResponseData = [
          {'id': 21, 'issueType': 99},
          'malformed',
        ];

        final issues = (await service.getIssuesResult(
          filter: SeerrIssueFilter.all,
        )).items;

        expect(issues, hasLength(1));
        expect(issues.single.issueTypeLabel, 'Issue');
      },
    );
  });

  group('media endpoints', () {
    test('getMovie hits /api/v1/movie/:id', () async {
      client.getResponseData = {'title': 'Movie'};
      final data = await service.getMovie(123);
      expect(client.lastGetPath, '/api/v1/movie/123');
      expect(data['title'], 'Movie');
    });

    test('getTv hits /api/v1/tv/:id', () async {
      client.getResponseData = {'name': 'Show'};
      final data = await service.getTv(123);
      expect(client.lastGetPath, '/api/v1/tv/123');
      expect(data['name'], 'Show');
    });

    test('getCollection throws when Seerr did not answer', () async {
      client.getException = Exception('offline');
      await expectLater(service.getCollection(5), throwsException);
      await expectLater(service.getPerson(5), throwsException);
    });

    test('a 404 is Seerr answering that there is no such record', () async {
      client.getException = DioException(
        requestOptions: RequestOptions(path: '/api/v1/collection/5'),
        type: DioExceptionType.badResponse,
        response: Response<dynamic>(
          requestOptions: RequestOptions(path: '/api/v1/collection/5'),
          statusCode: 404,
        ),
      );
      expect(await service.getCollection(5), isEmpty);
      expect(await service.getPerson(5), isEmpty);
    });

    test('deleteMedia hits /api/v1/media/:id', () async {
      await service.deleteMedia(123);
      expect(client.lastDeletePath, '/api/v1/media/123');
    });

    test('deleteMediaFile hits /api/v1/media/:id/file', () async {
      await service.deleteMediaFile(456);
      expect(client.lastDeletePath, '/api/v1/media/456/file');
      expect(client.lastDeleteQueryParameters, {'is4k': 'false'});
    });

    test('deleteMediaFile names the 4K copy when asked for it', () async {
      // Seerr reads `is4k` off the query; without it the standard copy goes.
      await service.deleteMediaFile(456, is4k: true);
      expect(client.lastDeleteQueryParameters, {'is4k': 'true'});
    });

    test('deleteRequest hits /api/v1/request/:id', () async {
      await service.deleteRequest(77);
      expect(client.lastDeletePath, '/api/v1/request/77');
    });
  });

  // The route is snake case in Seerr's person.ts. The camel-case spelling the
  // app used 404'd, so every Person page drew an empty filmography.
  group('person credits', () {
    test('the filmography asks Seerr for combined_credits', () async {
      client.getResponseData = jsonFixtureMap(
        'seerr/person_combined_credits.json',
      );

      final items = await service.getPersonCombinedCredits(1203);

      expect(client.lastGetPath, '/api/v1/person/1203/combined_credits');
      // Cast only, one entry per title, best rated first; the person row that
      // is not a title is dropped.
      expect(items.map((item) => item.title), ['Sintel', 'Cosmos Laundromat']);
      expect(items.last.mediaType, 'tv');
    });

    test(
      'crew is exposed with its job, its department and each title status',
      () async {
        client.getResponseData = jsonFixtureMap(
          'seerr/person_combined_credits.json',
        );

        final credits = await service.getPersonCredits(1203);

        expect(credits.cast, hasLength(3));
        expect(credits.crew, hasLength(4));
        final screenplay = credits.crew[1];
        expect(screenplay.role, PersonCreditRole.crew);
        expect(screenplay.job, 'Screenplay');
        expect(screenplay.department, 'Writing');
        expect(screenplay.character, isNull);
        expect(credits.cast.first.character, 'Guard');
        expect(credits.cast.first.job, isNull);

        // "Director · 1 of 3 on your server": one row per title, TMDB's job
        // name matched without regard to case, and Seerr's `mediaInfo` read
        // per credit.
        final directed = credits.crewAs('Director');
        expect(directed.map((credit) => credit.media.title), [
          'Tears of Steel',
          'Dynamo Dream',
          'Prelude',
        ]);
        expect(directed.where((credit) => credit.isOnServer), hasLength(1));
        expect(directed[0].status.availability, MediaAvailability.available);
        expect(directed[1].status.availability, MediaAvailability.notTracked);
        expect(directed[2].status.availability, MediaAvailability.missing);
        // A partly available series is on the server, in part.
        expect(credits.cast[1].isOnServer, isTrue);
      },
    );

    test(
      'a lookup that fails is a failure, not an empty filmography',
      () async {
        client.getException = Exception('offline');

        await expectLater(service.getPersonCredits(1203), throwsException);
        await expectLater(
          service.getPersonCombinedCredits(1203),
          throwsException,
        );
      },
    );
  });

  group('service integration endpoints', () {
    test('getRadarrServers returns list on success', () async {
      client.getResponseData = [
        {'id': 1, 'name': 'Main'},
      ];
      final servers = await service.getRadarrServers();
      expect(servers, hasLength(1));
      expect(client.lastGetPath, '/api/v1/service/radarr');
    });

    test('getRadarrServers throws when Seerr did not answer', () async {
      // "No Radarr servers" is an answer; a failure used to read as one.
      client.getException = Exception('boom');
      await expectLater(service.getRadarrServers(), throwsException);
    });

    test('getSonarrServers hits /api/v1/service/sonarr', () async {
      client.getResponseData = const <Map<String, dynamic>>[];
      await service.getSonarrServers();
      expect(client.lastGetPath, '/api/v1/service/sonarr');
    });

    test('getRadarrProfiles hits /api/v1/service/radarr/:id', () async {
      client.getResponseData = {'profiles': const [], 'rootFolders': const []};
      await service.getRadarrProfiles(42);
      expect(client.lastGetPath, '/api/v1/service/radarr/42');
    });

    test('getSonarrProfiles hits /api/v1/service/sonarr/:id', () async {
      client.getResponseData = {'profiles': const [], 'rootFolders': const []};
      await service.getSonarrProfiles(9);
      expect(client.lastGetPath, '/api/v1/service/sonarr/9');
    });
  });

  group('search reachability', () {
    // The rule: a Seerr that did not answer and a Seerr that found nothing are
    // different facts, and the caller decides which of them it can render. Both
    // used to come back as `[]`, so the global search could only ever draw "no
    // results" for a dead server and had nothing to colour.
    test('reports the failure when the caller asks for it', () async {
      client.getException = DioException(
        requestOptions: RequestOptions(path: '/api/v1/search'),
        type: DioExceptionType.connectionError,
      );

      expect(
        () => service.search('dune', reportFailure: true),
        throwsA(isA<DioException>()),
      );
    });

    test('degrades to an empty list by default', () async {
      // Seerr's own search-as-you-type field keeps the old behaviour: the user
      // is mid-word and an error card between keystrokes is noise.
      client.getException = Exception('boom');

      expect(await service.search('dune'), isEmpty);
    });

    test('an answer with no matches is not a failure', () async {
      client.getResponseData = {'results': const <dynamic>[]};

      expect(await service.search('dune', reportFailure: true), isEmpty);
    });

    test('an empty query is still not a failure', () async {
      // The empty-term guard runs before the try, so `reportFailure` has
      // nothing to report and the field starts quiet rather than red.
      expect(await service.search('', reportFailure: true), isEmpty);
      expect(client.getCallCount, 0);
    });
  });
}
