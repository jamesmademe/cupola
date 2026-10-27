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
}
