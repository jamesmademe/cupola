@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/settings/presentation/widgets/settings_signature.dart';

import 'catalog.dart';

Widget _foot(BuildContext context) => const Padding(
  padding: EdgeInsets.symmetric(horizontal: 24),
  child: Center(child: SettingsSignature()),
);

void main() {
  catalogCard(
    'SettingsSignature',
    scenes: [
      CatalogScene(
        'SettingsSignature · the foot of Settings on a phone: the mark, the '
        'claim and which Cupola this is',
        _foot,
        width: 390,
      ),
      CatalogScene(
        'SettingsSignature · at 200%, the claim on two lines',
        _foot,
        width: 390,
        textScale: catalogTextScale,
      ),
    ],
  );
}
