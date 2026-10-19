@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/features/settings/domain/nav_tab.dart';

import 'catalog.dart';

/// The shell's destinations for [audience]; only Activity carries a count.
List<FloatingNavDestination> _destinations({
  int searchesWaiting = 0,
  Audience audience = Audience.operator,
}) => [
  for (final tab in NavTab.barFor(audience))
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

/// The operator's bar, which is the shell's for everyone but a requester.
final _operatorBar = NavTab.barFor(Audience.operator);

Widget _bar(
  int selected, {
  int searchesWaiting = 0,
  Audience audience = Audience.operator,
}) => FloatingBottomNavBar(
  selectedIndex: selected,
  onDestinationSelected: (_) {},
  destinations: _destinations(
    searchesWaiting: searchesWaiting,
    audience: audience,
  ),
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
        'Home selected · four columns of one width, each a glyph over its '
        'name; the lit one a strong-fill pill filling its column in the '
        'primary ink, the rest in the secondary ink',
        _operatorBar.indexOf(NavTab.home),
      ),
      _scene(
        'Activity selected, 3 finished searches · the count on the ink disc, '
        'never a status tone and never a section colour',
        _operatorBar.indexOf(NavTab.activity),
        searchesWaiting: 3,
      ),
      _scene(
        'Discover selected, badge on Activity · a count past nine reads 9+',
        _operatorBar.indexOf(NavTab.discover),
        searchesWaiting: 12,
      ),
      _scene('Stack selected', _operatorBar.indexOf(NavTab.stack)),
      _scene(
        'Settings on screen · it has no place in the bar, so no tab is '
        'selected and every item rests',
        -1,
      ),
      CatalogScene(
        "The requester's bar · Home, Discover, Requests: no control room in it",
        (_) => _bar(
          NavTab.barFor(Audience.requester).indexOf(NavTab.requests),
          audience: Audience.requester,
        ),
        width: 390,
      ),
      _scene(
        '320pt window · the columns narrow and every name still fits',
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
        'At 2× reading size · the names and the badge clamp at 1.3×, the bar '
        'keeps its height and the badge grows to fit its count',
        (_) => _bar(1, searchesWaiting: 3),
        width: 390,
        textScale: catalogTextScale,
      ),
      CatalogScene(
        'At 2× reading size, Activity selected · 9+ over its name',
        (_) => _bar(2, searchesWaiting: 12),
        width: 390,
        textScale: catalogTextScale,
      ),
    ],
  );
}
