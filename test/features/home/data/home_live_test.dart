import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/providers/navigation_refresh_provider.dart';
import 'package:cupola/features/home/data/home_layout_provider.dart';
import 'package:cupola/features/home/data/home_live.dart';
import 'package:cupola/features/home/data/stack_lights.dart';
import 'package:cupola/features/home/domain/home_module.dart';
import 'package:cupola/features/home/domain/stack_lights.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/settings_scope.dart';

/// The Home's live modules, read again every thirty seconds while it is
/// seen, and only those that are on with their services set up.
void main() {
  Future<({ProviderContainer container, int Function() reads})> start({
    List<ServiceKey> configured = const [ServiceKey.radarr],
  }) async {
    var reads = 0;
    final container = ProviderContainer(
      overrides: [
        ...await settingsScopeOverrides(configured: configured),
        servicesQueueProvider.overrideWith((ref) async {
          reads++;
          return (
            items: const <ServiceQueueItem>[],
            coverage: SourceCoverage.none,
          );
        }),
      ],
    );
    addTearDown(container.dispose);
    container.listen(servicesQueueProvider, (_, _) {});
    await container.read(servicesQueueProvider.future);
    return (container: container, reads: () => reads);
  }

  testWidgets('every thirty seconds while watched, the queues again', (
    tester,
  ) async {
    final (:container, :reads) = await start();
    final poll = container.listen(homeLivePollProvider, (_, _) {});

    await tester.pump(homeLiveInterval - const Duration(seconds: 1));
    expect(reads(), 1);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(reads(), 2);
    await tester.pump(homeLiveInterval);
    await tester.pump();
    expect(reads(), 3);

    // The Home leaves the screen: the watch drops and the timer with it.
    poll.close();
    await tester.pump();
    await tester.pump(homeLiveInterval * 3);
    expect(reads(), 3);
  });

  testWidgets('Downloads switched off, and no media server: no timer', (
    tester,
  ) async {
    final (:container, :reads) = await start();
    container
        .read(homeLayoutProvider.notifier)
        .setOn(HomeModule.downloads, on: false);
    final poll = container.listen(homeLivePollProvider, (_, _) {});
    await tester.pump(homeLiveInterval * 2);
    expect(reads(), 1);
    poll.close();
    // Riverpod disposes on its own scheduler, a moment behind the close.
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('a module whose services are not set up asks nothing', (
    tester,
  ) async {
    final (:container, :reads) = await start(configured: const []);
    final poll = container.listen(homeLivePollProvider, (_, _) {});
    await tester.pump(homeLiveInterval * 2);
    expect(reads(), 1);
    poll.close();
    // Riverpod disposes on its own scheduler, a moment behind the close.
    await tester.pump(const Duration(milliseconds: 1));
  });

  group('a server that did not answer', () {
    Future<
      ({
        ProviderContainer container,
        int Function() probes,
        int Function() refreshes,
      })
    >
    recovering({required bool Function() answers}) async {
      var probes = 0;
      final container = ProviderContainer(
        overrides: [
          ...await settingsScopeOverrides(
            configured: const [ServiceKey.radarr],
          ),
          // Radarr is silent in the header until the Home reads it again.
          stackLightsProvider.overrideWith(
            (ref) => stackLightsOf(
              services: const [
                (service: ServiceKey.radarr, probes: [StackProbe.silent]),
              ],
              faults: const [],
            ),
          ),
          instanceSummaryProvider.overrideWith((ref, key) async {
            probes++;
            return ServiceSummary(
              service: key.service,
              status: answers()
                  ? ServiceSummaryStatus.online
                  : ServiceSummaryStatus.offline,
              host: 'nas.lan',
              version: null,
            );
          }),
        ],
      );
      addTearDown(container.dispose);
      return (
        container: container,
        probes: () => probes,
        refreshes: () =>
            container.read(navigationRefreshProvider(NavigationSection.home)),
      );
    }

    testWidgets('is asked again every thirty seconds, and nothing else', (
      tester,
    ) async {
      final (:container, :probes, :refreshes) = await recovering(
        answers: () => false,
      );
      final poll = container.listen(homeRecoveryPollProvider, (_, _) {});

      await tester.pump(homeLiveInterval);
      await tester.pump();
      expect(probes(), 1);
      await tester.pump(homeLiveInterval);
      await tester.pump();
      expect(probes(), 2);
      // Still silent: the Home is not read again for nothing.
      expect(refreshes(), 0);

      poll.close();
      await tester.pump(const Duration(milliseconds: 1));
    });

    testWidgets('answering again reads the whole Home again, once', (
      tester,
    ) async {
      var back = false;
      final (:container, :probes, :refreshes) = await recovering(
        answers: () => back,
      );
      final poll = container.listen(homeRecoveryPollProvider, (_, _) {});

      await tester.pump(homeLiveInterval);
      await tester.pump();
      expect(refreshes(), 0);

      back = true;
      await tester.pump(homeLiveInterval);
      await tester.pump();
      expect(probes(), 2);
      expect(refreshes(), 1);

      poll.close();
      await tester.pump(const Duration(milliseconds: 1));
    });
  });
}
