import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/utils/string_utils.dart';

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

  group('formatRuntimeMinutes', () {
    test('speaks hours and minutes', () {
      // Radarr shipped `127 min`, Seerr `173min`.
      expect(formatRuntimeMinutes(127), '2\u00A0h 7\u00A0min');
      expect(formatRuntimeMinutes(173), '2\u00A0h 53\u00A0min');
    });

    test('drops the hour under an hour', () {
      expect(formatRuntimeMinutes(47), '47\u00A0min');
      expect(formatRuntimeMinutes(1), '1\u00A0min');
    });

    test('drops the minutes on a whole hour', () {
      expect(formatRuntimeMinutes(120), '2\u00A0h');
      expect(formatRuntimeMinutes(60), '1\u00A0h');
    });

    test('reports nothing for a runtime the service does not have', () {
      // Zero is a missing fact, not a film of no length, and an empty string is
      // dropped by both the metadata line and the fact grid.
      expect(formatRuntimeMinutes(0), '');
      expect(formatRuntimeMinutes(-5), '');
    });
  });

  group('truncateTitle', () {
    test('leaves a title that fits alone', () {
      expect(truncateTitle('Inception'), 'Inception');
    });

    test('trims surrounding whitespace', () {
      expect(truncateTitle('  Inception  '), 'Inception');
    });

    test('caps a title that would grow a dialog past its own buttons', () {
      final long = 'A ${'very ' * 60}long title';
      final result = truncateTitle(long);

      expect(result.length, lessThanOrEqualTo(65));
      expect(result, endsWith('…'));
      // An ellipsis glyph, not three periods, which read as a pause.
      expect(result, isNot(contains('...')));
    });

    test('cuts on a word boundary rather than mid-word', () {
      final result = truncateTitle(
        'The Lord of the Rings The Fellowship of the Ring Extended Edition '
        'Remastered',
        maxChars: 40,
      );

      expect(result, 'The Lord of the Rings The Fellowship of…');
      expect(result.length, lessThanOrEqualTo(41));
    });

    test('hard-cuts a single word longer than the budget', () {
      // A word boundary is only honoured in the last third, so a title with no
      // early space cannot collapse to a lone ellipsis.
      final result = truncateTitle('A${'b' * 200}', maxChars: 20);

      expect(result.length, 21);
      expect(result, endsWith('…'));
    });

    test('is stable at exactly the budget', () {
      final exact = 'x' * 64;
      expect(truncateTitle(exact), exact);
      // One character over: 64 kept plus the ellipsis glyph.
      expect(truncateTitle('${exact}y').length, 65);
    });
  });
}
