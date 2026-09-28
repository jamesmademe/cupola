@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/features/settings/domain/nav_tab.dart';
import 'package:cupola/features/shell/presentation/desktop/desktop_nav_rail.dart';

import 'catalog.dart';

/// The destinations exactly as the shell builds them for the phone bar and
/// the rail alike: only Activity ever carries a count.
List<FloatingNavDestination> _destinations({int searchesWaiting = 0}) => [
  for (final tab in NavTab.values)
    FloatingNavDestination(
      icon: tab.icon,
      selectedIcon: tab.selectedIcon,
      railIcon: tab.railIcon,
      label: tab.label,
      accentColor: tab.accentColor,
      badgeCount: tab == NavTab.activity ? searchesWaiting : 0,
      badgeSemanticLabel: tab == NavTab.activity && searchesWaiting > 0
          ? '$searchesWaiting finished search'
                '${searchesWaiting == 1 ? '' : 'es'} to look at'
          : null,
    ),
];

Widget _rail(int selected, {int searchesWaiting = 0}) => Align(
  alignment: Alignment.topLeft,
  child: DesktopNavRail(
    selectedIndex: selected,
    destinations: _destinations(searchesWaiting: searchesWaiting),
    onDestinationSelected: (_) {},
    onCommandDeck: () {},
  ),
);

void main() {
  catalogCard(
    'DesktopNavRail',
    width: 1328,
    scenes: [
      CatalogScene(
        'DesktopNavRail · Dashboard selected · the pill is primary at 16%; '
        'every glyph stays an outline',
        (_) => _rail(NavTab.dashboard.index),
        width: DesktopNavRail.width,
        height: 360,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'DesktopNavRail · Activity selected, two finished searches · the '
        'badge in the section accent with its collar, never a status tone',
        (_) => _rail(NavTab.activity.index, searchesWaiting: 2),
        width: DesktopNavRail.width,
        height: 360,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'DesktopNavRail · Settings selected, twelve searches waiting · a '
        'two-digit badge grows sideways from its 18pt minimum',
        (_) => _rail(NavTab.settings.index, searchesWaiting: 12),
        width: DesktopNavRail.width,
        height: 360,
        platform: CatalogPlatform.desktop,
      ),
    ],
  );
}
