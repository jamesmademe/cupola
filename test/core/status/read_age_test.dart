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

/// A page that prints the age it was handed, and counts how often it was built.
class _Page extends ConsumerWidget {
  const _Page({required this.underBand, required this.onBuild});

  final bool underBand;
  final VoidCallback onBuild;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    onBuild();
    final age = ref.watchQueueReadAge(
      context,
      ServiceKey.sabnzbd,
      underBand: underBand,
    );
    return Text(age == null ? 'no age' : formatDurationAge(age));
  }
}

class _Host extends StatefulWidget {
  const _Host({super.key, required this.onBuild, this.underBand = true});

  final VoidCallback onBuild;
  final bool underBand;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late bool underBand = widget.underBand;
  bool branchActive = true;

  void update({bool? underBand, bool? branchActive}) => setState(() {
    this.underBand = underBand ?? this.underBand;
    this.branchActive = branchActive ?? this.branchActive;
  });

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: BranchActivityScope(
      isActive: branchActive,
      branchIndex: 0,
      child: _Page(underBand: underBand, onBuild: widget.onBuild),
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
  final readAt = DateTime(2026, 10, 12, 9);

  late DateTime now;
  late ReadClock clock;
  late int builds;
  final hostKey = GlobalKey<_HostState>();

  setUp(() {
    now = readAt.add(const Duration(minutes: 6));
    clock = ReadClock(now: () => now)..note(key, readAt);
    builds = 0;
    PollProbe.instance.reset();
  });

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    bool underBand = true,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentSettingsProvider.overrideWith((ref) => settings),
          readClockProvider.overrideWithValue(clock),
        ],
        child: _Host(
          key: hostKey,
          onBuild: () => builds++,
          underBand: underBand,
        ),
      ),
    );
    return ProviderScope.containerOf(tester.element(find.byType(_Page)));
  }

  /// One frame to rebuild the page, and one more for the disposal that a
  /// dropped watch schedules (Riverpod disposes at the end of the next frame).
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 1));
  }

  int minuteTicks() => PollProbe.instance.countFor('read_age.minute');

  group('a page under a band', () {
    testWidgets('is told how old the last read is', (tester) async {
      await pump(tester);

      expect(find.text('6\u00A0min ago'), findsOneWidget);
    });

    testWidgets('is told the age move when a minute passes', (tester) async {
      await pump(tester);
      expect(find.text('6\u00A0min ago'), findsOneWidget);

      now = now.add(const Duration(minutes: 1));
      await tester.pump(const Duration(minutes: 1));

      expect(find.text('7\u00A0min ago'), findsOneWidget);
      expect(minuteTicks(), 1);

      now = now.add(const Duration(minutes: 1));
      await tester.pump(const Duration(minutes: 1));

      expect(find.text('8\u00A0min ago'), findsOneWidget);
      expect(minuteTicks(), 2);
    });

    testWidgets('is not rebuilt between two minutes', (tester) async {
      await pump(tester);
      final before = builds;

      await tester.pump(const Duration(seconds: 59));

      expect(builds, before);
    });

    testWidgets('is told nothing when no read was ever recorded', (
      tester,
    ) async {
      clock = ReadClock(now: () => now);
      final container = await pump(tester);

      expect(find.text('no age'), findsOneWidget);
      expect(
        container.exists(minuteNowProvider),
        isFalse,
        reason: 'with no age to print there is nothing to renew',
      );
    });

    testWidgets('is not told the age of another connection', (tester) async {
      clock = ReadClock(now: () => now)
        ..note(queueReadKey(ServiceKey.sabnzbd, 'seedbox'), readAt);
      await pump(tester);

      expect(find.text('no age'), findsOneWidget);
    });

    testWidgets('is never told a negative age', (tester) async {
      now = readAt.subtract(const Duration(minutes: 3));
      await pump(tester);

      expect(find.text('just now'), findsOneWidget);
    });
  });

  group('a healthy page', () {
    testWidgets('never creates the minute, and nothing ticks', (tester) async {
      final container = await pump(tester, underBand: false);

      expect(find.text('no age'), findsOneWidget);
      expect(container.exists(minuteNowProvider), isFalse);
      final before = builds;

      await tester.pump(const Duration(minutes: 5));

      expect(minuteTicks(), 0);
      expect(builds, before);
      expect(container.exists(minuteNowProvider), isFalse);
    });

    testWidgets('is told nothing and starts no timer', (tester) async {
      final container = await pump(tester);
      hostKey.currentState!.update(underBand: false);
      await settle(tester);
      final before = builds;

      expect(find.text('no age'), findsOneWidget);
      expect(container.exists(minuteNowProvider), isFalse);

      await tester.pump(const Duration(minutes: 5));

      expect(minuteTicks(), 0, reason: 'a healthy page has no clock');
      expect(builds, before, reason: 'and never rebuilds on one');
    });

    testWidgets('stops its timer the moment the band goes', (tester) async {
      final container = await pump(tester);
      expect(container.exists(minuteNowProvider), isTrue);

      hostKey.currentState!.update(underBand: false);
      await settle(tester);

      expect(container.exists(minuteNowProvider), isFalse);
      await tester.pump(const Duration(minutes: 5));
      expect(minuteTicks(), 0);
    });
  });

  group('a page that is not the one on screen', () {
    testWidgets('keeps no timer, and reads the time when it returns', (
      tester,
    ) async {
      final container = await pump(tester);
      hostKey.currentState!.update(branchActive: false);
      await settle(tester);

      expect(container.exists(minuteNowProvider), isFalse);
      expect(find.text('6\u00A0min ago'), findsOneWidget);

      now = now.add(const Duration(minutes: 4));
      await tester.pump(const Duration(minutes: 5));
      expect(minuteTicks(), 0, reason: 'a hidden page spends nothing');

      hostKey.currentState!.update(branchActive: true);
      await tester.pump();

      expect(find.text('10\u00A0min ago'), findsOneWidget);
    });
  });
}
