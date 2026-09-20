import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/sabnzbd/presentation/sabnzbd_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

void main() {
  test('routes a second connection and reuses the lens client', () {
    final settings = SettingsModel(
      instances: [
        const ServiceInstance(
          id: 'sabnzbd',
          service: ServiceKey.sabnzbd,
          url: 'https://home.test',
          credential: 'home-key',
        ),
        const ServiceInstance(
          id: 'sab-seedbox',
          service: ServiceKey.sabnzbd,
          url: 'https://seedbox.test',
          credential: 'seedbox-key',
        ),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        currentSettingsProvider.overrideWith((ref) => settings),
        initialActiveInstancesProvider.overrideWithValue({
          ServiceKey.sabnzbd: 'sab-seedbox',
        }),
      ],
    );
    addTearDown(container.dispose);

    final lens = container.read(sabnzbdClientProvider);
    expect(lens.baseUrl, 'https://seedbox.test');
    expect(container.read(sabnzbdClientForProvider('')), same(lens));
    expect(container.read(sabnzbdClientForProvider('sab-seedbox')), same(lens));

    final second = container.read(sabnzbdClientForProvider('sabnzbd'));
    expect(second.baseUrl, 'https://home.test');
    expect(container.read(sabnzbdClientForProvider('sabnzbd')), same(second));
  });
}
