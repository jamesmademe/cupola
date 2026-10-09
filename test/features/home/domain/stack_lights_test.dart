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

/// Stack health: one light per service, faults counted in groups.
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

  group('the slab', () {
    test('counts faults in groups, and names the amber services', () {
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
      expect(lights.faultLine, 'Faults: Sonarr, qBittorrent, TrueNAS');
      expect(lights.silent, isEmpty);
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
}
