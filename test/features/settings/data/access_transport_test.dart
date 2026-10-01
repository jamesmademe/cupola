import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/settings_scope.dart';

/// A client is rebuilt when its connection's access changes, so a token
/// pasted in the form reaches the next request without a restart.
void main() {
  const radarr = ServiceInstance(
    id: 'radarr',
    service: ServiceKey.radarr,
    url: 'https://radarr.example.com',
    credential: 'key',
  );
  const token = CloudflareServiceToken(
    clientId: 'id.access',
    clientSecret: 'secret',
  );

  test('a changed access rebuilds the client with the new headers', () async {
    final container = ProviderContainer(
      overrides: await settingsScopeOverrides(
        customize: (_) => const SettingsModel(instances: [radarr]),
      ),
    );
    addTearDown(container.dispose);
    final subscription = container.listen(radarrServiceProvider, (_, _) {});
    addTearDown(subscription.close);

    final before = container.read(radarrServiceProvider).client;
    expect(before.headers.keys, isNot(contains('CF-Access-Client-Id')));

    await container
        .read(settingsProvider.notifier)
        .updateSettings(
          SettingsModel(instances: [radarr.copyWith(access: token)]),
        );
    final after = container.read(radarrServiceProvider).client;

    expect(identical(before, after), isFalse);
    expect(after.headers, containsPair('CF-Access-Client-Id', 'id.access'));
    expect(after.headers, containsPair('CF-Access-Client-Secret', 'secret'));
  });

  test('an unrelated write leaves the client alone', () async {
    final container = ProviderContainer(
      overrides: await settingsScopeOverrides(
        customize: (_) =>
            SettingsModel(instances: [radarr.copyWith(access: token)]),
      ),
    );
    addTearDown(container.dispose);
    final subscription = container.listen(radarrServiceProvider, (_, _) {});
    addTearDown(subscription.close);

    final before = container.read(radarrServiceProvider).client;
    await container
        .read(settingsProvider.notifier)
        .updateSettings(
          container.read(currentSettingsProvider).copyWith(region: 'DE'),
        );

    expect(
      identical(before, container.read(radarrServiceProvider).client),
      isTrue,
    );
  });
}
