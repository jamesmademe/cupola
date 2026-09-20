import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/transmission/presentation/transmission_provider.dart';

void main() {
  test('routes a second connection and reuses the lens client', () {
    final settings = SettingsModel(
      instances: [
        const ServiceInstance(
          id: 'transmission',
          service: ServiceKey.transmission,
          url: 'https://home.test',
          username: 'home',
          credential: 'home-password',
        ),
        const ServiceInstance(
          id: 'tr-seedbox',
          service: ServiceKey.transmission,
          url: 'https://seedbox.test',
          username: 'seedbox',
          credential: 'seedbox-password',
        ),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        currentSettingsProvider.overrideWith((ref) => settings),
        initialActiveInstancesProvider.overrideWithValue({
          ServiceKey.transmission: 'tr-seedbox',
        }),
      ],
    );
    addTearDown(container.dispose);

    final lens = container.read(transmissionClientProvider);
    expect(lens.baseUrl, 'https://seedbox.test');
    expect(container.read(transmissionClientForProvider('')), same(lens));
    expect(
      container.read(transmissionClientForProvider('tr-seedbox')),
      same(lens),
    );

    final second = container.read(
      transmissionClientForProvider('transmission'),
    );
    expect(second.baseUrl, 'https://home.test');
    expect(
      container.read(transmissionClientForProvider('transmission')),
      same(second),
    );
  });
}
