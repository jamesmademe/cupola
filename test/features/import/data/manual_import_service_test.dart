import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/features/import/data/manual_import_service.dart';
import 'package:cupola/features/import/domain/manual_import_models.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/fake_api_client.dart';

void main() {
  group('ManualImportService.startManualImport', () {
    test(
      'regression guard: bulk import still posts to /command with files list',
      () async {
        final client = FakeApiClient();
        client.postResponseData = {
          'id': 1,
          'name': 'ManualImport',
          'status': 'queued',
        };
        final service = ManualImportService(
          client: client,
          service: ServiceKey.radarr,
        );
        final itemA = ManualImportItem.fromJson({
          'path': '/downloads/a.mkv',
          'name': 'a.mkv',
          'movie': {'id': 1, 'title': 'A'},
        });
        final itemB = ManualImportItem.fromJson({
          'path': '/downloads/b.mkv',
          'name': 'b.mkv',
          'movie': {'id': 2, 'title': 'B'},
        });

        await service.startManualImport([
          itemA,
          itemB,
        ], importMode: ManualImportMode.auto);

        expect(client.lastPostPath, '/api/v3/command');
        final body = client.lastPostData as Map<String, dynamic>;
        expect(body['name'], 'ManualImport');
        expect(body['importMode'], 'auto');
        expect((body['files'] as List).length, 2);
      },
    );
  });

  group('ManualImportService scan timeouts', () {
    test(
      'getManualImportItems asks for the slow-scan receive timeout',
      () async {
        final client = FakeApiClient();
        client.getResponseData = const [];
        final service = ManualImportService(
          client: client,
          service: ServiceKey.sonarr,
        );

        await service.getManualImportItems(folder: '/downloads/complete');

        expect(client.lastGetPath, '/api/v3/manualimport');
        // The default 15s ceiling fires long before Sonarr finishes walking the
        // folder and probing each file, which surfaced as a bogus
        // "couldn't reach Sonarr" error.
        expect(client.lastGetReceiveTimeout, kSlowScanReceiveTimeout);
      },
    );

    test('getFileSystem asks for the slow-scan receive timeout', () async {
      final client = FakeApiClient();
      client.getResponseData = const {'directories': [], 'files': []};
      final service = ManualImportService(
        client: client,
        service: ServiceKey.radarr,
      );

      await service.getFileSystem('/mnt/media');

      expect(client.lastGetPath, '/api/v3/filesystem');
      expect(client.lastGetReceiveTimeout, kSlowScanReceiveTimeout);
    });

    test('getLibraryMatches asks for the slow-scan receive timeout', () async {
      final client = FakeApiClient();
      client.getResponseData = const [];
      final service = ManualImportService(
        client: client,
        service: ServiceKey.sonarr,
      );

      await service.getLibraryMatches();

      expect(client.lastGetPath, '/api/v3/series');
      expect(client.lastGetReceiveTimeout, kSlowScanReceiveTimeout);
    });
  });

  group('ManualImportService.getDownloadImportItems', () {
    test('reads a download by its id alone, never with the title\'s id: '
        'Sonarr then walks the series folder, and a new series has none '
        'yet', () async {
      final client = FakeApiClient();
      client.getResponseData = const [];
      final service = ManualImportService(
        client: client,
        service: ServiceKey.sonarr,
      );

      await service.getDownloadImportItems(downloadId: 'EE94CCA3');

      expect(client.lastGetPath, '/api/v3/manualimport');
      expect(client.lastGetQueryParameters, {
        'downloadId': 'EE94CCA3',
        'filterExistingFiles': true,
      });
    });
  });

  group('ManualImportService.startManualImport replace flag', () {
    final item = ManualImportItem.fromJson({
      'path': '/downloads/a.flac',
      'name': 'a.flac',
    });

    test('Lidarr carries replaceExistingFiles: without it a deliberate '
        're-import quietly does nothing', () async {
      final client = FakeApiClient();
      client.postResponseData = {'id': 4, 'name': 'ManualImport'};
      final service = ManualImportService(
        client: client,
        service: ServiceKey.lidarr,
      );

      await service.startManualImport(
        [item],
        importMode: ManualImportMode.move,
        replaceExistingFiles: true,
      );

      expect(client.lastPostPath, '/api/v1/command');
      final body = client.lastPostData as Map<String, dynamic>;
      expect(body['replaceExistingFiles'], isTrue);
      expect(body['importMode'], ManualImportMode.move.apiValue);
    });

    test('Radarr and Sonarr decide per file, so the flag stays out', () async {
      for (final key in [ServiceKey.radarr, ServiceKey.sonarr]) {
        final client = FakeApiClient();
        client.postResponseData = {'id': 4, 'name': 'ManualImport'};
        await ManualImportService(
          client: client,
          service: key,
        ).startManualImport(
          [item],
          importMode: ManualImportMode.auto,
          replaceExistingFiles: true,
        );

        final body = client.lastPostData as Map<String, dynamic>;
        expect(
          body.containsKey('replaceExistingFiles'),
          isFalse,
          reason: '$key',
        );
      }
    });
  });

  group('ManualImportService lookup and library', () {
    test('each service looks titles up at its own endpoint', () async {
      const endpoints = {
        ServiceKey.radarr: '/api/v3/movie/lookup',
        ServiceKey.sonarr: '/api/v3/series/lookup',
        ServiceKey.lidarr: '/api/v1/artist/lookup',
      };
      for (final MapEntry(:key, :value) in endpoints.entries) {
        final client = FakeApiClient();
        client.getResponseData = const [];
        await ManualImportService(client: client, service: key).lookup('dune');

        expect(client.lastGetPath, value, reason: '$key');
        expect(client.lastGetQueryParameters, {'term': 'dune'});
      }
    });

    test('a blank term asks the server nothing', () async {
      final client = FakeApiClient();
      final service = ManualImportService(
        client: client,
        service: ServiceKey.radarr,
      );

      expect(await service.lookup('   '), isEmpty);
      expect(client.getCallCount, 0);
    });

    test('the term is trimmed and results without an id are dropped: a '
        'lookup hit not in the library yet cannot take a file', () async {
      final client = FakeApiClient();
      client.getResponseData = [
        {'id': 12, 'title': 'Dune'},
        {'id': 0, 'title': 'Dune (1984)'},
        {'title': 'Dune Messiah'},
      ];
      final results = await ManualImportService(
        client: client,
        service: ServiceKey.radarr,
      ).lookup('  dune ');

      expect(client.lastGetQueryParameters, {'term': 'dune'});
      expect(results.map((result) => result.id), [12]);
    });

    test('each service reads its whole library, slowly', () async {
      const endpoints = {
        ServiceKey.radarr: '/api/v3/movie',
        ServiceKey.sonarr: '/api/v3/series',
        ServiceKey.lidarr: '/api/v1/artist',
      };
      for (final MapEntry(:key, :value) in endpoints.entries) {
        final client = FakeApiClient();
        client.getResponseData = [
          {'id': 3, 'title': 'Kept', 'artistName': 'Kept'},
          {'id': 0, 'title': 'Dropped'},
        ];
        final matches = await ManualImportService(
          client: client,
          service: key,
        ).getLibraryMatches();

        expect(client.lastGetPath, value, reason: '$key');
        expect(matches.map((match) => match.id), [3], reason: '$key');
      }
    });

    test('a service without manual import refuses lookup', () {
      final service = ManualImportService(
        client: FakeApiClient(),
        service: ServiceKey.readarr,
      );

      expect(() => service.lookup('dune'), throwsArgumentError);
      expect(service.getLibraryMatches, throwsArgumentError);
    });
  });

  group('ManualImportService pickers', () {
    late FakeApiClient client;
    late ManualImportService lidarr;

    setUp(() {
      client = FakeApiClient();
      lidarr = ManualImportService(client: client, service: ServiceKey.lidarr);
    });

    test('albums are read by artist, without the ones lacking an id', () async {
      client.getResponseData = [
        {'id': 5, 'title': 'Kid A'},
        {'id': 0, 'title': 'Ghost'},
      ];

      final albums = await lidarr.getAlbums(9);

      expect(client.lastGetPath, '/api/v1/album');
      expect(client.lastGetQueryParameters, {'artistId': 9});
      expect(albums.map((album) => album.id), [5]);
    });

    test('tracks are read by album, without the ones lacking an id', () async {
      client.getResponseData = [
        {'id': 7, 'title': 'Idioteque', 'trackNumber': 8},
        {'title': 'Ghost'},
      ];

      final tracks = await lidarr.getTracks(albumId: 5);

      expect(client.lastGetPath, '/api/v1/track');
      expect(client.lastGetQueryParameters, {'albumId': 5});
      expect(tracks.map((track) => track.id), [7]);
    });

    test('quality options take the id of the quality they define', () async {
      client.getResponseData = [
        {
          'id': 1,
          'title': 'FLAC',
          'quality': {'id': 6, 'name': 'FLAC'},
        },
        {
          'id': 0,
          'quality': {'id': 0, 'name': 'Unknown'},
        },
      ];

      final options = await lidarr.getQualityOptions();

      expect(client.lastGetPath, '/api/v1/qualitydefinition');
      expect(options.map((option) => option.id), [6]);
    });

    test('language options drop the ones lacking an id', () async {
      client.getResponseData = [
        {'id': 1, 'name': 'English'},
        {'id': 0, 'name': 'Unknown'},
      ];

      final options = await lidarr.getLanguageOptions();

      expect(client.lastGetPath, '/api/v1/language');
      expect(options.map((option) => option.name), ['English']);
    });

    test('a command is read back by its id', () async {
      client.getResponseData = {
        'id': 42,
        'name': 'ManualImport',
        'status': 'completed',
      };

      final status = await lidarr.getCommand(42);

      expect(client.lastGetPath, '/api/v1/command/42');
      expect(status.id, 42);
    });
  });
}
