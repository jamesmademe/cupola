@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/features/settings/domain/nav_tab.dart';

import 'catalog.dart';

/// The shell's four destinations; only Activity carries a count.
List<FloatingNavDestination> _destinations({int searchesWaiting = 0}) => [
  for (final tab in NavTab.values)
    FloatingNavDestination(
      icon: tab.icon,
      selectedIcon: tab.selectedIcon,
      railIcon: tab.railIcon,
      label: tab.label,
      badgeCount: tab == NavTab.activity ? searchesWaiting : 0,
      badgeSemanticLabel: tab == NavTab.activity && searchesWaiting > 0
          ? '$searchesWaiting finished searches to look at'
          : null,
    ),
];

Widget _bar(int selected, {int searchesWaiting = 0}) => FloatingBottomNavBar(
  selectedIndex: selected,
  onDestinationSelected: (_) {},
  destinations: _destinations(searchesWaiting: searchesWaiting),
);

CatalogScene _scene(
  String caption,
  int selected, {
  int searchesWaiting = 0,
  double width = 390,
}) => CatalogScene(
  caption,
  (_) => _bar(selected, searchesWaiting: searchesWaiting),
  width: width,
);

void main() {
  catalogCard(
    'FloatingBottomNavBar',
    width: 480,
    scenes: [
      _scene(
        'Dashboard selected · the strong-fill pill with icon and label in the '
        'primary ink, the other three icon only in the secondary ink',
        0,
      ),
      _scene(
        'Activity selected, 3 finished searches · the count on the ink disc, '
        'never a status tone and never a section colour',
        NavTab.activity.index,
        searchesWaiting: 3,
      ),
      _scene(
        'Discover selected, badge on Activity · a count past nine reads 9+',
        NavTab.discover.index,
        searchesWaiting: 12,
      ),
      _scene('Settings selected', NavTab.settings.index),
      _scene(
        '320pt window · the bar fills the width and the items tighten',
        0,
        searchesWaiting: 3,
        width: 320,
      ),
      CatalogScene(
        'Over artwork · the glass is a semi-opaque tint, not a blur',
        (_) => SizedBox(
          height: 120,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image(image: CatalogArt.backdropImage, fit: BoxFit.cover),
              Align(alignment: Alignment.bottomCenter, child: _bar(1)),
            ],
          ),
        ),
        width: 390,
      ),
      CatalogScene(
        'At 2× reading size · the label and the badge clamp at 1.3×, the bar '
        'grows to fit its pill and the badge to fit its count',
        (_) => _bar(1, searchesWaiting: 3),
        width: 390,
        textScale: catalogTextScale,
      ),
      CatalogScene(
        'At 2× reading size, Search selected · 9+ on a compact item',
        (_) => _bar(2, searchesWaiting: 12),
        width: 390,
        textScale: catalogTextScale,
      ),
    ],
  );
}
