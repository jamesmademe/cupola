/// Activity reads every qBittorrent connection to join its queue, and a
/// refused sign-in held on that connection's client stays held here.
///
/// A pull re-reads the page and never lifts it. Activity's Retry sits beside
/// the failures Activity draws, which are its own sources' (the arrs and
/// Seerr): a refusing qBittorrent draws no line of its own here yet, so no
/// Retry on this page sits beside it, and the one beside another source's
/// failure is not an ask about qBittorrent. Once the page draws the clients'
/// coverage, the Retry beside a qBittorrent line is a person's ask at it and
/// lifts the hold (`liftQbittorrentRefusals`), as the Dashboard's does.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/activity/presentation/global_activity_screen.dart';

import '../../../test_helpers/profiles/profiles.dart';

const _loginPath = '/api/v2/auth/login';

int _signIns(ProfileHarness harness) => harness.network
    .requestsTo(WorldIds.qbittorrent)
    .where((request) => request.path == _loginPath)
    .length;

Finder _faultLines() => find.byWidgetPredicate(
  (widget) =>
      widget.key is ValueKey<String> &&
      (widget.key! as ValueKey<String>).value.startsWith('activity-fault-line'),
);

void main() {
  testWidgets('P7: a pull and the Retry beside another failure leave a '
      'refused qBittorrent held', (tester) async {
    // P7: qBittorrent refuses the sign-in; Lidarr is home-only and away, so
    // the page draws a failure line, and a Retry, for Lidarr.
    final harness = await pumpWithProfile(
      tester,
      Profiles.p7,
      child: const GlobalActivityScreen(),
    );
    final first = _signIns(harness);
    expect(first, 1, reason: 'the queue join asked qBittorrent once');

    // No line on this page names qBittorrent, so no Retry sits beside it.
    expect(_faultLines(), findsWidgets);
    expect(
      find.descendant(
        of: _faultLines(),
        matching: find.textContaining('qBittorrent'),
      ),
      findsNothing,
    );

    int radarrReads() => harness.network.requestsTo(WorldIds.radarr).length;
    final beforePulls = radarrReads();
    for (var pull = 0; pull < 3; pull++) {
      await tester.fling(
        find.byType(Scrollable).last,
        const Offset(0, 400),
        1000,
      );
      await harness.settle(tester);
    }
    expect(radarrReads(), greaterThan(beforePulls), reason: 'it re-read');
    expect(_signIns(harness), first, reason: 'a pull re-reads, never lifts');

    final retry = find.descendant(
      of: _faultLines(),
      matching: find.widgetWithText(TextButton, 'Retry'),
    );
    expect(retry, findsWidgets);
    final beforeRetry = radarrReads();
    await tester.tap(retry.first);
    await harness.settle(tester);
    expect(radarrReads(), greaterThan(beforeRetry), reason: 'it re-read');
    expect(_signIns(harness), first, reason: 'a Retry beside Lidarr');

    await harness.unmount(tester);
  });
}
