@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/widgets/floating_nav_rail.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/settings/domain/nav_tab.dart';

import 'catalog.dart';

/// The shell's destinations for [audience]; only Activity carries a count,
/// [needYou] faults in amber.
List<FloatingNavDestination> _destinations({
  int needYou = 0,
  Audience audience = Audience.operator,
}) => [
  for (final tab in NavTab.barFor(audience))
    FloatingNavDestination(
      icon: tab.icon,
      selectedIcon: tab.selectedIcon,
      label: tab.label,
      badgeCount: tab == NavTab.activity ? needYou : 0,
      badgeTone: tab == NavTab.activity ? StatusTone.warning : null,
      badgeSemanticLabel: tab == NavTab.activity && needYou > 0
          ? '$needYou need you'
          : null,
    ),
];

final _operatorBar = NavTab.barFor(Audience.operator);

/// The rail in its gutter, as the shell sets it at the middle of the edge.
Widget _rail(
  int selected, {
  int needYou = 0,
  Audience audience = Audience.operator,
}) => Padding(
  padding: const EdgeInsets.all(FloatingNavRail.margin),
  child: Align(
    alignment: Alignment.centerLeft,
    child: FloatingNavRail(
      selectedIndex: selected,
      onDestinationSelected: (_) {},
      destinations: _destinations(needYou: needYou, audience: audience),
    ),
  ),
);

void main() {
  catalogCard(
    'FloatingNavRail',
    width: 840,
    scenes: [
      CatalogScene(
        'FloatingNavRail · the operator on the Home · the bar on its side: '
        'each glyph over its name, the lit one on the room\'s strong fill',
        (_) => _rail(_operatorBar.indexOf(NavTab.home)),
        width: 120,
        height: 320,
      ),
      CatalogScene(
        'FloatingNavRail · on Discover, three things need you · Activity\'s '
        'number on the amber fill, at the glyph\'s top right, as on the bar',
        (_) => _rail(_operatorBar.indexOf(NavTab.discover), needYou: 3),
        width: 120,
        height: 320,
      ),
      CatalogScene(
        'FloatingNavRail · the requester on her Requests',
        (_) => _rail(2, audience: Audience.requester),
        width: 120,
        height: 260,
      ),
      CatalogScene(
        'FloatingNavRail · in Settings · no section is lit',
        (_) => _rail(-1),
        width: 120,
        height: 320,
      ),
      CatalogScene(
        'Text at 200% · the names grow to the bar\'s 1.3 and the pill widens '
        'to hold them',
        (_) => _rail(_operatorBar.indexOf(NavTab.discover), needYou: 12),
        width: 160,
        height: 380,
        textScale: catalogTextScale,
      ),
    ],
  );
}
