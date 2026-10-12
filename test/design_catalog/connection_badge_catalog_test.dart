@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/widgets/connection_badge.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import 'catalog.dart';

Widget _row(String title, String label, String status) => Builder(
  builder: (context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTheme.rowTitle(Theme.of(context).brightness),
        ),
      ),
      const SizedBox(width: AppSpacing.md),
      StatusBadge(
        info: switch (status) {
          'downloading' => const MediaStatusInfo(
            pipeline: MediaPipeline.downloading,
            progress: 0.3,
          ),
          _ => const MediaStatusInfo(availability: MediaAvailability.available),
        },
      ),
      const SizedBox(width: AppSpacing.sm),
      ConnectionBadge(label: label, accent: ServiceKey.radarr.accent),
    ],
  ),
);

void main() {
  catalogCard(
    'ConnectionBadge',
    scenes: [
      CatalogScene(
        'ConnectionBadge · four services, on scheme.surface · the same '
        'neutral pill for every service: the accent is the lamp, its label ink',
        (_) => Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            ConnectionBadge(label: '4K', accent: ServiceKey.radarr.accent),
            ConnectionBadge(label: 'Main', accent: ServiceKey.radarr.accent),
            ConnectionBadge(label: 'Anime', accent: ServiceKey.sonarr.accent),
            ConnectionBadge(
              label: 'Seedbox',
              accent: ServiceKey.qbittorrent.accent,
            ),
          ],
        ),
      ),
      CatalogScene(
        'ConnectionBadge(surface: colorScheme.surfaceContainer) · on a card, '
        'the ground passed explicitly',
        (context) => Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          color: Theme.of(context).colorScheme.surfaceContainer,
          child: Wrap(
            spacing: 12,
            children: [
              ConnectionBadge(
                label: '4K',
                accent: ServiceKey.radarr.accent,
                surface: Theme.of(context).colorScheme.surfaceContainer,
              ),
              ConnectionBadge(
                label: 'Anime',
                accent: ServiceKey.sonarr.accent,
                surface: Theme.of(context).colorScheme.surfaceContainer,
              ),
            ],
          ),
        ),
      ),
      CatalogScene(
        "label: '' · renders nothing, a single connection grows no badge",
        (_) => Wrap(
          spacing: 12,
          children: [
            ConnectionBadge(label: '', accent: ServiceKey.sonarr.accent),
            const Text('(nothing drawn to the left)'),
          ],
        ),
      ),
      CatalogScene(
        'Activity row shape · StatusBadge, then ConnectionBadge naming which '
        'of two Radarr connections the row came from',
        (_) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row('Nosferatu (1922)', '4K', 'downloading'),
            const SizedBox(height: AppSpacing.sm),
            _row('Metropolis (1927)', 'Main', 'available'),
          ],
        ),
        width: 420,
      ),
      CatalogScene(
        'Text at 200% · the pill, and the Activity row shape: the badge grows '
        'with its label and the title gives way',
        (_) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ConnectionBadge(label: '4K', accent: ServiceKey.radarr.accent),
            const SizedBox(height: AppSpacing.sm),
            _row('Nosferatu (1922)', '4K', 'downloading'),
            const SizedBox(height: AppSpacing.sm),
            _row('Metropolis (1927)', 'Main', 'available'),
          ],
        ),
        width: 420,
        textScale: catalogTextScale,
      ),
      CatalogScene(
        'A long label · a connection named for where it lives, in the '
        'Activity row shape on a 320pt phone',
        (_) => _row('Nosferatu (1922)', 'Living room seedbox', 'downloading'),
        width: 320,
      ),
    ],
  );
}
