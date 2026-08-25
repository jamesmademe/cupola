import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/lifecycle/gated_poll.dart';
import 'package:cupola/core/lifecycle/page_activity.dart';
import 'package:cupola/core/lifecycle/poll_clock.dart';
import 'package:cupola/features/release_search/presentation/release_search_lifecycle.dart';

const _interval = Duration(seconds: 3);

/// Ticks recorded by the poller under test.
late List<String> ticks;

final _poller = Provider.autoDispose<void>((ref) {
  ref.gatedPoll(
    id: 'test.poller',
    interval: _interval,
    onTick: () => ticks.add('tick'),
  );
});

/// A page that polls only while it is the page on screen.
class _GatedPage extends ConsumerWidget {
  const _GatedPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activity = ref.watchWhileLive(context, _poller);
    return Text(
      activity.isLive ? 'live' : 'paused',
      textDirection: TextDirection.ltr,
    );
  }
}

/// The clock every test drives by hand: `tester.pump` advances timers but not
/// [DateTime.now], and the catch-up rule is written in wall-clock terms.
late DateTime now;
late PollClock clock;

Future<void> _pumpPage(
  WidgetTester tester, {
  bool branchActive = true,
  GlobalKey<NavigatorState>? navigatorKey,
  ValueListenable<bool>? covering,
}) async {
  Widget page = const _GatedPage();
  if (covering != null) {
    page = PageCoverageScope(covering: covering, child: page);
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: [pollClockProvider.overrideWithValue(clock)],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        home: BranchActivityScope(
          isActive: branchActive,
          branchIndex: 0,
          child: page,
        ),
      ),
    ),
  );
}

void main() {
  setUp(() {
    ticks = [];
    now = DateTime(2026, 8, 25, 12);
    clock = PollClock()..now = () => now;
  });

  /// Advances both clocks together, so the poller's timers and its catch-up
  /// bookkeeping agree on how much time has passed.
  Future<void> elapse(WidgetTester tester, Duration duration) async {
    now = now.add(duration);
    await tester.pump(duration);
  }

  group('gatedPoll cadence', () {
    testWidgets('ticks once on creation, then every interval', (tester) async {
      await _pumpPage(tester);
      // The catch-up tick is a microtask, so it lands on the next pump.
      await tester.pump();
      expect(ticks, hasLength(1));

      await elapse(tester, _interval);
      expect(ticks, hasLength(2));

      await elapse(tester, _interval);
      expect(ticks, hasLength(3));
    });

    testWidgets('onTick may invalidate providers — it never runs inside build', (
      tester,
    ) async {
      // The reason the first tick is deferred to a microtask: invalidating a
      // provider while one is building throws. This is that guarantee, stated as
      // the thing it exists to allow.
      var builds = 0;
      final target = Provider.autoDispose<int>((ref) => ++builds);
      final invalidating = Provider.autoDispose<void>((ref) {
        ref.gatedPoll(
          id: 'test.invalidating',
          interval: _interval,
          onTick: () {
            ticks.add('tick');
            ref.invalidate(target);
          },
        );
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [pollClockProvider.overrideWithValue(clock)],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                ref.watch(target);
                ref.watch(invalidating);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(ticks, hasLength(1));
    });
  });

  group('gatedPoll catch-up on return', () {
    testWidgets('a short absence does not earn an immediate tick', (
      tester,
    ) async {
      await _pumpPage(tester);
      await tester.pump();
      expect(ticks, hasLength(1));

      // Leave after one second of a three-second interval.
      await elapse(tester, const Duration(seconds: 1));
      await _pumpPage(tester, branchActive: false);
      await tester.pump();
      expect(ticks, hasLength(1));

      // Come straight back: two seconds of the interval are still owed.
      await _pumpPage(tester);
      await tester.pump();
      expect(ticks, hasLength(1), reason: 'not due yet');

      await elapse(tester, const Duration(seconds: 2));
      expect(ticks, hasLength(2), reason: 'due at the remainder');

      await elapse(tester, _interval);
      expect(ticks, hasLength(3), reason: 'then the steady cadence');
    });

    testWidgets('a long absence earns an immediate tick', (tester) async {
      await _pumpPage(tester);
      await tester.pump();
      expect(ticks, hasLength(1));

      await _pumpPage(tester, branchActive: false);
      await elapse(tester, const Duration(minutes: 5));
      expect(ticks, hasLength(1));

      await _pumpPage(tester);
      await tester.pump();
      expect(ticks, hasLength(2), reason: 'stale, so refresh at once');
    });
  });

  group('gatedPoll vetoes — the zero-tolerance assertions', () {
    testWidgets('an inactive branch never ticks, however long it waits', (
      tester,
    ) async {
      await _pumpPage(tester, branchActive: false);
      await tester.pump();

      await elapse(tester, _interval * 20);

      expect(ticks, isEmpty);
      expect(find.text('paused'), findsOneWidget);
    });

    testWidgets('a covering route stops the ticks', (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      await _pumpPage(tester, navigatorKey: navigatorKey);
      await tester.pump();
      expect(ticks, hasLength(1));

      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => const Text('on top')),
      );
      await tester.pumpAndSettle();

      await elapse(tester, _interval * 10);
      expect(ticks, hasLength(1));
    });

    testWidgets('a backgrounded app stops the ticks', (tester) async {
      late WidgetRef capturedRef;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [pollClockProvider.overrideWithValue(clock)],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                capturedRef = ref;
                return const _GatedPage();
              },
            ),
          ),
        ),
      );
      await tester.pump();
      expect(ticks, hasLength(1));

      capturedRef.read(appInForegroundProvider.notifier).set(false);
      await tester.pump();

      await elapse(tester, _interval * 10);
      expect(ticks, hasLength(1));
    });

    testWidgets('an open Portal stops the ticks', (tester) async {
      final covering = ValueNotifier<bool>(false);
      addTearDown(covering.dispose);

      await _pumpPage(tester, covering: covering);
      await tester.pump();
      expect(ticks, hasLength(1));

      covering.value = true;
      await tester.pump();

      await elapse(tester, _interval * 10);
      expect(ticks, hasLength(1));
    });
  });
}
