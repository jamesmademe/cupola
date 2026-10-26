import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/utils/service_action.dart';
import 'package:cupola/features/home/data/home_live.dart';
import 'package:cupola/features/qbittorrent/data/qbittorrent_service.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_actions.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_provider.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/transmission/presentation/transmission_provider.dart';

class _Qb extends Fake implements QbittorrentService {}

final _unrelated = FutureProvider<int>((ref) async => 1);

/// A pause, a resume or a remove from a download client's page shows on the
/// home's queue at once: the queue no longer watches the client's list, so the
/// action runners say so themselves.
void main() {
  late int queueReads;
  late ProviderContainer container;

  Future<void> pump(
    WidgetTester tester,
    Future<void> Function(BuildContext context, WidgetRef ref) onTap,
  ) async {
    queueReads = 0;
    container = ProviderContainer(
      overrides: [
        servicesQueueProvider.overrideWith((ref) async {
          queueReads++;
          return (
            items: const <ServiceQueueItem>[],
            coverage: SourceCoverage.none,
          );
        }),
        allTorrentsProvider.overrideWith((ref) async => const []),
        qbittorrentServiceProvider.overrideWithValue(_Qb()),
      ],
    );
    addTearDown(container.dispose);
    container.listen(servicesQueueProvider, (_, _) {});
    await container.read(servicesQueueProvider.future);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => onTap(context, ref),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('a write that drops a client list reads the queue again', (
    tester,
  ) async {
    await pump(
      tester,
      (context, ref) => runServiceAction(
        context,
        ref,
        action: () async {},
        failureMessage: 'Could not pause',
        invalidate: [transmissionTorrentsProvider],
      ),
    );

    expect(queueReads, 2);
  });

  testWidgets('a write that drops nothing of a client leaves it alone', (
    tester,
  ) async {
    await pump(
      tester,
      (context, ref) => runServiceAction(
        context,
        ref,
        action: () async {},
        failureMessage: 'Could not save',
        invalidate: [_unrelated],
      ),
    );

    expect(queueReads, 1);
  });

  testWidgets('a write that failed reads nothing again', (tester) async {
    await pump(
      tester,
      (context, ref) => runServiceAction(
        context,
        ref,
        action: () async => throw Exception('refused'),
        failureMessage: 'Could not pause',
        invalidate: [transmissionTorrentsProvider],
      ),
    );

    expect(queueReads, 1);
  });

  testWidgets('a qBittorrent pause from its page reads the queue again', (
    tester,
  ) async {
    await pump(
      tester,
      (context, ref) => runTorrentAction(
        context,
        ref,
        action: (_) async {},
        failureMessage: 'Could not pause',
        invalidate: [allTorrentsProvider],
      ),
    );

    expect(queueReads, 2);
  });

  test('the lists a client page holds are part of what the home reads', () {
    for (final list in downloadClientLists) {
      expect(homeDownloadsSources, contains(list));
    }
  });
}
