@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/tag_chip.dart';

import 'catalog.dart';

const _sonarr = Color(0xFF7C4DFF);
const _lidarr = Color(0xFF00BFA5);
const _bazarr = Color(0xFF3F51B5);

void main() {
  catalogCard(
    'TagChip',
    scenes: [
      CatalogScene(
        'TagChip · service accent at 12%, with and without a leading icon',
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
