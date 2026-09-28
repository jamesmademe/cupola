@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/cross_service_action.dart';

import 'catalog.dart';

Widget _gated(
  Widget Function(VoidCallback onPressed, Widget Function(Widget) annotate)
  build,
) => GatedAffordance.builder(
  enabled: false,
  hint: 'requires a read-write key',
  onTap: () {},
  onBlocked: () {},
  builder: (context, onPressed, annotate) => build(onPressed, annotate),
);

List<CatalogScene> _scenes(CatalogPlatform platform) => [
  CatalogScene(
    'FilledButton.icon · OutlinedButton · TextButton, as the theme draws them',
    (_) => Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        FilledButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.download_rounded),
          label: const Text('Grab'),
        ),
        OutlinedButton(
          onPressed: () {},
          child: const Text('Interactive search'),
        ),
        TextButton(onPressed: () {}, child: const Text('Open in qBittorrent')),
      ],
    ),
    platform: platform,
  ),
  CatalogScene(
    'GatedAffordance.builder(enabled: false) · label and glyph at 38%, '
    'container and target kept, still tappable',
    (_) => Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _gated(
          (onPressed, annotate) => FilledButton.icon(
            onPressed: onPressed,
            icon: annotate(const Icon(Icons.play_arrow_rounded)),
            label: annotate(const Text('Start')),
          ),
        ),
        _gated(
          (onPressed, annotate) => OutlinedButton(
            onPressed: onPressed,
            child: annotate(const Text('Update')),
          ),
        ),
        _gated(
          (onPressed, annotate) => TextButton(
            onPressed: onPressed,
            child: annotate(const Text('Renew')),
          ),
        ),
      ],
    ),
    platform: platform,
  ),
  CatalogScene(
    'onPressed: null · Material disabled, only where nothing the user can do '
    'would make it work',
    (_) => const Wrap(
      spacing: 12,
      children: [
        FilledButton(onPressed: null, child: Text('Grab')),
        OutlinedButton(onPressed: null, child: Text('Interactive search')),
      ],
    ),
    platform: platform,
  ),
];

void main() {
  catalogCard(
    'Button',
    scenes: [
      for (final platform in CatalogPlatform.values) ..._scenes(platform),
    ],
  );
}
