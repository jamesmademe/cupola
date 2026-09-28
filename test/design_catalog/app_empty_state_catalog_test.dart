@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/app_empty_state.dart';

import 'catalog.dart';

const _sonarr = Color(0xFF7C4DFF);

void main() {
  catalogCard(
    'AppEmptyState',
    scenes: [
      CatalogScene(
        'AppEmptyState() · full, neutral well, with an action',
        (_) => AppEmptyState(
          icon: Icons.search_off_rounded,
          title: 'No results found',
          message: 'Try a different title or spelling.',
          action: FilledButton(
            onPressed: () {},
            child: const Text('Clear search'),
          ),
        ),
        width: 320,
      ),
      CatalogScene(
        'AppEmptyState.compact(accentColor:) · smaller, an accent-tinted well',
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
    ],
  );
}
