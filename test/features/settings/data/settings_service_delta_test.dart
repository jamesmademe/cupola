import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// The in-memory store is the only seam that sees every preferences write.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'package:cupola/features/discover/domain/seerr_sign_in.dart';
import 'package:cupola/features/settings/data/settings_service.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/connection_address.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/fake_secure_settings_store.dart';

/// Saving settings writes what changed, and a reload from nothing but disk
/// always gives back exactly what was saved.
///
/// The same scenarios run twice: whole-model saves (what every save did
/// before) and saves against the last persisted model. Whatever the mode, the
/// disk afterwards must be byte for byte what one whole-model save of the
/// final model writes on an empty install.

/// Counts and, on demand, interrupts every write to preferences and to secure
/// storage, in the one order they happen.
class _Ops {
  int writes = 0;
  int? interruptAt;

  void tick() {
    writes++;
    final at = interruptAt;
    if (at != null && writes >= at) {
      throw StateError('interrupted');
    }
  }
}

class _CountingPrefsStore extends InMemorySharedPreferencesStore {
  _CountingPrefsStore(this.ops, Map<String, Object> data)
    : super.withData(data);

  final _Ops ops;
  int prefsWrites = 0;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    ops.tick();
    prefsWrites++;
    return super.setValue(valueType, key, value);
  }

  @override
  Future<bool> remove(String key) async {
    ops.tick();
    prefsWrites++;
    return super.remove(key);
  }
}

class _CountingSecureStore extends FakeSecureSettingsStore {
  _CountingSecureStore(this.ops);

  final _Ops ops;
  int secureWrites = 0;

  @override
  Future<void> write({required String key, required String value}) async {
    ops.tick();
    secureWrites++;
    await super.write(key: key, value: value);
  }

  @override
  Future<void> delete({required String key}) async {
    ops.tick();
    secureWrites++;
    await super.delete(key: key);
  }
}

/// One install: its preferences store, secure store and a service over them.
class _Disk {
  _Disk._(this.ops, this.prefsStore, this.secure);

  final _Ops ops;
  final _CountingPrefsStore prefsStore;
  final _CountingSecureStore secure;

  static Future<_Disk> empty() async {
    final ops = _Ops();
    final prefsStore = _CountingPrefsStore(ops, {});
    return _Disk._(ops, prefsStore, _CountingSecureStore(ops));
  }

  Future<SharedPreferences> prefs() async {
    SharedPreferencesStorePlatform.instance = prefsStore;
    SharedPreferences.resetStatic();
    return SharedPreferences.getInstance();
  }

  /// A service started now, as a new process would.
  Future<SettingsService> service() async =>
      SettingsService(await prefs(), secure);

  /// Everything on disk, read back from nothing.
  Future<SettingsModel> reload() async {
    final saved = ops.interruptAt;
    ops.interruptAt = null;
    final model = await (await service()).loadSettings();
    ops.interruptAt = saved;
    return model;
  }

  /// Every key and value on disk, preferences then secure storage.
  Future<Map<String, String>> dump() async => {
    for (final entry in (await prefsStore.getAll()).entries)
      'prefs:${entry.key}': '${entry.value}',
    for (final entry in secure.entries.entries)
      'secure:${entry.key}': entry.value,
  };
}

final _cloudflare = const CloudflareServiceToken(
  clientId: 'id-one',
  clientSecret: 'sentinel-cf-secret',
);

ServiceInstance _primary(
  ServiceKey key, {
  String url = 'http://nas.home.arpa:7878',
  String credential = '',
  String username = '',
  String viewerId = '',
  ConnectionAccess access = const NoAccess(),
  ConnectionAddress? away,
  SeerrAccountSignIn? account,
}) => ServiceInstance(
  id: ServiceInstance.primaryIdFor(key),
  service: key,
  url: url,
  credential: credential,
  username: username,
  viewerId: viewerId,
  access: access,
  away: away,
  account: account,
);

final _account = SeerrAccountSignIn(
  kind: SeerrAccountKind.local,
  login: 'anna@home.arpa',
  userId: 2,
  displayName: 'Anna',
  session: 'sentinel-session',
  permissions: 32,
  checkedAt: DateTime.utc(2026, 10, 1, 20, 41),
);

/// Six connections of every kind of stored thing: keys, credentials, a viewer,
/// a second instance, gateways at home and away, a Seerr account, a trusted
/// certificate.
SettingsModel _installed() => SettingsModel(
  region: 'IT',
  themeMode: AppThemeMode.light,
  plexClientId: 'plex-client-0001',
  trustedCertificates: const {'https://truenas.home.arpa:443': 'abcd1234'},
  instances: [
    _primary(
      ServiceKey.radarr,
      credential: 'sentinel-radarr-key',
      access: _cloudflare,
      away: const ConnectionAddress(
        url: 'https://radarr.example.net',
        access: CustomHeaders([
          (name: 'X-One', value: 'sentinel-h1'),
          (name: 'X-Two', value: 'sentinel-h2'),
          (name: 'X-Three', value: 'sentinel-h3'),
        ]),
      ),
    ),
    ServiceInstance(
      id: 'radarr-00000a1',
      service: ServiceKey.radarr,
      label: '4K',
      url: 'http://nas.home.arpa:7879',
      credential: 'sentinel-radarr4k-key',
    ),
    _primary(
      ServiceKey.sonarr,
      url: 'http://nas.home.arpa:8989',
      credential: 'sentinel-sonarr-key',
      access: const ProxyPassword(
        username: 'proxy-user',
        password: 'sentinel-proxy-pass',
      ),
    ),
    _primary(
      ServiceKey.qbittorrent,
      url: 'https://nas.home.arpa:8080',
      username: 'admin',
      credential: 'sentinel-qb-pass',
    ),
    _primary(
      ServiceKey.jellyfin,
      url: 'http://nas.home.arpa:8096',
      credential: 'sentinel-jf-key',
      viewerId: 'viewer-77',
    ),
    _primary(
      ServiceKey.seerr,
      url: 'http://nas.home.arpa:5055',
      account: _account,
    ),
  ],
);

/// [_installed] after a user's afternoon: a key changed, a password and an
/// away address taken off, headers shrunk, a connection removed, an account
/// replaced by a key, a new connection added, the theme and the trust map
/// changed. The Sonarr key, the Cloudflare secret and the Radarr key are
/// untouched.
SettingsModel _afterwards() {
  final before = _installed();
  return SettingsModel(
    region: 'IT',
    themeMode: AppThemeMode.dark,
    plexClientId: 'plex-client-0001',
    instances: [
      for (final instance in before.instances)
        if (instance.id == 'radarr-00000a1')
          // gone
          ...const <ServiceInstance>[]
        else if (instance.service == ServiceKey.radarr)
          instance.copyWith(
            away: const ConnectionAddress(
              url: 'https://radarr.example.net',
              access: CustomHeaders([(name: 'X-One', value: 'sentinel-h1')]),
            ),
          )
        else if (instance.service == ServiceKey.qbittorrent)
          instance.copyWith(credential: '')
        else if (instance.service == ServiceKey.jellyfin)
          instance.copyWith(credential: 'sentinel-jf-key-2', viewerId: '')
        else if (instance.service == ServiceKey.seerr)
          instance.copyWith(clearAccount: true, credential: 'sentinel-seerr')
        else
          instance,
      _primary(
        ServiceKey.lidarr,
        url: 'http://nas.home.arpa:8686',
        credential: 'sentinel-lidarr-key',
      ),
    ],
  );
}

/// The keys whose value differs between two installs, never the values.
Future<List<String>> _differences(_Disk a, _Disk b) async {
  final left = await a.dump();
  final right = await b.dump();
  return [
    for (final key in {...left.keys, ...right.keys})
      if (left[key] != right[key]) key,
  ]..sort();
}

SettingsModel _withKey(SettingsModel model, String id, String credential) =>
    model.copyWith(
      instances: [
        for (final instance in model.instances)
          if (instance.id == id)
            instance.copyWith(credential: credential)
          else
            instance,
      ],
    );

void main() {
  for (final delta in [false, true]) {
    group(delta ? 'saving against the last persisted' : 'whole-model', () {
      Future<void> save(
        SettingsService service,
        SettingsModel next,
        SettingsModel? previous,
      ) => service.saveSettings(next);

      Future<_Disk> savedThrough(List<SettingsModel> models) async {
        final disk = await _Disk.empty();
        final service = await disk.service();
        SettingsModel? last;
        for (final model in models) {
          await save(service, model, last);
          last = model;
        }
        return disk;
      }

      Future<_Disk> wholeOnEmpty(SettingsModel model) async {
        final disk = await _Disk.empty();
        await (await disk.service()).saveSettings(model);
        return disk;
      }

      void expectSameAs(SettingsModel loaded, SettingsModel expected) {
        expect(loaded.region, expected.region);
        expect(loaded.themeMode, expected.themeMode);
        expect(loaded.trustedCertificates, expected.trustedCertificates);
        expect(loaded.plexClientId, expected.plexClientId);
        expect(
          [for (final i in loaded.instances) i.id],
          [for (final i in expected.instances) i.id],
        );
        for (final instance in expected.instances) {
          expect(
            loaded.instanceById(instance.id),
            instance,
            reason: 'instance ${instance.id}',
          );
        }
      }

      test(
        'a reload gives back what was saved, instance by instance',
        () async {
          final disk = await savedThrough([_installed()]);
          expectSameAs(await disk.reload(), _installed());
        },
      );

      test('after changes, additions and removals the reload is the saved '
          'model and the disk is what one whole save writes', () async {
        final disk = await savedThrough([_installed(), _afterwards()]);

        expectSameAs(await disk.reload(), _afterwards());
        expect(
          await _differences(disk, await wholeOnEmpty(_afterwards())),
          isEmpty,
        );
      });

      test('taking everything off leaves nothing behind', () async {
        const bare = SettingsModel(region: 'IT', plexClientId: 'plex-0001');
        final disk = await savedThrough([_installed(), _afterwards(), bare]);

        expect(await _differences(disk, await wholeOnEmpty(bare)), isEmpty);
        expect(disk.secure.entries, isEmpty);
      });

      test('no secret ever reaches preferences', () async {
        final disk = await savedThrough([_installed(), _afterwards()]);

        for (final entry in (await disk.prefsStore.getAll()).entries) {
          expect('${entry.value}', isNot(contains('sentinel')));
        }
      });

      test('changing one secret leaves the others as they were', () async {
        final disk = await savedThrough([
          _installed(),
          _withKey(_installed(), 'sonarr', 'sentinel-sonarr-key-2'),
        ]);

        final loaded = await disk.reload();
        expect(
          loaded.instanceById('sonarr')?.credential,
          'sentinel-sonarr-key-2',
        );
        expect(
          loaded.instanceById('radarr')?.credential,
          'sentinel-radarr-key',
        );
        expect(loaded.instanceById('radarr')?.access, _cloudflare);
        expect(
          loaded.instanceById('radarr-00000a1')?.credential,
          'sentinel-radarr4k-key',
        );
        expect(loaded.instanceById('seerr')?.account, _account);
      });

      test('a legacy Seerr key and address survive saves of something '
          'else', () async {
        // An install from before the rename: the connection lives only under
        // the old keys, which the load falls back to.
        final disk = await _Disk.empty();
        final prefs = await disk.prefs();
        await prefs.setString('jellyseerr_url', 'http://nas.home.arpa:5055');
        await disk.secure.write(
          key: 'secure_jellyseerr_api_key',
          value: 'sentinel-legacy-seerr',
        );
        final service = await disk.service();
        final loaded = await service.loadSettings();
        expect(
          loaded.instanceById('seerr')?.credential,
          'sentinel-legacy-seerr',
        );

        final light = loaded.copyWith(themeMode: AppThemeMode.light);
        await save(service, light, loaded);
        await save(service, light.copyWith(region: 'DE'), light);

        final again = await disk.reload();
        expect(
          again.instanceById('seerr')?.credential,
          'sentinel-legacy-seerr',
        );
        expect(again.instanceById('seerr')?.url, 'http://nas.home.arpa:5055');
        expect(again.region, 'DE');
      });

      test('an interrupted save never costs a secret that did not change, '
          'and saving again finishes the job', () async {
        // How many writes the whole second save takes, to interrupt at each.
        final probe = await _Disk.empty();
        final probeService = await probe.service();
        await save(probeService, _installed(), null);
        probe.ops.writes = 0;
        await save(probeService, _afterwards(), _installed());
        final total = probe.ops.writes;
        expect(total, greaterThan(0));

        for (var k = 1; k <= total; k++) {
          final disk = await _Disk.empty();
          final service = await disk.service();
          await save(service, _installed(), null);

          // Whole-model: a new process saves next, as an app restarted.
          final saving = delta ? service : await disk.service();
          disk.ops
            ..writes = 0
            ..interruptAt = k;
          Object? failure;
          try {
            await save(saving, _afterwards(), _installed());
          } on StateError catch (error) {
            failure = error;
          }
          disk.ops.interruptAt = null;
          expect(failure, isNotNull, reason: 'interrupted at write $k');

          final loaded = await disk.reload();
          expect(
            loaded.instanceById('radarr')?.credential,
            'sentinel-radarr-key',
            reason: 'interrupted at write $k',
          );
          expect(
            loaded.instanceById('radarr')?.access,
            _cloudflare,
            reason: 'interrupted at write $k',
          );
          expect(
            loaded.instanceById('sonarr')?.credential,
            'sentinel-sonarr-key',
            reason: 'interrupted at write $k',
          );
          expect(
            loaded.instanceById('sonarr')?.access,
            const ProxyPassword(
              username: 'proxy-user',
              password: 'sentinel-proxy-pass',
            ),
            reason: 'interrupted at write $k',
          );

          // The last model written whole is still the one to diff against.
          await save(saving, _afterwards(), _installed());
          expect(
            await _differences(disk, await wholeOnEmpty(_afterwards())),
            isEmpty,
            reason: 'saved again after write $k',
          );
        }
      });
    });
  }
}
