/// Everything that reaches a server goes where the connection's route is:
/// the clients, the Dashboard's probe, the release search's reach and the
/// artwork's access. What names the connection stays on its address at home.
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/network/connection_access_registry.dart';
import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/features/discover/data/seerr_session.dart';
import 'package:cupola/features/release_search/domain/release_search_reach.dart';
import 'package:cupola/features/release_search/domain/release_search_target.dart';
import 'package:cupola/features/release_search/presentation/release_search_entry.dart';
import 'package:cupola/features/release_search/presentation/release_search_settings_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/connection_reach_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/connection_address.dart';
import 'package:cupola/features/settings/domain/connection_reach.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/fake_secure_settings_store.dart';

const _token = CloudflareServiceToken(
  clientId: 'id.access',
  clientSecret: 'sentinel-secret',
);

/// At home on the LAN in clear, away through a tunnel behind Cloudflare
/// Access with a certificate of its own.
const _radarr = ServiceInstance(
  id: 'radarr',
  service: ServiceKey.radarr,
  url: 'http://192.168.1.20:7878',
  credential: 'radarr-key',
  away: ConnectionAddress(url: 'https://radarr.example.com', access: _token),
);
const _seerr = ServiceInstance(
  id: 'seerr',
  service: ServiceKey.seerr,
  url: 'http://192.168.1.20:5055',
  credential: 'seerr-key',
  away: ConnectionAddress(url: 'https://seerr.example.com', access: _token),
);
const _awayPin =
    '11:22:33:44:55:66:77:88:99:00:aa:bb:cc:dd:ee:ff:'
    '11:22:33:44:55:66:77:88:99:00:aa:bb:cc:dd:ee:ff';

SettingsModel get _settings => const SettingsModel(
  instances: [_radarr, _seerr],
).copyWithTrustedCertificate(url: _radarr.away!.url, fingerprint: _awayPin);

/// What a client was built with.
typedef _Built = ({String url, String? pin, Map<String, String> headers});

Future<ProviderContainer> _container({
  List<_Built>? statusClients,
  List<ConnectionReach?>? seerrReaches,
  TargetPlatform? platform,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      secureSettingsStoreProvider.overrideWithValue(FakeSecureSettingsStore()),
      currentSettingsProvider.overrideWith((ref) => _settings),
      initialActiveInstancesProvider.overrideWithValue(const {}),
      if (statusClients != null)
        serviceStatusClientFactoryProvider.overrideWith(
          (ref) =>
              ({
                required String baseUrl,
                required String apiKey,
                String? pinnedCertFingerprint,
                Map<String, String> accessHeaders = const {},
              }) {
                statusClients.add((
                  url: baseUrl,
                  pin: pinnedCertFingerprint,
                  headers: accessHeaders,
                ));
                return _StatusClient();
              },
        ),
      if (seerrReaches != null)
        seerrClientFactoryProvider.overrideWith(
          (ref) =>
              (
                instance, {
                ConnectionReach? reach,
                SeerrSessionEvents events = const SeerrSessionEvents(),
              }) {
                seerrReaches.add(reach);
                return _StatusClient();
              },
        ),
      if (platform != null)
        releaseSearchPlatformProvider.overrideWith((ref) => platform),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _goAway(ProviderContainer container, String id) => container
    .read(connectionRoutesProvider.notifier)
    .set(id, ConnectionRoute.away);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the Dashboard\'s probe', () {
    test('asks the address away, with its access and its pin, and names the '
        'connection by its address at home', () async {
      final built = <_Built>[];
      final container = await _container(statusClients: built);
      await _goAway(container, 'radarr');

      final summary = await container.read(
        instanceSummaryProvider((
          service: ServiceKey.radarr,
          instanceId: 'radarr',
        )).future,
      );

      final client = built.single;
      expect(client.url, 'https://radarr.example.com');
      expect(client.pin, _awayPin);
      expect(client.headers, _token.headers());
      expect(summary.host, '192.168.1.20:7878');
    });

    test('asks again at home when the route comes back', () async {
      final built = <_Built>[];
      final container = await _container(statusClients: built);
      final key = (service: ServiceKey.radarr, instanceId: 'radarr');
      await _goAway(container, 'radarr');
      container.listen(instanceSummaryProvider(key), (_, _) {});
      await container.read(instanceSummaryProvider(key).future);

      await container
          .read(connectionRoutesProvider.notifier)
          .set('radarr', ConnectionRoute.home);
      await container.read(instanceSummaryProvider(key).future);

      expect(
        [for (final client in built) client.url],
        ['https://radarr.example.com', 'http://192.168.1.20:7878'],
      );
      expect(built.last.headers, isEmpty);
    });

    test('builds Seerr\'s client on the route\'s reach', () async {
      final reaches = <ConnectionReach?>[];
      final container = await _container(seerrReaches: reaches);
      await _goAway(container, 'seerr');

      await container.read(
        instanceSummaryProvider((
          service: ServiceKey.seerr,
          instanceId: 'seerr',
        )).future,
      );

      expect(reaches.single, (
        url: 'https://seerr.example.com',
        access: _token,
        pin: null,
      ));
    });
  });

  group('the clients of a connection', () {
    test('an arr\'s client goes to the address away with its access', () async {
      final container = await _container();
      await _goAway(container, 'radarr');
      final client = container.read(
        Provider((ref) => watchApiClient(ref, ServiceKey.radarr)),
      );

      expect(client.baseUrl, 'https://radarr.example.com');
      expect(client.headers, containsPair('CF-Access-Client-Id', 'id.access'));
    });

    test('Seerr\'s client goes to the address away with its access', () async {
      final container = await _container();
      await _goAway(container, 'seerr');
      final client = container.read(
        Provider((ref) => watchSeerrClient(ref, instanceId: 'seerr')),
      );

      expect(client.baseUrl, 'https://seerr.example.com');
      expect(client.headers, containsPair('CF-Access-Client-Id', 'id.access'));
    });
  });

  group('the release search', () {
    test('reads the scheme of the address it goes to', () async {
      final container = await _container(platform: TargetPlatform.iOS);
      container
          .read(releaseSearchSettingsProvider.notifier)
          .setBackgroundEnabled(true);
      final target = const ReleaseSearchTarget(
        service: ServiceKey.radarr,
        id: 1,
        scope: ReleaseSearchScope.movie,
        label: 'Sprite Fright',
      ).stampedWith('radarr');
      container.listen(releaseSearchReachProvider(target), (_, _) {});

      // At home the address is cleartext: the search stays in the app.
      expect(
        container.read(releaseSearchReachProvider(target)),
        ReleaseSearchReach.whileOpenCleartext,
      );

      // Away, the tunnel's certificate is trusted in Cupola alone: the
      // native task could not see it, so the search stays in the app too,
      // for the reason of the address it goes to.
      await _goAway(container, 'radarr');
      expect(
        container.read(releaseSearchReachProvider(target)),
        ReleaseSearchReach.whileOpenTrustedCert,
      );
    });
  });

  group('the artwork', () {
    tearDown(ConnectionAccessRegistry.reset);

    test('a poster built on the address away crosses its gateway, and one '
        'built at home sends nothing it asks for', () async {
      final container = await _container();
      ConnectionAccessRegistry.update(_settings.accessHeadersByAddress);
      await _goAway(container, 'radarr');
      const images = [
        {'coverType': 'poster', 'url': '/MediaCover/1/poster.jpg'},
      ];

      final away = ImageUtils.extractPosterUrl(
        images,
        baseUrl: container.read(connectionReachProvider('radarr'))!.url,
        apiKey: 'radarr-key',
      );
      final home = ImageUtils.extractPosterUrl(
        images,
        baseUrl: _radarr.url,
        apiKey: 'radarr-key',
      );

      expect(away.url, 'https://radarr.example.com/MediaCover/1/poster.jpg');
      expect(away.headers, {..._token.headers(), 'X-Api-Key': 'radarr-key'});
      expect(home.headers, {'X-Api-Key': 'radarr-key'});
    });
  });
}

/// A status endpoint that answers as any service does.
class _StatusClient extends ApiClient {
  _StatusClient() : super(baseUrl: 'https://status.example.com', apiKey: 'k');

  @override
  Future<Response> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    Duration? receiveTimeout,
  }) async => Response(
    requestOptions: RequestOptions(path: path),
    statusCode: 200,
    data: {'version': '5.4.6'},
  );

  @override
  void close({bool force = false}) {}
}
