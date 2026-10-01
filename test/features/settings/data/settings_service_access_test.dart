import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/features/settings/data/settings_service.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/fake_secure_settings_store.dart';

/// A connection's access survives a restart, its secrets stay out of
/// `SharedPreferences`, and removing the connection removes them.
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
    url: 'https://radarr.example.com',
    credential: 'radarr-key',
  );
  const radarr4k = ServiceInstance(
    id: 'radarr-4k00001',
    service: ServiceKey.radarr,
    label: '4K',
    url: 'https://radarr4k.example.com',
    credential: 'radarr4k-key',
  );

  const token = CloudflareServiceToken(
    clientId: '1a2b3c.access',
    clientSecret: 'sentinel-cf-secret',
  );
  const password = ProxyPassword(
    username: 'matt',
    password: 'sentinel-proxy-password',
  );
  const custom = CustomHeaders([
    (name: 'X-Proxy-Key', value: 'sentinel-header-one'),
    (name: 'X-Tenant', value: 'sentinel-header-two'),
  ]);

  Future<SettingsModel> saveAndReload(List<ServiceInstance> instances) async {
    await service.saveSettings(SettingsModel(instances: instances));
    return SettingsService(prefs, secureStore).loadSettings();
  }

  /// Every value `SharedPreferences` holds, as one string.
  String everythingInPrefs() =>
      [for (final key in prefs.getKeys()) '$key=${prefs.get(key)}'].join('\n');

  test('a connection saved before access existed reads as no access', () async {
    await prefs.setString('radarr_url', 'https://radarr.example.com');
    await secureStore.write(key: 'secure_radarr_api_key', value: 'radarr-key');

    final settings = await service.loadSettings();

    expect(settings.primaryOf(ServiceKey.radarr)?.access, const NoAccess());
  });

  for (final (name, access) in <(String, ConnectionAccess)>[
    ('a Cloudflare service token', token),
    ('a proxy password', password),
    ('custom headers', custom),
  ]) {
    group(name, () {
      test(
        'survives a restart, on the first connection and a second',
        () async {
          final loaded = await saveAndReload([
            radarr.copyWith(access: access),
            radarr4k.copyWith(access: access),
          ]);

          expect(loaded.instanceById(radarr.id)?.access, access);
          expect(loaded.instanceById(radarr4k.id)?.access, access);
        },
      );

      test(
        'keeps its secrets in secure storage, never in preferences',
        () async {
          await service.saveSettings(
            SettingsModel(instances: [radarr.copyWith(access: access)]),
          );

          expect(everythingInPrefs(), isNot(contains('sentinel')));
          expect(
            secureStore.entries.values.where((v) => v.startsWith('sentinel')),
            isNotEmpty,
          );
          // Under keys the connection's id derives, like its credential.
          for (final key in secureStore.entries.keys) {
            if (secureStore.entries[key]!.startsWith('sentinel')) {
              expect(key, startsWith('secure_radarr_access_'));
            }
          }
        },
      );

      test('goes with the connection when it is removed', () async {
        await service.saveSettings(
          SettingsModel(
            instances: [
              radarr,
              radarr4k.copyWith(access: access),
            ],
          ),
        );
        await service.saveSettings(const SettingsModel(instances: [radarr]));

        expect(prefs.getString(radarr4k.accessStorageKey), isNull);
        expect(
          secureStore.entries.keys.where((k) => k.contains(radarr4k.id)),
          isEmpty,
        );
      });

      test('goes when the connection is set back to None', () async {
        await service.saveSettings(
          SettingsModel(instances: [radarr.copyWith(access: access)]),
        );
        final loaded = await saveAndReload([radarr]);

        expect(loaded.primaryOf(ServiceKey.radarr)?.access, const NoAccess());
        expect(prefs.getString(radarr.accessStorageKey), isNull);
        expect(
          secureStore.entries.keys.where((k) => k.contains('_access_')),
          isEmpty,
        );
      });
    });
  }

  test('the non-secret half sits beside the address', () async {
    await service.saveSettings(
      SettingsModel(instances: [radarr.copyWith(access: token)]),
    );

    expect(jsonDecode(prefs.getString('radarr_access')!), {
      'kind': 'cloudflare',
      'clientId': '1a2b3c.access',
    });
    expect(
      await secureStore.read(key: 'secure_radarr_access_secret'),
      'sentinel-cf-secret',
    );
  });

  test('a shorter header list leaves no stale value behind', () async {
    await service.saveSettings(
      SettingsModel(instances: [radarr.copyWith(access: custom)]),
    );
    final loaded = await saveAndReload([
      radarr.copyWith(
        access: const CustomHeaders([
          (name: 'X-Proxy-Key', value: 'sentinel-header-one'),
        ]),
      ),
    ]);

    expect(
      loaded.primaryOf(ServiceKey.radarr)?.access,
      const CustomHeaders([
        (name: 'X-Proxy-Key', value: 'sentinel-header-one'),
      ]),
    );
    expect(
      await secureStore.read(key: radarr.accessHeaderStorageKey(1)),
      isNull,
    );
  });

  test('moving from a token to headers drops the token secret', () async {
    await service.saveSettings(
      SettingsModel(instances: [radarr.copyWith(access: token)]),
    );
    await service.saveSettings(
      SettingsModel(instances: [radarr.copyWith(access: custom)]),
    );

    expect(await secureStore.read(key: radarr.accessSecretStorageKey), isNull);
  });

  test('a stored value this build cannot read costs the access, not the '
      'connection', () async {
    await service.saveSettings(const SettingsModel(instances: [radarr]));
    await prefs.setString('radarr_access', '{"kind":"oauth"}');
    final first = await service.loadSettings();
    await prefs.setString('radarr_access', 'not json');
    final second = await service.loadSettings();

    for (final settings in [first, second]) {
      final loaded = settings.primaryOf(ServiceKey.radarr);
      expect(loaded?.url, radarr.url);
      expect(loaded?.access, const NoAccess());
    }
  });

  test('resetting the app removes every access value', () async {
    await service.saveSettings(
      SettingsModel(
        instances: [
          radarr.copyWith(access: token),
          radarr4k.copyWith(access: custom),
        ],
      ),
    );

    await service.clearAll();

    expect(prefs.getKeys().where((key) => key.endsWith('_access')), isEmpty);
    expect(secureStore.entries, isEmpty);
  });
}
