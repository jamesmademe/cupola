import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/nzbget/presentation/nzbget_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

void main() {
  test('routes a second connection and reuses the lens client', () {
    final settings = SettingsModel(
      instances: [
        const ServiceInstance(
          id: 'nzbget',
          service: ServiceKey.nzbget,
          url: 'https://home.test',
          username: 'home',
          credential: 'home-password',
        ),
        const ServiceInstance(
          id: 'nzb-seedbox',
          service: ServiceKey.nzbget,
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
          ServiceKey.nzbget: 'nzb-seedbox',
        }),
      ],
    );
    addTearDown(container.dispose);

    final lens = container.read(nzbgetClientProvider);
    expect(lens.baseUrl, 'https://seedbox.test');
    expect(container.read(nzbgetClientForProvider('')), same(lens));
    expect(container.read(nzbgetClientForProvider('nzb-seedbox')), same(lens));

    final second = container.read(nzbgetClientForProvider('nzbget'));
    expect(second.baseUrl, 'https://home.test');
    expect(container.read(nzbgetClientForProvider('nzbget')), same(second));
  });
}
