import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/domain/in_flight.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/services/presentation/kept_waiting_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Keep waiting takes a stuck download out of the faults for a day, keeps
/// the choice across launches, and gives it back on Undo or when it moves.
void main() {
  final now = DateTime(2026, 10, 9, 20, 53);

  ServiceQueueItem stuck({double progress = 0.47}) => ServiceQueueItem(
    service: ServiceKey.qbittorrent,
    id: 'abc',
    title: 'Big.Buck.Bunny.2008.1080p.BluRay',
    progress: progress,
    clientLabel: 'qBittorrent',
    clientService: ServiceKey.qbittorrent,
    instanceId: 'qb1',
    fault: InFlightFault.stalled,
  );

  Future<ProviderContainer> containerWith(
    ServiceQueueItem item, {
    Map<String, Object> prefs = const {},
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        stallClockProvider.overrideWithValue(() => now),
        servicesInFlightProvider.overrideWith(
          (ref) async => (
            preview: const <ServiceQueueItem>[],
            activeCount: 0,
            faults: [item],
            held: 0,
            rateBytesPerSecond: null,
            clients: 1,
            coverage: SourceCoverage.none,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<List<DashboardDecision>> stalls(ProviderContainer container) async {
    final read = await container.read(
      dashboardDecisionSourceProvider(DecisionSource.queue).future,
    );
    return read.decisions;
  }

  test('a stall kept waiting leaves the faults, and Undo brings it '
      'back', () async {
    final item = stuck();
    final container = await containerWith(item);
    expect(await stalls(container), hasLength(1));

    container.read(keptWaitingProvider.notifier).keep(item, now: now);
    expect(await stalls(container), isEmpty);

    container.read(keptWaitingProvider.notifier).release(item);
    expect(await stalls(container), hasLength(1));
  });

  test('the choice outlives the launch', () async {
    final item = stuck();
    final first = await containerWith(item);
    first.read(keptWaitingProvider.notifier).keep(item, now: now);
    final written = (await SharedPreferences.getInstance()).getString(
      'activity_kept_waiting',
    )!;

    final second = await containerWith(
      item,
      prefs: {'activity_kept_waiting': written},
    );
    expect(await stalls(second), isEmpty);
  });

  test('a download that moved since is a fault again when it sticks', () async {
    final kept = await containerWith(stuck());
    kept.read(keptWaitingProvider.notifier).keep(stuck(), now: now);
    final written = (await SharedPreferences.getInstance()).getString(
      'activity_kept_waiting',
    )!;

    final moved = await containerWith(
      stuck(progress: 0.52),
      prefs: {'activity_kept_waiting': written},
    );
    expect(await stalls(moved), hasLength(1));
  });
}
