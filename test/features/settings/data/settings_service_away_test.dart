import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/features/settings/data/settings_service.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/connection_address.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/fake_secure_settings_store.dart';

/// A connection's address away from home survives a restart beside the one
/// at home, its access keeps its secrets out of `SharedPreferences` and apart
/// from the access at home, and removing it removes them.
void main() {
  late SharedPreferences prefs;
  late FakeSecureSettingsStore secureStore;
  late SettingsService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    secureStore = FakeSecureSettingsStore();
    service = SettingsService(prefs, secureStore);
  });

  const radarr = ServiceInstance(
    id: 'radarr',
    service: ServiceKey.radarr,
    url: 'http://192.168.1.20:7878',
    credential: 'radarr-key',
  );
  const radarr4k = ServiceInstance(
    id: 'radarr-4k00001',
    service: ServiceKey.radarr,
    label: '4K',
    url: 'http://192.168.1.20:7879',
    credential: 'radarr4k-key',
  );

  const token = CloudflareServiceToken(
    clientId: '1a2b3c.access',
    clientSecret: 'sentinel-away-secret',
  );
  const custom = CustomHeaders([
    (name: 'X-Proxy-Key', value: 'sentinel-away-header'),
  ]);
  const away = ConnectionAddress(
    url: 'https://radarr.example.com',
    access: token,
  );

  Future<SettingsModel> saveAndReload(List<ServiceInstance> instances) async {
    await service.saveSettings(SettingsModel(instances: instances));
    return SettingsService(prefs, secureStore).loadSettings();
  }

  String everythingInPrefs() =>
      [for (final key in prefs.getKeys()) '$key=${prefs.get(key)}'].join('\n');

  test('a connection saved before addresses away reads as home only', () async {
    await prefs.setString('radarr_url', 'http://192.168.1.20:7878');
    await secureStore.write(key: 'secure_radarr_api_key', value: 'radarr-key');

    final settings = await service.loadSettings();

    expect(settings.primaryOf(ServiceKey.radarr)?.away, isNull);
  });

  test('the address away and its access survive a restart', () async {
    final loaded = await saveAndReload([radarr.copyWith(away: away)]);

    final reloaded = loaded.primaryOf(ServiceKey.radarr)!;
    expect(reloaded.away, away);
    expect(reloaded.url, radarr.url, reason: 'the address at home is kept');
    expect(reloaded.access, const NoAccess(), reason: 'home asks for nothing');
  });

  test('the access away is stored apart from the access at home', () async {
    await saveAndReload([
      radarr.copyWith(
        access: custom,
        away: const ConnectionAddress(url: 'https://radarr.example.com'),
      ),
    ]);
    expect(prefs.getString('radarr_away_url'), 'https://radarr.example.com');
    expect(prefs.getString('radarr_away_access'), isNull);
    expect(prefs.getString('radarr_access'), isNotNull);

    final loaded = await saveAndReload([radarr.copyWith(away: away)]);
    final reloaded = loaded.primaryOf(ServiceKey.radarr)!;
    expect(reloaded.access, const NoAccess());
    expect(reloaded.away!.access, token);
    expect(jsonDecode(prefs.getString('radarr_away_access')!), {
      'kind': 'cloudflare',
      'clientId': '1a2b3c.access',
    });
    expect(
      await secureStore.read(key: 'secure_radarr_away_access_secret'),
      'sentinel-away-secret',
    );
  });

  test('no secret of the access away reaches SharedPreferences', () async {
    await saveAndReload([
      radarr.copyWith(away: away),
      radarr4k.copyWith(
        away: const ConnectionAddress(
          url: 'https://radarr4k.example.com',
          access: custom,
        ),
      ),
    ]);

    expect(everythingInPrefs(), isNot(contains('sentinel')));
  });

  test('a second connection keeps its own address away', () async {
    final loaded = await saveAndReload([radarr, radarr4k.copyWith(away: away)]);

    expect(loaded.instanceById('radarr')!.away, isNull);
    expect(loaded.instanceById('radarr-4k00001')!.away, away);
  });

  test('taking the address away off removes it and its secrets', () async {
    await saveAndReload([radarr.copyWith(away: away)]);

    final loaded = await saveAndReload([radarr]);

    expect(loaded.primaryOf(ServiceKey.radarr)!.away, isNull);
    expect(prefs.getString('radarr_away_url'), isNull);
    expect(prefs.getString('radarr_away_access'), isNull);
    expect(secureStore.entries.keys, isNot(contains(contains('away'))));
  });

  test('removing the connection removes its address away', () async {
    await saveAndReload([radarr, radarr4k.copyWith(away: away)]);

    await saveAndReload([radarr]);

    expect(prefs.getKeys().where((key) => key.contains('away')), isEmpty);
    expect(secureStore.entries.keys.where((k) => k.contains('away')), isEmpty);
  });

  test('resetting the app removes every address away', () async {
    await service.saveSettings(
      SettingsModel(
        instances: [
          radarr.copyWith(away: away),
          radarr4k.copyWith(away: away),
        ],
      ),
    );

    await service.clearAll();

    expect(prefs.getKeys().where((key) => key.contains('away')), isEmpty);
    expect(secureStore.entries, isEmpty);
  });

  test('a secret away the keychain will not hand over marks the access unread, '
      'and saving leaves it where it is', () async {
    await service.saveSettings(
      SettingsModel(instances: [radarr.copyWith(away: away)]),
    );
    secureStore.unreadable.add('secure_radarr_away_access_secret');

    final loaded = await SettingsService(prefs, secureStore).loadSettings();
    final reloaded = loaded.primaryOf(ServiceKey.radarr)!;
    expect(reloaded.unreadSecret, UnreadSecret.access);
    expect(reloaded.isConfigured, isFalse);

    await SettingsService(prefs, secureStore).saveSettings(loaded);
    secureStore.unreadable.clear();

    expect(
      await secureStore.read(key: 'secure_radarr_away_access_secret'),
      'sentinel-away-secret',
    );
  });

  test('the address away prints its kind of access, never a value', () {
    final printed = '${radarr.copyWith(away: away)}';

    expect(printed, contains('https://radarr.example.com'));
    expect(printed, contains('cloudflare'));
    expect(printed, isNot(contains('sentinel')));
  });
}
