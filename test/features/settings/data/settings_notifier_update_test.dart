import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/features/discover/data/seerr_accounts.dart';
import 'package:cupola/features/discover/domain/seerr_sign_in.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/data/settings_service.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/fake_secure_settings_store.dart';

/// Two changes to the settings made at once both land, a write that fails
/// changes nothing, and the one after it is not poisoned by it.

/// A secure store whose writes wait for [gate] when one is set, and count.
class _GatedStore extends FakeSecureSettingsStore {
  Completer<void>? gate;
  int writes = 0;

  @override
  Future<void> write({required String key, required String value}) async {
    writes++;
    await gate?.future;
    await super.write(key: key, value: value);
  }
}

SeerrAccountSignIn _account(String name, {int permissions = 2}) =>
    SeerrAccountSignIn(
      kind: SeerrAccountKind.local,
      login: '$name@home.arpa',
      userId: 2,
      displayName: name,
      session: 'sentinel-$name',
      permissions: permissions,
    );

void main() {
  late SharedPreferences prefs;
  late _GatedStore store;

  final radarr = ServiceInstance(
    id: 'radarr',
    service: ServiceKey.radarr,
    url: 'http://nas.home.arpa:7878',
    credential: 'sentinel-radarr',
  );
  final sonarr = ServiceInstance(
    id: 'sonarr',
    service: ServiceKey.sonarr,
    url: 'http://nas.home.arpa:8989',
    credential: 'sentinel-sonarr',
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    store = _GatedStore();
  });

  ProviderContainer containerWith(SettingsModel initial) {
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith((ref) => prefs),
        secureSettingsStoreProvider.overrideWith((ref) => store),
        initialSettingsProvider.overrideWith((ref) => initial),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<SettingsModel> reload() =>
      SettingsService(prefs, store).loadSettings();

  test('two changes made together both land, in memory and on disk', () async {
    final container = containerWith(SettingsModel(instances: [radarr, sonarr]));
    final notifier = container.read(settingsProvider.notifier);
    // The first save stops on its first secret.
    await notifier.updateSettings(container.read(settingsProvider));
    store.gate = Completer<void>();

    final first = notifier.update(
      (current) => current.copyWithInstance(
        radarr.copyWith(credential: 'sentinel-radarr-2'),
      ),
    );
    final second = notifier.update(
      (current) => current.copyWithInstance(
        sonarr.copyWith(credential: 'sentinel-sonarr-2'),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    store.gate!.complete();
    await Future.wait([first, second]);

    final state = container.read(settingsProvider);
    expect(state.instanceById('radarr')?.credential, 'sentinel-radarr-2');
    expect(state.instanceById('sonarr')?.credential, 'sentinel-sonarr-2');
    final loaded = await reload();
    expect(loaded.instanceById('radarr')?.credential, 'sentinel-radarr-2');
    expect(loaded.instanceById('sonarr')?.credential, 'sentinel-sonarr-2');
  });

  test('two Seerr accounts answering together both keep their '
      'permissions', () async {
    final anna = ServiceInstance(
      id: 'seerr',
      service: ServiceKey.seerr,
      url: 'http://nas.home.arpa:5055',
      account: _account('anna'),
    );
    final sara = ServiceInstance(
      id: 'seerr-00000a1',
      service: ServiceKey.seerr,
      url: 'https://seerr.example.net',
      account: _account('sara'),
    );
    final container = containerWith(SettingsModel(instances: [anna, sara]));
    await container
        .read(settingsProvider.notifier)
        .updateSettings(container.read(settingsProvider));
    store.gate = Completer<void>();

    final accounts = container.read(seerrAccountsProvider);
    final both = Future.wait([
      accounts.recordWhoAmI('seerr', {'permissions': 32}),
      accounts.recordWhoAmI('seerr-00000a1', {'permissions': 64}),
    ]);
    await Future<void>.delayed(Duration.zero);
    store.gate!.complete();
    await both;

    final state = container.read(settingsProvider);
    expect(state.instanceById('seerr')?.account?.permissions, 32);
    expect(state.instanceById('seerr-00000a1')?.account?.permissions, 64);
    final loaded = await reload();
    expect(loaded.instanceById('seerr')?.account?.permissions, 32);
    expect(loaded.instanceById('seerr-00000a1')?.account?.permissions, 64);
  });

  test(
    'a change that returns the settings it was given writes nothing',
    () async {
      final container = containerWith(SettingsModel(instances: [radarr]));
      final notifier = container.read(settingsProvider.notifier);
      await notifier.updateSettings(container.read(settingsProvider));
      final before = store.writes;

      await notifier.update((current) => current);

      expect(store.writes, before);
    },
  );

  test('a write that fails changes nothing and the next one still lands '
      'whole', () async {
    final container = containerWith(SettingsModel(instances: [radarr, sonarr]));
    final notifier = container.read(settingsProvider.notifier);
    await notifier.updateSettings(container.read(settingsProvider));
    final before = container.read(settingsProvider);

    store.failureMessage = 'keychain locked';
    await expectLater(
      notifier.update(
        (current) => current.copyWithInstance(
          radarr.copyWith(credential: 'sentinel-radarr-2'),
        ),
      ),
      throwsException,
    );
    expect(container.read(settingsProvider), same(before));

    // The failed change never became state; a later one starts without it.
    store.failureMessage = null;
    await notifier.update((current) => current.copyWith(region: 'DE'));

    final loaded = await reload();
    expect(loaded.region, 'DE');
    expect(loaded.instanceById('radarr')?.credential, 'sentinel-radarr');
    expect(loaded.instanceById('sonarr')?.credential, 'sentinel-sonarr');
  });
}
