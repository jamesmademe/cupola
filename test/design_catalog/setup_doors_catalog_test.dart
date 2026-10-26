@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/setup_doors.dart';

import 'catalog.dart';

WidgetBuilder _doors({bool? showLines, bool demo = false}) =>
    (_) => Padding(
      padding: const EdgeInsets.all(24),
      child: SetupDoors(
        onSetUp: () {},
        onCopy: () {},
        onSignIn: () {},
        onDemo: demo ? () {} : null,
        showLines: showLines,
      ),
    );

void main() {
  catalogCard(
    'SetupDoors',
    scenes: [
      CatalogScene(
        'SetupDoors · the Welcome and the Home at zero: set up a service, '
        'copy from another device, or sign in with a Seerr account, each said '
        'under its door',
        _doors(),
        width: 390,
      ),
      CatalogScene(
        'SetupDoors · where the claim and the lines do not both fit (the '
        'Welcome on a 402 by 874pt phone): the verbs alone, each line said as '
        'its door\'s hint',
        _doors(showLines: false),
        width: 390,
      ),
      CatalogScene(
        'SetupDoors · at 200% the doors alone, their lines said as hints',
        _doors(),
        width: 390,
        textScale: catalogTextScale,
      ),
      CatalogScene(
        'SetupDoors · the Welcome of an app with no connection: the demo\'s '
        'door last, a link in ink under the copy\'s, its line under it',
        _doors(demo: true),
        width: 390,
      ),
      CatalogScene(
        'SetupDoors · the four doors as every listed phone\'s Welcome draws '
        'them: the verbs alone, each line said as its door\'s hint',
        _doors(showLines: false, demo: true),
        width: 390,
      ),
      CatalogScene(
        'SetupDoors · the four doors at 200%',
        _doors(demo: true),
        width: 390,
        textScale: catalogTextScale,
      ),
    ],
  );
}
