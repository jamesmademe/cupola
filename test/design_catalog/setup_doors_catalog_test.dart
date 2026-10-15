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
        'SetupDoors · the Welcome and the Home at zero: set up a service, '
        'or sign in with a Seerr account, each said under its door',
        (_) => Padding(
          padding: const EdgeInsets.all(24),
          child: SetupDoors(onSetUp: () {}, onSignIn: () {}),
        ),
        width: 390,
      ),
      CatalogScene(
        'SetupDoors · at 200% the doors alone, their lines said as hints',
        (_) => Padding(
          padding: const EdgeInsets.all(24),
          child: SetupDoors(onSetUp: () {}, onSignIn: () {}),
        ),
        width: 390,
        textScale: catalogTextScale,
      ),
    ],
  );
}
