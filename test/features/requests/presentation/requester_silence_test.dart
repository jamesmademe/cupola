/// The requester's one line says since when the server stopped answering,
/// from what the probe recorded, and no time when nothing recorded one.
///
/// It used to say the time the line first appeared, which is not the time
/// anything stopped answering: a person who opened the page at 21:30 on a
/// server that had been dark since 20:00 read `since 21:30`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/status/read_clock.dart';
import 'package:cupola/core/status/silence_clock.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/widgets/brief_failure_line.dart';
import 'package:cupola/features/discover/presentation/discover_calendar_band.dart';
import 'package:cupola/features/discover/presentation/library_calendar_provider.dart'
    show calendarClockProvider;
import 'package:cupola/features/requests/presentation/requests_screen.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/profiles/profiles.dart';

void main() {
  final silent = Profiles.p2.withBehaviour(
    WorldIds.seerr,
    ConnectionBehaviour.didNotAnswer,
  );
  late DateTime now;

  setUp(() => now = DateTime(2026, 10, 12, 20, 41));

  Future<ProfileHarness> pump(
    WidgetTester tester, {
    List<Override> overrides = const [],
  }) => pumpWithProfile(
    tester,
    silent,
    child: const RequestsScreen(),
    now: now,
    overrides: [
      calendarClockProvider.overrideWithValue(() => now),
      readClockProvider.overrideWithValue(ReadClock(now: () => now)),
      ...overrides,
    ],
    surfaceSize: const Size(390, 3200),
  );

  group('the line', () {
    testWidgets('says the time the probe first did not get an answer', (
      tester,
    ) async {
      final harness = await pump(tester);

      expect(find.text("Can't reach the server since 20:41."), findsOne);

      await harness.unmount(tester);
    });

    testWidgets('says the recorded time, not the time it appeared', (
      tester,
    ) async {
      // A server that has been dark since 20:00, and a page opened at 20:41.
      now = DateTime(2026, 10, 12, 20, 41);
      final recorded = SilenceClock(now: () => now)
        ..noteSilent(
          silenceKey(ServiceKey.seerr, WorldIds.seerr),
          DateTime(2026, 10, 12, 20, 0),
        );
      final harness = await pump(
        tester,
        overrides: [silenceClockProvider.overrideWithValue(recorded)],
      );

      expect(find.text("Can't reach the server since 20:00."), findsOne);
      expect(find.textContaining('20:41'), findsNothing);

      await harness.unmount(tester);
    });

    testWidgets('keeps that time when Retry fails again', (tester) async {
      final harness = await pump(tester);
      expect(find.text("Can't reach the server since 20:41."), findsOne);

      now = DateTime(2026, 10, 12, 21, 30);
      await tester.tap(find.text('Retry'));
      await harness.settle(tester);

      expect(find.text("Can't reach the server since 20:41."), findsOne);

      await harness.unmount(tester);
    });

    testWidgets('says no time when nothing recorded a silence', (tester) async {
      // A cold start, or a probe that has not come back: the server did not
      // answer this read, and the app has not seen it silent.
      final harness = await pump(
        tester,
        overrides: [
          instanceSummaryProvider.overrideWith(
            (ref, key) async => ServiceSummary(
              service: key.service,
              status: ServiceSummaryStatus.online,
              host: 'seerr.example.com',
              version: '3.0.0',
            ),
          ),
        ],
      );

      expect(find.text("Can't reach the server."), findsOne);
      expect(find.textContaining('since'), findsNothing);
      expect(find.text('Retry'), findsOne);

      await harness.unmount(tester);
    });
  });

  group('the calendar band', () {
    Future<ProfileHarness> pumpBand(
      WidgetTester tester, {
      List<Override> overrides = const [],
    }) => pumpWithProfile(
      tester,
      silent,
      child: const DiscoverCalendarBand(),
      now: now,
      overrides: [
        calendarClockProvider.overrideWithValue(() => now),
        readClockProvider.overrideWithValue(ReadClock(now: () => now)),
        ...overrides,
      ],
    );

    testWidgets('says the recorded time, in her words', (tester) async {
      final recorded = SilenceClock(now: () => now)
        ..noteSilent(
          silenceKey(ServiceKey.seerr, WorldIds.seerr),
          DateTime(2026, 10, 12, 20, 0),
        );
      final harness = await pumpBand(
        tester,
        overrides: [silenceClockProvider.overrideWithValue(recorded)],
      );

      expect(
        find.textContaining("Can't reach the server since 20:00"),
        findsOne,
      );
      expect(find.textContaining('20:41'), findsNothing);

      await harness.unmount(tester);
    });

    testWidgets('says no time when nothing recorded a silence', (tester) async {
      final harness = await pumpBand(
        tester,
        overrides: [
          instanceSummaryProvider.overrideWith(
            (ref, key) async => ServiceSummary(
              service: key.service,
              status: ServiceSummaryStatus.online,
              host: 'seerr.example.com',
              version: '3.0.0',
            ),
          ),
        ],
      );

      expect(find.textContaining("Can't reach the server"), findsOne);
      expect(find.textContaining('since'), findsNothing);

      await harness.unmount(tester);
    });
  });

  group('the words', () {
    test('with a time say since when', () {
      expect(
        BriefFailureLine.wordsFor(
          ServiceFailureReason.unreachable,
          since: DateTime(2026, 10, 12, 20, 41),
        ).headline,
        "Can't reach the server since 20:41",
      );
    });

    test('without a time say only that the server cannot be reached', () {
      final words = BriefFailureLine.wordsFor(ServiceFailureReason.unreachable);

      expect(words.headline, "Can't reach the server");
      expect(words.headline, Lexicon.cantReach('the server'));
      expect(words.sentence, isNull);
    });

    test('name the player she watches with, with or without a time', () {
      expect(
        BriefFailureLine.wordsFor(
          ServiceFailureReason.unreachable,
          service: ServiceKey.jellyfin,
        ).headline,
        "Can't reach Jellyfin",
      );
      expect(
        BriefFailureLine.wordsFor(
          ServiceFailureReason.unreachable,
          service: ServiceKey.plex,
          since: DateTime(2026, 10, 12, 20, 41),
        ).headline,
        "Can't reach Plex since 20:41",
      );
    });

    test('never name another service, with or without a time', () {
      expect(
        BriefFailureLine.wordsFor(
          ServiceFailureReason.unreachable,
          service: ServiceKey.radarr,
        ).headline,
        isNot(contains('Radarr')),
      );
    });

    test('of a session that ended carry no time at all', () {
      final words = BriefFailureLine.wordsFor(
        ServiceFailureReason.sessionEnded,
        since: DateTime(2026, 10, 12, 20, 41),
      );

      expect(words.headline, Lexicon.youWereSignedOut);
      expect(words.sentence, Lexicon.signInToKeepAsking);
    });
  });
}
