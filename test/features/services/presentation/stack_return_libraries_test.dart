/// A silent return to Stack re-reads what moves (queues, sessions, probes) and
/// leaves the arrs' whole libraries alone until they are fifteen minutes old.
/// Seen in review: every return after two minutes downloaded Radarr's,
/// Sonarr's and Lidarr's libraries again, megabytes for three counts.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/lifecycle/page_activity.dart';
import 'package:cupola/core/lifecycle/poll_clock.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/services/presentation/stack_screen.dart';

import '../../../test_helpers/profiles/profiles.dart';

class _Host extends StatefulWidget {
  const _Host();

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  bool active = true;

  void setActive(bool value) => setState(() => active = value);

  @override
  Widget build(BuildContext context) => BranchActivityScope(
    isActive: active,
    branchIndex: 0,
    child: const StackScreen(),
  );
}

void main() {
  testWidgets('P1: a return after three minutes re-reads the queue and not '
      'the library; one after sixteen reads both', (tester) async {
    var now = DateTime(2026, 10, 19, 12);
    final clock = PollClock()..now = () => now;
    final harness = await ProfileHarness.start(
      Profiles.p1,
      overrides: [pollClockProvider.overrideWithValue(clock)],
    );
    var movies = 0;
    var queues = 0;
    harness.network.on(WorldIds.radarr, 'GET', '/api/v3/movie', (_) {
      movies++;
      return NetworkReply.json(<Object?>[]);
    });
    harness.network.on(WorldIds.radarr, 'GET', '/api/v3/queue', (_) {
      queues++;
      return NetworkReply.json({'totalRecords': 0, 'records': <Object?>[]});
    });
    harness.network.followFakeTime(tester.binding);
    await tester.binding.setSurfaceSize(const Size(430, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: harness.overrides,
        child: MaterialApp(theme: AppTheme.darkTheme(), home: const _Host()),
      ),
    );
    await harness.settle(tester);
    final host = tester.state<_HostState>(find.byType(_Host));
    expect(movies, greaterThan(0), reason: 'the stack counts the library');
    expect(queues, greaterThan(0));

    Future<void> returnAfter(Duration away) async {
      host.setActive(false);
      await harness.settle(tester);
      now = now.add(away);
      host.setActive(true);
      // The refresh runs after the frame and its answers arrive over real
      // async, past the point where `settle` sees no frame scheduled.
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    var moviesBefore = movies;
    var queuesBefore = queues;
    await returnAfter(const Duration(minutes: 3));
    expect(queues, greaterThan(queuesBefore), reason: 'the queue moves');
    expect(movies, moviesBefore, reason: 'three counts are not worth MBs');

    moviesBefore = movies;
    queuesBefore = queues;
    await returnAfter(const Duration(minutes: 16));
    expect(queues, greaterThan(queuesBefore));
    expect(movies, greaterThan(moviesBefore));

    await harness.unmount(tester);
  });
}
