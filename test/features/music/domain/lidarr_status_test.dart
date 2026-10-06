import 'package:flutter_test/flutter_test.dart';
import 'package:cupola/features/music/domain/lidarr_status.dart';

import '../../../test_helpers/model_builders.dart';

void main() {
  group('lidarrAlbumSummary', () {
    test('states the manifest gap', () {
      expect(
        lidarrAlbumSummary(
          buildAlbum(
            statistics: const {'totalTrackCount': 12, 'trackFileCount': 7},
          ),
        ),
        '7 of 12 tracks',
      );
    });

    test('an album with no known tracks has no summary', () {
      expect(lidarrAlbumSummary(buildAlbum()), isNull);
    });
  });
}
