@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/cross_service_action.dart';
import 'package:cupola/core/widgets/failure_remedy.dart';

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
    'FloatingActionButton · .extended · the ink button, floating: a screen\'s '
    'one floating action is its primary, never a service\'s colour',
    (_) => Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FloatingActionButton(
          heroTag: null,
          onPressed: () {},
          tooltip: 'New',
          child: const Icon(Icons.add_rounded),
        ),
        FloatingActionButton.extended(
          heroTag: null,
          onPressed: () {},
          icon: const Icon(Icons.add_rounded),
          label: const Text('Dataset'),
        ),
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
    'remedyFillStyle · an amber fault\'s remedy, the one fill a fault gets: '
    'regular and compact (the line\'s control), beside Retry in ink',
    (_) => Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Builder(
          builder: (context) => FilledButton(
            onPressed: () {},
            style: remedyFillStyle(context),
            child: const Text('Paste the key again'),
          ),
        ),
        Builder(
          builder: (context) => FilledButton(
            onPressed: () {},
            style: remedyFillStyle(context, compact: true),
            child: const Text('Check the address'),
          ),
        ),
        TextButton(onPressed: () {}, child: const Text('Retry')),
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
  CatalogScene(
    'A long label · each button on a 300pt measure: the label takes a second '
    'line and the button grows with it, 44 high at the least',
    (_) => Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        FilledButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.search_rounded),
          label: const Text('Search every monitored episode in this season'),
        ),
        OutlinedButton(
          onPressed: () {},
          child: const Text('Open the release in the download client'),
        ),
        TextButton(
          onPressed: () {},
          child: const Text('Open the movie in Radarr to change its quality'),
        ),
      ],
    ),
    width: 300,
    platform: platform,
  ),
  CatalogScene(
    'Text at 200% · filled, outlined, text, the gated one and the amber '
    'remedy, at twice the reading size',
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
        _gated(
          (onPressed, annotate) => FilledButton.icon(
            onPressed: onPressed,
            icon: annotate(const Icon(Icons.play_arrow_rounded)),
            label: annotate(const Text('Start')),
          ),
        ),
        Builder(
          builder: (context) => FilledButton(
            onPressed: () {},
            style: remedyFillStyle(context),
            child: const Text('Paste the key again'),
          ),
        ),
        Builder(
          builder: (context) => FilledButton(
            onPressed: () {},
            style: remedyFillStyle(context, compact: true),
            child: const Text('Retry'),
          ),
        ),
      ],
    ),
    width: 390,
    textScale: catalogTextScale,
    platform: platform,
  ),
];

void main() {
  catalogCard(
    'Button',
    scenes: [
      for (final platform in CatalogPlatform.values) ..._scenes(platform),
      // Focus is global to a render, so one scene holds it, on the desktop,
      // where the keyboard is the pointer and the ring is drawn.
      CatalogScene(
        'Focused (keyboard) · the filled button with focus: the theme\'s own '
        'focus overlay on the ink fill; one control holds focus per sheet',
        (_) => Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton(
              autofocus: true,
              onPressed: () {},
              child: const Text('Grab'),
            ),
            OutlinedButton(onPressed: () {}, child: const Text('Search')),
          ],
        ),
        platform: CatalogPlatform.desktop,
      ),
    ],
  );
}
