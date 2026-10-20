@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/features/settings/domain/nav_tab.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/shell/presentation/desktop/desktop_nav_rail.dart';
import 'package:cupola/features/shell/presentation/desktop/in_flight_glance.dart';

import 'catalog.dart';

/// The operator's bar, which the rail draws above Settings.
final _bar = NavTab.barFor(Audience.operator);

/// The destinations exactly as the shell builds them for the phone bar and
/// the rail alike: only Activity ever carries a count, here [needYou] faults
/// in amber.
List<FloatingNavDestination> _destinations({int needYou = 0}) => [
  for (final tab in _bar)
    FloatingNavDestination(
      icon: tab.icon,
      selectedIcon: tab.selectedIcon,
      railIcon: tab.railIcon,
      label: tab.label,
      badgeCount: tab == NavTab.activity ? needYou : 0,
      badgeTone: tab == NavTab.activity ? StatusTone.warning : null,
      badgeSemanticLabel: tab == NavTab.activity && needYou > 0
          ? '$needYou need you'
          : null,
    ),
];

/// The configured services of a full stack in Stack's order, with what the
/// sidebar says of each: Seerr's requests in blue, Sonarr's imports to fix in
/// amber, qBittorrent's fault with no count as a light, TrueNAS silent.
const _services = <DesktopRailService>[
  (
    service: ServiceKey.seerr,
    tone: StatusTone.info,
    state: '2 requests wait for approval',
    count: '2',
  ),
  (service: ServiceKey.radarr, tone: null, state: null, count: null),
  (
    service: ServiceKey.sonarr,
    tone: StatusTone.warning,
    state: '18 need you',
    count: '18',
  ),
  (service: ServiceKey.lidarr, tone: null, state: null, count: null),
  (service: ServiceKey.bazarr, tone: null, state: null, count: null),
  (
    service: ServiceKey.qbittorrent,
    tone: StatusTone.warning,
    state: 'a fault',
    count: null,
  ),
  (service: ServiceKey.prowlarr, tone: null, state: null, count: null),
  (service: ServiceKey.sabnzbd, tone: null, state: null, count: null),
  (service: ServiceKey.jellyfin, tone: null, state: null, count: null),
  (
    service: ServiceKey.truenas,
    tone: StatusTone.error,
    state: 'did not answer',
    count: null,
  ),
  (service: ServiceKey.dockge, tone: null, state: null, count: null),
];

/// What is in flight, as the glance draws it: three moving, one stuck.
const _inFlight = InFlightGlanceData(
  title: '3 moving',
  rate: '40.4 MB/s',
  bars: [
    (progress: 0.88, stuck: false),
    (progress: 0.62, stuck: false),
    (progress: 0.31, stuck: false),
    (progress: 0.47, stuck: true),
  ],
  stuck: 1,
);

/// The sidebar with [selected] lit among the bar's sections, or with Settings
/// lit at the foot ([settingsSelected]) and none of them.
Widget _rail(
  int selected, {
  int needYou = 0,
  bool settingsSelected = false,
  bool compact = false,
  bool requester = false,
  ServiceKey? room,
  InFlightGlanceData? inFlight = _inFlight,
}) => Align(
  alignment: Alignment.topLeft,
  child: DesktopNavRail(
    compact: compact,
    selectedIndex: selected,
    destinations: requester
        ? _requesterDestinations()
        : _destinations(needYou: needYou),
    onDestinationSelected: (_) {},
    settings: FloatingNavDestination(
      icon: NavTab.settings.icon,
      selectedIcon: NavTab.settings.selectedIcon,
      railIcon: NavTab.settings.railIcon,
      label: NavTab.settings.label,
    ),
    settingsSelected: settingsSelected,
    onSettings: () {},
    services: requester ? const [] : _services,
    stackFigure: requester
        ? null
        : (text: '10/11', spoken: '10 of 11 answering'),
    footer: requester || inFlight == null
        ? null
        : InFlightGlanceTile(glance: inFlight, onOpen: () {}),
    selectedService: room,
    onService: (_) {},
  ),
);

List<FloatingNavDestination> _requesterDestinations() => [
  for (final tab in NavTab.barFor(Audience.requester))
    FloatingNavDestination(
      icon: tab.icon,
      selectedIcon: tab.selectedIcon,
      railIcon: tab.railIcon,
      label: tab.label,
    ),
];

void main() {
  catalogCard(
    'DesktopNavRail',
    width: 1328,
    scenes: [
      CatalogScene(
        'DesktopNavRail · the operator on the Home · the sections, Stack\'s '
        'figure, the services in their domains with a number where something '
        'waits on the person, Activity with all of them (Sonarr\'s 18), In '
        'flight and Settings at the foot',
        (_) => _rail(_bar.indexOf(NavTab.home), needYou: 18),
        width: DesktopNavRail.fullWidth,
        height: 856,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'DesktopNavRail · in Sonarr\'s room, two things need you · the room '
        'is lit in Stack\'s place; Activity\'s count is the services\' amber '
        'pill',
        (_) => _rail(
          _bar.indexOf(NavTab.stack),
          needYou: 2,
          room: ServiceKey.sonarr,
        ),
        width: DesktopNavRail.fullWidth,
        height: 856,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'DesktopNavRail · on Activity · In flight gives way to the page that '
        'is the whole of it',
        (_) => _rail(_bar.indexOf(NavTab.activity), inFlight: null),
        width: DesktopNavRail.fullWidth,
        height: 856,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'In flight · nothing moving, two queued; reading; could not be read',
        (_) => const SizedBox(
          width: DesktopNavRail.fullWidth - 20,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InFlightGlanceTile(
                glance: InFlightGlanceData(
                  title: 'Nothing in flight',
                  note: '2 queued',
                ),
                onOpen: _noop,
              ),
              SizedBox(height: 12),
              InFlightGlanceTile(
                glance: InFlightGlanceData.reading(),
                onOpen: _noop,
              ),
              SizedBox(height: 12),
              InFlightGlanceTile(
                glance: InFlightGlanceData.unread(),
                onOpen: _noop,
              ),
            ],
          ),
        ),
        width: DesktopNavRail.fullWidth,
        height: 240,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'DesktopNavRail · the requester in Settings · her three sections, no '
        'service, nothing lit but Settings',
        (_) => _rail(-1, requester: true, settingsSelected: true),
        width: DesktopNavRail.fullWidth,
        height: 480,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'DesktopNavRail folded, under 1100pt · Home selected, two things need '
        'you · glyphs with their tooltips, Activity\'s number on the amber '
        'disc',
        (_) => _rail(_bar.indexOf(NavTab.home), needYou: 2, compact: true),
        width: DesktopNavRail.compactWidth,
        height: 360,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'DesktopNavRail folded · Settings selected at the foot, twelve things '
        'need you · past nine the badge reads 9+ and grows away from the '
        'glyph, not across it',
        (_) => _rail(-1, needYou: 12, settingsSelected: true, compact: true),
        width: DesktopNavRail.compactWidth,
        height: 360,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'Text at 200% · the sidebar on Home with twelve things needing you, '
        'and folded',
        (_) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _rail(_bar.indexOf(NavTab.home), needYou: 12),
            const SizedBox(width: 24),
            _rail(_bar.indexOf(NavTab.home), needYou: 12, compact: true),
          ],
        ),
        width: DesktopNavRail.fullWidth + 24 + DesktopNavRail.compactWidth,
        height: 856,
        platform: CatalogPlatform.desktop,
        textScale: catalogTextScale,
      ),
    ],
  );
}

void _noop() {}
