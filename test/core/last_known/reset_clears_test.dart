import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/last_known/last_known_store.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../test_helpers/settings_scope.dart';

void main() {
  test('resetting the app forgets every last drawing', () async {
    final store = LastKnownStore.memory()
      ..write(
        'home.operator.arrived',
        validity: 'v',
        schema: 1,
        data: const ['Sintel'],
        takenAt: DateTime(2026, 10, 12),
      );
    final container = ProviderContainer(
      overrides: [
        ...await settingsScopeOverrides(configured: const [ServiceKey.radarr]),
        lastKnownStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);

    await container.read(settingsProvider.notifier).resetSettings();

    expect(
      store.read('home.operator.arrived', validity: 'v', schema: 1),
      isNull,
    );
  });
}
