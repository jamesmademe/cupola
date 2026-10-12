/// A day is a day, also on the two nights a year the clocks change.
///
/// Every sentence that says which day a moment was on (`Yesterday`, `tomorrow
/// 09:10`, the weekday within the week) counts calendar days. On the night the
/// clocks go forward a day is 23 h long, and counting the hours between two
/// local midnights called a day apart `0` days: tomorrow read `Today`.
///
/// The change is found in this machine's own zone (`test_helpers/clock_change`),
/// so these tests skip in a zone that has none; run them with
/// `TZ=Europe/Rome`.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/utils/date_format.dart';
import 'package:cupola/features/activity/domain/activity_history.dart';
import 'package:cupola/features/activity/domain/activity_readout.dart';
import 'package:cupola/features/home/domain/downloads.dart';
import 'package:cupola/features/media/domain/media_series.dart';
import 'package:cupola/features/media/presentation/media_series_sections.dart';
import 'package:cupola/features/requests/domain/my_requests.dart';
import 'package:cupola/features/services/presentation/dashboard_sections.dart';

import '../test_helpers/clock_change.dart';

void main() {
  final spring = springForwardDay();
  final fall = fallBackDay();
  final skipSpring = spring == null ? noClockChange : null;
  final skipFall = fall == null ? noClockChange : null;

  group('the night the clocks go forward (a 23 h day)', () {
    // `day` is the 23 h day; `next` the day after it, at noon.
    final day = spring ?? DateTime(2026, 3, 29);
    final next = dayAfter(day, 1, hour: 12);

    test('is built from the machine\'s own zone', () {
      expect(
        dayAfter(day, 1).difference(day),
        const Duration(hours: 23),
        reason: 'the day the helper found is 23 h long',
      );
    }, skip: skipSpring);

    test('calendarDaysBetween counts the days, not the hours', () {
      expect(calendarDaysBetween(day, dayAfter(day, 1)), 1);
      expect(calendarDaysBetween(dayAfter(day, -1), dayAfter(day, 1)), 2);
      expect(calendarDaysBetween(day, dayAfter(day, 7)), 7);
      expect(calendarDaysBetween(dayAfter(day, 1), day), -1);
    }, skip: skipSpring);

    test('formatDayLabel says Tomorrow for the next day', () {
      final now = dayAfter(day, 0, hour: 12);
      expect(formatDayLabel(dayAfter(day, 0, hour: 22), now), 'Today');
      expect(formatDayLabel(dayAfter(day, 1, hour: 9), now), 'Tomorrow');
      expect(
        formatDayLabel(dayAfter(day, 2, hour: 9), now),
        '${shortWeekdayName(dayAfter(day, 2))} ${dayAfter(day, 2).day}',
      );
    }, skip: skipSpring);

    test('History names the day before Yesterday', () {
      expect(activityDayLabel(day, now: next), 'Yesterday');
      expect(activityDayLabel(dayAfter(day, 1), now: next), 'Today');
    }, skip: skipSpring);

    test(
      'the last download says yesterday, and the week ends on the 7th',
      () {
        final at = dayAfter(day, 0, hour: 18);
        expect(
          lastDownloadFinished(at, now: next),
          'Last download finished yesterday 18:00',
        );
        expect(
          lastFinishedLine(at, now: next),
          'The last download finished yesterday at 18:00.',
        );
        final week = dayAfter(day, -6, hour: 18);
        expect(lastDownloadFinished(week, now: next), isNull);
        expect(lastFinishedLine(week, now: next), isNull);
      },
      skip: skipSpring,
    );

    test('a request says yesterday for the day before', () {
      final at = dayAfter(day, 0, hour: 8);
      final now = dayAfter(day, 1, hour: 20);
      expect(askedAgo(at, now: now), 'yesterday');
      expect(dayWords(at, now: now), 'yesterday');
      expect(sinceWords(at, now: now), 'yesterday');
    }, skip: skipSpring);

    test('the day words say yesterday for the day before', () {
      final at = dayAfter(day, 0, hour: 8);
      final now = dayAfter(day, 1, hour: 20);
      expect(formatPastDay(at, now: now), 'yesterday');
      expect(formatPastDayOn(at, now: now), 'yesterday');
      expect(formatDayWords(at, now: now), 'yesterday');
      // And the week still ends on the 7th day, not a day early.
      expect(
        formatPastDay(dayAfter(day, -6, hour: 8), now: now),
        formatShortDay(dayAfter(day, -6, hour: 8), now: now),
      );
    }, skip: skipSpring);

    test('a download that ends tomorrow says tomorrow', () {
      expect(
        aroundWords(
          dayAfter(day, 1, hour: 9, minute: 10),
          now: dayAfter(day, 0, hour: 12),
        ),
        'tomorrow 09:10',
      );
    }, skip: skipSpring);

    test(
      'the next episode airs Tomorrow, and a week on names its date',
      () {
        MediaNextAiring airing(DateTime at) =>
            MediaNextAiring(season: 1, number: 2, at: at, timed: false);
        final now = dayAfter(day, 0, hour: 12);
        expect(mediaAiringDay(airing(dayAfter(day, 1)), now), 'Tomorrow');
        expect(
          mediaAiringDay(airing(dayAfter(day, 7)), now),
          formatDayMonth(dayAfter(day, 7), now: now),
        );
      },
      skip: skipSpring,
    );
  });

  group('the night the clocks go back (a 25 h day)', () {
    final day = fall ?? DateTime(2026, 10, 25);

    test('is built from the machine\'s own zone', () {
      expect(
        dayAfter(day, 1).difference(day),
        const Duration(hours: 25),
        reason: 'the day the helper found is 25 h long',
      );
    }, skip: skipFall);

    test('calendarDaysBetween still counts one day for it', () {
      expect(calendarDaysBetween(day, dayAfter(day, 1)), 1);
      expect(calendarDaysBetween(dayAfter(day, -1), dayAfter(day, 1)), 2);
      expect(calendarDaysBetween(day, dayAfter(day, 7)), 7);
    }, skip: skipFall);

    test('formatDayLabel and History keep their words', () {
      final now = dayAfter(day, 0, hour: 12);
      expect(formatDayLabel(dayAfter(day, 1, hour: 9), now), 'Tomorrow');
      expect(
        activityDayLabel(day, now: dayAfter(day, 1, hour: 12)),
        'Yesterday',
      );
    }, skip: skipFall);
  });
}
