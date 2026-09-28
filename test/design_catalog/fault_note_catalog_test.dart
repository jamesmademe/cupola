@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/fault_note.dart';

import 'catalog.dart';

Widget _ground(Color Function(ColorScheme) pick, Widget child) => Builder(
  builder: (context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: pick(scheme),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  },
);

void main() {
  catalogCard(
    'FaultNote',
    scenes: [
      CatalogScene(
        '.unreachable · in a request sheet (surfaceContainer), the retry is '
        'the sheet\'s own submit',
        (_) => _ground(
          (scheme) => scheme.surfaceContainer,
          Builder(
            builder: (context) => FaultNote.unreachable(
              message: 'Failed to load servers: the connection timed out.',
              surface: Theme.of(context).colorScheme.surfaceContainer,
            ),
          ),
        ),
      ),
      CatalogScene(
        '.fault · in a purchase sheet (surfaceContainerLow), restarted by '
        'tapping a tier again',
        (_) => _ground(
          (scheme) => scheme.surfaceContainerLow,
          Builder(
            builder: (context) => FaultNote.fault(
              message: 'Purchase failed. You have not been charged.',
              surface: Theme.of(context).colorScheme.surfaceContainerLow,
            ),
          ),
        ),
      ),
      CatalogScene(
        '.unreachable · on the default surface, no surface passed',
        (_) => const FaultNote.unreachable(
          message: 'Failed to load instances: the connection timed out.',
        ),
      ),
      CatalogScene(
        '.fault · long message wraps, glyph stays top-aligned',
        (_) => const FaultNote.fault(
          message:
              'Could not add Nosferatu (1922): Radarr rejected the request '
              'because the root folder no longer exists on disk.',
        ),
        width: 260,
      ),
    ],
  );
}
