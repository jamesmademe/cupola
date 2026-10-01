import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/activity/presentation/widgets/activity_actions.dart';
import 'package:cupola/features/services/presentation/service_all_screens.dart';

import '../../../test_helpers/profiles/profiles.dart';

/// An approval says it is working from the tap, and waits one budget.
///
/// Approving reads where the request goes before the confirmation opens. On
/// a slow Seerr that read used to run with nothing on screen, for up to a
/// 4 s cap per read, and every tap meanwhile started another.
void main() {
  int reads(ProfileHarness harness, String path) => harness.network
      .requestsTo(WorldIds.seerr)
      .where((r) => r.method == 'GET' && r.uri.path == path)
      .length;

  testWidgets('P6, Seerr slow: the tapped Approve is busy at once, in its own '
      'place, and a second tap does nothing', (tester) async {
    final semantics = tester.ensureSemantics();
    final harness = await pumpWithProfile(
      tester,
      Profiles.p6.withLatency(WorldIds.seerr, const Duration(seconds: 1)),
      child: const ServiceAllRequestsScreen(),
    );
    final approve = find.byTooltip('Approve request for Charge');
    await tester.ensureVisible(approve);
    await tester.pump();
    final rect = tester.getRect(approve);

    await tester.tap(approve);
    await tester.pump();

    // Busy in the first frame, where the glyph was, at the glyph's size.
    expect(
      find.descendant(
        of: approve,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    expect(tester.getRect(approve), rect);
    expect(
      tester.getSemantics(approve),
      containsSemantics(
        tooltip: 'Approve request for Charge',
        value: 'Checking where it goes',
        isButton: true,
        isEnabled: true,
      ),
    );

    // A second tap while it reads starts nothing.
    await tester.tap(approve);
    await tester.pump();
    await harness.settle(tester);

    expect(find.text('Approve this request?'), findsOneWidget);
    expect(reads(harness, '/api/v1/settings/radarr'), 1);

    // Idle again behind the confirmation, and after it.
    expect(
      find.descendant(
        of: approve,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsNothing,
    );
    await tester.tap(find.text('Cancel'));
    await harness.settle(tester);
    expect(reads(harness, '/api/v1/settings/radarr'), 1);

    semantics.dispose();
    await harness.unmount(tester);
  });

  testWidgets('P6, Seerr slow: reading the request and its servers shares one '
      '4 s budget', (tester) async {
    // Every answer takes 3 s: the request arrives at 3 s, its servers would
    // at 6 s.
    final harness = await pumpWithProfile(
      tester,
      Profiles.p6.withLatency(WorldIds.seerr, const Duration(seconds: 3)),
      child: Scaffold(
        body: Consumer(
          builder: (context, ref, _) => TextButton(
            onPressed: () => ActivityActions.approveRequest(
              context,
              ref,
              instanceId: '',
              requestId: 1,
              title: 'Charge',
            ),
            child: const Text('Decide'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Decide'));
    await tester.pump(const Duration(milliseconds: 3900));
    expect(find.text('Approve this request?'), findsNothing);

    // At the budget it says what it knows. It used to give each read a cap
    // of its own and wait for the servers until 6 s.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(find.text('Approve this request?'), findsOneWidget);
    expect(
      find.text("Charge goes to Seerr's Radarr and starts downloading."),
      findsOneWidget,
    );

    await tester.tap(find.text('Cancel'));
    // Let the read that ran out of budget finish in the background.
    await tester.pump(const Duration(seconds: 5));
    await harness.settle(tester);
    await harness.unmount(tester);
  });
}
