import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/prowlarr/presentation/prowlarr_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/settings_scope.dart';

void main() {
  test('a non-lens id resolves Prowlarr to its named connection', () async {
    final settings = const SettingsModel(
      instances: [
        ServiceInstance(
          id: 'prowlarr',
          service: ServiceKey.prowlarr,
          url: 'https://lens.test',
          credential: 'lens-key',
        ),
        ServiceInstance(
          id: 'prowlarr-away',
          service: ServiceKey.prowlarr,
          url: 'https://away.test/',
          credential: 'away-key',
        ),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        ...await settingsScopeOverrides(customize: (_) => settings),
        initialActiveInstancesProvider.overrideWithValue(const {
          ServiceKey.prowlarr: 'prowlarr',
        }),
      ],
    );
    addTearDown(container.dispose);

    final service = container.read(prowlarrServiceForProvider('prowlarr-away'));

    expect(service.client.baseUrl, 'https://away.test');
    expect(service.client.headers['X-Api-Key'], 'away-key');
    expect(
      identical(
        container.read(prowlarrServiceForProvider('')),
        container.read(prowlarrServiceProvider),
      ),
      isTrue,
    );
    expect(
      identical(
        container.read(prowlarrServiceForProvider('prowlarr')),
        container.read(prowlarrServiceProvider),
      ),
      isTrue,
    );
  });
}
