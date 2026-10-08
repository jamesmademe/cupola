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

  group("TMDB's score, as a list draws it", () {
    MediaPreview rated(double average, int? votes) => MediaPreview.fromJson({
      'id': 1,
      'title': 'Caligari',
      'mediaType': 'movie',
      'voteAverage': average,
      'voteCount': ?votes,
    });

    test('an average over enough votes is drawn', () {
      expect(rated(7.2, 23).tmdbScore, 7.2);
      expect(rated(7.2, 23).voteCount, 23);
    });

    test('a 10 from one vote is one opinion, and is not', () {
      expect(rated(10, 1).tmdbScore, isNull);
      expect(rated(8, 19).tmdbScore, isNull);
    });

    test("TMDB's zero is nobody's rating", () {
      expect(rated(0, 0).tmdbScore, isNull);
    });

    test('a count the answer did not send hides nothing', () {
      expect(rated(7.2, null).tmdbScore, 7.2);
    });
  });
}
