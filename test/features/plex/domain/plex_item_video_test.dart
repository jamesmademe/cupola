import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/plex/domain/models/plex_item_mapper.dart';

void main() {
  test('a list read carries the frame of the first version, not its range', () {
    final item = plexItemFromJson({
      'ratingKey': '7',
      'type': 'movie',
      'title': 'Sintel',
      'Media': [
        {'width': 1920, 'height': 818, 'videoResolution': '1080'},
      ],
    })!;
    expect(item.video?.words, '1080p');
  });

  test('no Media, no picture', () {
    final item = plexItemFromJson({
      'ratingKey': '7',
      'type': 'movie',
      'title': 'Sintel',
    })!;
    expect(item.video, isNull);
  });
}
