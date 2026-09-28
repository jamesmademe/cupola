@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/widgets/connection_badge.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/core/theme.dart';

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
      ConnectionBadge(label: label, accent: AppColors.radarr),
    ],
  ),
);

void main() {
  catalogCard(
    'ConnectionBadge',
    scenes: [
      CatalogScene(
        'ConnectionBadge · four services, on scheme.surface',
        (_) => const Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            ConnectionBadge(label: '4K', accent: AppColors.radarr),
            ConnectionBadge(label: 'Main', accent: AppColors.radarr),
            ConnectionBadge(label: 'Anime', accent: AppColors.sonarr),
            ConnectionBadge(label: 'Seedbox', accent: AppColors.qbittorrent),
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
                accent: AppColors.radarr,
                surface: Theme.of(context).colorScheme.surfaceContainer,
              ),
              ConnectionBadge(
                label: 'Anime',
                accent: AppColors.sonarr,
                surface: Theme.of(context).colorScheme.surfaceContainer,
              ),
            ],
          ),
        ),
      ),
      CatalogScene(
        "label: '' · renders nothing — a single connection grows no badge",
        (_) => const Wrap(
          spacing: 12,
          children: [
            ConnectionBadge(label: '', accent: AppColors.sonarr),
            Text('(nothing drawn to the left)'),
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
    ],
  );
}
