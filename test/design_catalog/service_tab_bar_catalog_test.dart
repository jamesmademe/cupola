@Tags(['catalog'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/service_tab_bar.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/services/presentation/widgets/instance_lens_badge.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import 'catalog.dart';

/// Two Radarr connections, so the header's lens draws.
const _twoRadarrs = SettingsModel(
  instances: [
    ServiceInstance(
      id: 'radarr',
      service: ServiceKey.radarr,
      label: '4K',
      url: 'https://four-k.lan:7878',
      credential: 'k',
    ),
    ServiceInstance(
      id: 'radarr-hd11111',
      service: ServiceKey.radarr,
      label: 'HD',
      url: 'https://hd.lan:7879',
      credential: 'k',
    ),
  ],
);

ServiceTab _tab(ServiceKey service, String label) =>
    tabsFor(service)!.firstWhere((tab) => tab.label == label);

void main() {
  catalogCard(
    'ServiceTabBar',
    width: 1328,
    overrides: () async => [
      currentSettingsProvider.overrideWith((ref) => _twoRadarrs),
      initialActiveInstancesProvider.overrideWithValue(const {}),
    ],
    scenes: [
      CatalogScene(
        'ServiceTabBar.header · Radarr, Overview, with the instance lens · the '
        'room light: the lamp at 12% over the band, bloom to 30% in the lower '
        '11pt; the selected tab the strong-fill pill, the mark a lit tile in '
        'ink',
        (_) => ServiceTabBar.header(
          service: ServiceKey.radarr,
          current: _tab(ServiceKey.radarr, 'Overview'),
          onSelected: (_) {},
          lens: const InstanceLensBadge(service: ServiceKey.radarr),
        ),
        width: 1280,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'ServiceTabBar.header · Transmission, Queue, no lens',
        (_) => ServiceTabBar.header(
          service: ServiceKey.transmission,
          current: _tab(ServiceKey.transmission, 'Queue'),
          onSelected: (_) {},
        ),
        width: 1280,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'ServiceTabBar · Radarr, Queue selected · the four *arr share this bar',
        (_) => ServiceTabBar(
          service: ServiceKey.radarr,
          current: _tab(ServiceKey.radarr, 'Queue'),
          onSelected: (_) {},
        ),
        width: 390,
      ),
      CatalogScene(
        'ServiceTabBar · Radarr, Overview, at 200% · the labels grow to 1.3x, '
        'the phone bar\'s ceiling, and stay whole in the 44pt row',
        (_) => ServiceTabBar(
          service: ServiceKey.radarr,
          current: _tab(ServiceKey.radarr, 'Overview'),
          onSelected: (_) {},
        ),
        width: 390,
        textScale: catalogTextScale,
      ),
      CatalogScene(
        'ServiceTabBar.header · Radarr, Overview, with the lens, at 200% · the '
        'desktop header, name, lens and tabs at twice the reading size',
        (_) => ServiceTabBar.header(
          service: ServiceKey.radarr,
          current: _tab(ServiceKey.radarr, 'Overview'),
          onSelected: (_) {},
          lens: const InstanceLensBadge(service: ServiceKey.radarr),
        ),
        width: 1280,
        textScale: catalogTextScale,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'ServiceTabBar · Nginx Proxy Manager, Certificates · wider than the '
        'phone, so it scrolls from the start; TrueNAS draws no bar',
        (_) => ServiceTabBar(
          service: ServiceKey.nginxProxyManager,
          current: _tab(ServiceKey.nginxProxyManager, 'Certificates'),
          onSelected: (_) {},
        ),
        width: 390,
      ),
    ],
  );
}
