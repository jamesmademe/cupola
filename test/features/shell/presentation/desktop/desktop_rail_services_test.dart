import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/home/data/stack_lights.dart';
import 'package:cupola/features/home/domain/stack_lights.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/shell/presentation/desktop/desktop_rail_services.dart';

/// What the sidebar lights: the light of Stack health where a service needs a
/// look, Seerr's blue while requests wait, and nothing for a calm service.
void main() {
  List<({ServiceKey service, StatusTone? tone, String? state})> read(
    List<StackLightRow> rows, {
    ({int count, bool floor})? waiting,
  }) {
    final container = ProviderContainer(
      overrides: [
        stackLightsProvider.overrideWithValue(StackLights(rows: rows)),
        pendingRequestCountProvider.overrideWith((ref) async => waiting),
      ],
    );
    addTearDown(container.dispose);
    return container.read(desktopRailServicesProvider);
  }

  test('a fault is amber, one that did not answer red, the rest unlit', () {
    final services = read(const [
      (service: ServiceKey.radarr, light: StackLight.answering),
      (service: ServiceKey.sonarr, light: StackLight.fault),
      (service: ServiceKey.truenas, light: StackLight.silent),
      (service: ServiceKey.lidarr, light: StackLight.checking),
    ]);

    expect(services, [
      (service: ServiceKey.radarr, tone: null, state: null),
      (service: ServiceKey.sonarr, tone: StatusTone.warning, state: 'a fault'),
      (
        service: ServiceKey.truenas,
        tone: StatusTone.error,
        state: 'did not answer',
      ),
      (service: ServiceKey.lidarr, tone: null, state: null),
    ]);
  });

  test('Seerr is blue while requests wait, and its fault still wins', () async {
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
      ),
    ]);

    final faulted = read(
      const [(service: ServiceKey.seerr, light: StackLight.fault)],
      waiting: (count: 1, floor: false),
    );
    expect(faulted.single.tone, StatusTone.warning);
  });
}
