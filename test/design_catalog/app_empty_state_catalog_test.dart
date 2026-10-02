@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/app_empty_state.dart';

import 'catalog.dart';

// What a service page hands these widgets: its accent, which is the lamp.
const _sonarr = AppColors.lamp;

void main() {
  catalogCard(
    'AppEmptyState',
    scenes: [
      CatalogScene(
        'AppEmptyState() · full, neutral well, with an action',
        (_) => AppEmptyState(
          icon: Icons.search_off_rounded,
          title: 'No results',
          message: 'Try a different title or spelling.',
          action: FilledButton(
            onPressed: () {},
            child: const Text('Clear search'),
          ),
        ),
        width: 320,
      ),
      CatalogScene(
        'AppEmptyState.compact(accentColor:) · smaller, a lamp-tinted well '
        '(a service\'s accent is the lamp)',
        (_) => const AppEmptyState.compact(
          icon: Icons.tv_rounded,
          title: 'No seasons yet',
          message: 'Sonarr lists nothing under Specials yet.',
          accentColor: _sonarr,
        ),
        width: 280,
      ),
      CatalogScene(
        'AppEmptyState.inline · one left-aligned line beside a small glyph, no '
        'action — for an expected absence, not a failure',
        (_) => const AppEmptyState.inline(
          icon: Icons.info_outline_rounded,
          title: 'Nothing trusted yet',
          message: 'No certificates have been pinned for this connection.',
        ),
        width: 340,
      ),
      CatalogScene(
        'Text at 200% · full, compact and inline, at twice the reading size',
        (_) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppEmptyState(
              icon: Icons.search_off_rounded,
              title: 'No results',
              message: 'Try a different title or spelling.',
              action: FilledButton(
                onPressed: () {},
                child: const Text('Clear search'),
              ),
            ),
            const AppEmptyState.compact(
              icon: Icons.tv_rounded,
              title: 'No seasons yet',
              message: 'Sonarr lists nothing under Specials yet.',
              accentColor: _sonarr,
            ),
            const AppEmptyState.inline(
              icon: Icons.info_outline_rounded,
              title: 'Nothing trusted yet',
              message: 'No certificates have been pinned for this connection.',
            ),
          ],
        ),
        width: 340,
        textScale: catalogTextScale,
      ),
      CatalogScene(
        'A long title and message · the full state on a 280pt phone',
        (_) => const AppEmptyState(
          icon: Icons.movie_filter_rounded,
          title: 'Nothing matches the filters you have chosen',
          message:
              'Clear one of the quality, language or release group filters, or '
              'widen the date range, and the movies that were hidden come back.',
        ),
        width: 280,
      ),
    ],
  );
}
