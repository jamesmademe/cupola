@Tags(['catalog'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/models/rating_source.dart';
import 'package:cupola/core/utils/rating_display.dart';
import 'package:cupola/core/widgets/media_metadata_line.dart';
import 'package:cupola/core/widgets/rating_chips_row.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import 'catalog.dart';

void main() {
  catalogCard(
    'RatingChip',
    width: 640,
    scenes: [
      CatalogScene(
        'RatingChipsRow · Radarr, each source on its own scale — IMDb /10, '
        'TMDB /10, Metacritic /100, Rotten Tomatoes %',
        (_) => RatingChipsRow(
          accent: ServiceKey.radarr.accent,
          ratings: legibleRatings(const [
            RatingSource(name: 'imdb', value: 8.6, votes: 512300, icon: 'imdb'),
            RatingSource(name: 'tmdb', value: 8.2, votes: 5120, icon: 'tmdb'),
            RatingSource(name: 'mc', value: 79, votes: 0, icon: 'mc'),
            RatingSource(name: 'ro', value: 92, votes: 0, icon: 'ro'),
          ]),
        ),
      ),
      CatalogScene(
        'RatingChipsRow · Sonarr, a single-source payload — one pill, votes '
        'under 1,000 print the plain count',
        (_) => RatingChipsRow(
          accent: ServiceKey.sonarr.accent,
          ratings: legibleRatings(const [
            RatingSource(name: 'tvdb', value: 8.4, votes: 842, icon: 'tvdb'),
          ]),
        ),
      ),
      CatalogScene(
        'RatingChipsRow(accent: null) · no page accent, the primary ink',
        (_) => RatingChipsRow(
          ratings: legibleRatings(const [
            RatingSource(name: 'tmdb', value: 7.1, votes: 842, icon: 'tmdb'),
          ]),
        ),
      ),
      CatalogScene(
        'RatingChipsRow · an unreleased source (0.0, 0 votes) is dropped — only '
        'the two scored sources render',
        (_) => RatingChipsRow(
          accent: ServiceKey.radarr.accent,
          ratings: legibleRatings(const [
            RatingSource(name: 'imdb', value: 7.4, votes: 1800, icon: 'imdb'),
            RatingSource(name: 'tmdb', value: 0, votes: 0, icon: 'tmdb'),
            RatingSource(name: 'mc', value: 61, votes: 0, icon: 'mc'),
          ]),
        ),
      ),
      CatalogScene(
        'MediaMetadataLine · the hero fact line, non-empty items joined with '
        'the house middot',
        (_) => const MediaMetadataLine(
          items: ['1922', '1\u00A0h 34\u00A0min', 'Horror'],
        ),
      ),
    ],
  );
}
