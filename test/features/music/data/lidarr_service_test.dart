import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/fake_api_client.dart';

import '../../../test_helpers/settings_scope.dart';

void main() {
  group('lidarrServiceProvider', () {
    test('throws when Lidarr is not configured', () {
      final container = ProviderContainer(
        overrides: [
          currentSettingsProvider.overrideWith((ref) => const SettingsModel()),
        ],
      );
      addTearDown(container.dispose);

      expect(() => container.read(lidarrServiceProvider), throwsException);
    });

    test('returns a service when Lidarr is configured', () {
      final container = ProviderContainer(
        overrides: [
          currentSettingsProvider.overrideWith(
            (ref) => settingsWith(
              lidarrUrl: 'https://lidarr.example.com',
              lidarrApiKey: 'key',
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(lidarrServiceProvider), isA<LidarrService>());
    });
  });

  group('LidarrService', () {
    late FakeApiClient client;
    late LidarrService service;

    setUp(() {
      client = FakeApiClient();
      service = LidarrService(client);
    });

    test('uses the Lidarr API config', () {
      expect(service.config.apiVersion, 'v1');
      expect(service.config.sortKey, 'releaseDate');
    });

    test('getArtists fetches and maps artists', () async {
      client.getResponseData = [
        _artistJson(id: 1, artistName: 'The National'),
        _artistJson(id: 2, artistName: 'Mogwai'),
      ];

      final artists = await service.getArtists();

      expect(client.lastGetPath, '/api/v1/artist');
      expect(artists, hasLength(2));
      expect(artists.first.artistName, 'The National');
      expect(artists.last.id, 2);
    });

    test('getArtists returns empty list on error', () async {
      client.getException = Exception('boom');

      final artists = await service.getArtists();

      expect(artists, isEmpty);
    });

    test('getArtistById returns a typed artist on success', () async {
      client.getResponseData = _artistJson(id: 5, artistName: 'Band');

      final artist = await service.getArtistById(5);

      expect(client.lastGetPath, '/api/v1/artist/5');
      expect(artist?.id, 5);
      expect(artist?.artistName, 'Band');
    });

    test('getArtistById returns null on error', () async {
      client.getException = Exception('boom');

      final artist = await service.getArtistById(5);

      expect(artist, isNull);
    });

    test('getAlbums fetches albums for the artist', () async {
      client.getResponseData = [
        _albumJson(id: 10, title: 'Album 1', monitored: true),
        _albumJson(id: 11, title: 'Album 2', monitored: false),
      ];

      final albums = await service.getAlbums(7);

      expect(client.lastGetPath, '/api/v1/album');
      expect(client.lastGetQueryParameters, {'artistId': 7});
      expect(albums, hasLength(2));
      expect(albums.first.title, 'Album 1');
      expect(albums.last.monitored, isFalse);
    });

    test('getTracks fetches tracks for the album', () async {
      client.getResponseData = [
        _trackJson(id: 20, title: 'Track 1', duration: 180000),
      ];

      final tracks = await service.getTracks(10);

      expect(client.lastGetPath, '/api/v1/track');
      expect(client.lastGetQueryParameters, {'albumId': 10});
      expect(tracks, hasLength(1));
      expect(tracks.single.title, 'Track 1');
      expect(tracks.single.duration, 180000);
    });

    test('searchArtist posts the ArtistSearch command', () async {
      await service.searchArtist(1);

      expect(client.lastPostPath, '/api/v1/command');
      expect(client.lastPostData, {'name': 'ArtistSearch', 'artistId': 1});
    });

    test('searchAlbums posts the AlbumSearch command', () async {
      await service.searchAlbums([10, 11]);

      expect(client.lastPostPath, '/api/v1/command');
      expect(client.lastPostData, {
        'name': 'AlbumSearch',
        'albumIds': [10, 11],
      });
    });

    test('getQueue asks for the artist and the album it will print', () async {
      client.getResponseData = const [];

      await service.getQueue();

      expect(client.lastGetPath, '/api/v1/queue');
      expect(client.lastGetQueryParameters?['includeArtist'], isTrue);
      expect(client.lastGetQueryParameters?['includeAlbum'], isTrue);
    });

    test('getHistoryPage asks for the artist and the album', () async {
      client.getResponseData = const {'records': []};

      await service.getHistoryPage();

      expect(client.lastGetPath, '/api/v1/history');
      expect(client.lastGetQueryParameters?['includeArtist'], isTrue);
      expect(client.lastGetQueryParameters?['includeAlbum'], isTrue);
    });

    // The embeds hang off the **page** primitive so the record-only spelling
    // inherits them; hung off `getHistory` instead, every caller that reaches
    // for the envelope's total — which is every caller that prints a figure —
    // would get records with no `album` to fold on.
    test('getHistory inherits the embeds through the page primitive', () async {
      client.getResponseData = const {'records': []};

      await service.getHistory();

      expect(client.lastGetQueryParameters?['includeArtist'], isTrue);
      expect(client.lastGetQueryParameters?['includeAlbum'], isTrue);
    });

    test('a caller may still add its own history parameters', () async {
      client.getResponseData = const {'records': []};

      await service.getHistoryPage(
        queryParameters: const {
          'sortKey': 'date',
          'sortDirection': 'ascending',
        },
      );

      expect(client.lastGetQueryParameters?['includeArtist'], isTrue);
      expect(client.lastGetQueryParameters?['sortKey'], 'date');
      expect(client.lastGetQueryParameters?['sortDirection'], 'ascending');
    });

    test('getReleases passes artistId query params', () async {
      client.getResponseData = [
        {'title': 'Artist Release'},
      ];

      final releases = await service.getReleases(artistId: 1);

      expect(client.lastGetPath, '/api/v1/release');
      expect(client.lastGetQueryParameters, {'artistId': 1});
      expect(releases, hasLength(1));
    });

    test('getReleases passes albumId query params', () async {
      client.getResponseData = const [];

      await service.getReleases(albumId: 10);

      expect(client.lastGetQueryParameters, {'albumId': 10});
    });

    test('getReleases passes both artistId and albumId query params', () async {
      client.getResponseData = const [];

      await service.getReleases(artistId: 1, albumId: 10);

      expect(client.lastGetQueryParameters, {'artistId': 1, 'albumId': 10});
    });

    test('getReleases forwards the cancel token to ApiClient', () async {
      client.getResponseData = const [];
      final cancelToken = CancelToken();

      await service.getReleases(artistId: 1, cancelToken: cancelToken);

      expect(client.lastGetPath, '/api/v1/release');
      expect(client.lastGetQueryParameters, {'artistId': 1});
      expect(client.lastGetCancelToken, same(cancelToken));
    });

    test('grabRelease posts the release payload', () async {
      await service.grabRelease(guid: 'guid-123', indexerId: 9);

      expect(client.lastPostPath, '/api/v1/release');
      expect(client.lastPostData, {'guid': 'guid-123', 'indexerId': 9});
    });

    test('lookupArtists returns empty list for empty terms', () async {
      final artists = await service.lookupArtists('');

      expect(artists, isEmpty);
      expect(client.lastGetPath, isNull);
    });

    test('lookupArtists encodes the term and maps results', () async {
      client.getResponseData = [_artistJson(id: 3, artistName: 'Metallica')];

      final artists = await service.lookupArtists('metallica & friends');

      expect(client.lastGetPath, '/api/v1/artist/lookup');
      expect(client.lastGetQueryParameters, {
        'term': 'metallica%20%26%20friends',
      });
      expect(artists.single.artistName, 'Metallica');
    });

    test('lookupArtists forwards the cancel token to ApiClient', () async {
      client.getResponseData = const [];
      final cancelToken = CancelToken();

      await service.lookupArtists('metallica', cancelToken: cancelToken);

      // Global search re-runs this leg on every debounced keystroke; without a
      // token the superseded request runs to completion.
      expect(client.lastGetCancelToken, same(cancelToken));
    });

    test('getQualityProfiles returns mapped profiles', () async {
      client.getResponseData = [
        {'id': 1, 'name': 'Lossless'},
      ];

      final profiles = await service.getQualityProfiles();

      expect(client.lastGetPath, '/api/v1/qualityprofile');
      expect(profiles, [
        {'id': 1, 'name': 'Lossless'},
      ]);
    });

    test('updateArtistProfile fetches then updates the artist', () async {
      client.getResponseData = _artistJson(
        id: 3,
        artistName: 'Artist',
        qualityProfileId: 1,
      );

      await service.updateArtistProfile(3, 7);

      expect(client.lastGetPath, '/api/v1/artist/3');
      expect(client.lastPutPath, '/api/v1/artist/3');
      expect(client.lastPutData['qualityProfileId'], 7);
      expect(client.lastPutData['artistName'], 'Artist');
    });

    test('deleteArtist sends default delete params', () async {
      await service.deleteArtist(1);

      expect(client.lastDeletePath, '/api/v1/artist/1');
      expect(client.lastDeleteQueryParameters, {
        'deleteFiles': false,
        'addImportListExclusion': false,
      });
    });

    test('deleteArtist sends custom delete params', () async {
      await service.deleteArtist(
        1,
        deleteFiles: true,
        addImportListExclusion: true,
      );

      expect(client.lastDeleteQueryParameters, {
        'deleteFiles': true,
        'addImportListExclusion': true,
      });
    });

    group('addArtist', () {
      LidarrArtist lookupHit() => LidarrArtist.fromJson({
        // What `artist/lookup` sends for an artist the server does NOT have:
        // no library id, and the MusicBrainz id that names the artist
        // everywhere else. The model dropped that id until now, which is what
        // made an add impossible to build.
        'id': 0,
        'artistName': 'Boards of Canada',
        'foreignArtistId': '69158f97-4c07-4c4e-baf8-4e4ab1ed666e',
        'status': 'active',
        'monitored': false,
        'images': const [
          {'coverType': 'poster', 'url': '/MediaCover/Artists/0/poster.jpg'},
        ],
        'genres': const ['electronic'],
      });

      test('posts the lookup payload with the chosen options', () async {
        final client = FakeApiClient()
          ..postResponseData = {
            'id': 12,
            'artistName': 'Boards of Canada',
            'monitored': true,
            'images': const [],
          };
        final service = LidarrService(client);

        final added = await service.addArtist(
          lookupHit(),
          qualityProfileId: 2,
          metadataProfileId: 1,
          rootFolderPath: '/data/music',
          monitored: true,
          searchForMissingAlbums: true,
        );

        expect(client.lastPostPath, '/api/v1/artist');
        final body = client.lastPostData as Map<String, dynamic>;
        // The one field that makes this an add rather than a 400: Lidarr keys
        // an artist on the MusicBrainz id, not on the name.
        expect(body['foreignArtistId'], '69158f97-4c07-4c4e-baf8-4e4ab1ed666e');
        expect(body['artistName'], 'Boards of Canada');
        expect(body['qualityProfileId'], 2);
        // Lidarr's extra axis: an add without it is rejected outright.
        expect(body['metadataProfileId'], 1);
        expect(body['rootFolderPath'], '/data/music');
        expect(body['monitored'], isTrue);
        expect(body['addOptions'], {
          'monitored': true,
          'searchForMissingAlbums': true,
        });
        expect(added.id, 12);
      });

      test('a rejected add is not swallowed', () async {
        final client = FakeApiClient()
          ..postException = Exception('400 ArtistExistsValidator');
        final service = LidarrService(client);

        expect(
          service.addArtist(
            lookupHit(),
            qualityProfileId: 2,
            metadataProfileId: 1,
            rootFolderPath: '/data/music',
          ),
          throwsA(isA<Exception>()),
        );
      });

      test('fetchMetadataProfiles reads the axis Lidarr adds', () async {
        final client = FakeApiClient()
          ..getResponseData = [
            {'id': 1, 'name': 'Standard'},
            {'id': 2, 'name': 'Everything'},
          ];
        final service = LidarrService(client);

        final profiles = await service.fetchMetadataProfiles();

        expect(client.lastGetPath, '/api/v1/metadataprofile');
        expect(profiles.map((profile) => profile['name']), [
          'Standard',
          'Everything',
        ]);
      });
    });
  });
}

Map<String, dynamic> _artistJson({
  required int id,
  required String artistName,
  String status = 'active',
  bool monitored = true,
  int? qualityProfileId,
}) {
  return {
    'id': id,
    'artistName': artistName,
    'status': status,
    'monitored': monitored,
    'images': const [],
    'genres': const [],
    'qualityProfileId': ?qualityProfileId,
  };
}

Map<String, dynamic> _albumJson({
  required int id,
  required String title,
  required bool monitored,
}) {
  return {'id': id, 'title': title, 'monitored': monitored, 'images': const []};
}

Map<String, dynamic> _trackJson({
  required int id,
  required String title,
  required int duration,
}) {
  return {'id': id, 'title': title, 'hasFile': true, 'duration': duration};
}
