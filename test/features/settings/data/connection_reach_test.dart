import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/features/settings/data/connection_reach_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/data/settings_service.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/connection_address.dart';
import 'package:cupola/features/settings/domain/connection_reach.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/fake_secure_settings_store.dart';

final _transportProvider = Provider.family<ServiceTransport, ServiceKey>(
  (ref, service) => watchTransport(ref, service),
);

const _token = CloudflareServiceToken(
  clientId: 'id.access',
  clientSecret: 'sentinel-secret',
);
const _radarr = ServiceInstance(
  id: 'radarr',
  service: ServiceKey.radarr,
  url: 'https://192.168.1.20:7878',
  credential: 'radarr-key',
  away: ConnectionAddress(url: 'https://radarr.example.com', access: _token),
);
const _sonarr = ServiceInstance(
  id: 'sonarr',
  service: ServiceKey.sonarr,
  url: 'http://192.168.1.20:8989',
  credential: 'sonarr-key',
);
const _homePin =
    'aa:bb:cc:dd:ee:ff:00:11:22:33:44:55:66:77:88:99:'
    'aa:bb:cc:dd:ee:ff:00:11:22:33:44:55:66:77:88:99';
const _awayPin =
    '11:22:33:44:55:66:77:88:99:00:aa:bb:cc:dd:ee:ff:'
    '11:22:33:44:55:66:77:88:99:00:aa:bb:cc:dd:ee:ff';

SettingsModel get _settings =>
    const SettingsModel(instances: [_radarr, _sonarr])
        .copyWithTrustedCertificate(url: _radarr.url, fingerprint: _homePin)
        .copyWithTrustedCertificate(
          url: _radarr.away!.url,
          fingerprint: _awayPin,
        );

Future<ProviderContainer> _container() async {
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      secureSettingsStoreProvider.overrideWithValue(FakeSecureSettingsStore()),
      currentSettingsProvider.overrideWith((ref) => _settings),
      initialActiveInstancesProvider.overrideWithValue(const {}),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('reachOf', () {
    test('at home: the address saved, its access, its pin', () {
      final reach = reachOf(_settings, _radarr, ConnectionRoute.home);

      expect(reach.url, 'https://192.168.1.20:7878');
      expect(reach.access, const NoAccess());
      expect(reach.pin, _homePin);
    });

    test('away: the address away, its gateway access, its own pin', () {
      final reach = reachOf(_settings, _radarr, ConnectionRoute.away);

      expect(reach.url, 'https://radarr.example.com');
      expect(reach.access, _token);
      expect(reach.pin, _awayPin);
    });

    test('a connection with one address is at home on either route', () {
      expect(
        reachOf(_settings, _sonarr, ConnectionRoute.away),
        reachOf(_settings, _sonarr, ConnectionRoute.home),
      );
    });
  });

  group('watchTransport', () {
    test('reaches the address at home until the route moves', () async {
      final container = await _container();

      expect(
        container.read(_transportProvider(ServiceKey.radarr)).url,
        'https://192.168.1.20:7878',
      );

      await container
          .read(connectionRoutesProvider.notifier)
          .set('radarr', ConnectionRoute.away);
      final away = container.read(_transportProvider(ServiceKey.radarr));

      expect(away.url, 'https://radarr.example.com');
      expect(away.access, _token);
      expect(away.pin, _awayPin);
      expect(away.apiKey, 'radarr-key', reason: 'the same server, same key');
    });

    test('moving one route rebuilds another connection only to say it is '
        'only at home', () async {
      final container = await _container();
      var sonarrBuilds = 0;
      container.listen(
        _transportProvider(ServiceKey.sonarr),
        (_, _) => sonarrBuilds++,
        fireImmediately: true,
      );
      expect(
        container.read(_transportProvider(ServiceKey.sonarr)).onlyAtHome,
        isFalse,
      );

      // Radarr moving away takes the app away: Sonarr, with no address away,
      // is now the one nothing may be sent to.
      await container
          .read(connectionRoutesProvider.notifier)
          .set('radarr', ConnectionRoute.away);
      final away = container.read(_transportProvider(ServiceKey.sonarr));
      expect(sonarrBuilds, 2);
      expect(away.onlyAtHome, isTrue);
      // The client built off it refuses every request without dialling.
      expect(away.onlyAtHomeOf(ServiceKey.sonarr), ServiceKey.sonarr);
      // Its address is untouched: the home one, for the day it comes back.
      expect(away.url, 'http://192.168.1.20:8989');

      await container
          .read(connectionRoutesProvider.notifier)
          .set('radarr', ConnectionRoute.home);
      expect(
        container.read(_transportProvider(ServiceKey.sonarr)).onlyAtHome,
        isFalse,
      );
      expect(sonarrBuilds, 3);
    });
  });

  test('connectionReachProvider follows its connection\'s route', () async {
    final container = await _container();
    expect(
      container.read(connectionReachProvider('radarr'))?.url,
      'https://192.168.1.20:7878',
    );

    await container
        .read(connectionRoutesProvider.notifier)
        .set('radarr', ConnectionRoute.away);

    expect(
      container.read(connectionReachProvider('radarr'))?.url,
      'https://radarr.example.com',
    );
    expect(container.read(connectionReachProvider('gone')), isNull);
  });

  group('the routes', () {
    test('are remembered for the next launch, away only', () async {
      final container = await _container();
      final routes = container.read(connectionRoutesProvider.notifier);

      await routes.set('radarr', ConnectionRoute.away);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('connection_routes'), '["radarr"]');
      expect(
        SettingsService(
          prefs,
          FakeSecureSettingsStore(),
        ).loadConnectionRoutes(),
        {'radarr': ConnectionRoute.away},
      );

      await routes.set('radarr', ConnectionRoute.home);
      expect(prefs.getString('connection_routes'), isNull);
    });

    test(
      'a value that does not parse reads as every connection at home',
      () async {
        SharedPreferences.setMockInitialValues({'connection_routes': '{nope'});
        final prefs = await SharedPreferences.getInstance();

        expect(
          SettingsService(
            prefs,
            FakeSecureSettingsStore(),
          ).loadConnectionRoutes(),
          isEmpty,
        );
      },
    );

    test('resetting the app forgets them', () async {
      SharedPreferences.setMockInitialValues({
        'connection_routes': '["radarr"]',
      });
      final prefs = await SharedPreferences.getInstance();

      await SettingsService(prefs, FakeSecureSettingsStore()).clearAll();

      expect(prefs.getString('connection_routes'), isNull);
    });
  });
}
