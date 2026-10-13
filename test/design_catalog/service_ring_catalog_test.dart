@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/service_ring.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import 'catalog.dart';

/// Onboarding half-way through its walk: some services chosen, some reached,
/// one configured and silent, Prowlarr the one being set up now.
const _midWalk = {
  ServiceKey.seerr: ServiceRingState.picked,
  ServiceKey.radarr: ServiceRingState.connected,
  ServiceKey.sonarr: ServiceRingState.connected,
  ServiceKey.qbittorrent: ServiceRingState.connected,
  ServiceKey.prowlarr: ServiceRingState.picked,
  ServiceKey.jellyfin: ServiceRingState.connected,
  ServiceKey.truenas: ServiceRingState.picked,
  ServiceKey.dockge: ServiceRingState.silent,
};

/// A settled stack: everything chosen answers but one.
final _settled = {
  for (final key in [
    ServiceKey.seerr,
    ServiceKey.radarr,
    ServiceKey.sonarr,
    ServiceKey.lidarr,
    ServiceKey.bazarr,
    ServiceKey.qbittorrent,
    ServiceKey.prowlarr,
    ServiceKey.sabnzbd,
    ServiceKey.jellyfin,
    ServiceKey.plex,
    ServiceKey.truenas,
    ServiceKey.nginxProxyManager,
  ])
    key: ServiceRingState.connected,
  ServiceKey.dockge: ServiceRingState.silent,
};

Widget _pair(List<Widget> children) => Wrap(
  spacing: 32,
  runSpacing: 24,
  crossAxisAlignment: WrapCrossAlignment.center,
  children: children,
);

void main() {
  catalogCard(
    'ServiceRing',
    width: 768,
    scenes: [
      CatalogScene(
        'ServiceRing · 268 · mid-walk, progress 0.5, Prowlarr active · unlit, '
        'picked, connected with its spoke, silent drained with a collar',
        (_) => const ServiceRing(
          states: _midWalk,
          diameter: 268,
          progress: 0.5,
          activeService: ServiceKey.prowlarr,
        ),
      ),
      CatalogScene(
        'Nothing set up (the Dashboard empty state, spin: true in the app) · '
        'then a settled stack with one service that did not answer, progress 1',
        (_) => _pair([
          const ServiceRing(states: {}, diameter: 268),
          ServiceRing(states: _settled, diameter: 268, progress: 1),
        ]),
      ),
      CatalogScene(
        'Active service states · picked, connected and silent each take the '
        'halo and an ink collar when they are the one being configured',
        (_) => _pair(const [
          ServiceRing(
            states: {ServiceKey.radarr: ServiceRingState.picked},
            diameter: 200,
            activeService: ServiceKey.radarr,
            progress: 0.2,
          ),
          ServiceRing(
            states: {ServiceKey.radarr: ServiceRingState.connected},
            diameter: 200,
            activeService: ServiceKey.radarr,
            progress: 0.2,
          ),
          ServiceRing(
            states: {ServiceKey.radarr: ServiceRingState.silent},
            diameter: 200,
            activeService: ServiceKey.radarr,
            progress: 0.2,
          ),
        ]),
      ),
      CatalogScene(
        'entrance 0.5 · the nodes ride in from the centre and the mark fades '
        'in; markFraction 0.34 at the compact 132 ceiling',
        (_) => _pair(const [
          ServiceRing(states: _midWalk, diameter: 200, entrance: 0.5),
          ServiceRing(states: _midWalk, diameter: 132, markFraction: 0.34),
        ]),
      ),
      CatalogScene(
        'serviceRingDiameter at a 1.6× reading size · 268 shrinks to 168 so '
        'the text around it gets the room',
        (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.6)),
          child: Builder(
            builder: (context) => Align(
              alignment: Alignment.topLeft,
              child: ServiceRing(
                states: _midWalk,
                diameter: serviceRingDiameter(context, preferred: 268),
              ),
            ),
          ),
        ),
        width: 390,
      ),
      CatalogScene(
        'OnePunchline · the claim, on the Welcome: two lines in displayMedium '
        'at 1.10 leading, one ink; the display face carries the words, not a '
        'hue',
        (_) => const OnePunchline(),
        width: 390,
      ),
      CatalogScene(
        'OnePunchline.closing · the promise, on the close once everything '
        'tried has joined: the same lockup',
        (_) => const OnePunchline.closing(),
        width: 390,
      ),
      CatalogScene(
        'ServiceRing on the desktop · onboarding at 268',
        (_) => const ServiceRing(
          states: _midWalk,
          diameter: 268,
          progress: 0.5,
          activeService: ServiceKey.prowlarr,
        ),
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'serviceRingDiameter at a 2× reading size, with the punchline: the '
        'ring shrinks to give the text its room',
        (context) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Builder(
              builder: (context) => ServiceRing(
                states: _midWalk,
                diameter: serviceRingDiameter(context, preferred: 268),
              ),
            ),
            const OnePunchline(),
          ],
        ),
        width: 390,
        textScale: catalogTextScale,
      ),
    ],
  );
}
