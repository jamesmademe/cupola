import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/lifecycle/poll_clock.dart';
import 'package:cupola/features/home/data/home_live.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/shell/presentation/desktop/desktop_downloads_poll.dart';

import '../../../../test_helpers/settings_scope.dart';

/// What keeps the desktop chrome's downloads current once the client pages'
/// own ticks no longer start the queue: thirty seconds, unless a Home or
/// Activity poll has just read the same group.
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

  testWidgets('every thirty seconds the group is read again', (tester) async {
    final (:container, :reads) = await start();
    final poll = container.listen(desktopDownloadsPollProvider, (_, _) {});

    await tester.pump(homeLiveInterval - const Duration(seconds: 1));
    expect(reads(), 1);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(reads(), 2);

    poll.close();
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(homeLiveInterval * 3);
    expect(reads(), 2);
  });

  testWidgets('it stands aside for a Home poll that has just read it', (
    tester,
  ) async {
    final (:container, :reads) = await start();
    final poll = container.listen(desktopDownloadsPollProvider, (_, _) {});

    // `pump` moves the test's timers, not the wall clock the poll clock reads.
    var elapsed = Duration.zero;
    final origin = DateTime(2026, 10, 26, 12);
    final clock = container.read(pollClockProvider)
      ..now = () => origin.add(elapsed);
    Future<void> advance(Duration by) async {
      elapsed += by;
      await tester.pump(by);
      await tester.pump();
    }

    // The Home read the group ten seconds before this tick is due.
    await advance(const Duration(seconds: 20));
    clock.note('home.live');
    await advance(const Duration(seconds: 10));
    expect(reads(), 1);

    // Nothing has read it since: the next tick does.
    await advance(homeLiveInterval);
    expect(reads(), 2);

    poll.close();
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('no service set up, no timer', (tester) async {
    final (:container, :reads) = await start(configured: const []);
    final poll = container.listen(desktopDownloadsPollProvider, (_, _) {});

    await tester.pump(homeLiveInterval * 3);
    expect(reads(), 1);

    poll.close();
    await tester.pump(const Duration(milliseconds: 1));
  });
}
