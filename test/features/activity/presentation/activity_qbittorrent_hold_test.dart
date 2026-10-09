/// Activity reads every qBittorrent connection to join its queue, and a
/// refused sign-in held on that connection's client stays held here.
///
/// A pull re-reads the page and never lifts it. The connection draws a line
/// of its own in Needs you, with the remedy that is a person's ask at it
/// (`Sign in again`), and nothing the page does on its own (a pull, a poll,
/// a return) asks the client again.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/activity/domain/activity_tab.dart';
import 'package:cupola/features/activity/presentation/activity_page.dart';

import '../../../test_helpers/profiles/profiles.dart';

const _loginPath = '/api/v2/auth/login';

int _signIns(ProfileHarness harness) => harness.network
    .requestsTo(WorldIds.qbittorrent)
    .where((request) => request.path == _loginPath)
    .length;

void main() {
  testWidgets('P7: a pull leaves a refused qBittorrent held, and the page '
      'names it with the remedy', (tester) async {
    // P7: qBittorrent refuses the sign-in; Lidarr is home-only and away.
    final harness = await pumpWithProfile(
      tester,
      Profiles.p7,
      // A phone's height: a pull has to travel a quarter of it to count.
      surfaceSize: const Size(430, 900),
      child: const ActivityPage(tab: ActivityTab.all),
    );
    final first = _signIns(harness);
    expect(first, 1, reason: 'the queue join asked qBittorrent once');

    // The connection has its line, and the way out is the person's.
    expect(
      find.text('qBittorrent answered but refused the sign-in'),
      findsOneWidget,
    );
    expect(find.text('Sign in again'), findsOneWidget);

    int radarrReads() => harness.network.requestsTo(WorldIds.radarr).length;
    final beforePulls = radarrReads();
    for (var pull = 0; pull < 3; pull++) {
      await tester.drag(
        find
            .descendant(
              of: find.byType(RefreshIndicator),
              matching: find.byType(Scrollable),
            )
            .first,
        const Offset(0, 300),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 1));
      await harness.settle(tester);
    }
    expect(radarrReads(), greaterThan(beforePulls), reason: 'it re-read');
    expect(_signIns(harness), first, reason: 'a pull re-reads, never lifts');

    await harness.unmount(tester);
  });
}
