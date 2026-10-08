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

  test('the background is the backdrop, and an episode takes its show\'s', () {
    final movie = plexItemFromJson({
      'ratingKey': '7',
      'type': 'movie',
      'title': 'Sintel',
      'art': '/library/metadata/7/art/1',
    })!;
    expect(movie.backdropPath, isNotNull);
    expect(movie.backdropPath, contains('/library/metadata/7/art'));
    final episode = plexItemFromJson({
      'ratingKey': '9',
      'type': 'episode',
      'title': 'The Second Cycle',
      'art': '/library/metadata/9/art/1',
      'grandparentArt': '/library/metadata/3/art/1',
    })!;
    expect(episode.backdropPath, contains('/library/metadata/3/art'));
  });
}
