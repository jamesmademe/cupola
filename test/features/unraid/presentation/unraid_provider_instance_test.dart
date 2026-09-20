import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/unraid/presentation/unraid_provider.dart';

const _home = ServiceInstance(
  id: 'unraid',
  service: ServiceKey.unraid,
  url: 'https://unraid.home',
  credential: 'home-key',
);
const _away = ServiceInstance(
  id: 'unraid-away',
  service: ServiceKey.unraid,
  url: 'https://unraid.away',
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
  test('empty and active ids collapse onto the lensed client', () {
    final container = _container(lenses: {ServiceKey.unraid: _away.id});

    expect(
      identical(
        container.read(unraidClientForProvider('')),
        container.read(unraidClientProvider),
      ),
      isTrue,
    );
    expect(
      identical(
        container.read(unraidClientForProvider(_away.id)),
        container.read(unraidClientProvider),
      ),
      isTrue,
    );
  });

  test('a non-active id routes the client to its own GraphQL endpoint', () {
    final container = _container(lenses: {ServiceKey.unraid: _home.id});

    final client = container.read(unraidClientForProvider(_away.id));
    expect(client.baseUrl, 'https://unraid.away');
  });
}
