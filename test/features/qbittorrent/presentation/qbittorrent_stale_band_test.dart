import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/qbittorrent/presentation/qbittorrent_screen.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/profiles/profiles.dart';
import '../../../test_helpers/queue_stale_scenarios.dart';

final _case = QueueStaleCase(
  service: ServiceKey.qbittorrent,
  profile: Profiles.p1,
  connectionId: WorldIds.qbittorrent,
  screen: () => const QbittorrentScreen(),
  isQueueRead: (request) => request.path == '/api/v2/sync/maindata',
  // `QbittorrentSync` hands a read asked for in flight the one in flight.
  sharesReadInFlight: true,
);

void main() {
  defineQueueStaleScenarios(_case);

  testWidgets('a band that comes up leaves the list where it was scrolled', (
    tester,
  ) async {
    final scene = await openQueueStaleScene(tester, _case);
    final rows = find.descendant(
      of: find.byKey(const ValueKey('torrent-rows')),
      matching: find.byType(Scrollable),
    );
    final before = tester.state<ScrollableState>(rows.first);
    before.position.jumpTo(60);
    await tester.pump();
    expect(before.position.pixels, 60, reason: 'the list is long enough');

    scene.hung = true;
    await scene.elapse(const Duration(seconds: 4));
    await scene.elapseTo(
      scene.readClock.at(scene.readKey)!.add(const Duration(seconds: 15)),
    );
    expect(scene.bands, findsOneWidget);

    final after = tester.state<ScrollableState>(rows.first);
    expect(after, same(before), reason: 'the same list, not a new one');
    expect(after.position.pixels, 60);

    await scene.finish();
  });
}
