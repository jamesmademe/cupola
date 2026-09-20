import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/dockge/presentation/dockge_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

const _home = ServiceInstance(
  id: 'dockge',
  service: ServiceKey.dockge,
  url: 'https://dockge.home',
  credential: 'home-password',
  username: 'admin',
);
const _away = ServiceInstance(
  id: 'dockge-away',
  service: ServiceKey.dockge,
  url: 'https://dockge.away',
  credential: 'away-password',
  username: 'admin',
);

ProviderContainer _container({Map<ServiceKey, String> lenses = const {}}) {
  final container = ProviderContainer(
    overrides: [
      currentSettingsProvider.overrideWith(
        (ref) => const SettingsModel(instances: [_home, _away]),
      ),
      initialActiveInstancesProvider.overrideWithValue(lenses),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('empty and active ids collapse onto the lensed Dockge facade', () {
    final container = _container(lenses: {ServiceKey.dockge: _away.id});

    expect(
      identical(
        container.read(dockgeServiceForProvider('')),
        container.read(dockgeServiceProvider),
      ),
      isTrue,
    );
    expect(
      identical(
        container.read(dockgeServiceForProvider(_away.id)),
        container.read(dockgeServiceProvider),
      ),
      isTrue,
    );
  });

  test('a non-active id routes the KPI facade to its own connection', () {
    final container = _container(lenses: {ServiceKey.dockge: _home.id});

    final service = container.read(dockgeServiceForProvider(_away.id));
    expect(service.client.baseUrl, 'https://dockge.away');
    expect(service.client.endpoint, isEmpty);
  });
}
