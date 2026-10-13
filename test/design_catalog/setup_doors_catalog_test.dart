@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/setup_doors.dart';

import 'catalog.dart';

void main() {
  catalogCard(
    'SetupDoors',
    scenes: [
      CatalogScene(
        'SetupDoors · the Welcome and the Home at zero: one door, Seerr '
        'named under it',
        (_) => Padding(
          padding: const EdgeInsets.all(24),
          child: SetupDoors(onSetUp: () {}),
        ),
        width: 390,
      ),
      CatalogScene(
        'SetupDoors · at 200% the hint wraps under the door, which keeps its '
        'height',
        (_) => Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SetupDoors(onSetUp: () {}),
            ),
          ),
        ),
        width: 390,
      ),
    ],
  );
}
