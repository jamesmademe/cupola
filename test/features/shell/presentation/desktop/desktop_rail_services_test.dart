import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/home/data/stack_lights.dart';
import 'package:cupola/features/home/domain/stack_lights.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/shell/presentation/desktop/desktop_nav_rail.dart';
import 'package:cupola/features/shell/presentation/desktop/desktop_rail_services.dart';

/// What the sidebar says of each service: a number where things wait on the
/// person, a light where a fault has no count, red where it did not answer,
/// and nothing for a calm service.
void main() {
  DashboardDecision decision(
    ServiceKey service, {
    DecisionKind kind = DecisionKind.importBlocked,
    int count = 1,
    String id = 'd',
  }) => DashboardDecision(
    kind: kind,
    id: '${service.name}-$id',
    service: service,
    title: 'title',
    detail: 'detail',
    occurredAt: null,
    count: count,
  );

  List<DesktopRailService> read(
    List<StackLightRow> rows, {
    ({int count, bool floor})? waiting,
    List<DashboardDecision> decisions = const [],
    SourceCoverage coverage = SourceCoverage.none,
  }) {
    final container = ProviderContainer(
      overrides: [
        stackLightsProvider.overrideWithValue(StackLights(rows: rows)),
        pendingRequestCountProvider.overrideWith((ref) async => waiting),
        dashboardDecisionsProvider.overrideWithValue((
          decisions: decisions,
          coverage: coverage,
        )),
      ],
    );
    addTearDown(container.dispose);
    return container.read(desktopRailServicesProvider);
  }

  test('a fault without a count keeps its light, silence is red, the rest '
      'say nothing', () {
    final services = read(const [
      (service: ServiceKey.radarr, light: StackLight.answering),
      (service: ServiceKey.sonarr, light: StackLight.fault),
      (service: ServiceKey.truenas, light: StackLight.silent),
      (service: ServiceKey.lidarr, light: StackLight.checking),
    ]);

    expect(services, [
      (service: ServiceKey.radarr, tone: null, state: null, count: null),
      (
        service: ServiceKey.sonarr,
        tone: StatusTone.warning,
        state: 'a fault',
        count: null,
      ),
      (
        service: ServiceKey.truenas,
        tone: StatusTone.error,
        state: 'did not answer',
        count: null,
      ),
      (service: ServiceKey.lidarr, tone: null, state: null, count: null),
    ]);
  });

  test('the things to fix are counted per service, each group by its size', () {
    final services = read(
      const [
        (service: ServiceKey.sonarr, light: StackLight.fault),
        (service: ServiceKey.qbittorrent, light: StackLight.answering),
        (service: ServiceKey.radarr, light: StackLight.answering),
      ],
      decisions: [
        decision(ServiceKey.sonarr, count: 18),
        decision(
          ServiceKey.qbittorrent,
          kind: DecisionKind.stalledDownload,
          id: 'a',
        ),
        // A request waits politely: never counted as a thing to fix.
        decision(ServiceKey.radarr, kind: DecisionKind.pendingRequest),
      ],
    );

    expect(services, [
      (
        service: ServiceKey.sonarr,
        tone: StatusTone.warning,
        state: '18 need you',
        count: '18',
      ),
      (
        service: ServiceKey.qbittorrent,
        tone: StatusTone.warning,
        state: '1 needs you',
        count: '1',
      ),
      (service: ServiceKey.radarr, tone: null, state: null, count: null),
    ]);
  });

  test('a count read from a walk that stopped short is a floor', () {
    final services = read(
      const [(service: ServiceKey.sonarr, light: StackLight.fault)],
      decisions: [decision(ServiceKey.sonarr, count: 50)],
      coverage: SourceCoverage.answeredBy(ServiceKey.sonarr, cutShort: true),
    );

    expect(services.single.count, '50+');
    expect(services.single.state, 'at least 50 need you');
  });

  test('a silent service says so, whatever it held before', () {
    final services = read(
      const [(service: ServiceKey.sonarr, light: StackLight.silent)],
      decisions: [decision(ServiceKey.sonarr, count: 18)],
    );

    expect(services.single.tone, StatusTone.error);
    expect(services.single.count, isNull);
  });

  test('Seerr is blue with its count while requests wait, and its fault '
      'still wins', () async {
    final container = ProviderContainer(
      overrides: [
        stackLightsProvider.overrideWithValue(
          const StackLights(
            rows: [(service: ServiceKey.seerr, light: StackLight.answering)],
          ),
        ),
        pendingRequestCountProvider.overrideWith(
          (ref) async => (count: 50, floor: true),
        ),
        dashboardDecisionsProvider.overrideWithValue((
          decisions: const [],
          coverage: SourceCoverage.none,
        )),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(desktopRailServicesProvider, (_, _) {});
    addTearDown(sub.close);
    await container.read(pendingRequestCountProvider.future);

    expect(container.read(desktopRailServicesProvider), [
      (
        service: ServiceKey.seerr,
        tone: StatusTone.info,
        state: '50+ requests wait for approval',
        count: '50+',
      ),
    ]);

    final faulted = read(
      const [(service: ServiceKey.seerr, light: StackLight.fault)],
      waiting: (count: 1, floor: false),
    );
    expect(faulted.single.tone, StatusTone.warning);
  });

  test('Stack\'s figure is how many answer, and nothing while checking', () {
    ({String text, String spoken})? figure(List<StackLightRow> rows) {
      final container = ProviderContainer(
        overrides: [
          stackLightsProvider.overrideWithValue(StackLights(rows: rows)),
        ],
      );
      addTearDown(container.dispose);
      return container.read(desktopStackFigureProvider);
    }

    expect(
      figure(const [
        (service: ServiceKey.radarr, light: StackLight.answering),
        (service: ServiceKey.sonarr, light: StackLight.fault),
        (service: ServiceKey.truenas, light: StackLight.silent),
      ]),
      (text: '2/3', spoken: '2 of 3 answering'),
    );
    expect(
      figure(const [(service: ServiceKey.radarr, light: StackLight.checking)]),
      isNull,
    );
    expect(figure(const []), isNull);
  });
}
