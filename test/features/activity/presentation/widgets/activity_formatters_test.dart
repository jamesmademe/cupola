import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/utils/release_utils.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_formatters.dart';

void main() {
  group('formatActivitySize', () {
    test('reads the same ladder as the queue sheet next to it', () {
      // The Activity detail sheet renders "Size" twice — the queue half through
      // formatActivityBytes, the history half through this — and the two used
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

      expect(formatActivitySize(311385129), '297 MB');
      expect(formatActivitySize(2199023255552), '2.0 TB');
    });

    test('parses the loosely typed shapes the arr JSON arrives in', () {
      expect(formatActivitySize('8003897815'), '7.5 GB');
      expect(formatActivitySize(8003897815.4), '7.5 GB');
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
}
