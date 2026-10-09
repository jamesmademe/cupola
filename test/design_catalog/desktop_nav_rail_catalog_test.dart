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

/// The configured services of a full stack in Stack's order, with what the
/// sidebar lights: Seerr's requests, a fault, one that did not answer.
const _services = <DesktopRailService>[
  (
    service: ServiceKey.seerr,
    tone: StatusTone.info,
    state: '2 requests wait for approval',
  ),
  (service: ServiceKey.jellyfin, tone: null, state: null),
  (service: ServiceKey.radarr, tone: null, state: null),
  (service: ServiceKey.sonarr, tone: StatusTone.warning, state: 'a fault'),
  (service: ServiceKey.lidarr, tone: null, state: null),
  (service: ServiceKey.bazarr, tone: null, state: null),
  (service: ServiceKey.prowlarr, tone: null, state: null),
  (service: ServiceKey.qbittorrent, tone: StatusTone.warning, state: 'a fault'),
  (service: ServiceKey.sabnzbd, tone: null, state: null),
  (
    service: ServiceKey.truenas,
    tone: StatusTone.error,
    state: 'did not answer',
  ),
  (service: ServiceKey.dockge, tone: null, state: null),
];

/// The sidebar with [selected] lit among the bar's sections, or with Settings
/// lit at the foot ([settingsSelected]) and none of them.
Widget _rail(
  int selected, {
  int searchesWaiting = 0,
  bool settingsSelected = false,
  bool compact = false,
  bool requester = false,
  ServiceKey? room,
}) => Align(
  alignment: Alignment.topLeft,
  child: DesktopNavRail(
    compact: compact,
    selectedIndex: selected,
    destinations: requester
        ? _requesterDestinations()
        : _destinations(searchesWaiting: searchesWaiting),
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
        'DesktopNavRail · the operator on the Home · each section with its '
        'key, the services with a light only where one needs a look, '
        'Settings at the foot',
        (_) => _rail(_bar.indexOf(NavTab.home)),
        width: DesktopNavRail.fullWidth,
        height: 856,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'DesktopNavRail · in Sonarr\'s room, two finished searches · the room '
        'is lit in Stack\'s place; the count is the ink disc before the key',
        (_) => _rail(
          _bar.indexOf(NavTab.stack),
          searchesWaiting: 2,
          room: ServiceKey.sonarr,
        ),
        width: DesktopNavRail.fullWidth,
        height: 856,
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
        'DesktopNavRail folded, under 1100pt · Activity selected, two finished '
        'searches · glyphs with their tooltips, the badge never a status tone',
        (_) => _rail(
          _bar.indexOf(NavTab.activity),
          searchesWaiting: 2,
          compact: true,
        ),
        width: DesktopNavRail.compactWidth,
        height: 360,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'DesktopNavRail folded · Settings selected at the foot, twelve '
        'searches waiting · past nine the badge reads 9+ and grows away from '
        'the glyph, not across it',
        (_) => _rail(
          -1,
          searchesWaiting: 12,
          settingsSelected: true,
          compact: true,
        ),
        width: DesktopNavRail.compactWidth,
        height: 360,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'Text at 200% · the sidebar on Activity with twelve searches waiting, '
        'and folded',
        (_) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _rail(_bar.indexOf(NavTab.activity), searchesWaiting: 12),
            const SizedBox(width: 24),
            _rail(
              _bar.indexOf(NavTab.activity),
              searchesWaiting: 12,
              compact: true,
            ),
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
