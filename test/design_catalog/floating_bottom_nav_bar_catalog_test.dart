@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/features/settings/domain/nav_tab.dart';
import 'package:cupola/features/shell/presentation/activity_badge.dart';

import 'catalog.dart';

/// The shell's destinations for [audience]; only Activity carries a count.
/// Activity's number as the shell sets it: [faults] amber, else [requests]
/// and [searches] blue; nothing on the page it counts.
ActivityBadge? _activity({
  int faults = 0,
  int requests = 0,
  int searches = 0,
}) => activityBadgeOf(
  faults: faults,
  faultsFloor: false,
  requests: requests,
  requestsFloor: false,
  searches: searches,
);

List<FloatingNavDestination> _destinations({
  ActivityBadge? activity,
  Audience audience = Audience.operator,
}) => [
  for (final tab in NavTab.barFor(audience))
    FloatingNavDestination(
      icon: tab.icon,
      selectedIcon: tab.selectedIcon,
      railIcon: tab.railIcon,
      label: tab.label,
      badgeCount: tab == NavTab.activity ? activity?.count ?? 0 : 0,
      badgeTone: tab == NavTab.activity ? activity?.tone : null,
      badgeSemanticLabel: tab == NavTab.activity ? activity?.spoken : null,
    ),
];

/// The operator's bar, which is the shell's for everyone but a requester.
final _operatorBar = NavTab.barFor(Audience.operator);

Widget _bar(
  int selected, {
  ActivityBadge? activity,
  Audience audience = Audience.operator,
}) => FloatingBottomNavBar(
  selectedIndex: selected,
  onDestinationSelected: (_) {},
  destinations: _destinations(activity: activity, audience: audience),
);

CatalogScene _scene(
  String caption,
  int selected, {
  ActivityBadge? activity,
  double width = 390,
}) => CatalogScene(
  caption,
  (_) => _bar(selected, activity: activity),
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
        'Something needs you · Activity carries the faults Needs you counts, '
        'on the amber fill with its ink, a 2pt collar in the bar\'s ground; '
        'heard as "Activity, 3 need you"',
        _operatorBar.indexOf(NavTab.home),
        activity: _activity(faults: 3, requests: 2),
      ),
      _scene(
        'Only answers wait · blue: 2 requests and a finished search',
        _operatorBar.indexOf(NavTab.discover),
        activity: _activity(requests: 2, searches: 1),
      ),
      _scene(
        'A count past nine reads 9+',
        _operatorBar.indexOf(NavTab.discover),
        activity: _activity(faults: 18),
      ),
      _scene(
        'On Activity itself · no number: the page says it, larger',
        _operatorBar.indexOf(NavTab.activity),
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
        activity: _activity(faults: 3),
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
        (_) => _bar(1, activity: _activity(faults: 3)),
        width: 390,
        textScale: catalogTextScale,
      ),
      CatalogScene(
        'At 2× reading size, blue · 9+ over its name',
        (_) => _bar(0, activity: _activity(requests: 12)),
        width: 390,
        textScale: catalogTextScale,
      ),
    ],
  );
}
