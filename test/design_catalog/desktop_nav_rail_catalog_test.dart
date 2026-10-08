@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/features/settings/domain/nav_tab.dart';
import 'package:cupola/features/shell/presentation/desktop/desktop_nav_rail.dart';

import 'catalog.dart';

/// The operator's bar, which the rail draws above Settings.
final _bar = NavTab.barFor(Audience.operator);

/// The destinations exactly as the shell builds them for the phone bar and
/// the rail alike: only Activity ever carries a count.
List<FloatingNavDestination> _destinations({int searchesWaiting = 0}) => [
  for (final tab in _bar)
    FloatingNavDestination(
      icon: tab.icon,
      selectedIcon: tab.selectedIcon,
      railIcon: tab.railIcon,
      label: tab.label,
      badgeCount: tab == NavTab.activity ? searchesWaiting : 0,
      badgeSemanticLabel: tab == NavTab.activity && searchesWaiting > 0
          ? '$searchesWaiting finished search'
                '${searchesWaiting == 1 ? '' : 'es'} to look at'
          : null,
    ),
];

/// The rail with [selected] lit among the bar's sections, or with Settings lit
/// at the foot ([settingsSelected]) and none of them.
Widget _rail(
  int selected, {
  int searchesWaiting = 0,
  bool settingsSelected = false,
}) => Align(
  alignment: Alignment.topLeft,
  child: DesktopNavRail(
    selectedIndex: selected,
    destinations: _destinations(searchesWaiting: searchesWaiting),
    onDestinationSelected: (_) {},
    settings: FloatingNavDestination(
      icon: NavTab.settings.icon,
      selectedIcon: NavTab.settings.selectedIcon,
      railIcon: NavTab.settings.railIcon,
      label: NavTab.settings.label,
    ),
    settingsSelected: settingsSelected,
    onSettings: () {},
    onCommandDeck: () {},
  ),
);

void main() {
  catalogCard(
    'DesktopNavRail',
    width: 1328,
    scenes: [
      CatalogScene(
        'DesktopNavRail · Home selected · the pill is primary at 16%; '
        'every glyph stays an outline',
        (_) => _rail(_bar.indexOf(NavTab.home)),
        width: DesktopNavRail.width,
        height: 360,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'DesktopNavRail · Activity selected, two finished searches · the '
        'badge is the ink disc with its collar, never a status tone',
        (_) => _rail(_bar.indexOf(NavTab.activity), searchesWaiting: 2),
        width: DesktopNavRail.width,
        height: 360,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'DesktopNavRail · Settings selected at the foot, twelve searches '
        'waiting · no section is lit; past nine the badge reads 9+ and grows '
        'away from the glyph, not across it',
        (_) => _rail(-1, searchesWaiting: 12, settingsSelected: true),
        width: DesktopNavRail.width,
        height: 360,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'Text at 200% · DesktopNavRail, Activity selected with twelve searches '
        'waiting: the 9+ badge at twice the reading size',
        (_) => _rail(_bar.indexOf(NavTab.activity), searchesWaiting: 12),
        width: DesktopNavRail.width,
        height: 360,
        platform: CatalogPlatform.desktop,
        textScale: catalogTextScale,
      ),
    ],
  );
}
