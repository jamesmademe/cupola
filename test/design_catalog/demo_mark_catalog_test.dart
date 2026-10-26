@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/widgets/screen_title.dart';
import 'package:cupola/demo/demo_door.dart';
import 'package:cupola/demo/demo_session.dart';
import 'package:cupola/demo/presentation/demo_settings_card.dart';

import 'catalog.dart';

/// Inside the demo: the mark is drawn and Settings has its way out.
Widget _inDemo(Widget child) => ProviderScope(
  overrides: [
    demoRunningProvider.overrideWithValue(true),
    demoDoorProvider.overrideWithValue(
      DemoDoor(enter: (_) async {}, leave: () async {}),
    ),
  ],
  child: child,
);

Widget _titles(BuildContext context) => _inDemo(
  const Padding(
    padding: EdgeInsets.all(AppSpacing.gutter),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ScreenTitle('Monday 26'),
        SizedBox(height: AppSpacing.lg),
        ScreenTitle('Discover'),
        SizedBox(height: AppSpacing.lg),
        ScreenTitle('Activity'),
      ],
    ),
  ),
);

Widget _settings(BuildContext context) => _inDemo(
  const Padding(
    padding: EdgeInsets.all(AppSpacing.lg),
    child: DemoSettingsCard(),
  ),
);

void main() {
  catalogCard(
    'DemoMark',
    scenes: [
      CatalogScene(
        'DemoMark · in the demo, a neutral Demo after each tab\'s name: the '
        'Home\'s day, Discover, Activity',
        _titles,
        width: 390,
      ),
      CatalogScene(
        'DemoMark · Settings opens on where the visitor is, and the way out',
        _settings,
        width: 390,
      ),
      CatalogScene(
        'DemoMark · at 200%, the mark beside the day and Settings\' card',
        (context) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [_titles(context), _settings(context)],
        ),
        width: 390,
        textScale: catalogTextScale,
      ),
    ],
  );
}
