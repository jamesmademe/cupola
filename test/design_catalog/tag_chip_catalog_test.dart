@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/tag_chip.dart';

import 'catalog.dart';

// What a service page hands these widgets: its accent, which is the lamp.
const _sonarr = AppColors.lamp;
const _lidarr = AppColors.lamp;
const _bazarr = AppColors.lamp;

void main() {
  catalogCard(
    'TagChip',
    scenes: [
      CatalogScene(
        'TagChip · a service\'s accent (the lamp) at 12% under the primary '
        'ink, with and without a leading icon',
        (_) => const Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            TagChip(text: '3 seasons', color: _sonarr, icon: Icons.tv_rounded),
            TagChip(text: '12 albums', color: _lidarr),
            TagChip(text: '4K'),
            TagChip(text: 'All covered', color: _bazarr),
          ],
        ),
      ),
      CatalogScene(
        'GenreChip · neutral, outline-variant border, on-surface-variant label',
        (_) => const Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            GenreChip(genre: 'Drama'),
            GenreChip(genre: 'Thriller'),
            GenreChip(genre: 'Science Fiction'),
          ],
        ),
      ),
      CatalogScene(
        'TagChip(surface:) · the ground the chip lands on measures its ink — '
        'a card container here, not the page surface',
        (_) => SizedBox(
          width: 220,
          child: Builder(
            builder: (context) {
              final container = Theme.of(context).colorScheme.surfaceContainer;
              return AppCard.filled(
                child: TagChip(
                  text: 'Upgradable',
                  color: _sonarr,
                  surface: container,
                ),
              );
            },
          ),
        ),
      ),
    ],
  );
}
