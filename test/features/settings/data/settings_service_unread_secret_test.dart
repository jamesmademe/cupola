/// A secret secure storage will not hand over costs its connection, never the
/// whole start, and is never deleted by the next save; a store that hands
/// nothing over stops the start; forgetting the keys keeps every connection,
/// each asking for its secret again.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/features/settings/data/settings_service.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/fake_secure_settings_store.dart';

void main() {
  late SharedPreferences prefs;
  late FakeSecureSettingsStore secureStore;
  late SettingsService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    secureStore = FakeSecureSettingsStore();
    service = SettingsService(prefs, secureStore);
    await prefs.setString('radarr_url', 'https://nas.lan:7878');
    await prefs.setString('sonarr_url', 'https://nas.lan:8989');
    await prefs.setString('qbittorrent_url', 'https://nas.lan:8080');
    await prefs.setString('qbittorrent_username', 'matt');
    await secureStore.write(key: 'secure_radarr_api_key', value: 'radarr-key');
    await secureStore.write(key: 'secure_sonarr_api_key', value: 'sonarr-key');
    await secureStore.write(
      key: 'secure_qbittorrent_password',
      value: 'qb-pass',
    );
  });

  ServiceInstance only(settings, ServiceKey key) =>
      settings.instancesOf(key).single as ServiceInstance;

  test('one unreadable key marks its connection, and the rest load', () async {
    secureStore.unreadable.add('secure_radarr_api_key');

    final settings = await service.loadSettings();

    final radarr = only(settings, ServiceKey.radarr);
    expect(radarr.unreadSecret, UnreadSecret.credential);
    expect(radarr.isConfigured, isFalse);
    expect(settings.hasServiceConnection(ServiceKey.radarr), isTrue);
    expect(settings.unreadConnectionOf(ServiceKey.radarr)?.id, radarr.id);
    expect(only(settings, ServiceKey.sonarr).credential, 'sonarr-key');
    expect(only(settings, ServiceKey.sonarr).unreadSecret, isNull);
  });

  test(
    'an unreadable password stops its sign-in service from being used',
    () async {
      secureStore.unreadable.add('secure_qbittorrent_password');

      final settings = await service.loadSettings();

      final qb = only(settings, ServiceKey.qbittorrent);
      expect(qb.unreadSecret, UnreadSecret.credential);
      // A sign-in service is otherwise configured by its address alone, and
      // an empty password counts against qBittorrent's ban.
      expect(qb.isConfigured, isFalse);
    },
  );

  test('saving does not delete a key it could not read', () async {
    secureStore.unreadable.add('secure_radarr_api_key');
    final settings = await service.loadSettings();

    // The address changes, the key field is left as it loaded.
    final radarr = only(settings, ServiceKey.radarr);
    await service.saveSettings(
      settings.copyWithInstance(radarr.copyWith(url: 'https://nas.lan:7879')),
    );

    secureStore.unreadable.clear();
    expect(secureStore.entries['secure_radarr_api_key'], 'radarr-key');
    final again = await service.loadSettings();
    expect(only(again, ServiceKey.radarr).credential, 'radarr-key');
    expect(only(again, ServiceKey.radarr).url, 'https://nas.lan:7879');
  });

  test('a key pasted again replaces the one that could not be read', () async {
    secureStore.unreadable.add('secure_radarr_api_key');
    final settings = await service.loadSettings();

    final pasted = only(
      settings,
      ServiceKey.radarr,
    ).copyWith(credential: 'new');
    expect(pasted.unreadSecret, isNull);
    await service.saveSettings(settings.copyWithInstance(pasted));

    expect(secureStore.entries['secure_radarr_api_key'], 'new');
  });

  test('a store that hands nothing over stops the load', () async {
    secureStore.unreadableAll = true;

    await expectLater(
      service.loadSettings(),
      throwsA(isA<SecureStorageUnavailable>()),
    );
  });

  test(
    'forgetting the keys keeps each connection, asking for its secret',
    () async {
      await service.forgetSecrets();

      expect(secureStore.entries, isEmpty);
      final settings = await service.loadSettings();
      for (final key in [
        ServiceKey.radarr,
        ServiceKey.sonarr,
        ServiceKey.qbittorrent,
      ]) {
        final instance = only(settings, key);
        expect(instance.url, isNotEmpty, reason: key.name);
        expect(
          instance.unreadSecret,
          UnreadSecret.credential,
          reason: key.name,
        );
      }

      // Pasted again, it is off the list for good.
      final radarr = only(
        settings,
        ServiceKey.radarr,
      ).copyWith(credential: 'k');
      await service.saveSettings(settings.copyWithInstance(radarr));
      final again = await service.loadSettings();
      expect(only(again, ServiceKey.radarr).unreadSecret, isNull);
      expect(
        only(again, ServiceKey.sonarr).unreadSecret,
        UnreadSecret.credential,
      );
    },
  );
}
