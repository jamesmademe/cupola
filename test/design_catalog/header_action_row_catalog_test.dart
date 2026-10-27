@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/widgets/header_action_row.dart';

import 'catalog.dart';

/// The promoted primary, as the Videos button draws it: the ink fill, one line
/// of label, 52 tall.
Widget _expanded({required bool enabled}) => Builder(
  builder: (context) => SizedBox(
    height: HeaderActionRow.buttonHeight,
    child: FilledButton.icon(
      onPressed: enabled ? () {} : null,
      icon: const Icon(Icons.play_circle_outline_rounded),
      label: const Text('Videos'),
      style: HeaderActionRow.expandedButtonStyle(context),
    ),
  ),
);

/// The square disc beside a title's actions: an icon, 52 across.
Widget _iconOnly({required bool enabled}) => Builder(
  builder: (context) => SizedBox.square(
    dimension: HeaderActionRow.buttonHeight,
    child: FilledButton(
      onPressed: enabled ? () {} : null,
      style: HeaderActionRow.iconOnlyButtonStyle(context),
      child: Icon(
        Icons.play_circle_outline_rounded,
        size: HeaderActionRow.glyphSize,
      ),
    ),
  ),
);

/// The promoted primary with its disc beside it, the way a title's header lays
/// them out.
Widget _pair() => Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    Expanded(child: _expanded(enabled: true)),
    const SizedBox(width: AppSpacing.sm),
    _iconOnly(enabled: true),
  ],
);

void main() {
  catalogCard(
    'HeaderActionRow',
    width: 720,
    scenes: [
      CatalogScene(
        'Expanded · Videos · the ink fill with the on-ink label, 52pt tall '
        '(button-l), radius.button: never the service\'s colour',
        (_) => _expanded(enabled: true),
        width: 390,
        platform: CatalogPlatform.phone,
      ),
      CatalogScene(
        'Expanded · no videos · disabled: the fill drops, the label stays',
        (_) => _expanded(enabled: false),
        width: 390,
        platform: CatalogPlatform.phone,
      ),
      CatalogScene(
        'Icon only · the square disc beside the primary, 52 across',
        (_) => _pair(),
        width: 390,
        platform: CatalogPlatform.phone,
      ),
      CatalogScene(
        'Icon only · no videos · disabled',
        (_) => _iconOnly(enabled: false),
        width: 390,
        platform: CatalogPlatform.phone,
      ),
      CatalogScene(
        'At 2× reading size · the primary label takes the room it needs and '
        'the disc keeps 52pt',
        (_) => _pair(),
        width: 390,
        textScale: catalogTextScale,
      ),
      CatalogScene(
        'Expanded · Videos · desktop',
        (_) => _expanded(enabled: true),
        width: 560,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'Icon only · desktop',
        (_) => _iconOnly(enabled: true),
        width: 560,
        platform: CatalogPlatform.desktop,
      ),
    ],
  );
}
