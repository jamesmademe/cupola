@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/status_badge.dart';

import 'catalog.dart';

const _states = <MediaStatusInfo>[
  MediaStatusInfo(availability: MediaAvailability.available),
  MediaStatusInfo(pipeline: MediaPipeline.downloading, progress: 0.42),
  MediaStatusInfo(pipeline: MediaPipeline.queued),
  MediaStatusInfo(pipeline: MediaPipeline.importPending),
  // A Seerr request awaiting approval, as resolveRequestStatus returns it.
  MediaStatusInfo(
    labelOverride: 'Waiting for approval',
    toneOverride: StatusTone.info,
  ),
  MediaStatusInfo(pipeline: MediaPipeline.stalled, progress: 0.61),
  MediaStatusInfo(pipeline: MediaPipeline.importBlocked),
  MediaStatusInfo(pipeline: MediaPipeline.failed),
  MediaStatusInfo(pipeline: MediaPipeline.clientUnavailable),
  MediaStatusInfo(availability: MediaAvailability.notTracked),
  MediaStatusInfo(availability: MediaAvailability.missing),
  MediaStatusInfo(availability: MediaAvailability.upgradable),
  MediaStatusInfo(pipeline: MediaPipeline.paused),
  MediaStatusInfo(availability: MediaAvailability.missing, unmonitored: true),
];

Widget _onPoster(Widget badge) => SizedBox(
  width: 120,
  height: 180,
  child: ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: Stack(
      fit: StackFit.expand,
      children: [
        Image(image: CatalogArt.posterImage, fit: BoxFit.cover),
        Positioned(top: 8, right: 8, child: badge),
      ],
    ),
  ),
);

void main() {
  catalogCard(
    'StatusBadge',
    scenes: [
      CatalogScene(
        'StatusBadge() · every arm of the tone rule: green, blue, amber, red, '
        'neutral',
        (_) => Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [for (final info in _states) StatusBadge(info: info)],
        ),
      ),
      CatalogScene(
        'StatusBadge(compact: true) over artwork · downloading, available, '
        'stalled; then StatusBadge(iconOnly: true)',
        (_) => Wrap(
          spacing: 12,
          children: [
            _onPoster(
              const StatusBadge(
                info: MediaStatusInfo(
                  pipeline: MediaPipeline.downloading,
                  progress: 0.42,
                ),
                compact: true,
              ),
            ),
            _onPoster(
              const StatusBadge(
                info: MediaStatusInfo(
                  availability: MediaAvailability.available,
                ),
                compact: true,
              ),
            ),
            _onPoster(
              const StatusBadge(
                info: MediaStatusInfo(pipeline: MediaPipeline.stalled),
                compact: true,
              ),
            ),
            _onPoster(
              const StatusBadge(
                info: MediaStatusInfo(
                  availability: MediaAvailability.available,
                ),
                iconOnly: true,
              ),
            ),
          ],
        ),
      ),
      CatalogScene(
        'Text at 200% · every arm of the tone rule, and a long label '
        '(Waiting for approval), at twice the reading size',
        (_) => Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [for (final info in _states) StatusBadge(info: info)],
        ),
        width: 390,
        textScale: catalogTextScale,
      ),
      CatalogScene(
        'A long label · a label of forty characters and a downloading figure, '
        'each badge in a 150pt room',
        (_) => const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StatusBadge(
              info: MediaStatusInfo(
                labelOverride: 'Waiting for approval from the household',
                toneOverride: StatusTone.info,
              ),
            ),
            SizedBox(height: 8),
            StatusBadge(
              info: MediaStatusInfo(
                pipeline: MediaPipeline.downloading,
                progress: 0.42,
              ),
            ),
          ],
        ),
        width: 150,
      ),
    ],
  );
}
