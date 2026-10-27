import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/bazarr/data/bazarr_service.dart';

import '../../../test_helpers/fake_api_client.dart';

void main() {
  group('BazarrService.getBadges', () {
    test('parses the unwrapped badges payload and totals wanted', () async {
      final client = FakeApiClient()
        ..getResponseData = {
          'episodes': 12,
          'movies': 4,
          'providers': 3,
          'status': true,
          'sonarr_signalr': true,
          'radarr_signalr': false,
          'announcements': 1,
        };
      final service = BazarrService(client);

      final badges = await service.getBadges();

      expect(badges.episodes, 12);
      expect(badges.movies, 4);
      expect(badges.totalWanted, 16);
      expect(badges.providers, 3);
      expect(badges.status, isTrue);
      expect(badges.sonarrSignalR, isTrue);
      expect(badges.radarrSignalR, isFalse);
      expect(badges.announcements, 1);
      expect(client.lastGetPath, '/api/badges');
    });

    test('a payload that is not the badge map is a failure, not zeros', () {
      // All-zero badges read "Wanted 0" for a Bazarr that never said.
      final client = FakeApiClient()..getResponseData = 'unexpected';
      final service = BazarrService(client);

      expect(service.getBadges(), throwsA(isA<Exception>()));
    });
  });

  group('BazarrService.getHealthIssues', () {
    test(
      'reads Bazarr\'s issues, each with its object and its words',
      () async {
        final client = FakeApiClient()
          ..getResponseData = {
            'data': [
              {
                'object': 'Missing languages profile',
                'issue':
                    'You must create at least one languages profile and assign '
                    'it to your content.',
              },
              {'object': '', 'issue': ''},
            ],
          };

        final issues = await BazarrService(client).getHealthIssues();

        expect(client.lastGetPath, '/api/system/health');
        expect(issues, hasLength(1));
        expect(issues.single.headline, 'Bazarr has no languages profile');
        expect(issues.single.issue, startsWith('You must create'));
      },
    );

    test('an answer that is not the list is no healthy Bazarr', () async {
      final client = FakeApiClient()..getResponseData = '<html></html>';

      expect(
        BazarrService(client).getHealthIssues(),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('BazarrService provider status', () {
    test('parses the official provider status envelope', () async {
      final client = FakeApiClient()
        ..getResponseData = {
          'data': [
            {
              'name': 'opensubtitlescom',
              'status': 'TooManyRequests',
              'retry': 'in 2 hours',
            },
            {'name': 'podnapisi', 'status': 'Good', 'retry': '-'},
          ],
        };

      final providers = await BazarrService(client).getProviderStatuses();

      expect(client.lastGetPath, '/api/providers');
      expect(providers, hasLength(2));
      // Every enabled provider is listed: the throttled one in its reason's
      // words, the ready one ready.
      expect(providers.first.displayName, 'OpenSubtitles.com');
      expect(providers.first.throttled, isTrue);
      expect(providers.first.statusLabel, 'Too many requests');
      expect(providers.first.retryLabel, 'in 2 hours');
      expect(providers.first.tone, StatusTone.warning);
      expect(providers.last.throttled, isFalse);
      expect(providers.last.statusLabel, 'Ready');
      expect(providers.last.retryLabel, isNull);
      expect(providers.last.tone, StatusTone.neutral);
    });

    test('an answer that is not the list is no Bazarr without providers', () {
      final client = FakeApiClient()..getResponseData = '<html></html>';

      expect(
        BazarrService(client).getProviderStatuses(),
        throwsA(isA<FormatException>()),
      );
    });

    test('resets provider throttles through the official action', () async {
      final client = FakeApiClient();

      await BazarrService(client).resetProviderStatuses();

      expect(client.lastPostPath, '/api/providers');
      expect(client.lastPostQueryParameters, {'action': 'reset'});
    });
  });

  group('BazarrService paged endpoints', () {
    test('getSeries forwards start/length and unwraps data + total', () async {
      final client = FakeApiClient()
        ..getResponseData = {
          'data': [
            {
              'sonarrSeriesId': 1,
              'title': 'The Series',
              'monitored': true,
              'episodeMissingCount': 2,
              'profileId': 4,
              'tags': ['tvdb:123'],
            },
          ],
          'total': 42,
        };
      final service = BazarrService(client);

      final result = await service.getSeries(start: 0, length: 10);

      expect(client.lastGetPath, '/api/series');
      expect(client.lastGetQueryParameters, {'start': 0, 'length': 10});
      expect(result.data, hasLength(1));
      expect(result.total, 42);
      expect(result.hasMore, isTrue);
      final series = result.data.single;
      expect(series.sonarrSeriesId, 1);
      expect(series.title, 'The Series');
      expect(series.monitored, isTrue);
      expect(series.episodeMissingCount, 2);
      expect(series.profileId, 4);
      expect(series.tags, ['tvdb:123']);
    });

    test('getSeries hasMore respects start offset on later pages', () async {
      final client = FakeApiClient()
        ..getResponseData = {
          'data': List.generate(
            50,
            (i) => {'sonarrSeriesId': 1000 + i, 'title': 'Series $i'},
          ),
          'total': 100,
        };
      final service = BazarrService(client);

      final result = await service.getSeries(start: 50, length: 50);

      expect(result.hasMore, isFalse);
    });

    test(
      'getMovies parses missing_subtitles language list and radarrId',
      () async {
        final client = FakeApiClient()
          ..getResponseData = {
            'data': [
              {
                'radarrId': 99,
                'title': 'Dune: Part Two',
                'year': '2024',
                'monitored': true,
                'missing_subtitles': [
                  {'name': 'English', 'code2': 'en', 'code3': 'eng'},
                  {
                    'name': 'Italian',
                    'code2': 'it',
                    'code3': 'ita',
                    'forced': true,
                  },
                ],
              },
            ],
            'total': 1,
          };
        final service = BazarrService(client);

        final result = await service.getMovies(start: 0, length: 25);

        expect(client.lastGetPath, '/api/movies');
        expect(client.lastGetQueryParameters, {'start': 0, 'length': 25});
        final movie = result.data.single;
        expect(movie.radarrId, 99);
        expect(movie.title, 'Dune: Part Two');
        expect(movie.missingSubtitlesCount, 2);
        expect(movie.missingLanguages.first.code2, 'en');
        expect(movie.missingLanguages.last.forced, isTrue);
        expect(result.hasMore, isFalse);
      },
    );

    // The languages on disk used to be dropped: only `missing_subtitles` was
    // read, so "English, Italian · German wanted" could only ever say its last
    // half.
    test('getMovies parses the subtitles already on disk', () async {
      final client = FakeApiClient()
        ..getResponseData = {
          'data': [
            {
              'radarrId': 99,
              'title': 'Sintel',
              'monitored': true,
              // The shape `postprocess` builds from `get_subtitles`: one row
              // per file, `path` null for an embedded track.
              'subtitles': [
                {
                  'name': 'English',
                  'code2': 'en',
                  'code3': 'eng',
                  'path': null,
                  'forced': false,
                  'hi': false,
                  'file_size': null,
                },
                {
                  'name': 'English',
                  'code2': 'en',
                  'code3': 'eng',
                  'path': '/movies/Sintel/Sintel.en.srt',
                  'forced': false,
                  'hi': false,
                  'file_size': 41213,
                },
                {
                  'name': 'Italian',
                  'code2': 'it',
                  'code3': 'ita',
                  'path': '/movies/Sintel/Sintel.it.forced.srt',
                  'forced': true,
                  'hi': false,
                  'file_size': 1024,
                },
              ],
              'missing_subtitles': [
                {'name': 'German', 'code2': 'de', 'code3': 'deu'},
              ],
            },
          ],
          'total': 1,
        };
      final service = BazarrService(client);

      final movie = (await service.getMovies()).data.single;

      // One entry per language and flavour, not one per file.
      expect(movie.presentLanguages.map((l) => l.code2).toList(), ['en', 'it']);
      expect(movie.presentLanguages.last.forced, isTrue);
      expect(movie.missingLanguages.single.code2, 'de');
    });

    test('a record with no subtitles list has none on disk', () async {
      final client = FakeApiClient()
        ..getResponseData = {
          'data': [
            {'radarrId': 1, 'title': 'Charge', 'monitored': true},
          ],
          'total': 1,
        };
      final service = BazarrService(client);

      final movie = (await service.getMovies()).data.single;

      expect(movie.presentLanguages, isEmpty);
    });

    test(
      'getWantedEpisodes returns wanted items with missing languages',
      () async {
        final client = FakeApiClient()
          ..getResponseData = {
            'data': [
              {
                'seriesTitle': 'Foundation',
                'episode_number': '1x02',
                'episodeTitle': 'The Emperor',
                'sonarrSeriesId': 11,
                'sonarrEpisodeId': 22,
                'missing_subtitles': [
                  {'name': 'English', 'code2': 'en', 'code3': 'eng'},
                  {'name': 'Spanish', 'code2': 'es', 'code3': 'spa'},
                ],
                'tags': ['tvdb:1'],
              },
            ],
            'total': 1,
          };
        final service = BazarrService(client);

        final result = await service.getWantedEpisodes();

        expect(client.lastGetPath, '/api/episodes/wanted');
        final item = result.data.single;
        expect(item.seriesTitle, 'Foundation');
        expect(item.episodeNumber, '1x02');
        expect(item.season, 1);
        expect(item.missingSubtitlesCount, 2);
        expect(item.missingLanguages.map((l) => l.code2).toList(), [
          'en',
          'es',
        ]);
        expect(item.sonarrSeriesId, 11);
        expect(item.sonarrEpisodeId, 22);
      },
    );

    test('getWantedMovies returns movie wanted items', () async {
      final client = FakeApiClient()
        ..getResponseData = {
          'data': [
            {
              'title': 'Dune',
              'radarrId': 7,
              'missing_subtitles': [
                {'name': 'Italian', 'code2': 'it', 'code3': 'ita', 'hi': true},
              ],
              'sceneName': 'Dune.2021',
            },
          ],
          'total': 1,
        };
      final service = BazarrService(client);

      final result = await service.getWantedMovies();

      expect(client.lastGetPath, '/api/movies/wanted');
      final item = result.data.single;
      expect(item.title, 'Dune');
      expect(item.radarrId, 7);
      expect(item.sceneName, 'Dune.2021');
      expect(item.missingSubtitlesCount, 1);
      expect(item.missingLanguages.single.code2, 'it');
      expect(item.missingLanguages.single.hi, isTrue);
    });
  });
}
