import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/lifecycle/poll_clock.dart';
import 'package:cupola/core/status/read_age.dart';
import 'package:cupola/core/status/read_clock.dart';
import 'package:cupola/core/widgets/fault_band.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import 'profiles/profiles.dart';

/// One download client's Queue tab, as the stale-band scenarios need to know
/// it: where it is configured, what it draws, and which request is its queue.
class QueueStaleCase {
  const QueueStaleCase({
    required this.service,
    required this.profile,
    required this.connectionId,
    required this.screen,
    required this.isQueueRead,
    this.sharesReadInFlight = false,
  });

  final ServiceKey service;
  final ConfigProfile profile;

  /// The connection the page reads: the profile's id for it.
  final String connectionId;

  /// The page, as the tab hosts it.
  final Widget Function() screen;

  /// Whether [request] is the read the page's rows come from, and not the
  /// probe, a count or a login: the one request a scenario holds back.
  final bool Function(NetworkRequest request) isQueueRead;

  /// Whether a read asked for while one is in flight joins it instead of
  /// asking the server again (qBittorrent's incremental copy does, so two
  /// reads never apply the same changes twice). A Refresh over a read that is
  /// stuck then waits for that read's own deadline.
  final bool sharesReadInFlight;
}

/// Pumps [c]'s page under its profile (or [profile]) with every clock on the
/// test's own, and a first read already in. The scene's `hung` is the switch
/// that makes the queue's own route take requests and never answer.
///
/// End the test with [QueueStaleScene.finish].
Future<QueueStaleScene> openQueueStaleScene(
  WidgetTester tester,
  QueueStaleCase c, {
  ConfigProfile? profile,
}) async {
  final now = tester.binding.clock.now;
  final readClock = ReadClock(now: now);
  final readKey = queueReadKey(c.service, c.connectionId);
  final scene = QueueStaleScene(tester, readClock, c, readKey);
  scene.harness = await pumpWithProfile(
    tester,
    profile ?? c.profile,
    child: c.screen(),
    overrides: [
      readClockProvider.overrideWithValue(readClock),
      pollClockProvider.overrideWithValue(PollClock()..now = now),
    ],
  );
  scene.harness.network.on(c.connectionId, 'GET', RegExp('.*'), scene.route);
  scene.harness.network.on(c.connectionId, 'POST', RegExp('.*'), scene.route);
  // The first read, and a few polls over it.
  await scene.elapse(const Duration(seconds: 4));
  expect(
    readClock.at(readKey),
    isNotNull,
    reason: '${c.service.title} is answering before the scenario starts',
  );
  return scene;
}

/// The scenarios every download client's Queue tab must pass when its queue
/// stops coming back while the connection itself answers: a request nobody
/// answers (`NetworkReply.hang`) on the queue's own route.
///
/// Through the profile world and the widget test's own clock, so what it asks
/// of the app is what the app does: the real polls, the real transport
/// deadline (a hung request fails after fifteen seconds), the real band.
void defineQueueStaleScenarios(QueueStaleCase c) {
  final title = c.service.title;
  final readKey = queueReadKey(c.service, c.connectionId);

  Future<QueueStaleScene> open(WidgetTester tester, ConfigProfile profile) =>
      openQueueStaleScene(tester, c, profile: profile);

  group('$title queue that stops coming back', () {
    testWidgets('says how old it is once it has been silent past the '
        'threshold, and its rows say so too', (tester) async {
      final scene = await open(tester, c.profile);
      expect(scene.bands, findsNothing, reason: 'healthy: no band');
      expect(scene.rowsSayAge, findsNothing, reason: 'healthy: time left');

      scene.hung = true;
      await scene.elapse(const Duration(seconds: 4));
      final lastRead = scene.readClock.at(readKey)!;

      await scene.elapseTo(lastRead.add(const Duration(seconds: 15)));

      expect(scene.bands, findsOneWidget);
      expect(
        find.textContaining(
          'These figures have stopped updating. '
          "$title's queue has not returned.",
        ),
        findsOneWidget,
      );
      expect(find.text('Refresh'), findsOneWidget);
      expect(scene.rowsSayAge, findsWidgets, reason: 'rows trade time left');

      await scene.finish();
    });

    testWidgets('says nothing before the threshold', (tester) async {
      final scene = await open(tester, c.profile);
      scene.hung = true;
      await scene.elapse(const Duration(seconds: 4));
      final lastRead = scene.readClock.at(readKey)!;

      await scene.elapseTo(
        lastRead.add(queueStaleAfter - const Duration(seconds: 1)),
      );

      expect(scene.bands, findsNothing);
      expect(scene.rowsSayAge, findsNothing);

      await scene.finish();
    });

    testWidgets('leaves the page to the fault band once the transport gives '
        'up on the read: never both', (tester) async {
      final scene = await open(tester, c.profile);
      scene.hung = true;
      await scene.elapse(const Duration(seconds: 4));
      final lastRead = scene.readClock.at(readKey)!;

      await scene.elapseTo(lastRead.add(const Duration(seconds: 15)));
      expect(find.textContaining('These figures'), findsOneWidget);

      await scene.elapseTo(lastRead.add(const Duration(seconds: 40)));

      expect(scene.bands, findsOneWidget);
      expect(find.textContaining('These figures'), findsNothing);

      await scene.finish();
    });

    testWidgets('shows only the fault band when the connection stops '
        'answering', (tester) async {
      final scene = await open(tester, c.profile);

      scene.harness.network.behave(
        c.connectionId,
        ConnectionBehaviour.didNotAnswer,
      );
      final lastRead = scene.readClock.at(readKey)!;
      await scene.elapseTo(lastRead.add(const Duration(seconds: 45)));

      expect(scene.bands, findsOneWidget);
      expect(find.textContaining('did not answer'), findsOneWidget);
      expect(find.textContaining('These figures'), findsNothing);
      expect(scene.rowsSayAge, findsWidgets, reason: 'under the fault band');

      await scene.finish();
    });

    testWidgets(
      c.sharesReadInFlight
          ? "the band's Refresh joins the read in flight"
          : "the band's Refresh asks the queue again",
      (tester) async {
        final scene = await open(tester, c.profile);
        scene.hung = true;
        await scene.elapse(const Duration(seconds: 4));
        final lastRead = scene.readClock.at(readKey)!;
        await scene.elapseTo(lastRead.add(const Duration(seconds: 15)));
        expect(find.text('Refresh'), findsOneWidget);

        // The server answers again, but the read in flight holds the poll back
        // (it is not asked twice): only a tap can ask now.
        scene.hung = false;
        final before = scene.queueReads;
        await scene.elapse(const Duration(seconds: 1));
        expect(scene.queueReads, before, reason: 'the poll is held back');

        await tester.tap(find.text('Refresh'));
        await scene.elapse(const Duration(milliseconds: 200));

        if (c.sharesReadInFlight) {
          // The read stuck in flight is the one the page is waiting for: it
          // answers when the transport's deadline fails it, and the band stays
          // until then.
          expect(scene.queueReads, before);
          expect(scene.bands, findsOneWidget);
        } else {
          expect(scene.queueReads, greaterThan(before));
          expect(scene.bands, findsNothing, reason: 'the answer took it down');
          expect(scene.rowsSayAge, findsNothing);
        }

        await scene.finish();
      },
    );

    testWidgets('does not say it stopped for a server that answers slowly: '
        'four seconds a read, every three', (tester) async {
      final scene = await open(
        tester,
        c.profile.withLatency(c.connectionId, const Duration(seconds: 4)),
      );

      // The stale band only. A connection this slow can fail its own probe
      // (its deadline is shorter than the requests it makes in turn), and
      // that fault band is the probe's to say.
      for (var i = 0; i < 120; i++) {
        await scene.elapse(const Duration(seconds: 1));
        expect(
          find.textContaining('These figures'),
          findsNothing,
          reason: 'second $i of a slow server: ${scene.bandWords}',
        );
      }

      await scene.finish();
    });
  });
}

/// A page under a profile, and what the scenarios do to it.
class QueueStaleScene {
  QueueStaleScene(this.tester, this.readClock, this.c, this.readKey);

  final WidgetTester tester;
  final ReadClock readClock;
  final QueueStaleCase c;
  final String readKey;
  late final ProfileHarness harness;

  /// While true, the queue's own route takes requests and never answers.
  bool hung = false;

  NetworkReply? route(NetworkRequest request) =>
      hung && c.isQueueRead(request) ? const NetworkReply.hang() : null;

  Finder get bands => find.byType(FaultBand);

  /// What the bands on the page say, for a failure to name.
  String get bandWords => tester
      .widgetList<FaultBand>(bands)
      .map((band) => band.message)
      .join(' | ');

  /// A row that gave up its time left for the age of its figures.
  Finder get rowsSayAge => find.textContaining('as of ');

  /// How many times the queue was asked for, hung requests included.
  int get queueReads => harness.network.requests.where(c.isQueueRead).length;

  /// One second at a time: a request crosses Dio's zero-delay hops and the
  /// poll timers fire in their order, as they would live.
  Future<void> elapse(Duration duration) async {
    var left = duration;
    while (left > Duration.zero) {
      final step = left < const Duration(seconds: 1)
          ? left
          : const Duration(seconds: 1);
      await tester.pump(step);
      left -= step;
    }
  }

  Future<void> elapseTo(DateTime moment) async {
    final now = tester.binding.clock.now();
    if (moment.isAfter(now)) await elapse(moment.difference(now));
  }

  /// Unmounts, then lets a request still in flight meet its deadline: its
  /// timer would otherwise fail the test for being pending.
  Future<void> finish() async {
    hung = false;
    await harness.unmount(tester);
    await elapse(const Duration(seconds: 20));
  }
}
