import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/utils/date_format.dart';

void main() {
  group('formatMediumDate', () {
    test('is the detail pages one date voice', () {
      // The drift this ends: Radarr printed `2019-05-22` in its Details grid
      // while Seerr printed `May 22, 2019` for the same film, two taps away.
      expect(formatMediumDate('2019-05-22'), 'May 22, 2019');
      expect(formatIsoDate('2019-05-22'), '2019-05-22');
    });

    test('does not pad a single-digit day', () {
      expect(formatMediumDate('1965-06-09'), 'Jun 9, 1965');
    });

    test('ignores a time component', () {
      expect(formatMediumDate('2026-07-17T20:00:00.000Z'), 'Jul 17, 2026');
    });

    test('covers both ends of the month table', () {
      expect(formatMediumDate('2020-01-31'), 'Jan 31, 2020');
      expect(formatMediumDate('2020-12-01'), 'Dec 1, 2020');
    });

    test('returns what the service said when it cannot be parsed', () {
      // A service that answers with something unexpected still shows its answer
      // rather than an empty cell.
      expect(formatMediumDate('not a date'), 'not a date');
      expect(formatMediumDate('2019-05'), '2019-05');
    });

    test('leaves an empty value empty', () {
      expect(formatMediumDate(''), '');
      expect(formatMediumDate('   '), '');
    });
  });

  group('formatShortDate', () {
    // 2026-10-02 is a Friday; 29 Sep 2026 is the Tuesday the brand book draws.
    final now = DateTime(2026, 10, 2);

    test('is the brand book\'s date: weekday, day, month', () {
      expect(formatShortDate('2026-09-29', now: now), 'Tue 29 Sep');
    });

    test('names every weekday and does not pad a single-digit day', () {
      expect(
        [
          for (final day in const [
            '2026-09-28',
            '2026-09-29',
            '2026-09-30',
            '2026-10-01',
            '2026-10-02',
            '2026-10-03',
            '2026-10-04',
          ])
            formatShortDate(day, now: now),
        ],
        [
          'Mon 28 Sep',
          'Tue 29 Sep',
          'Wed 30 Sep',
          'Thu 1 Oct',
          'Fri 2 Oct',
          'Sat 3 Oct',
          'Sun 4 Oct',
        ],
      );
    });

    test('carries the year only when it is another year', () {
      expect(formatShortDate('2025-09-29', now: now), 'Mon 29 Sep 2025');
      expect(formatShortDate('2027-01-01', now: now), 'Fri 1 Jan 2027');
      expect(formatShortDate('2026-01-01', now: now), 'Thu 1 Jan');
    });

    test('reads the day the string states, whatever the clock or the zone', () {
      expect(formatShortDate('2026-09-29T00:00:00Z', now: now), 'Tue 29 Sep');
      expect(formatShortDate('2026-09-29T23:30:00Z', now: now), 'Tue 29 Sep');
      expect(formatShortDate('2026-09-29T08:00:00', now: now), 'Tue 29 Sep');
    });

    test('is never the sortable form', () {
      expect(formatShortDate('2026-09-29', now: now), isNot(contains('2026-')));
    });

    test('returns what the service said when it cannot be parsed', () {
      expect(formatShortDate('not a date', now: now), 'not a date');
      expect(formatShortDate('2019-05', now: now), '2019-05');
      expect(formatShortDate('', now: now), '');
    });
  });

  group('formatMediumDateOrNull', () {
    test('speaks the same prose as formatMediumDate', () {
      // The whole point of the nullable variant is that a child row and the
      // Details grid above it cannot disagree about what a date looks like.
      expect(formatMediumDateOrNull('2026-07-17'), 'Jul 17, 2026');
      expect(
        formatMediumDateOrNull('2026-07-17T20:00:00Z'),
        formatMediumDate('2026-07-17T20:00:00Z'),
      );
    });

    test('drops a fact it cannot read instead of echoing raw JSON', () {
      // A dot-separated facts line has no cell to leave blank, so an unreadable
      // date has to leave the line entirely.
      expect(formatMediumDateOrNull('not a date'), isNull);
      expect(formatMediumDateOrNull('2019-05'), isNull);
    });

    test('treats absent and blank alike', () {
      expect(formatMediumDateOrNull(null), isNull);
      expect(formatMediumDateOrNull(''), isNull);
      expect(formatMediumDateOrNull('   '), isNull);
    });
  });

  group('formatIsoDate', () {
    test('is the sortable form, padded to a fixed width', () {
      expect(formatIsoDate('2026-09-02'), '2026-09-02');
      expect(formatIsoDate('2026-09-02T08:12:00'), '2026-09-02');
    });

    test('returns what the service said when it cannot be parsed', () {
      expect(formatIsoDate('not a date'), 'not a date');
      expect(formatIsoDate(''), '');
    });
  });

  group('formatDayMonth', () {
    final now = DateTime(2026, 10, 2);

    test('is the day and the month, with no weekday and no padding', () {
      expect(formatDayMonth(DateTime(2026, 9, 12), now: now), '12 Sep');
      expect(formatDayMonth(DateTime(2026, 1, 3), now: now), '3 Jan');
    });

    test('carries the year only when it is another year', () {
      expect(formatDayMonth(DateTime(2025, 9, 12), now: now), '12 Sep 2025');
      expect(formatDayMonth(DateTime(2027, 1, 3), now: now), '3 Jan 2027');
    });
  });

  group('weekdayName and monthName', () {
    test('spell the weekday and the month in full', () {
      final day = DateTime(2026, 10, 8);
      expect(weekdayName(day), 'Thursday');
      expect(monthName(day), 'October');
    });

    test('cover both ends of each table', () {
      expect(weekdayName(DateTime(2026, 10, 5)), 'Monday');
      expect(weekdayName(DateTime(2026, 10, 11)), 'Sunday');
      expect(monthName(DateTime(2026, 1, 1)), 'January');
      expect(monthName(DateTime(2026, 12, 1)), 'December');
    });
  });

  group('formatClockTime', () {
    test('is 24 h and zero-padded, so a column stays a column', () {
      expect(formatClockTime(DateTime(2026, 9, 2, 9, 5)), '09:05');
      expect(formatClockTime(DateTime(2026, 9, 2, 20, 41)), '20:41');
      expect(formatClockTime(DateTime(2026, 9, 2)), '00:00');
      expect(formatClockTime(DateTime(2026, 9, 2, 23, 59)), '23:59');
    });

    test('reads this device\'s clock, whatever zone the value carries', () {
      final utc = DateTime.utc(2026, 9, 2, 9, 5);
      expect(formatClockTime(utc), formatClockTime(utc.toLocal()));
    });
  });

  group('the short names', () {
    test('are the first three letters of the full ones, Monday first', () {
      expect(shortWeekdayNames, [
        'Mon',
        'Tue',
        'Wed',
        'Thu',
        'Fri',
        'Sat',
        'Sun',
      ]);
      expect(shortWeekdayName(DateTime(2026, 10, 8)), 'Thu');
    });

    test('name every month and never pad the day', () {
      expect(
        [
          for (var month = 1; month <= 12; month++)
            formatDayMonthNoYear(DateTime(2026, month, 3)),
        ],
        [
          '3 Jan',
          '3 Feb',
          '3 Mar',
          '3 Apr',
          '3 May',
          '3 Jun',
          '3 Jul',
          '3 Aug',
          '3 Sep',
          '3 Oct',
          '3 Nov',
          '3 Dec',
        ],
      );
    });

    test('never carry a year when they say they do not', () {
      expect(formatDayMonthNoYear(DateTime(2031, 10, 14)), '14 Oct');
      expect(formatWeekdayDayMonth(DateTime(2026, 10, 21)), 'Wed 21 Oct');
      expect(formatWeekdayDayMonth(DateTime(2027, 10, 21)), 'Thu 21 Oct');
    });
  });

  group('formatShortDay', () {
    final now = DateTime(2026, 10, 2);

    test('says what formatShortDate says of the same day', () {
      expect(formatShortDay(DateTime(2026, 9, 29), now: now), 'Tue 29 Sep');
      expect(
        formatShortDay(DateTime(2025, 9, 29), now: now),
        'Mon 29 Sep 2025',
      );
      expect(
        formatShortDay(DateTime(2026, 9, 29), now: now),
        formatShortDate('2026-09-29', now: now),
      );
    });

    test('keeps the components it was given, in any zone', () {
      expect(
        formatShortDay(DateTime.utc(2026, 9, 29, 23, 30), now: now),
        'Tue 29 Sep',
      );
    });
  });
}
