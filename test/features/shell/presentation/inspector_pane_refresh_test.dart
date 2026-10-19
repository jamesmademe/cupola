/// The inspector reads again while it is on screen.
///
/// Its providers are the app's only copy of "what is downloading now" and
/// "what finished today", and neither had a poll: the pane kept the first read
/// of the session, so a transfer sat at 40% on the side while the page beside it
/// moved on.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/lifecycle/poll_clock.dart';
import 'package:cupola/features/activity/presentation/activity_provider.dart';
import 'package:cupola/features/shell/domain/stack_health.dart';
import 'package:cupola/features/shell/presentation/desktop/inspector_pane.dart';

import '../../../test_helpers/settings_scope.dart';

Widget _pane() => const MaterialApp(
  home: Scaffold(
    body: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [SizedBox(width: 360, child: InspectorPane())],
    ),
  ),
);

void main() {
  late int reads;
  late DateTime now;
  late ProviderContainer container;

  setUp(() async {
    reads = 0;
    now = DateTime(2026, 10, 19, 12);
    container = ProviderContainer(
      overrides: [
        ...await settingsScopeOverrides(),
        pollClockProvider.overrideWithValue(PollClock()..now = () => now),
        globalNowItemsProvider.overrideWith((ref) async {
          reads++;
          return const ActivityFeed(items: [], results: []);
        }),
        unreachableServicesProvider.overrideWithValue(const []),
      ],
    );
    addTearDown(container.dispose);
  });

  Future<void> show(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: child),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a pane left open reads the queue again every fifteen seconds', (
    tester,
  ) async {
    await show(tester, _pane());
    final opened = reads;
    expect(opened, greaterThan(0));

    await tester.pump(const Duration(seconds: 16));
    await tester.pumpAndSettle();

    expect(reads, opened + 1);

    // Closed, the timer goes with it.
    await show(tester, const SizedBox());
  });

  testWidgets('a pane opened again after a while shows a fresh read, not the '
      'one it held', (tester) async {
    await show(tester, _pane());
    final firstOpen = reads;

    // Closed: nothing may be read for a pane nobody sees.
    await show(tester, const SizedBox());
    now = now.add(const Duration(seconds: 90));
    await tester.pump(const Duration(seconds: 90));
    expect(reads, firstOpen);

    await show(tester, _pane());

    expect(reads, firstOpen + 1);
    await show(tester, const SizedBox());
  });
}
