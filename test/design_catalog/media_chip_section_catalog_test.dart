@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/media_chip_section.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import 'catalog.dart';

const _genres = ['Horror', 'Fantasy', 'Drama'];

const _keywords = [
  'vampire',
  'silent film',
  'german expressionism',
  'plague',
  'transylvania',
  'based on novel or book',
  'shadow',
];

/// A detail column on a phone: the 390 screen less the 16 gutters.
Widget _column(Widget child) => SizedBox(width: 358, child: child);

void main() {
  catalogCard(
    'MediaChipSection',
    scenes: [
      CatalogScene(
        'MediaChipSection.neutral · genres · surface-container pills with an '
        'outline-variant edge, no accent',
        (_) => _column(const MediaChipSection.neutral(values: _genres)),
      ),
      CatalogScene(
        'MediaChipSection.neutral · TMDB keywords, wrapping at the phone '
        'column · space-sm between chips and between runs',
        (_) => _column(const MediaChipSection.neutral(values: _keywords)),
      ),
      CatalogScene(
        'MediaChipSection.accented · Radarr tags · the page accent is the '
        'lamp: a 12% lamp wash under a primary-ink label, no hue',
        (_) => _column(
          MediaChipSection.accented(
            values: const ['4k', 'family', 'watchlist'],
            accent: ServiceKey.radarr.accent,
          ),
        ),
      ),
      CatalogScene(
        'MediaChipSection.accented · Sonarr and Bazarr tags · the same chip on '
        'every service',
        (_) => _column(
          Wrap(
            spacing: 24,
            runSpacing: 12,
            children: [
              MediaChipSection.accented(
                values: const ['anime', 'hdr', 'silent-era'],
                accent: ServiceKey.sonarr.accent,
              ),
              MediaChipSection.accented(
                values: const ['subtitles-de', 'intertitles'],
                accent: ServiceKey.bazarr.accent,
              ),
            ],
          ),
        ),
      ),
      CatalogScene(
        'MediaChipSection.neutral, then .accented · the desktop column',
        (_) => SizedBox(
          width: 720,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const MediaChipSection.neutral(values: _keywords),
              const SizedBox(height: 16),
              MediaChipSection.accented(
                values: const ['4k', 'family', 'watchlist'],
                accent: ServiceKey.radarr.accent,
              ),
            ],
          ),
        ),
        platform: CatalogPlatform.desktop,
      ),
    ],
  );
}
