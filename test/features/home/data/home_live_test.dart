import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/home/data/home_layout_provider.dart';
import 'package:cupola/features/home/data/home_live.dart';
import 'package:cupola/features/home/domain/home_module.dart';
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
}
