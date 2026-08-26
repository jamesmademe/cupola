import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/lifecycle/page_activity.dart';
import 'package:cupola/core/lifecycle/poll_clock.dart';
import 'package:cupola/core/lifecycle/refresh_on_return.dart';

const _maxAge = Duration(minutes: 2);

late List<String> refreshes;
late DateTime now;
late PollClock clock;

class _Host extends StatefulWidget {
  const _Host();

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  bool branchActive = true;

  void setBranchActive(bool value) => setState(() => branchActive = value);

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: BranchActivityScope(
      isActive: branchActive,
      branchIndex: 0,
      child: RefreshOnReturn(
        id: 'test.page',
        maxAge: _maxAge,
        onStale: () => refreshes.add('refresh'),
        child: const SizedBox.shrink(),
      ),
    ),
  );
}

void main() {
  setUp(() {
    refreshes = [];
    now = DateTime(2026, 8, 25, 12);
    clock = PollClock()..now = () => now;
  });

  Future<_HostState> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [pollClockProvider.overrideWithValue(clock)],
        child: const _Host(),
      ),
    );
    await tester.pumpAndSettle();
    return tester.state<_HostState>(find.byType(_Host));
  }

  group('RefreshOnReturn', () {
    testWidgets('does not refresh on first appearance', (tester) async {
      await pump(tester);

      // Whatever it shows, it has just loaded it.
      expect(refreshes, isEmpty);
    });

    testWidgets('a short absence is not worth a fetch', (tester) async {
      final host = await pump(tester);

      host.setBranchActive(false);
      await tester.pumpAndSettle();
      now = now.add(const Duration(seconds: 20));
      host.setBranchActive(true);
      await tester.pumpAndSettle();

      expect(
        refreshes,
        isEmpty,
        reason: 'a glance at another tab must cost nothing',
      );
    });

    testWidgets('a long absence refreshes once on return', (tester) async {
      final host = await pump(tester);

      host.setBranchActive(false);
      await tester.pumpAndSettle();
      now = now.add(const Duration(minutes: 10));
      host.setBranchActive(true);
      await tester.pumpAndSettle();

      expect(refreshes, hasLength(1));
    });

    testWidgets('returning twice in a row refreshes only when stale again', (
      tester,
    ) async {
      final host = await pump(tester);

      host.setBranchActive(false);
      await tester.pumpAndSettle();
      now = now.add(const Duration(minutes: 10));
      host.setBranchActive(true);
      await tester.pumpAndSettle();
      expect(refreshes, hasLength(1));

      // Straight out and back: the return that just happened reset the clock.
      host.setBranchActive(false);
      await tester.pumpAndSettle();
      now = now.add(const Duration(seconds: 5));
      host.setBranchActive(true);
      await tester.pumpAndSettle();

      expect(refreshes, hasLength(1));
    });

    testWidgets('a rebuild while visible does not refresh', (tester) async {
      final host = await pump(tester);
      now = now.add(const Duration(minutes: 10));

      // Same visibility, new frame: staleness alone must not fire it, or a
      // visible page would refresh on every rebuild once it aged.
      host.setBranchActive(true);
      await tester.pumpAndSettle();

      expect(refreshes, isEmpty);
    });
  });
}
