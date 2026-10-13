import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/home/domain/stack_lights.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

DashboardDecision _fault(ServiceKey service, DecisionKind kind) =>
    DashboardDecision(
      kind: kind,
      id: '${service.name}-${kind.name}',
      service: service,
      title: 'Big Buck Bunny',
      detail: '',
      occurredAt: null,
    );

/// Stack health: one light per service, faults counted as the lights show them.
void main() {
  group('a service\'s light', () {
    test('hollow until a connection answers', () {
      expect(stackLightOf([StackProbe.checking]), StackLight.checking);
      expect(stackLightOf(const []), StackLight.checking);
    });

    test('green when it answered and nothing waits for the person', () {
      expect(stackLightOf([StackProbe.answered]), StackLight.answering);
      expect(
        stackLightOf([StackProbe.answered, StackProbe.checking]),
        StackLight.answering,
      );
    });

    test('red only when every connection did not answer', () {
      expect(
        stackLightOf([StackProbe.silent, StackProbe.silent]),
        StackLight.silent,
      );
      // One of two did not answer: it answers, and part of it does not.
      expect(
        stackLightOf([StackProbe.answered, StackProbe.silent]),
        StackLight.fault,
      );
    });

    test('amber for a refused key or a fault that waits for the person', () {
      expect(stackLightOf([StackProbe.fault]), StackLight.fault);
      expect(
        stackLightOf([StackProbe.answered], needsYou: true),
        StackLight.fault,
      );
      // Silence outranks a fault it can no longer show.
      expect(
        stackLightOf([StackProbe.silent], needsYou: true),
        StackLight.silent,
      );
    });
  });

  group('a server reached that never replied', () {
    test('is amber, and not answering', () {
      expect(stackLightOf([StackProbe.stuck]), StackLight.stuck);
      // Stuck beside dark: nothing replied, and the host is there.
      expect(
        stackLightOf([StackProbe.stuck, StackProbe.silent]),
        StackLight.stuck,
      );
      // Beside one that answered: it answers, partly.
      expect(
        stackLightOf([StackProbe.stuck, StackProbe.answered]),
        StackLight.fault,
      );
    });

    test('is out of the count, said beside it, and named apart', () {
      final lights = stackLightsOf(
        services: [
          (service: ServiceKey.radarr, probes: [StackProbe.stuck]),
          (service: ServiceKey.sonarr, probes: [StackProbe.stuck]),
          (service: ServiceKey.lidarr, probes: [StackProbe.answered]),
        ],
        faults: const [],
      );
      expect(lights.line, '1 of 3 answering · 2 timed out');
      // Its probe's fault is the same fact: said once, as timed out.
      expect(
        stackLightsOf(
          services: [
            (service: ServiceKey.radarr, probes: [StackProbe.stuck]),
          ],
          faults: [_fault(ServiceKey.radarr, DecisionKind.connectionFault)],
        ).line,
        '0 of 1 answering · 1 timed out',
      );
      expect(lights.stuck, [ServiceKey.radarr, ServiceKey.sonarr]);
      expect(lights.silent, isEmpty);
      expect(lights.faultLine, isNull);
      expect(lights.spoken, 'Answering: Lidarr. Timed out: Radarr, Sonarr.');
    });
  });

  group('the slab', () {
    test('counts the amber lights, and names them', () {
      final lights = stackLightsOf(
        services: [
          (service: ServiceKey.radarr, probes: [StackProbe.answered]),
          (service: ServiceKey.sonarr, probes: [StackProbe.answered]),
          (service: ServiceKey.qbittorrent, probes: [StackProbe.answered]),
          (service: ServiceKey.truenas, probes: [StackProbe.fault]),
        ],
        faults: [
          _fault(ServiceKey.sonarr, DecisionKind.importBlocked),
          _fault(ServiceKey.qbittorrent, DecisionKind.stalledDownload),
        ],
      );
      expect(lights.line, '4 of 4 answering · 3 faults');
      expect(lights.faultLine, 'Faults: Sonarr, qBittorrent and TrueNAS');
      expect(lights.silent, isEmpty);
    });

    test('a health check folded across arrs is amber on each, and counted '
        'on each: the figure is the names under it', () {
      final lights = stackLightsOf(
        services: [
          for (final service in [
            ServiceKey.radarr,
            ServiceKey.sonarr,
            ServiceKey.lidarr,
          ])
            (service: service, probes: [StackProbe.answered]),
        ],
        faults: [
          DashboardDecision(
            kind: DecisionKind.serviceHealth,
            id: 'health-group',
            service: ServiceKey.radarr,
            title: 'No indexer is watching for new releases',
            detail: 'Radarr, Sonarr and Lidarr',
            occurredAt: null,
            members: [
              for (final service in [
                ServiceKey.radarr,
                ServiceKey.sonarr,
                ServiceKey.lidarr,
              ])
                _fault(service, DecisionKind.serviceHealth),
            ],
          ),
        ],
      );
      expect(lights.line, '3 of 3 answering · 3 faults');
      expect(lights.faultLine, 'Faults: Radarr, Sonarr and Lidarr');
    });

    test('many faults on one service are one light, one count', () {
      final lights = stackLightsOf(
        services: [
          (service: ServiceKey.sonarr, probes: [StackProbe.answered]),
          (service: ServiceKey.radarr, probes: [StackProbe.answered]),
        ],
        faults: [
          _fault(ServiceKey.sonarr, DecisionKind.importBlocked),
          _fault(ServiceKey.sonarr, DecisionKind.failedImport),
          _fault(ServiceKey.sonarr, DecisionKind.serviceHealth),
        ],
      );
      expect(lights.line, '2 of 2 answering · 1 fault');
      expect(lights.faultLine, 'Faults: Sonarr');
    });

    test('past five names, the rest are counted, and still add up', () {
      final amber = [
        ServiceKey.radarr,
        ServiceKey.sonarr,
        ServiceKey.lidarr,
        ServiceKey.prowlarr,
        ServiceKey.bazarr,
        ServiceKey.qbittorrent,
        ServiceKey.plex,
      ];
      final lights = stackLightsOf(
        services: [
          for (final service in amber)
            (service: service, probes: [StackProbe.fault]),
        ],
        faults: const [],
      );
      expect(lights.line, '7 of 7 answering · 7 faults');
      expect(
        lights.faultLine,
        'Faults: Radarr, Sonarr, Lidarr, Prowlarr, Bazarr and 2 others',
      );
    });

    test('a service that did not answer is out of the count, and named', () {
      final lights = stackLightsOf(
        services: [
          (service: ServiceKey.radarr, probes: [StackProbe.silent]),
          (service: ServiceKey.sonarr, probes: [StackProbe.answered]),
        ],
        faults: const [],
      );
      expect(lights.line, '1 of 2 answering');
      expect(lights.silent, [ServiceKey.radarr]);
      expect(lights.faultLine, isNull);
    });

    test('before anything answers: Checking, every light hollow', () {
      final lights = stackLightsOf(
        services: [
          for (final service in [ServiceKey.radarr, ServiceKey.sonarr])
            (service: service, probes: [StackProbe.checking]),
        ],
        faults: const [],
      );
      expect(lights.checking, isTrue);
      expect(lights.line, 'Checking 2');
    });

    test('one still being asked is said beside the count', () {
      final lights = stackLightsOf(
        services: [
          (service: ServiceKey.radarr, probes: [StackProbe.answered]),
          (service: ServiceKey.sonarr, probes: [StackProbe.checking]),
        ],
        faults: const [],
      );
      expect(lights.line, '1 of 2 answering · 1 checking');
    });
  });

  group('away from home', () {
    test('a service only at home is lit neutral and out of the count', () {
      expect(stackLightOf([StackProbe.onlyAtHome]), StackLight.onlyAtHome);
      expect(
        stackLightOf([StackProbe.onlyAtHome, StackProbe.answered]),
        StackLight.answering,
      );
      final lights = stackLightsOf(
        services: [
          (service: ServiceKey.radarr, probes: [StackProbe.answered]),
          (service: ServiceKey.sabnzbd, probes: [StackProbe.onlyAtHome]),
        ],
        faults: const [],
      );
      expect(lights.configured, 1);
      expect(lights.onlyAtHome, [ServiceKey.sabnzbd]);
      expect(lights.line, '1 of 1 answering · 1 only at home');
      expect(lights.spoken, 'Answering: Radarr. Only at home: SABnzbd.');
    });
  });
}
