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
      expect(formatClockTime(DateTime(2026, 9, 2, 21)), '21:00');
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

  group('formatDayLabel', () {
    final now = DateTime(2026, 9, 2, 14, 30);

    test('Today and Tomorrow are a calendar day apart, not 24 hours', () {
      expect(formatDayLabel(DateTime(2026, 9, 2, 23, 59), now), 'Today');
      expect(formatDayLabel(DateTime(2026, 9, 3, 0, 1), now), 'Tomorrow');
      expect(formatDayLabel(DateTime(2026, 9, 4, 3), now), 'Fri 4');
    });

    test('names the weekday and the day of the month beyond tomorrow', () {
      expect(formatDayLabel(DateTime(2026, 9, 7, 21), now), 'Mon 7');
      expect(formatDayLabel(DateTime(2026, 10, 1, 21), now), 'Thu 1');
    });
  });

  group('formatIsoDay', () {
    test(
      'pads the month and the day, and keeps the components it was given',
      () {
        expect(formatIsoDay(DateTime(2026, 9, 2)), '2026-09-02');
        expect(formatIsoDay(DateTime.utc(2026, 12, 31, 23, 59)), '2026-12-31');
      },
    );
  });

  group('formatDateTimeStamp', () {
    test('is the sortable day and the 24 h clock', () {
      expect(
        formatDateTimeStamp(DateTime(2026, 9, 20, 14, 3)),
        '2026-09-20 14:03',
      );
      expect(
        formatDateTimeStamp(DateTime(2026, 1, 2, 3, 4)),
        '2026-01-02 03:04',
      );
    });

    test('reads this device\'s clock, whatever zone the value carries', () {
      final utc = DateTime.utc(2026, 9, 20, 14, 3);
      expect(formatDateTimeStamp(utc), formatDateTimeStamp(utc.toLocal()));
    });

    test('answers the em dash when there is no timestamp', () {
      expect(formatDateTimeStamp(null), '—');
    });
  });

  group('formatRelativeDateTime', () {
    final now = DateTime(2026, 10, 9, 20, 30);

    test('says just now under a minute', () {
      expect(
        formatRelativeDateTime(DateTime(2026, 10, 9, 20, 29, 30), now: now),
        'just now',
      );
    });

    test('counts back within the week', () {
      // The figure and its unit are held together by a no-break space.
      expect(
        formatRelativeDateTime(DateTime(2026, 10, 9, 20, 10), now: now),
        '20\u00A0min ago',
      );
      expect(
        formatRelativeDateTime(DateTime(2026, 10, 9, 18, 30), now: now),
        '2\u00A0h ago',
      );
      expect(
        formatRelativeDateTime(DateTime(2026, 10, 8, 20, 30), now: now),
        '1 day ago',
      );
      expect(
        formatRelativeDateTime(DateTime(2026, 10, 6, 20, 0), now: now),
        '3 days ago',
      );
    });

    test('counts forward the same way for a time ahead', () {
      expect(
        formatRelativeDateTime(DateTime(2026, 10, 9, 20, 30, 40), now: now),
        'in < 1\u00A0min',
      );
      expect(
        formatRelativeDateTime(DateTime(2026, 10, 9, 20, 50), now: now),
        'in 20\u00A0min',
      );
      expect(
        formatRelativeDateTime(DateTime(2026, 10, 9, 23, 30), now: now),
        'in 3\u00A0h',
      );
      expect(
        formatRelativeDateTime(DateTime(2026, 10, 12, 20, 30), now: now),
        'in 3 days',
      );
    });

    test('names the day past a week, as the app dates, never ISO', () {
      expect(
        formatRelativeDateTime(DateTime(2026, 9, 29, 12), now: now),
        'Tue 29 Sep',
      );
      expect(
        formatRelativeDateTime(DateTime(2025, 9, 29, 12), now: now),
        'Mon 29 Sep 2025',
      );
    });
  });

  group('calendarDaysBetween', () {
    test('counts the days on the calendar, never the hours between them', () {
      // Twenty minutes apart and a day apart on the calendar.
      expect(
        calendarDaysBetween(
          DateTime.utc(2026, 10, 24, 23, 50),
          DateTime.utc(2026, 10, 25, 0, 10),
        ),
        1,
      );
      // A 23 h gap (the night the clocks go forward) is still one day...
      expect(
        calendarDaysBetween(
          DateTime.utc(2026, 3, 29, 0, 30),
          DateTime.utc(2026, 3, 30, 0, 10),
        ),
        1,
      );
      // ...and 47 h across two midnights is two.
      expect(
        calendarDaysBetween(
          DateTime.utc(2026, 3, 28, 1),
          DateTime.utc(2026, 3, 30, 0),
        ),
        2,
      );
    });

    test('is zero within a day and negative backwards', () {
      expect(
        calendarDaysBetween(
          DateTime(2026, 9, 2, 0, 1),
          DateTime(2026, 9, 2, 23, 59),
        ),
        0,
      );
      expect(
        calendarDaysBetween(DateTime(2026, 9, 3, 8), DateTime(2026, 9, 2, 20)),
        -1,
      );
    });

    test('crosses a month and a year', () {
      expect(
        calendarDaysBetween(DateTime(2026, 12, 31), DateTime(2027, 1, 1)),
        1,
      );
      expect(
        calendarDaysBetween(DateTime(2026, 2, 27), DateTime(2026, 3, 1)),
        2,
      );
    });
  });

  group('the day words: formatPastDay and formatPastDayOn', () {
    // Monday 12 Oct 2026, mid-afternoon.
    final now = DateTime(2026, 10, 12, 15);

    test('are null for today and for a day ahead', () {
      expect(formatPastDay(DateTime(2026, 10, 12, 0, 1), now: now), isNull);
      expect(formatPastDay(DateTime(2026, 10, 12, 23, 59), now: now), isNull);
      expect(formatPastDay(DateTime(2026, 10, 13, 9), now: now), isNull);
      expect(formatPastDayOn(DateTime(2026, 10, 12, 9), now: now), isNull);
    });

    test('say yesterday for the day before, however near midnight', () {
      expect(
        formatPastDay(DateTime(2026, 10, 11, 0, 1), now: now),
        'yesterday',
      );
      expect(
        formatPastDay(DateTime(2026, 10, 11, 23, 59), now: now),
        'yesterday',
      );
      expect(formatPastDayOn(DateTime(2026, 10, 11, 9), now: now), 'yesterday');
    });

    test('name the weekday within the week', () {
      expect(formatPastDay(DateTime(2026, 10, 7, 18), now: now), 'Wednesday');
      expect(formatPastDay(DateTime(2026, 10, 6, 18), now: now), 'Tuesday');
      expect(
        formatPastDayOn(DateTime(2026, 10, 7, 18), now: now),
        'on Wednesday',
      );
    });

    test('name the date from the seventh day, a year only in another', () {
      expect(formatPastDay(DateTime(2026, 10, 5, 18), now: now), 'Mon 5 Oct');
      expect(formatPastDay(DateTime(2026, 9, 29, 18), now: now), 'Tue 29 Sep');
      expect(
        formatPastDay(DateTime(2025, 9, 29, 18), now: now),
        'Mon 29 Sep 2025',
      );
      expect(
        formatPastDayOn(DateTime(2026, 9, 29, 18), now: now),
        'on Tue 29 Sep',
      );
      expect(
        formatPastDayOn(DateTime(2025, 9, 29, 18), now: now),
        'on Mon 29 Sep 2025',
      );
    });

    test('read both values on the device clock, whatever zone they carry', () {
      final at = DateTime(2026, 10, 7, 18);
      expect(
        formatPastDay(at.toUtc(), now: now.toUtc()),
        formatPastDay(at, now: now),
      );
      expect(
        formatPastDayOn(at.toUtc(), now: now.toUtc()),
        formatPastDayOn(at, now: now),
      );
    });
  });

  group('formatDayWords', () {
    final now = DateTime(2026, 10, 12, 15);

    test('is the hours through the day', () {
      expect(
        formatDayWords(DateTime(2026, 10, 12, 14, 59, 30), now: now),
        'just now',
      );
      expect(
        formatDayWords(DateTime(2026, 10, 12, 13), now: now),
        '2\u00A0h ago',
      );
      expect(
        formatDayWords(DateTime(2026, 10, 12, 1), now: now),
        '14\u00A0h ago',
      );
    });

    test('keeps the hours through the half day before midnight', () {
      final morning = DateTime(2026, 10, 12, 7);
      expect(
        formatDayWords(DateTime(2026, 10, 11, 23), now: morning),
        '8\u00A0h ago',
      );
      // And says yesterday once the evening is more than half a day back.
      expect(formatDayWords(DateTime(2026, 10, 11, 23), now: now), 'yesterday');
    });

    test('then the day: yesterday, the weekday, the date', () {
      expect(formatDayWords(DateTime(2026, 10, 11, 9), now: now), 'yesterday');
      expect(formatDayWords(DateTime(2026, 10, 7, 9), now: now), 'Wednesday');
      expect(formatDayWords(DateTime(2026, 9, 29, 9), now: now), 'Tue 29 Sep');
      expect(
        formatDayWords(DateTime(2025, 9, 29, 9), now: now),
        'Mon 29 Sep 2025',
      );
    });

    test('reads a time ahead of the clock as just now', () {
      expect(formatDayWords(DateTime(2026, 10, 12, 18), now: now), 'just now');
    });

    test('reads the same for a clock and a value in UTC', () {
      final at = DateTime(2026, 10, 7, 9);
      expect(
        formatDayWords(at.toUtc(), now: now.toUtc()),
        formatDayWords(at, now: now),
      );
    });
  });
}
