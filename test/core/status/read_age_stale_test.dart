import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/lifecycle/page_activity.dart';
import 'package:cupola/core/lifecycle/poll_probe.dart';
import 'package:cupola/core/status/read_age.dart';
import 'package:cupola/core/status/read_clock.dart';
import 'package:cupola/core/utils/sample_age.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../test_helpers/settings_scope.dart';

/// A queue page's decision, printed: the age it is told when its read has
/// stopped coming back, or `fresh`.
class _Page extends ConsumerWidget {
  const _Page({
    required this.underBand,
    required this.hasQueue,
    required this.onBuild,
  });

  final bool underBand;
  final bool hasQueue;
  final VoidCallback onBuild;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    onBuild();
    final age = ref.watchQueueStaleAge(
      context,
      ServiceKey.sabnzbd,
      underBand: underBand,
      hasQueue: hasQueue,
    );
    return Text(age == null ? 'fresh' : 'stale ${formatDurationAge(age)}');
  }
}

class _Host extends StatefulWidget {
  const _Host({super.key, required this.onBuild});

  final VoidCallback onBuild;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  bool underBand = false;
  bool hasQueue = true;
  bool branchActive = true;

  void update({bool? underBand, bool? hasQueue, bool? branchActive}) =>
      setState(() {
        this.underBand = underBand ?? this.underBand;
        this.hasQueue = hasQueue ?? this.hasQueue;
        this.branchActive = branchActive ?? this.branchActive;
      });

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: BranchActivityScope(
      isActive: branchActive,
      branchIndex: 0,
      child: _Page(
        underBand: underBand,
        hasQueue: hasQueue,
        onBuild: widget.onBuild,
      ),
    ),
  );
}

void main() {
  final settings = settingsWith(
    sabnzbdUrl: 'http://sab.test',
    sabnzbdApiKey: 'key',
  );
  final connection = settings.primaryOf(ServiceKey.sabnzbd)!.id;
  final key = queueReadKey(ServiceKey.sabnzbd, connection);
  final checkId = 'read_age.stale.$key';
  final start = DateTime(2026, 10, 18, 9);

  late DateTime now;
  late ReadClock clock;
  late int builds;
  final hostKey = GlobalKey<_HostState>();

  setUp(() {
    now = start;
    clock = ReadClock(now: () => now);
    builds = 0;
    PollProbe.instance.reset();
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentSettingsProvider.overrideWith((ref) => settings),
          readClockProvider.overrideWithValue(clock),
        ],
        child: _Host(key: hostKey, onBuild: () => builds++),
      ),
    );
  }

  /// Time passes: the clock the page reads, and the timers that wake it.
  Future<void> elapse(WidgetTester tester, Duration duration) async {
    now = now.add(duration);
    await tester.pump(duration);
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 1));
  }

  int checks() => PollProbe.instance.countFor(checkId);

  group('a queue page on screen', () {
    testWidgets('is not stale while its read is fresh', (tester) async {
      clock.note(key);
      await pump(tester);

      await elapse(tester, const Duration(seconds: 10));

      expect(find.text('fresh'), findsOneWidget);
    });

    testWidgets('is told how old its read is once none has come back for '
        'longer than the threshold', (tester) async {
      clock.note(key);
      await pump(tester);

      await elapse(tester, queueStaleAfter + const Duration(seconds: 3));

      expect(find.text('stale just now'), findsOneWidget);
    });

    testWidgets('is told the age of the last read, which is older than the '
        'wait when the read predates the page', (tester) async {
      clock.note(key, start.subtract(const Duration(minutes: 5)));
      await pump(tester);

      // The read is five minutes old, but the page has not waited five
      // minutes for it: it is given the threshold of its own first.
      expect(find.text('fresh'), findsOneWidget);
      await elapse(tester, const Duration(seconds: 10));
      expect(find.text('fresh'), findsOneWidget);

      await elapse(tester, const Duration(seconds: 6));
      expect(find.text('stale 5\u00A0min ago'), findsOneWidget);
    });

    testWidgets('keeps its age moving while it is stale', (tester) async {
      clock.note(key);
      await pump(tester);
      await elapse(tester, queueStaleAfter + const Duration(seconds: 3));
      expect(find.text('stale just now'), findsOneWidget);

      await elapse(tester, const Duration(minutes: 1));
      expect(find.text('stale 1\u00A0min ago'), findsOneWidget);

      await elapse(tester, const Duration(minutes: 1));
      expect(find.text('stale 2\u00A0min ago'), findsOneWidget);
    });

    testWidgets('is told no more when a read comes back', (tester) async {
      clock.note(key);
      await pump(tester);
      await elapse(tester, queueStaleAfter + const Duration(seconds: 3));
      expect(find.text('stale just now'), findsOneWidget);

      // The read lands between two checks: the page is rebuilt by its own
      // data, and reads the clock afresh.
      clock.note(key);
      hostKey.currentState!.update();
      await tester.pump();

      expect(find.text('fresh'), findsOneWidget);
    });

    testWidgets('is not stale for a read that came back just under the '
        'threshold, however often it is asked', (tester) async {
      clock.note(key);
      await pump(tester);

      for (var i = 0; i < 20; i++) {
        await elapse(tester, const Duration(seconds: 6));
        clock.note(key);
        expect(find.text('fresh'), findsOneWidget);
      }
    });

    testWidgets('is not rebuilt by the check while it stays fresh', (
      tester,
    ) async {
      clock.note(key);
      await pump(tester);
      final before = builds;

      for (var i = 0; i < 5; i++) {
        await elapse(tester, const Duration(seconds: 2));
        clock.note(key);
      }

      expect(checks(), greaterThanOrEqualTo(4), reason: 'it is being asked');
      expect(builds, before, reason: 'and the answer did not change');
    });
  });

  group('a queue page that has nothing to call old', () {
    testWidgets('is never stale on a cold open, and starts no timer', (
      tester,
    ) async {
      await pump(tester);

      await elapse(tester, const Duration(minutes: 2));

      expect(find.text('fresh'), findsOneWidget);
      expect(checks(), 0);
    });

    testWidgets('is never stale while it holds no queue to draw', (
      tester,
    ) async {
      clock.note(key);
      await pump(tester);
      hostKey.currentState!.update(hasQueue: false);
      await settle(tester);

      await elapse(tester, const Duration(minutes: 2));

      expect(find.text('fresh'), findsOneWidget);
    });

    testWidgets('is never stale under a fault band, which says why, and '
        'asks nothing', (tester) async {
      clock.note(key);
      await pump(tester);
      hostKey.currentState!.update(underBand: true);
      await settle(tester);
      final before = checks();

      await elapse(tester, const Duration(minutes: 2));

      expect(find.text('fresh'), findsOneWidget);
      expect(checks(), before, reason: 'a fault band owns the page');
    });

    testWidgets('is not stale for a read it has not waited the threshold for '
        'after the band goes', (tester) async {
      clock.note(key);
      await pump(tester);
      hostKey.currentState!.update(underBand: true);
      await settle(tester);
      await elapse(tester, const Duration(minutes: 2));

      hostKey.currentState!.update(underBand: false);
      await tester.pump();

      expect(find.text('fresh'), findsOneWidget);
    });
  });

  group('a queue page that is not the one on screen', () {
    testWidgets('keeps no timer, and gets the threshold of its own when it '
        'returns', (tester) async {
      clock.note(key);
      await pump(tester);
      hostKey.currentState!.update(branchActive: false);
      await settle(tester);
      final before = checks();

      await elapse(tester, const Duration(minutes: 5));
      expect(checks(), before, reason: 'a hidden page spends nothing');
      expect(find.text('fresh'), findsOneWidget);

      // Back on screen after five minutes, with a read five minutes old: it
      // was not waiting for an answer, and its catch-up read is on its way.
      hostKey.currentState!.update(branchActive: true);
      await tester.pump();
      expect(find.text('fresh'), findsOneWidget);

      await elapse(tester, const Duration(seconds: 10));
      expect(find.text('fresh'), findsOneWidget);

      await elapse(tester, const Duration(seconds: 6));
      expect(find.text('stale 5\u00A0min ago'), findsOneWidget);
    });
  });
}
