import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/npm/presentation/npm_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/settings_scope.dart';

void main() {
  test('a non-lens id resolves NPM to its named connection', () async {
    final settings = const SettingsModel(
      instances: [
        ServiceInstance(
          id: 'npm',
          service: ServiceKey.nginxProxyManager,
          url: 'https://lens.test',
          username: 'lens@example.test',
          credential: 'lens-password',
        ),
        ServiceInstance(
          id: 'npm-away',
          service: ServiceKey.nginxProxyManager,
          url: 'https://away.test/',
          username: 'away@example.test',
          credential: 'away-password',
        ),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        ...await settingsScopeOverrides(customize: (_) => settings),
        initialActiveInstancesProvider.overrideWithValue(const {
          ServiceKey.nginxProxyManager: 'npm',
        }),
      ],
    );
    addTearDown(container.dispose);

    final client = container.read(npmClientForProvider('npm-away'));

    expect(client.baseUrl, 'https://away.test');
    expect(client.identity, 'away@example.test');
    expect(client.secret, 'away-password');
    expect(
      identical(
        container.read(npmClientForProvider('')),
        container.read(npmClientProvider),
      ),
      isTrue,
    );
    expect(
      identical(
        container.read(npmClientForProvider('npm')),
        container.read(npmClientProvider),
      ),
      isTrue,
    );
  });
}
