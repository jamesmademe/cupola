import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/connection_reach_provider.dart';
import 'package:cupola/features/settings/data/service_connection_provider.dart';
import 'package:cupola/features/settings/data/service_verification.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_address.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/fake_secure_settings_store.dart';

/// Away from home, a connection with no address away is not asked: it reads
/// `Only at home`, neutral (Q1, 13/10).
///
/// Every address here is a TEST-NET one nothing answers: a probe that went
/// out would hang the case until its timeout rather than pass it.
const _radarr = ServiceInstance(
  id: 'radarr',
  service: ServiceKey.radarr,
  url: 'http://192.0.2.10:7878',
  credential: 'radarr-key',
  away: ConnectionAddress(url: 'https://radarr.example.net'),
);
const _sabnzbd = ServiceInstance(
  id: 'sabnzbd',
  service: ServiceKey.sabnzbd,
  url: 'http://192.0.2.10:8080',
  credential: 'sab-key',
);

Future<ProviderContainer> _container({
  List<ServiceInstance> instances = const [_radarr, _sabnzbd],
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final store = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(store),
      secureSettingsStoreProvider.overrideWithValue(FakeSecureSettingsStore()),
      currentSettingsProvider.overrideWith(
        (ref) => SettingsModel(instances: instances),
      ),
      initialActiveInstancesProvider.overrideWithValue(const {}),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _away(ProviderContainer container) => container
    .read(connectionRoutesProvider.notifier)
    .set('radarr', ConnectionRoute.away);

void main() {
  group('awayFromHomeProvider', () {
    test('is false while no connection has an address away', () async {
      // Without one the app cannot tell away from a server that is down.
      final container = await _container(instances: const [_sabnzbd]);
      expect(container.read(awayFromHomeProvider), isFalse);
    });

    test('follows the connection that moved away, and back', () async {
      final container = await _container();
      expect(container.read(awayFromHomeProvider), isFalse);

      await _away(container);
      expect(container.read(awayFromHomeProvider), isTrue);

      await container
          .read(connectionRoutesProvider.notifier)
          .set('radarr', ConnectionRoute.home);
      expect(container.read(awayFromHomeProvider), isFalse);
    });

    test('is away at a cold start, from the route remembered', () async {
      final container = await _container(
        prefs: {'connection_routes': '["radarr"]'},
      );
      expect(container.read(awayFromHomeProvider), isTrue);
    });

    test(
      'ignores a route kept for a connection with no address away',
      () async {
        // The map can keep the id of a connection whose address away was
        // taken off: it is no evidence of being away.
        final container = await _container(
          instances: const [
            ServiceInstance(
              id: 'radarr-4k',
              service: ServiceKey.radarr,
              url: 'http://192.0.2.10:7879',
              credential: 'radarr-key',
              away: ConnectionAddress(url: 'https://radarr-4k.example.net'),
            ),
            _sabnzbd,
          ],
          prefs: {'connection_routes': '["radarr"]'},
        );
        expect(container.read(awayFromHomeProvider), isFalse);
      },
    );
  });

  group('away from home, a connection with no address away', () {
    test('reads only at home, and is not asked', () async {
      final container = await _container();
      await _away(container);

      final diagnosis = await container.read(
        instanceDiagnosisProvider('sabnzbd').future,
      );
      expect(diagnosis.status, ServiceConnectionStatus.disconnected);
      expect(diagnosis.reason, ServiceFailureReason.onlyAtHome);

      final summary = await container.read(
        instanceSummaryProvider((
          service: ServiceKey.sabnzbd,
          instanceId: 'sabnzbd',
        )).future,
      );
      expect(summary.status, ServiceSummaryStatus.onlyAtHome);
      expect(summary.isOnlyAtHome, isTrue);
      expect(summary.didNotAnswer, isFalse);
      expect(summary.isFault, isFalse);
      expect(summary.failureReason, ServiceFailureReason.onlyAtHome);
      expect(summary.host, '192.0.2.10:8080');
    });

    test('folds apart from silence and faults', () async {
      final container = await _container();
      await _away(container);
      await container.read(
        instanceSummaryProvider((
          service: ServiceKey.sabnzbd,
          instanceId: 'sabnzbd',
        )).future,
      );

      expect(container.read(foldedServiceHealthProvider(ServiceKey.sabnzbd)), (
        total: 1,
        offline: 0,
        faulted: 0,
        stuck: 0,
        checking: 0,
        onlyAtHome: 1,
      ));
    });

    test('a folded service is never better than its worst answer, and only '
        'at home is below a fault', () {
      const answered = ServiceDiagnosis.connected();
      const home = ServiceDiagnosis.onlyAtHome();
      const silent = ServiceDiagnosis.dropped();
      expect(
        worstDiagnosis([answered, home]).reason,
        ServiceFailureReason.onlyAtHome,
      );
      expect(
        worstDiagnosis([home, silent]).reason,
        ServiceFailureReason.unreachable,
      );
    });
  });
}
