/// Prowlarr's Needs attention leads where the fault is fixed: several failing
/// indexers are one row that opens the Indexers tab, one failing indexer opens
/// its own page and can be tested from the row, through the action the
/// indexer's page and the list already run.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_overview_screen.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/overview_shell.dart';
import '../../../test_helpers/profiles/profiles.dart';

/// The statuses Prowlarr reports for [ids]: each one failing, and blocked
/// until an hour from now.
NetworkReply _failing(NetworkRequest request, List<int> ids) {
  final until = DateTime.now().add(const Duration(hours: 1));
  return NetworkReply.json([
    for (final id in ids)
      {
        'id': id,
        'indexerId': id,
        'disabledTill': until.toUtc().toIso8601String(),
        'mostRecentFailure': DateTime.now().toUtc().toIso8601String(),
        'initialFailure': DateTime.now().toUtc().toIso8601String(),
      },
  ]);
}

Future<(ProfileHarness, OverviewShell)> _pump(
  WidgetTester tester, {
  required List<int> failing,
}) async {
  final harness = await ProfileHarness.start(Profiles.p1);
  harness.network.on(
    WorldIds.prowlarr,
    'GET',
    '/api/v1/indexerstatus',
    (request) => _failing(request, failing),
  );
  harness.network.on(
    WorldIds.prowlarr,
    'POST',
    '/api/v1/indexer/test',
    (request) => NetworkReply.json(const <String, Object?>{}),
  );
  harness.network.followFakeTime(tester.binding);
  await tester.binding.setSurfaceSize(const Size(430, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final shell = OverviewShell(
    ServiceKey.prowlarr,
    const ProwlarrOverviewScreen(topPadding: 0),
  );
  await tester.pumpWidget(
    ProviderScope(overrides: harness.overrides, child: shell.app),
  );
  await harness.settle(tester);
  return (harness, shell);
}

/// The Needs attention region's rows, not the indexer table under it.
Finder get _attentionRows => find.descendant(
  of: find.ancestor(
    of: find.text('Needs attention'),
    matching: find.byType(Column),
  ),
  matching: find.byType(ServiceOverviewRow),
);

List<int> _testRequests(ProfileHarness harness) => [
  for (final request in harness.network.requestsTo(WorldIds.prowlarr))
    if (request.method == 'POST' && request.path == '/api/v1/indexer/test')
      (request.json as Map)['id'] as int,
];

void main() {
  testWidgets('P1: three failing indexers are one row, and its door is the '
      'Indexers tab', (tester) async {
    final (harness, shell) = await _pump(tester, failing: [1, 2, 3]);

    // One row for the three, with the names behind it; not three rows.
    expect(find.text('3 indexers failing'), findsOneWidget);
    expect(find.text('Atlas NZB, Beacon Usenet, Cedar Index'), findsOneWidget);
    // The header still counts the faults the row stands for.
    expect(find.text('3'), findsWidgets);

    // A door: one button for a screen reader, and where it goes.
    expect(
      find.semantics.byLabel(
        '3 indexers failing, Atlas NZB, Beacon Usenet, Cedar Index',
      ),
      isSemantics(
        isButton: true,
        hasTapAction: true,
        hint: 'opens the Prowlarr Indexers tab',
      ),
    );
    // And no verb: a test is of one indexer.
    expect(find.text('Test'), findsNothing);

    await tester.tap(find.text('3 indexers failing'));
    await harness.settle(tester);

    expect(shell.tab, ServiceTab.indexers);

    await harness.unmount(tester);
  });

  testWidgets('P1: one failing indexer opens its own page, and Test runs the '
      'indexer test the page runs', (tester) async {
    final (harness, shell) = await _pump(tester, failing: [2]);

    expect(find.text('Beacon Usenet'), findsWidgets);
    expect(find.textContaining('indexers failing'), findsNothing);
    expect(
      find.semantics.byHint('tests Beacon Usenet'),
      isSemantics(label: 'Test', isButton: true, hasTapAction: true),
    );

    await tester.tap(find.text('Test'));
    await harness.settle(tester);

    // The saved indexer, sent to Prowlarr as the page and the list send it.
    expect(_testRequests(harness), [2]);
    expect(find.text('Beacon Usenet answered'), findsOneWidget);
    // Testing is not opening: the Overview stays where it was.
    expect(shell.tab, ServiceTab.overview);

    // The row's body, not the verb, is the way to the page.
    await tester.tap(
      find.descendant(of: _attentionRows, matching: find.text('Beacon Usenet')),
    );
    await harness.settle(tester);
    expect(shell.location, '/stack/prowlarr/indexers/indexer/2');
    expect(_testRequests(harness), [
      2,
    ], reason: 'opening the page does not run the test again');

    await harness.unmount(tester);
  });

  testWidgets('P1: with nothing failing the region is its resting note, and '
      'no row is a door', (tester) async {
    final (harness, _) = await _pump(tester, failing: const []);

    expect(find.text('Every indexer is answering'), findsOneWidget);
    expect(find.text('Test'), findsNothing);

    await harness.unmount(tester);
  });
}
