@Tags(['catalog'])
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/utils/rating_display.dart';
import 'package:cupola/core/widgets/media_metadata_line.dart';
import 'package:cupola/core/widgets/rating_chip.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import 'catalog.dart';

/// One pill the way a score reaches it: the source named in full and the value
/// on its own scale, as `ratingSourceLabel` and `ratingDisplayFor` decide.
Widget _pill(String key, double value, int votes, {Color? accent}) {
  final label = ratingSourceLabel(icon: key, name: key);
  final display = ratingDisplayFor(icon: key, name: key, value: value);
  return RatingChip(
    value: display.value,
    denominator: display.denominator,
    votes: votes,
    sourceName: label,
    sourceIcon: label,
    accent: accent,
  );
}

/// The pills in a wrapping row, `space-xs` both ways.
Widget _pills(List<Widget> pills) =>
    Wrap(spacing: AppSpacing.xs, runSpacing: AppSpacing.xs, children: pills);

List<Widget> _radarr() {
  final accent = ServiceKey.radarr.accent;
  return [
    _pill('imdb', 8.6, 512300, accent: accent),
    _pill('tmdb', 8.2, 5120, accent: accent),
    _pill('mc', 79, 0, accent: accent),
    _pill('ro', 92, 0, accent: accent),
  ];
}

void main() {
  catalogCard(
    'RatingChip',
    width: 640,
    scenes: [
      CatalogScene(
        'RatingChip · Radarr, each source on its own scale — IMDb /10, '
        'TMDB /10, Metacritic /100, Rotten Tomatoes %',
        (_) => _pills(_radarr()),
      ),
      CatalogScene(
        'RatingChip · Sonarr, a single-source payload — one pill, votes '
        'under 1,000 print the plain count',
        (_) =>
            _pills([_pill('tvdb', 8.4, 842, accent: ServiceKey.sonarr.accent)]),
      ),
      CatalogScene(
        'RatingChip(accent: null) · no page accent, the primary ink',
        (_) => _pills([_pill('tmdb', 7.1, 842)]),
      ),
      CatalogScene(
        'MediaMetadataLine · the hero fact line, non-empty items joined with '
        'the house middot',
        (_) => const MediaMetadataLine(
          items: ['1922', '1\u00A0h 34\u00A0min', 'Horror'],
        ),
      ),
      CatalogScene(
        'Text at 200% · the four sources and the fact line on a 390pt phone: '
        'the pills wrap onto more runs',
        (_) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _pills(_radarr()),
            const SizedBox(height: 12),
            const MediaMetadataLine(
              items: ['1922', '1\u00A0h 34\u00A0min', 'Horror'],
            ),
          ],
        ),
        width: 390,
        textScale: catalogTextScale,
      ),
    ],
  );
}
