import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/models/media_preview.dart';

void main() {
  test("keeps what Seerr holds of a title, as Seerr sent it", () {
    final preview = MediaPreview.fromJson({
      'id': 45745,
      'title': 'Sintel',
      'mediaType': 'movie',
      'mediaInfo': {'status': 5, 'status4k': 1},
    });

    expect(preview.mediaInfo, {'status': 5, 'status4k': 1});
  });

  test('holds nothing for a title Seerr holds nothing of', () {
    final preview = MediaPreview.fromJson({
      'id': 1,
      'title': 'Caligari',
      'mediaType': 'movie',
    });

    expect(preview.mediaInfo, isNull);
  });
}
