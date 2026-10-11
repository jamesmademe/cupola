import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/activity/presentation/widgets/import_done_card.dart';
import 'package:cupola/features/import/domain/manual_import_models.dart';
import 'package:cupola/features/import/presentation/manual_import_provider.dart';
import 'package:cupola/features/services/domain/in_flight.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/blocked_import_world.dart';

ProviderContainer _container(
  FakeBlockedImportService fake, {
  List<ServiceQueueItem>? queue,
}) {
  final container = ProviderContainer(
    overrides: blockedImportOverrides(fake, queue: queue),
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('startBlocked', () {
    test("reads each blocked download by the client's id for it", () async {
      final fake = FakeBlockedImportService();
      final container = _container(fake);
      await container
          .read(manualImportFlowProvider.notifier)
          .startBlocked(ServiceKey.sonarr, instanceId: blockedImportConnection);

      expect(fake.reads, hasLength(18));
      expect(fake.reads.first, 'clear-1-1');
      final state = container.read(manualImportFlowProvider);
      expect(state.isLoadingItems, isFalse);
      expect(state.items, hasLength(18));
      final review = state.blocked!;
      expect(review.downloads, hasLength(18));
      expect(review.needYouPaths, hasLength(6));
      expect(review.needYouPaths.first, contains('Laundromat.Tapes.E01'));
      // The twelve the arr would take arrive selected; the six do not.
      expect(state.selectedPaths, hasLength(12));
      expect(
        state.selectedPaths.any((path) => path.contains('Tapes')),
        isFalse,
      );
      // What each clear file replaces, from the series' episode files.
      expect(review.replacing, hasLength(12));
      expect(review.replacing.values.toSet(), {'HDTV-720p'});
    });

    test(
      'only the connection the link names, and only blocked imports',
      () async {
        final fake = FakeBlockedImportService();
        final container = _container(
          fake,
          queue: [
            ...cosmosBlockedQueue().take(2),
            // Another Sonarr's, and a stall on this one: neither is here.
            ...cosmosBlockedQueue(instanceId: 'sonarr-2').skip(2).take(1),
            const ServiceQueueItem(
              service: ServiceKey.sonarr,
              title: 'Stuck',
              progress: 0.4,
              clientLabel: 'qBittorrent',
              fault: InFlightFault.stalled,
              downloadId: 'stuck',
              instanceId: blockedImportConnection,
            ),
          ],
        );
        await container
            .read(manualImportFlowProvider.notifier)
            .startBlocked(
              ServiceKey.sonarr,
              instanceId: blockedImportConnection,
            );

        expect(fake.reads, ['clear-1-1', 'clear-1-2']);
      },
    );

    test(
      "one download that won't list its files takes nobody else's",
      () async {
        final fake = FakeBlockedImportService()..failing.add('tape-3');
        final container = _container(fake);
        await container
            .read(manualImportFlowProvider.notifier)
            .startBlocked(
              ServiceKey.sonarr,
              instanceId: blockedImportConnection,
            );

        final state = container.read(manualImportFlowProvider);
        expect(state.error, isNull);
        expect(state.items, hasLength(17));
        expect(state.blocked!.unread, 1);
      },
    );

    test('an import still running keeps its files out of the Review', () async {
      final fake = FakeBlockedImportService();
      final container = _container(fake);
      final notifier = container.read(manualImportFlowProvider.notifier);
      await notifier.startBlocked(
        ServiceKey.sonarr,
        instanceId: blockedImportConnection,
      );
      await notifier.confirmImport();
      expect(fake.posted, hasLength(12));

      await notifier.startBlocked(
        ServiceKey.sonarr,
        instanceId: blockedImportConnection,
      );
      final state = container.read(manualImportFlowProvider);
      // The twelve are on their way: only the six remain, and the running
      // command stays for Needs you to report.
      expect(state.items, hasLength(6));
      expect(state.selectedPaths, isEmpty);
      expect(state.command?.id, 41);
      expect(state.submittedItems, hasLength(12));
    });
  });

  group('placeEpisode', () {
    test('puts a tape on its episode and into the import', () async {
      final fake = FakeBlockedImportService();
      final container = _container(fake);
      final notifier = container.read(manualImportFlowProvider.notifier);
      await notifier.startBlocked(
        ServiceKey.sonarr,
        instanceId: blockedImportConnection,
      );
      final tape = container
          .read(manualImportFlowProvider)
          .items
          .firstWhere((item) => item.path.contains('Tapes.E03'));

      final error = await notifier.placeEpisode(tape, season: 1, episode: 3);

      expect(error, isNull);
      final state = container.read(manualImportFlowProvider);
      final placed = state.items.firstWhere((item) => item.path == tape.path);
      expect(placed.episodes.single['episodeNumber'], 3);
      expect(placed.isReadyForImportFor(ServiceKey.sonarr), isTrue);
      expect(state.selectedPaths, contains(tape.path));
      // It keeps its place among the six.
      expect(state.blocked!.needYouPaths, contains(tape.path));
    });

    test('says so when the season has no such episode', () async {
      final fake = FakeBlockedImportService();
      final container = _container(fake);
      final notifier = container.read(manualImportFlowProvider.notifier);
      await notifier.startBlocked(
        ServiceKey.sonarr,
        instanceId: blockedImportConnection,
      );
      final tape = container
          .read(manualImportFlowProvider)
          .items
          .firstWhere((item) => item.path.contains('Tapes.E01'));

      expect(
        await notifier.placeEpisode(tape, season: 2, episode: 9),
        'S2 has no E9.',
      );
      expect(
        container.read(manualImportFlowProvider).selectedPaths,
        isNot(contains(tape.path)),
      );
    });
  });

  test('the import is dated by this device, whatever clock the arr '
      'keeps', () async {
    final fake = FakeBlockedImportService();
    final now = DateTime(2026, 10, 9, 21);
    final container = ProviderContainer(
      overrides: [
        ...blockedImportOverrides(fake),
        stallClockProvider.overrideWith(
          (ref) =>
              () => now,
        ),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(manualImportFlowProvider.notifier);
    await notifier.startBlocked(
      ServiceKey.sonarr,
      instanceId: blockedImportConnection,
    );
    await notifier.confirmImport();
    expect(container.read(manualImportFlowProvider).commandEndedAt, isNull);
    expect(container.read(importReportProvider)?.command.isActive, isTrue);

    // Done, by a server whose clock is years behind.
    fake.command = ManualImportCommandStatus.fromJson(const {
      'id': 41,
      'name': 'ManualImport',
      'status': 'completed',
      'ended': '2020-01-01T00:00:00Z',
    });
    await notifier.pollCommand();

    expect(container.read(manualImportFlowProvider).commandEndedAt, now);
    final report = container.read(importReportProvider);
    expect(report, isNotNull);
    expect(report!.endedAt, now);
  });

  test('the import posts each file with its download', () async {
    final fake = FakeBlockedImportService();
    final container = _container(fake);
    final notifier = container.read(manualImportFlowProvider.notifier);
    await notifier.startBlocked(
      ServiceKey.sonarr,
      instanceId: blockedImportConnection,
    );
    await notifier.confirmImport();

    final posted = fake.posted!;
    expect(posted, hasLength(12));
    expect(posted.first.downloadId, 'clear-1-1');
    expect(
      posted.first.toCommandFileJson(ServiceKey.sonarr)['downloadId'],
      'clear-1-1',
    );
  });
}
