import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/features/settings/data/settings_service.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

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
  });

  /// An install written by a build that predates instances: values under the
  /// per-service keys, and no roster anywhere.
  Future<void> seedLegacyInstall() async {
    await prefs.setString('radarr_url', 'https://nas.lan:7878');
    await prefs.setString('sonarr_url', 'https://nas.lan:8989');
    await prefs.setString('qbittorrent_url', 'https://nas.lan:8080');
    await prefs.setString('qbittorrent_username', 'matt');
    await prefs.setString('jellyfin_url', 'https://nas.lan:8096');
    await prefs.setString('jellyfin_user_id', 'viewer-1');
    await secureStore.write(key: 'secure_radarr_api_key', value: 'radarr-key');
    await secureStore.write(key: 'secure_sonarr_api_key', value: 'sonarr-key');
    await secureStore.write(
      key: 'secure_qbittorrent_password',
      value: 'qb-pass',
    );
    await secureStore.write(key: 'secure_jellyfin_api_key', value: 'jelly-key');
  }

  group('an install that predates the roster', () {
    test('loads every connection it had, with no roster present', () async {
      await seedLegacyInstall();
      expect(prefs.getString('service_instances'), isNull);

      final settings = await service.loadSettings();

      expect(settings.radarrUrl, 'https://nas.lan:7878');
      expect(settings.radarrApiKey, 'radarr-key');
      expect(settings.qbittorrentUsername, 'matt');
      expect(settings.qbittorrentPassword, 'qb-pass');
      expect(settings.jellyfinUserId, 'viewer-1');
      expect(settings.instances.map((i) => i.id).toSet(), {
        'radarr',
        'sonarr',
        'qbittorrent',
        'jellyfin',
      });
    });

    test('mints no instance for the services it never set up', () async {
      await seedLegacyInstall();
      final settings = await service.loadSettings();

      expect(settings.instancesOf(ServiceKey.plex), isEmpty);
      expect(settings.instancesOf(ServiceKey.truenas), isEmpty);
      expect(settings.instances, hasLength(4));
    });

    test(
      'the roster appears on the next save, and the secrets do not move',
      () async {
        await seedLegacyInstall();
        final settings = await service.loadSettings();

        await service.saveSettings(settings);

        expect(prefs.getString('service_instances'), isNotNull);
        // The whole point of naming the first instance after the service.
        expect(
          await secureStore.read(key: 'secure_radarr_api_key'),
          'radarr-key',
        );
        expect(prefs.getString('radarr_url'), 'https://nas.lan:7878');
        expect(prefs.getString('jellyfin_user_id'), 'viewer-1');
      },
    );
  });

  group('a second instance', () {
    Future<SettingsModel> withTwoRadarr() async {
      await seedLegacyInstall();
      var settings = await service.loadSettings();
      settings = settings
          .copyWithInstance(
            settings.primaryOf(ServiceKey.radarr)!.copyWith(label: '4K'),
          )
          .copyWithInstance(
            settings
                .newInstanceFor(ServiceKey.radarr)
                .copyWith(
                  label: 'HD',
                  url: 'https://nas.lan:7879',
                  credential: 'hd-key',
                ),
          );
      await service.saveSettings(settings);
      return settings;
    }

    test('round-trips through storage with its label and order', () async {
      final saved = await withTwoRadarr();
      final reloaded = await service.loadSettings();

      final radarrs = reloaded.instancesOf(ServiceKey.radarr);
      expect(radarrs.map((i) => i.label), ['4K', 'HD']);
      expect(radarrs.map((i) => i.url), [
        'https://nas.lan:7878',
        'https://nas.lan:7879',
      ]);
      expect(radarrs.map((i) => i.credential), ['radarr-key', 'hd-key']);
      expect(
        reloaded.instances.map((i) => i.id),
        saved.instances.map((i) => i.id),
      );
    });

    test('writes to keys of its own, never onto the first one\'s', () async {
      await withTwoRadarr();
      final extraId = (await service.loadSettings())
          .instancesOf(ServiceKey.radarr)
          .last
          .id;

      expect(extraId, isNot('radarr'));
      expect(prefs.getString('${extraId}_url'), 'https://nas.lan:7879');
      expect(
        await secureStore.read(key: 'secure_${extraId}_api_key'),
        'hd-key',
      );
      // Untouched.
      expect(prefs.getString('radarr_url'), 'https://nas.lan:7878');
      expect(
        await secureStore.read(key: 'secure_radarr_api_key'),
        'radarr-key',
      );
    });

    test('a reorder survives the round trip', () async {
      await withTwoRadarr();
      var settings = await service.loadSettings();
      final radarrs = settings.instancesOf(ServiceKey.radarr);
      final others = settings.instances
          .where((i) => i.service != ServiceKey.radarr)
          .toList();

      settings = settings.copyWith(
        instances: [radarrs.last, radarrs.first, ...others],
      );
      await service.saveSettings(settings);

      final reloaded = await service.loadSettings();
      expect(reloaded.instancesOf(ServiceKey.radarr).map((i) => i.label), [
        'HD',
        '4K',
      ]);
      expect(reloaded.primaryOf(ServiceKey.radarr)?.label, 'HD');
      // Identity did not move with the order: values stay where they were.
      expect(
        reloaded.primaryOf(ServiceKey.radarr)?.url,
        'https://nas.lan:7879',
      );
    });
  });

  group('removing a connection forgets it', () {
    test('the extra instance leaves nothing behind, secret included', () async {
      await seedLegacyInstall();
      var settings = await service.loadSettings();
      final extra = settings
          .newInstanceFor(ServiceKey.radarr)
          .copyWith(
            label: 'HD',
            url: 'https://nas.lan:7879',
            credential: 'hd-key',
            username: 'someone',
          );
      await service.saveSettings(settings.copyWithInstance(extra));

      expect(prefs.getString('${extra.id}_url'), isNotNull);

      settings = (await service.loadSettings()).copyWithoutInstance(extra.id);
      await service.saveSettings(settings);

      expect(prefs.getString('${extra.id}_url'), isNull);
      expect(prefs.getString('${extra.id}_username'), isNull);
      // The one that matters: an orphaned key would sit in the keychain for the
      // life of the install, unreachable and still a secret.
      expect(await secureStore.read(key: extra.credentialStorageKey), isNull);
      expect(
        (await service.loadSettings()).instancesOf(ServiceKey.radarr),
        hasLength(1),
      );
    });

    test('removing the only instance clears the primary keys too', () async {
      await seedLegacyInstall();
      final settings = (await service.loadSettings()).copyWithoutInstance(
        'sonarr',
      );
      await service.saveSettings(settings);

      expect(prefs.getString('sonarr_url'), isNull);
      expect(await secureStore.read(key: 'secure_sonarr_api_key'), isNull);
      // And it does not come back through the legacy walk on the next load.
      expect(
        (await service.loadSettings()).instancesOf(ServiceKey.sonarr),
        isEmpty,
      );
    });

    test(
      'the Plex install id survives a Plex instance being removed',
      () async {
        await prefs.setString('plex_url', 'https://nas.lan:32400');
        await secureStore.write(key: 'secure_plex_token', value: 'tok');
        var settings = await service.loadSettings();
        final clientId = settings.plexClientId;
        expect(clientId, isNotEmpty);

        settings = settings.copyWithoutInstance('plex');
        await service.saveSettings(settings);

        expect(prefs.getString('plex_url'), isNull);
        expect(prefs.getString('plex_client_id'), clientId);
        expect((await service.loadSettings()).plexClientId, clientId);
      },
    );
  });

  group('a roster that cannot be trusted', () {
    test('garbage json falls back to the connections on disk', () async {
      await seedLegacyInstall();
      await prefs.setString('service_instances', 'not json at all');

      final settings = await service.loadSettings();

      expect(settings.radarrUrl, 'https://nas.lan:7878');
      expect(settings.instances, hasLength(4));
    });

    test('an unknown service name is skipped, the rest still load', () async {
      await seedLegacyInstall();
      await prefs.setString(
        'service_instances',
        jsonEncode([
          {'id': 'radarr', 'service': 'radarr', 'label': '4K'},
          {'id': 'ghost', 'service': 'somethingRemoved', 'label': 'x'},
        ]),
      );

      final settings = await service.loadSettings();

      expect(settings.primaryOf(ServiceKey.radarr)?.label, '4K');
      expect(settings.instanceById('ghost'), isNull);
      // The three the roster forgot to mention are still here: a roster that
      // lost a write must not hide a connection that is plainly on disk.
      expect(settings.instances, hasLength(4));
    });
  });

  test('clearAll wipes the extras and the roster with them', () async {
    await seedLegacyInstall();
    var settings = await service.loadSettings();
    final extra = settings
        .newInstanceFor(ServiceKey.radarr)
        .copyWith(
          label: 'HD',
          url: 'https://nas.lan:7879',
          credential: 'hd-key',
        );
    settings = settings.copyWithInstance(extra);
    await service.saveSettings(settings);

    await service.clearAll();

    expect(prefs.getString('service_instances'), isNull);
    expect(prefs.getString('${extra.id}_url'), isNull);
    expect(await secureStore.read(key: extra.credentialStorageKey), isNull);
    expect((await service.loadSettings()).instances, isEmpty);
  });
}
