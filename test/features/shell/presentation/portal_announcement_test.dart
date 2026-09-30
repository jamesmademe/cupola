import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/shell/presentation/portal_announcement.dart';

void main() {
  group('the sentence', () {
    String say({required int services, int faults = 0, int checking = 0}) =>
        portalOpenedAnnouncement(
          PortalFloorCensus(
            services: services,
            faults: faults,
            checking: checking,
          ),
        );

    test('a clean floor says so', () {
      expect(say(services: 12), 'Portal open. 12 services, none with a fault.');
    });

    test('one fault and several read the same way', () {
      expect(
        say(services: 12, faults: 1),
        'Portal open. 12 services, 1 with a fault.',
      );
      expect(
        say(services: 12, faults: 3),
        'Portal open. 12 services, 3 with a fault.',
      );
    });

    test('one service is one service', () {
      expect(say(services: 1), 'Portal open. 1 service, none with a fault.');
    });

    test('a probe still out is said, and never counted clean', () {
      // "None with a fault" is a claim, and it cannot be made about a cell
      // that has not answered yet.
      expect(
        say(services: 12, checking: 2),
        'Portal open. 12 services, 2 checking.',
      );
      expect(
        say(services: 12, faults: 1, checking: 2),
        'Portal open. 12 services, 1 with a fault, 2 checking.',
      );
    });

    test('an empty floor says what is true', () {
      expect(say(services: 0), 'Portal open. No services are set up.');
    });
  });

  group('the census', () {
    test('counts the cells the floor draws, one per connection', () async {
      final container = ProviderContainer(
        overrides: [
          currentSettingsProvider.overrideWith(
            (ref) => const SettingsModel(instances: _instances),
          ),
          _answers('radarr', ServiceSummaryStatus.online),
          _answers('radarr-hd', ServiceSummaryStatus.offline),
          _answers('sonarr', ServiceSummaryStatus.online),
          // Never answers: the probe is still out.
          instanceSummaryProvider((
            service: ServiceKey.sabnzbd,
            instanceId: 'sabnzbd',
          )).overrideWith((ref) => Completer<ServiceSummary>().future),
        ],
      );
      addTearDown(container.dispose);

      // Let the three answers land.
      container.listen(portalFloorCensusProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final census = container.read(portalFloorCensusProvider);
      expect(
        census.services,
        4,
        reason:
            'two Radarr connections are two cells on the floor, and the '
            'half-filled Lidarr slot is not a cell at all',
      );
      expect(census.faults, 1, reason: 'the Radarr that did not answer');
      expect(census.checking, 1, reason: 'the SABnzbd still being asked');
    });
  });
}

const _instances = [
  ServiceInstance(
    id: 'radarr',
    service: ServiceKey.radarr,
    label: '4K',
    url: 'https://four-k.lan:7878',
    credential: 'k',
  ),
  ServiceInstance(
    id: 'radarr-hd',
    service: ServiceKey.radarr,
    label: 'HD',
    url: 'https://hd.lan:7879',
    credential: 'k',
  ),
  ServiceInstance(
    id: 'sonarr',
    service: ServiceKey.sonarr,
    url: 'https://tv.lan:8989',
    credential: 'k',
  ),
  ServiceInstance(
    id: 'sabnzbd',
    service: ServiceKey.sabnzbd,
    url: 'https://nzb.lan:8080',
    credential: 'k',
  ),
  // A slot with no address: the settings screen shows it, the floor does not.
  ServiceInstance(id: 'lidarr', service: ServiceKey.lidarr),
];

Override _answers(String id, ServiceSummaryStatus status) {
  final instance = _instances.firstWhere((instance) => instance.id == id);
  return instanceSummaryProvider((
    service: instance.service,
    instanceId: id,
  )).overrideWith(
    (ref) async => ServiceSummary(
      service: instance.service,
      status: status,
      host: 'somewhere',
      version: '5.0',
    ),
  );
}
