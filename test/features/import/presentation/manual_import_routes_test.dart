import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/import/presentation/manual_import_routes.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

void main() {
  group('manualImportLocation', () {
    test('encodes the folder path for the Activity fast-path', () {
      final location = manualImportLocation(
        manualImportBrowsePath,
        ServiceKey.radarr,
        folderPath: '/downloads/complete/Movie (2024)',
      );
      final uri = Uri.parse(location);
      expect(uri.path, manualImportBrowsePath);
      expect(uri.queryParameters['service'], 'radarr');
      expect(uri.queryParameters['path'], '/downloads/complete/Movie (2024)');
    });

    test('omits empty optional parameters', () {
      final uri = Uri.parse(
        manualImportLocation(manualImportReviewPath, ServiceKey.sonarr),
      );
      expect(uri.queryParameters.keys, ['service']);
    });

    test('carries the connection the flow is bound to', () {
      // The rule: a wizard opened on one connection must still be that
      // connection one station later. Without the parameter the next screen
      // re-resolves through the lens and can move the files into the other
      // server's library.
      final uri = Uri.parse(
        manualImportLocation(
          manualImportBrowsePath,
          ServiceKey.radarr,
          instanceId: 'radarr-4k',
        ),
      );
      expect(uri.queryParameters['i'], 'radarr-4k');
    });

    test('an unnamed connection stays unnamed', () {
      // Empty means "the lens", which is what every link written before the
      // parameter existed means, and it must not become the literal id ''.
      for (final id in const [null, '']) {
        final uri = Uri.parse(
          manualImportLocation(
            manualImportBrowsePath,
            ServiceKey.radarr,
            instanceId: id,
          ),
        );
        expect(uri.queryParameters.containsKey('i'), isFalse);
      }
    });
  });

  group('manualImportFolderFromOutputPath', () {
    test('keeps a folder path as-is', () {
      expect(
        manualImportFolderFromOutputPath('/downloads/complete/Movie (2024)'),
        '/downloads/complete/Movie (2024)',
      );
    });

    test('trims a trailing separator', () {
      expect(
        manualImportFolderFromOutputPath('/downloads/complete/'),
        '/downloads/complete',
      );
    });

    test('trims a file path to its parent folder', () {
      expect(
        manualImportFolderFromOutputPath('/downloads/complete/Movie.mkv'),
        '/downloads/complete',
      );
    });

    test('does not mistake a dotted folder name for a file', () {
      expect(
        manualImportFolderFromOutputPath(
          '/downloads/Movie.2024.1080p.BluRay.x264-GROUP',
        ),
        '/downloads/Movie.2024.1080p.BluRay.x264-GROUP',
      );
    });

    test('preserves Windows separators', () {
      expect(
        manualImportFolderFromOutputPath(r'C:\downloads\complete\Movie.mkv'),
        r'C:\downloads\complete',
      );
    });

    test('returns null for null or empty input', () {
      expect(manualImportFolderFromOutputPath(null), isNull);
      expect(manualImportFolderFromOutputPath('  '), isNull);
    });
  });
}
