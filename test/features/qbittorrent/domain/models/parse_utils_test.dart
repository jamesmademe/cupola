import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/utils/date_format.dart';
import 'package:cupola/features/qbittorrent/domain/models/parse_utils.dart';

void main() {
  group('parseInt', () {
    test('returns int as-is', () {
      expect(parseInt(42), 42);
    });

    test('truncates double to int', () {
      expect(parseInt(3.9), 3);
      expect(parseInt(-1.5), -1);
    });

    test('parses numeric string', () {
      expect(parseInt('123'), 123);
    });

    test('returns 0 for invalid or null', () {
      expect(parseInt(null), 0);
      expect(parseInt('not a number'), 0);
      expect(parseInt({}), 0);
    });
  });

  group('parseDouble', () {
    test('returns double as-is', () {
      expect(parseDouble(3.14), 3.14);
    });

    test('promotes int to double', () {
      expect(parseDouble(7), 7.0);
    });

    test('parses numeric string', () {
      expect(parseDouble('2.5'), 2.5);
    });

    test('returns 0 for invalid or null', () {
      expect(parseDouble(null), 0);
      expect(parseDouble('not a number'), 0);
    });
  });

  // formatSize/formatSpeed are thin sentinel wrappers over the shared ladders
  // in core/utils/byte_format.dart; these tests pin the sentinels and the
  // choice of ladder, not the arithmetic (that lives in byte_format_test).
  group('formatSize', () {
    test('returns em-dash for non-positive values', () {
      expect(formatSize(0), '—');
      expect(formatSize(-10), '—');
    });

    test('formats bytes as whole things', () {
      expect(formatSize(512), '512\u00A0B');
    });

    test('formats kilobytes', () {
      expect(formatSize(2048), '2.0\u00A0KB');
    });

    test('formats megabytes', () {
      expect(formatSize(5 * 1024 * 1024), '5.0\u00A0MB');
    });

    test('formats gigabytes', () {
      expect(formatSize(2 * 1024 * 1024 * 1024), '2.0\u00A0GB');
    });

    test('formats terabytes', () {
      expect(formatSize(1024 * 1024 * 1024 * 1024), '1.0\u00A0TB');
    });

    test('keeps a tenth of a terabyte', () {
      // TrueNAS pools go through this formatter too, and "46 TB" for a 45.5 TB
      // pool would lose the figure the storage screen exists to show.
      expect(
        formatSize((45.5 * 1024 * 1024 * 1024 * 1024).round()),
        '45.5\u00A0TB',
      );
    });

    test('climbs past TB instead of stopping there', () {
      expect(formatSize(1024 * 1024 * 1024 * 1024 * 1024), '1.0\u00A0PB');
    });
  });

  group('formatSpeed', () {
    test('returns 0 B/\u2060s for non-positive values', () {
      expect(formatSpeed(0), '0\u00A0B/\u2060s');
      expect(formatSpeed(-1), '0\u00A0B/\u2060s');
    });

    test('formats KB/\u2060s', () {
      expect(formatSpeed(2048), '2.0\u00A0KB/\u2060s');
    });

    test('reads the one ladder, matching the other services KPI cells', () {
      // SABnzbd and NZBGet render their rates from the same ladder, and all
      // three land in the same /services grid.
      expect(formatSpeed(52 * 1024 * 1024), '52.0\u00A0MB/\u2060s');
      expect(formatSpeed(120 * 1024 * 1024), '120\u00A0MB/\u2060s');
      expect(formatSpeed(512), '512\u00A0B/\u2060s');
    });

    test('formats GB/\u2060s', () {
      expect(formatSpeed(3 * 1024 * 1024 * 1024), '3.0\u00A0GB/\u2060s');
    });
  });

  group('parseBool', () {
    test('null is false', () {
      expect(parseBool(null), isFalse);
    });

    test('bool passes through', () {
      expect(parseBool(true), isTrue);
      expect(parseBool(false), isFalse);
    });

    test('non-zero num is true, zero is false', () {
      expect(parseBool(1), isTrue);
      expect(parseBool(0), isFalse);
      expect(parseBool(-1), isTrue);
      expect(parseBool(1.5), isTrue);
      expect(parseBool(0.0), isFalse);
    });

    test('parses truthy/falsy strings case-insensitively', () {
      expect(parseBool('true'), isTrue);
      expect(parseBool('TRUE'), isTrue);
      expect(parseBool('True'), isTrue);
      expect(parseBool('false'), isFalse);
      expect(parseBool('FALSE'), isFalse);
      expect(parseBool('1'), isTrue);
      expect(parseBool('0'), isFalse);
    });

    test('unknown string is false', () {
      expect(parseBool('maybe'), isFalse);
      expect(parseBool(''), isFalse);
    });
  });

  group('formatDuration', () {
    test('returns empty string for non-positive values', () {
      expect(formatDuration(0), '');
      expect(formatDuration(-1), '');
    });

    test('renders sub-day durations with zero-padded HH:MM:SS', () {
      expect(formatDuration(1), '00:00:01');
      expect(formatDuration(65), '00:01:05');
      expect(formatDuration(3600), '01:00:00');
      expect(formatDuration(3661), '01:01:01');
    });

    test('prepends day count when >= 1 day', () {
      expect(formatDuration(86400), '1\u00A0d 00:00:00');
      expect(formatDuration(90000), '1\u00A0d 01:00:00');
      expect(
        formatDuration(2 * 86400 + 3 * 3600 + 4 * 60 + 5),
        '2\u00A0d 03:04:05',
      );
    });
  });

  group('formatLimit', () {
    test('negative is unlimited (∞)', () {
      expect(formatLimit(-1), '∞');
      expect(formatLimit(-1024), '∞');
    });

    test('zero is bare 0 (not 0 B/\u2060s)', () {
      expect(formatLimit(0), '0');
    });

    test('positive defers to formatSpeed', () {
      expect(formatLimit(2048), '2.0\u00A0KB/\u2060s');
      expect(formatLimit(5 * 1024 * 1024), '5.0\u00A0MB/\u2060s');
    });
  });

  group('formatEpochDate', () {
    test('non-positive seconds is em-dash', () {
      expect(formatEpochDate(0), '—');
      expect(formatEpochDate(-1), '—');
    });

    test('renders local YYYY-MM-DD HH:MM with zero-padding', () {
      // 2026-06-15 14:30:00 UTC. We don't assert the hour exactly (depends on
      // the test machine's timezone), so we just verify the format shape and
      // the date components.
      final epoch =
          DateTime.utc(2026, 6, 15, 14, 30).millisecondsSinceEpoch ~/ 1000;
      final formatted = formatEpochDate(epoch);
      expect(formatted, matches(RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$')));
      // Date components should always be correct regardless of TZ.
      expect(formatted.startsWith('2026-06-15'), isTrue);
    });

    test('is the app stamp: the local day and the local 24 h clock', () {
      final local = DateTime(2026, 6, 5, 9, 7);
      final epoch = local.millisecondsSinceEpoch ~/ 1000;
      expect(formatEpochDate(epoch), '2026-06-05 09:07');
      expect(formatEpochDate(epoch), formatDateTimeStamp(local));
    });
  });

}
