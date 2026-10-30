@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/features/settings/presentation/widgets/settings_app_rows.dart';
import 'package:cupola/features/settings/presentation/widgets/settings_section_label.dart';
import 'package:cupola/features/settings/presentation/widgets/settings_signature.dart';

import 'catalog.dart';

Widget _foot(BuildContext context) => const Padding(
  padding: EdgeInsets.symmetric(horizontal: 24),
  child: Center(child: SettingsSignature()),
);

/// The operator's About group, the last words Cupola says about itself before
/// Danger zone and the signature: who makes it, and how to reach them.
Widget _about(BuildContext context) => Padding(
  padding: const EdgeInsets.symmetric(horizontal: 16),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      const SettingsSectionLabel('About'),
      const SizedBox(height: AppSpacing.sm),
      SettingsGroupCard(children: settingsAboutRows(context)),
    ],
  ),
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
      CatalogScene(
        'The About group above it · GitHub, feedback, support and the '
        'licences, in the voice of the people who make Cupola',
        _about,
        width: 390,
      ),
    ],
  );
}
