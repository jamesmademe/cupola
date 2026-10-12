import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/utils/release_utils.dart';
import 'package:cupola/features/activity/domain/service_type.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_formatters.dart';

void main() {
  group('formatActivitySize', () {
    test('reads the same ladder as the queue sheet next to it', () {
      // The Activity detail sheet renders "Size" twice: the queue half through
      // formatActivityBytes, the history half through this, and the two used
      // to disagree, because this one was a GB-only ladder: 297 MB printed as
      // "0.29 GB" and 2 TiB as "2048.00 GB".
      for (final bytes in const [
        512,
        311385129,
        5307309140,
        8003897815,
        2199023255552,
      ]) {
        expect(formatActivitySize(bytes), formatActivityBytes(bytes));
        expect(formatActivitySize(bytes), formatReleaseSize(bytes));
      }

      expect(formatActivitySize(311385129), '297\u00A0MB');
      expect(formatActivitySize(2199023255552), '2.0\u00A0TB');
    });

    test('parses the loosely typed shapes the arr JSON arrives in', () {
      expect(formatActivitySize('8003897815'), '7.5\u00A0GB');
      expect(formatActivitySize(8003897815.4), '7.5\u00A0GB');
    });

    test('answers the em dash for anything that is not a size', () {
      expect(formatActivitySize(null), '—');
      expect(formatActivitySize('not a number'), '—');
      expect(formatActivitySize(double.nan), '—');
      expect(formatActivitySize(double.infinity), '—');
    });
  });

  group('formatActivityTimeOnly', () {
    test('prints the clock and leaves the date to the heading', () {
      // "Finished today" already says which day in its header, so repeating the
      // date on six consecutive rows answers "which day" six times instead of
      // "when today". `formatActivityDateTime` prints both and every one of its
      // other callers wants that, hence a sibling rather than a change.
      final stamp = DateTime(2026, 9, 16, 8, 12).toIso8601String();
      final printed = formatActivityTimeOnly(stamp);

      expect(printed, '08:12');
      expect(printed, isNot(contains('2026')));
      // Zero-padded, so six of them make a column rather than a ragged edge.
      expect(
        formatActivityTimeOnly(DateTime(2026, 9, 16, 9, 5).toIso8601String()),
        '09:05',
      );
    });

    test('answers the em dash for anything that is not a timestamp', () {
      expect(formatActivityTimeOnly(null), '—');
      expect(formatActivityTimeOnly('   '), '—');
      // An unparseable string is handed back rather than swallowed: the same
      // contract the rest of this file's formatters keep.
      expect(formatActivityTimeOnly('yesterday'), 'yesterday');
    });
  });

  group('formatActivityDuration', () {
    test('reads an *arr timeleft in the brand book units', () {
      expect(formatActivityDuration('00:12:40'), '12\u00A0min');
      expect(formatActivityDuration('12:05:00'), '12\u00A0h 5\u00A0min');
      expect(formatActivityDuration('02:00:00'), '2\u00A0h');
      expect(formatActivityDuration('00:00:48'), '48\u00A0s');
      expect(formatActivityDuration('00:00:00'), '0\u00A0s');
    });

    test('reads the days an *arr puts in front of the hours', () {
      // `1.02:03:04` is one day, two hours: it used to read `3m`, because the
      // hours field did not parse.
      expect(formatActivityDuration('1.02:03:04'), '1\u00A0d 2\u00A0h');
      expect(formatActivityDuration('3.00:10:00'), '3\u00A0d');
    });

    test('ignores the fractional seconds an *arr appends', () {
      expect(formatActivityDuration('00:00:48.1234567'), '48\u00A0s');
    });

    test('an absent timeleft is an em dash, and a stranger passes through', () {
      expect(formatActivityDuration(null), '—');
      expect(formatActivityDuration('  '), '—');
      expect(formatActivityDuration('soon'), 'soon');
    });
  });

  group('wantedSubtitle', () {
    test('a movie\'s release date is the brand book\'s, not the ISO stamp', () {
      // 1 May 2024 was a Wednesday, and 2024 is another year.
      expect(
        wantedSubtitle({
          'inCinemas': '2024-05-01T00:00:00Z',
        }, ServiceType.movies),
        'Release Wed 1 May 2024',
      );
    });

    test('says nothing for a movie with no date', () {
      expect(wantedSubtitle({}, ServiceType.movies), isNull);
    });
  });

  group('formatRelativeDateTime', () {
    final now = DateTime(2026, 10, 9, 20, 30);

    test('counts back within the week', () {
      // The figure and its unit are held together by a no-break space.
      expect(
        formatRelativeDateTime(DateTime(2026, 10, 9, 18, 30), now: now),
        '2\u00A0h ago',
      );
      expect(
        formatRelativeDateTime(DateTime(2026, 10, 6, 20, 0), now: now),
        '3 days ago',
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
}
