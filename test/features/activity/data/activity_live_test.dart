/// What Activity reads again while it is on screen, view by view: the
/// downloads and who is watching every fifteen seconds, the requests every
/// minute, History never on a clock, and what a pull drops.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/activity/data/activity_live.dart';
import 'package:cupola/features/activity/domain/activity_tab.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/presentation/stream_activity_provider.dart';

import '../../../test_helpers/settings_scope.dart';

const _noDecisions = (
  decisions: <DashboardDecision>[],
  coverage: SourceCoverage.none,
);

/// A tree whose reads are counted by name, every provider the poll and a
/// pull touch answering at once unless a test holds one open.
class _Rig {
  _Rig(this.container, this.tester);

  final ProviderContainer container;
  final WidgetTester tester;
  final reads = <String, int>{};
  late WidgetRef ref;

  /// Held open while it is set: a slow Seerr, say.
  Completer<List<SeerrRequest>>? heldRequests;

  /// What a name has been read since the last [forget].
  int operator [](String name) => reads[name] ?? 0;

  void forget() => reads.clear();

  void listenToEverything() {
    container
      ..listen(servicesQueueProvider, (_, _) {})
      ..listen(requestsProvider, (_, _) {})
      ..listen(pendingRequestCountProvider, (_, _) {})
      ..listen(servicesArrivalsProvider, (_, _) {})
      ..listen(servicesFailuresSinceProvider, (_, _) {})
      ..listen(servicesArrHistoryProvider, (_, _) {})
      ..listen(streamActivityProvider, (_, _) {})
      ..listen(dashboardDecisionSourceProvider(DecisionSource.queue), (_, _) {})
      ..listen(
        dashboardDecisionSourceProvider(DecisionSource.requests),
        (_, _) {},
      );
  }
}

Future<_Rig> _start(
  WidgetTester tester, {
  bool holdRequests = false,
  bool queueFails = false,
  Completer<void>? queueGate,
}) async {
  late final _Rig rig;
  final container = ProviderContainer(
    overrides: [
      ...await settingsScopeOverrides(
        configured: const [ServiceKey.radarr, ServiceKey.seerr],
      ),
      servicesQueueProvider.overrideWith((ref) async {
        rig.reads.update('queue', (n) => n + 1, ifAbsent: () => 1);
        await queueGate?.future;
        if (queueFails) throw Exception('down');
        return (
          items: const <ServiceQueueItem>[],
          coverage: SourceCoverage.none,
        );
      }),
      // The rows are what the page reads again; the list with titles derives
      // from them, here as it does in the app.
      requestsProvider.overrideWith(
        (ref) => ref.watch(requestRowsProvider.future),
      ),
      requestRowsProvider.overrideWith((ref) async {
        rig.reads.update('requests', (n) => n + 1, ifAbsent: () => 1);
        final held = rig.heldRequests;
        if (held != null && !held.isCompleted) return held.future;
        return const <SeerrRequest>[];
      }),
      pendingRequestCountProvider.overrideWith((ref) async {
        rig.reads.update('pending', (n) => n + 1, ifAbsent: () => 1);
        return (count: 0, floor: false);
      }),
      dashboardDecisionSourceProvider.overrideWith((ref, source) async {
        rig.reads.update(
          'decisions.${source.name}',
          (n) => n + 1,
          ifAbsent: () => 1,
        );
        return _noDecisions;
      }),
      servicesArrivalsProvider.overrideWith((ref) async {
        rig.reads.update('arrivals', (n) => n + 1, ifAbsent: () => 1);
        return (
          entries: const <ArrHistoryEntry>[],
          coverage: SourceCoverage.none,
        );
      }),
      servicesFailuresSinceProvider.overrideWith((ref) async {
        rig.reads.update('failures', (n) => n + 1, ifAbsent: () => 1);
        return (
          entries: const <ArrHistoryEntry>[],
          coverage: SourceCoverage.none,
        );
      }),
      servicesArrHistoryProvider.overrideWith((ref) async {
        rig.reads.update('history', (n) => n + 1, ifAbsent: () => 1);
        return (
          entries: const <ArrHistoryEntry>[],
          coverage: SourceCoverage.none,
        );
      }),
      streamActivityProvider.overrideWith((ref) async {
        rig.reads.update('sessions', (n) => n + 1, ifAbsent: () => 1);
        return const <StreamActivityRow>[];
      }),
    ],
  );
  rig = _Rig(container, tester);
  addTearDown(container.dispose);
  if (holdRequests) rig.heldRequests = Completer<List<SeerrRequest>>();

  // A widget to hold a `WidgetRef`, which a pull is written against.
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: Consumer(
        builder: (context, ref, _) {
          rig.ref = ref;
          return const SizedBox();
        },
      ),
    ),
  );
  rig.listenToEverything();
  await tester.pump();
  await tester.pump();
  rig.forget();
  return rig;
}

/// Lets the reads an invalidation started finish and be counted.
Future<void> _flush(WidgetTester tester) async {
  // Riverpod rebuilds what was dropped on a timer of its own, which only
  // elapsed time turns.
  await tester.pump(const Duration(milliseconds: 1));
  await tester.pump(const Duration(milliseconds: 1));
}

void main() {
  group('the poll', () {
    testWidgets('All: the queues and who is watching every fifteen seconds, '
        'the requests every minute', (tester) async {
      final rig = await _start(tester);
      final poll = rig.container.listen(
        activityLivePollProvider(ActivityTab.all),
        (_, _) {},
      );

      await tester.pump(activityLiveInterval - const Duration(seconds: 1));
      expect(rig['queue'], 0);
      await tester.pump(const Duration(seconds: 1));
      await _flush(tester);
      expect(rig['queue'], 1);
      expect(rig['decisions.queue'], 1);
      expect(rig['sessions'], 1);
      // The requests keep their own, slower clock.
      expect(rig['requests'], 0);

      await tester.pump(activityLiveInterval);
      await _flush(tester);
      expect(rig['queue'], 2);
      expect(rig['sessions'], 2);
      expect(rig['requests'], 0);

      // Sixty seconds in: the requests, once.
      await tester.pump(activityLiveInterval * 2);
      await _flush(tester);
      expect(rig['queue'], 4);
      expect(rig['requests'], 1);
      expect(rig['pending'], 1);
      expect(rig['decisions.requests'], 1);

      poll.close();
      await tester.pump(const Duration(milliseconds: 1));
    });

    testWidgets('Downloads: the queues, never who is watching, never the '
        'requests', (tester) async {
      final rig = await _start(tester);
      final poll = rig.container.listen(
        activityLivePollProvider(ActivityTab.downloads),
        (_, _) {},
      );

      await tester.pump(activityLiveInterval * 5);
      await _flush(tester);
      expect(rig['queue'], 5);
      expect(rig['decisions.queue'], 5);
      expect(rig['sessions'], 0);
      expect(rig['requests'], 0);
      expect(rig['pending'], 0);

      poll.close();
      await tester.pump(const Duration(milliseconds: 1));
    });

    testWidgets('Requests: the requests every minute and nothing of the '
        'queues', (tester) async {
      final rig = await _start(tester);
      final poll = rig.container.listen(
        activityLivePollProvider(ActivityTab.requests),
        (_, _) {},
      );

      await tester.pump(activityRequestsInterval - const Duration(seconds: 1));
      expect(rig['requests'], 0);
      await tester.pump(const Duration(seconds: 1));
      await _flush(tester);
      expect(rig['requests'], 1);
      expect(rig['pending'], 1);
      expect(rig['decisions.requests'], 1);

      await tester.pump(activityRequestsInterval * 2);
      await _flush(tester);
      expect(rig['requests'], 3);

      expect(rig['queue'], 0);
      expect(rig['decisions.queue'], 0);
      expect(rig['sessions'], 0);

      poll.close();
      await tester.pump(const Duration(milliseconds: 1));
    });

    testWidgets('History has no clock: a week does not change by the '
        'second', (tester) async {
      final rig = await _start(tester);
      final poll = rig.container.listen(
        activityLivePollProvider(ActivityTab.history),
        (_, _) {},
      );

      await tester.pump(const Duration(minutes: 10));
      await _flush(tester);
      expect(rig.reads, isEmpty);

      poll.close();
      await tester.pump(const Duration(milliseconds: 1));
    });

    testWidgets('the page leaves the screen: the timers go with it', (
      tester,
    ) async {
      final rig = await _start(tester);
      final poll = rig.container.listen(
        activityLivePollProvider(ActivityTab.all),
        (_, _) {},
      );
      await tester.pump(activityLiveInterval);
      await _flush(tester);
      expect(rig['queue'], 1);

      poll.close();
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(activityRequestsInterval * 3);
      await _flush(tester);
      expect(rig['queue'], 1);
      expect(rig['requests'], 0);
    });

    testWidgets('a slow queue is left to answer, and who is watching is '
        'still read', (tester) async {
      // Servers that take the connection and say nothing: the queue's read
      // outlasts the tick, and every tick used to throw it away (13/10).
      final gate = Completer<void>();
      final rig = await _start(tester, queueGate: gate);
      final poll = rig.container.listen(
        activityLivePollProvider(ActivityTab.all),
        (_, _) {},
      );
      await tester.pump(activityLiveInterval * 3);
      await _flush(tester);
      expect(rig['queue'], 0);
      expect(rig['decisions.queue'], 0);
      expect(rig['sessions'], 3);

      // It answers, and the next tick reads it again.
      gate.complete();
      await _flush(tester);
      await tester.pump(activityLiveInterval);
      await _flush(tester);
      expect(rig['queue'], 1);
      expect(rig['decisions.queue'], 1);

      poll.close();
      await tester.pump(const Duration(milliseconds: 1));
    });

    testWidgets('a slow Seerr is asked once, never a second time on top of '
        'the first', (tester) async {
      final rig = await _start(tester, holdRequests: true);
      // The first read of the list is still out.
      invalidateSeerrRequests(rig.container);
      await _flush(tester);
      expect(rig['requests'], 1);
      rig.forget();

      final poll = rig.container.listen(
        activityLivePollProvider(ActivityTab.requests),
        (_, _) {},
      );
      await tester.pump(activityRequestsInterval * 3);
      await _flush(tester);
      expect(rig['requests'], 0);

      // It answers, and the next minute asks again.
      rig.heldRequests!.complete(const <SeerrRequest>[]);
      await _flush(tester);
      await tester.pump(activityRequestsInterval);
      await _flush(tester);
      expect(rig['requests'], 1);

      poll.close();
      await tester.pump(const Duration(milliseconds: 1));
    });
  });

  group('what a pull drops', () {
    testWidgets('All: everything the page draws, but the week\'s failures', (
      tester,
    ) async {
      final rig = await _start(tester);

      invalidateActivity(rig.ref, ActivityTab.all);
      await _flush(tester);

      expect(rig['queue'], 1);
      expect(rig['decisions.queue'], 1);
      expect(rig['decisions.requests'], 1);
      expect(rig['sessions'], 1);
      expect(rig['requests'], 1);
      expect(rig['arrivals'], 1);
      expect(rig['history'], 1);
      expect(rig['failures'], 0);
    });

    testWidgets('Downloads: the queues and what finished, not the requests '
        'nor who is watching', (tester) async {
      final rig = await _start(tester);

      invalidateActivity(rig.ref, ActivityTab.downloads);
      await _flush(tester);

      expect(rig['queue'], 1);
      expect(rig['arrivals'], 1);
      expect(rig['history'], 1);
      expect(rig['requests'], 0);
      expect(rig['sessions'], 0);
      expect(rig['failures'], 0);
    });

    testWidgets('Requests: the list alone', (tester) async {
      final rig = await _start(tester);

      invalidateActivity(rig.ref, ActivityTab.requests);
      await _flush(tester);

      expect(rig['requests'], 1);
      expect(rig['queue'], 0);
      expect(rig['arrivals'], 0);
      expect(rig['failures'], 0);
      expect(rig['sessions'], 0);
    });

    testWidgets('History: the week\'s two halves, nothing else', (
      tester,
    ) async {
      final rig = await _start(tester);

      invalidateActivity(rig.ref, ActivityTab.history);
      await _flush(tester);

      expect(rig['arrivals'], 1);
      expect(rig['failures'], 1);
      expect(rig['queue'], 0);
      expect(rig['requests'], 0);
      expect(rig['history'], 0);
    });

    testWidgets('the spinner is held until what the view draws is back', (
      tester,
    ) async {
      final gate = Completer<void>();
      final rig = await _start(tester, queueGate: gate);

      var done = false;
      unawaited(
        refreshActivity(
          rig.ref,
          ActivityTab.downloads,
        ).then((_) => done = true),
      );
      await _flush(tester);
      expect(rig['queue'], 1);
      expect(done, isFalse);

      gate.complete();
      await _flush(tester);
      expect(done, isTrue);
    });

    testWidgets('a failure does not break the pull: each section paints '
        'its own', (tester) async {
      final rig = await _start(tester, queueFails: true);

      var done = false;
      Object? failure;
      unawaited(
        refreshActivity(
          rig.ref,
          ActivityTab.downloads,
        ).then((_) => done = true, onError: (Object error) => failure = error),
      );
      // A read that throws is asked again, with a growing wait, before it is
      // called failed: fake time passes it.
      for (var second = 0; second < 90; second += 2) {
        await tester.pump(const Duration(seconds: 2));
      }

      expect(failure, isNull);
      expect(done, isTrue);
      expect(rig['queue'], greaterThan(1));
    });
  });
}
