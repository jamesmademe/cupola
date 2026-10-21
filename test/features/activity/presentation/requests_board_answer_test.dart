/// A request that waits is answered on the Requests view with the control
/// every list draws: the same question, the same busy state, the same word
/// once it went through.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/activity/presentation/widgets/requests_board.dart';

import '../../../test_helpers/profiles/profiles.dart';

void main() {
  Iterable<String> seerrWrites(ProfileHarness harness) => harness.network
      .requestsTo(WorldIds.seerr)
      .where((r) => r.method != 'GET')
      .map((r) => '${r.method} ${r.uri.path}');

  Future<ProfileHarness> pump(WidgetTester tester) => pumpWithProfile(
    tester,
    Profiles.p1,
    child: Scaffold(
      body: ListView(children: const [RequestsBoard(only: '')]),
    ),
    // Wide enough for the pair to stand side by side in the test's font,
    // whose letters are as wide as they are tall.
    surfaceSize: const Size(600, 1600),
  );

  testWidgets('P1: each waiting row carries the pair, named by its title', (
    tester,
  ) async {
    final harness = await pump(tester);

    for (final title in ['Charge', 'Metropolis']) {
      expect(find.byTooltip('Approve $title'), findsOneWidget);
      expect(find.byTooltip('Decline $title'), findsOneWidget);
    }
    // One width each, side by side.
    final approve = find.widgetWithText(FilledButton, 'Approve').first;
    final decline = find.widgetWithText(OutlinedButton, 'Decline').first;
    expect(tester.getSize(approve).width, tester.getSize(decline).width);
    expect(tester.getTopLeft(approve).dy, tester.getTopLeft(decline).dy);

    await harness.unmount(tester);
  });

  testWidgets('P1: Decline asks the one question, and the row says '
      'Declined in the pair\'s place', (tester) async {
    final harness = await pump(tester);

    final decline = find.byTooltip('Decline Metropolis');
    await tester.ensureVisible(decline);
    await tester.tap(decline);
    await harness.settle(tester);
    // The same words as every other list, not a dialog of this row's own.
    expect(find.text('Decline this request?'), findsOneWidget);
    expect(
      find.text(
        'Metropolis will not be downloaded. The request stays on record as '
        'declined.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Decline request'));
    await harness.settle(tester);

    expect(seerrWrites(harness), ['POST /api/v1/request/2/decline']);
    expect(find.text('Request declined'), findsOneWidget);
    expect(find.byTooltip('Decline Metropolis'), findsNothing);
    expect(find.byTooltip('Approve Metropolis'), findsNothing);
    // Charge, still waiting, keeps its pair.
    expect(find.byTooltip('Approve Charge'), findsOneWidget);

    await harness.unmount(tester);
  });

  testWidgets('P1: Approve names the server, and the row says where it '
      'went', (tester) async {
    final harness = await pump(tester);

    final approve = find.byTooltip('Approve Charge');
    await tester.ensureVisible(approve);
    await tester.tap(approve);
    await harness.settle(tester);
    expect(find.text('Approve Charge'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Approve request'));
    await harness.settle(tester);

    expect(seerrWrites(harness), ['POST /api/v1/request/1/approve']);
    expect(find.textContaining('Approved\u00A0· '), findsOneWidget);
    expect(find.byTooltip('Approve Charge'), findsNothing);

    await harness.unmount(tester);
  });
}
