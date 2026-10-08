/// The four scores read from an arr's record when Seerr has none.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/features/media/domain/media_copies.dart';
import 'package:cupola/features/media/domain/media_reading.dart';
import 'package:cupola/features/media/domain/media_rows.dart';
import 'package:cupola/features/media/presentation/media_identity.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

void main() {
  test('Radarr\'s ratings fill the four, by their display names', () {
    final movie = RadarrMovie.fromJson({
      'id': 7,
      'title': 'Nosferatu',
      'tmdbId': 653,
      'year': 1922,
      'ratings': {
        'imdb': {'value': 7.8, 'votes': 113000},
        'tmdb': {'value': 7.6, 'votes': 2400},
        'metacritic': {'value': 91, 'votes': 0},
        'rottenTomatoes': {'value': 97, 'votes': 0},
      },
    });
    final rows = [
      MediaConnectionRow<MediaRadarrCopy>(
        const ServiceInstance(id: 'radarr', service: ServiceKey.radarr),
        MediaReadingAnswered(
          MediaAnswer(
            MediaRadarrCopy(movie: movie, queue: ArrQueueSnapshot.empty),
            DateTime(2026, 10, 3),
          ),
        ),
      ),
    ];

    final scores = mediaScoresOf(rows, MediaIdentity.of(rows));

    expect(scores.tmdb, 7.6);
    expect(scores.imdb, 7.8);
    expect(scores.rottenTomatoes, 97);
    expect(scores.metacritic, 91);
  });

  test('an average over a handful of votes reads as no score', () {
    final movie = RadarrMovie.fromJson({
      'id': 8,
      'title': 'Die Brad Pitt Story',
      'tmdbId': 1,
      'year': 2020,
      'ratings': {
        'imdb': {'value': 9.1, 'votes': 7},
        'tmdb': {'value': 10, 'votes': 1},
        'rottenTomatoes': {'value': 60, 'votes': 0},
      },
    });
    final rows = [
      MediaConnectionRow<MediaRadarrCopy>(
        const ServiceInstance(id: 'radarr', service: ServiceKey.radarr),
        MediaReadingAnswered(
          MediaAnswer(
            MediaRadarrCopy(movie: movie, queue: ArrQueueSnapshot.empty),
            DateTime(2026, 10, 8),
          ),
        ),
      ),
    ];

    final scores = mediaScoresOf(rows, MediaIdentity.of(rows));

    expect(scores.tmdb, isNull);
    expect(scores.imdb, isNull);
    // A critics' score carries no votes, and stands.
    expect(scores.rottenTomatoes, 60);
  });
}
