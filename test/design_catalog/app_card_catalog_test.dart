@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/app_card.dart';

import 'catalog.dart';

Widget _tile(String title, String subtitle) => Builder(
  builder: (context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 176,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall!.weight(FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  },
);

void main() {
  catalogCard(
    'AppCard',
    scenes: [
      CatalogScene(
        'AppCard.filled · .outlined · .surfaceOutlined · .elevated · '
        'non-tappable, no shadow unless elevated',
        (_) => Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            AppCard.filled(child: _tile('Nosferatu', 'Filled · flat panel')),
            AppCard.outlined(
              child: _tile('Metropolis', 'Outlined · transparent'),
            ),
            AppCard.surfaceOutlined(
              child: _tile(
                'The Cabinet of Dr. Caligari',
                'Surface outlined · outline-variant',
              ),
            ),
            AppCard.elevated(
              child: _tile('Sherlock Jr.', 'Elevated · level-2 shadow'),
            ),
          ],
        ),
      ),
      CatalogScene(
        'AppCard.elevated(accentColor:) · tappable, ink feedback · one '
        'signature card, glow at 22% from the top right',
        (_) => SizedBox(
          width: 220,
          child: AppCard.elevated(
            onTap: () {},
            accentColor: const Color(0xFFFFA000),
            semanticLabel: 'Nosferatu',
            semanticValue: 'Available',
            semanticHint: 'opens the movie',
            child: _tile('Nosferatu', 'Tap for details'),
          ),
        ),
      ),
      CatalogScene(
        "AppCard.filled(accentColor:, accentGlowAlpha: 0.08) · a grid cell's "
        'fraction of the same glow, three cells lit from the top left',
        (_) => Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final title in ['Nosferatu', 'Metropolis', 'Sherlock Jr.'])
              AppCard.filled(
                accentColor: const Color(0xFFFFA000),
                accentGlowAlpha: 0.08,
                accentGlowCenter: Alignment.topLeft,
                child: _tile(title, 'One cell of a matrix'),
              ),
          ],
        ),
      ),
      CatalogScene(
        'AppCard.outlined(pressFeedback: .scale) · tappable, dips to 0.97 with '
        'a light haptic · no ink ripple',
        (_) => SizedBox(
          width: 220,
          child: AppCard.outlined(
            onTap: () {},
            pressFeedback: AppCardPressFeedback.scale,
            semanticLabel: 'The Cabinet of Dr. Caligari',
            child: _tile('The Cabinet of Dr. Caligari', 'Dense grid cell'),
          ),
        ),
      ),
    ],
  );
}
