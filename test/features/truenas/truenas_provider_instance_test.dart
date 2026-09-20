import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/truenas/presentation/truenas_provider.dart';

const _home = ServiceInstance(
  id: 'truenas',
  service: ServiceKey.truenas,
  url: 'https://nas.home',
  credential: 'home-key',
);
const _away = ServiceInstance(
  id: 'truenas-away',
  service: ServiceKey.truenas,
  url: 'https://nas.away',
  credential: 'away-key',
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
  test('empty and active ids collapse onto the dashboard service', () {
    final container = _container(lenses: {ServiceKey.truenas: _away.id});

    expect(
      identical(
        container.read(truenasServiceForProvider('')),
        container.read(truenasServiceProvider),
      ),
      isTrue,
    );
    expect(
      identical(
        container.read(truenasServiceForProvider(_away.id)),
        container.read(truenasServiceProvider),
      ),
      isTrue,
    );
  });

  test('a non-active id routes the dashboard service to its own WebSocket', () {
    final container = _container(lenses: {ServiceKey.truenas: _home.id});

    final service = container.read(truenasServiceForProvider(_away.id));
    expect(service.client.baseUrl, 'https://nas.away');
    expect(service.client.apiKey, 'away-key');
  });
}
