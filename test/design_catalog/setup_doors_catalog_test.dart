@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/setup_doors.dart';

import 'catalog.dart';

Widget _doors(_) => Padding(
  padding: const EdgeInsets.all(24),
  child: SetupDoors(onSetUp: () {}, onCopy: () {}, onSignIn: () {}),
);

void main() {
  catalogCard(
    'SetupDoors',
    scenes: [
      CatalogScene(
        'SetupDoors · the Welcome and the Home at zero: set up a service, '
        'copy from another device, or sign in with a Seerr account, each said '
        'under its door',
        _doors,
        width: 390,
      ),
      CatalogScene(
        'SetupDoors · on a short phone (667pt tall) the lines are not drawn, '
        'and each is said as its door\'s hint',
        _doors,
        width: 390,
        height: 667,
      ),
      CatalogScene(
        'SetupDoors · at 200% the doors alone, their lines said as hints',
        _doors,
        width: 390,
        textScale: catalogTextScale,
      ),
    ],
  );
}
