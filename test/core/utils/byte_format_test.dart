import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/utils/byte_format.dart';

const int _kib = 1024;
const int _mib = _kib * 1024;
const int _gib = _mib * 1024;
const int _tib = _gib * 1024;
const int _pib = _tib * 1024;

void main() {
  group('formatBytes', () {
    test('renders bytes as whole things', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(1), '1 B');
      expect(formatBytes(512), '512 B');
      expect(formatBytes(1023), '1023 B');
    });

    test('one decimal above bytes, from the first rung to 99.9', () {
      expect(formatBytes(1024), '1.0 KB');
      expect(formatBytes(1536), '1.5 KB');
      // The compact ladder this replaced printed `10 KB` here and `46 TB` for a
      // 45.5 TB pool: a decimal is on every figure under 100 now.
      expect(formatBytes(10 * _kib), '10.0 KB');
      expect(formatBytes(26 * _gib), '26.0 GB');
      expect(formatBytes((45.5 * _tib).round()), '45.5 TB');
      expect(formatBytes((99.9 * _kib).round()), '99.9 KB');
    });

    test('whole from 100 up in a unit, where a decimal is false precision', () {
      expect(formatBytes(100 * _kib), '100 KB');
      expect(formatBytes(798 * _mib), '798 MB');
      expect(formatBytes(999 * _kib), '999 KB');
      expect(formatBytes((152.3 * _gib).round()), '152 GB');
      expect(formatBytes((152.7 * _gib).round()), '153 GB');
    });

    test('reads the whole-number edge after rounding, not before', () {
      // 99.96 rounds to 100.0 at one decimal, which is already a figure that
      // prints whole: `100 KB`, never the false precision of `100.0 KB`.
      expect(formatBytes((99.96 * _kib).round()), '100 KB');
      expect(formatBytes((99.94 * _kib).round()), '99.9 KB');
    });

    test('a size under one unit drops a rung instead of printing 0.4 GB', () {
      expect(formatBytes((0.4 * _gib).round()), '410 MB');
      expect(formatBytes(_mib ~/ 2), '512 KB');
    });

    test('climbs the whole binary ladder', () {
      expect(formatBytes(_mib), '1.0 MB');
      expect(formatBytes(_gib), '1.0 GB');
      expect(formatBytes(5497558138880), '5.0 TB');
      expect(formatBytes(_pib), '1.0 PB');
      // Nothing above PB to promote into, so the number simply keeps growing
      // rather than falling off the ladder.
      expect(formatBytes(4096 * _pib), '4096 PB');
    });

    test('promotes after rounding, never printing 1024 of a unit', () {
      // 1023.96 KB rounds to "1024" at this unit's precision, which contradicts
      // its own label: the check reads the rendered number, not the raw one.
      expect(formatBytes((1023.96 * _kib).round()), '1.0 MB');
      expect(formatBytes(1023.6), '1.0 KB');
      expect(formatBytes((1023.99 * _mib).round()), '1.0 GB');
    });

    test('1000 to 1023 of a unit stay in it, whole', () {
      // The services' own UIs print `1000 KiB` too: the unit changes at 1024.
      expect(formatBytes(1000 * _kib), '1000 KB');
      expect(formatBytes(1023 * _mib), '1023 MB');
    });

    test('every figure on the ladder has the rule\'s shape', () {
      // Bytes whole; 1.0 to 99.9 with one decimal; 100 and over whole; and
      // never a unit's own 1024.
      final shape = RegExp(
        r'^(?:\d{1,4} B|(?:[1-9]\.\d|[1-9]\d\.\d|[1-9]\d{2,3}) '
        r'(?:KB|MB|GB|TB|PB))$',
      );
      final seen = <String>{};
      for (var unit = 0; unit <= 5; unit++) {
        final scale = BigInt.from(_kib).pow(unit).toDouble();
        // Dense around the places the rule changes its mind: the first rung,
        // the whole-number edge, and the promotion threshold.
        for (final factor in <double>[
          0.9995,
          1,
          1.04,
          9.96,
          10,
          99.9,
          99.94,
          99.95,
          99.96,
          100,
          999.4,
          999.5,
          1000,
          1023.4,
          1023.5,
          1023.96,
          1023.999,
        ]) {
          final text = formatBytes(scale * factor);
          seen.add(text);
          expect(text, matches(shape), reason: '$factor x 1024^$unit');
          // The top rung has nothing to promote into and keeps growing.
          if (unit < 5) expect(text, isNot(startsWith('1024')), reason: text);
        }
      }
      expect(seen.length, greaterThan(40));
    });

    test('carries a sign rather than pretending a negative is zero', () {
      expect(formatBytes(-1536), '-1.5 KB');
      expect(formatBytes(-152 * _gib), '-152 GB');
    });

    test('a value that is not finite is the em dash, never a number', () {
      expect(formatBytes(double.nan), '—');
      expect(formatBytes(double.infinity), '—');
    });

    test('two releases a tenth of a gigabyte apart read apart', () {
      // What a size is on screen for: telling two apart. The ladder this
      // replaced printed whole terabytes from 10 up, so a 45.5 TB pool read
      // `46 TB` and every array from 30.5 to 31.5 TB read `31 TB`.
      expect(formatBytes((4.3 * _gib).round()), '4.3 GB');
      expect(formatBytes((4.4 * _gib).round()), '4.4 GB');
      expect(formatBytes((31.2 * _tib).round()), '31.2 TB');
      expect(formatBytes((31.9 * _tib).round()), '31.9 TB');
      expect(formatBytes(4700000000), '4.4 GB');
    });
  });

  group('formatBytesPerSecond', () {
    test('appends the rate suffix at every magnitude', () {
      expect(formatBytesPerSecond(0), '0 B/s');
      expect(formatBytesPerSecond(512), '512 B/s');
      expect(formatBytesPerSecond(2097152), '2.0 MB/s');
    });

    test('follows the same rule: one decimal, whole from 100, promoted', () {
      expect(formatBytesPerSecond((4.2 * _mib).round()), '4.2 MB/s');
      expect(formatBytesPerSecond((15.5 * _mib).round()), '15.5 MB/s');
      expect(formatBytesPerSecond(120 * _mib), '120 MB/s');
      expect(formatBytesPerSecond((1023.96 * _kib).round()), '1.0 MB/s');
      expect(formatBytesPerSecond(-2 * _mib), '-2.0 MB/s');
    });
  });

  group('formatMegabytes', () {
    test('reads SABnzbd/NZBGet MB fields on the same ladder as raw bytes', () {
      expect(formatMegabytes(0), '0 B');
      expect(formatMegabytes(512), '512 MB');
      expect(formatMegabytes(1500), '1.5 GB');
      expect(formatMegabytes(3000), '2.9 GB');
      expect(formatMegabytes(40 * 1024), '40.0 GB');
      expect(formatMegabytes(150 * 1024), '150 GB');
    });

    test('drops below MB when the remainder is small, instead of "0.0 MB"', () {
      // The old SABnzbd-only formatter bottomed out at MB and printed
      // "0.5 MB" for half a megabyte; the shared ladder goes all the way down.
      expect(formatMegabytes(0.5), '512 KB');
    });
  });

  group('formatKilobytesPerSecond', () {
    test('reads SABnzbd kbpersec', () {
      expect(formatKilobytesPerSecond(0), '0 B/s');
      expect(formatKilobytesPerSecond(512), '512 KB/s');
      expect(formatKilobytesPerSecond(2048.5), '2.0 MB/s');
      expect(formatKilobytesPerSecond(50 * 1024), '50.0 MB/s');
    });
  });

  group('formatBytesOfTotal', () {
    test('writes the unit once, on the total\'s', () {
      expect(formatBytesOfTotal(14 * _gib, 15 * _gib), '14.0 of 15.0 GB');
      expect(formatBytesOfTotal(_gib, 4 * _gib), '1.0 of 4.0 GB');
      // On its own a transfer 900 MB into a 15.2 GB file reads `900 MB`.
      expect(
        formatBytesOfTotal(900 * _mib, (15.2 * _gib).round()),
        '0.9 of 15.2 GB',
      );
    });

    test('a done figure under one unit reads a tenth, not 0', () {
      expect(
        formatBytesOfTotal((0.4 * _gib).round(), 4 * _gib),
        '0.4 of 4.0 GB',
      );
      expect(formatBytesOfTotal(0, 2 * _gib), '0.0 of 2.0 GB');
    });

    test('whole from 100 up, each half on its own', () {
      expect(formatBytesOfTotal(120 * _gib, 152 * _gib), '120 of 152 GB');
      expect(
        formatBytesOfTotal((5.2 * _gib).round(), 152 * _gib),
        '5.2 of 152 GB',
      );
      expect(
        formatBytesOfTotal((99.96 * _gib).round(), 152 * _gib),
        '100 of 152 GB',
      );
    });

    test('takes the unit the total promotes to, after rounding', () {
      expect(
        formatBytesOfTotal(500 * _kib, (1023.96 * _kib).round()),
        '0.5 of 1.0 MB',
      );
    });

    test('bytes are whole, and so is the pair', () {
      expect(formatBytesOfTotal(300, 512), '300 of 512 B');
    });

    test('agrees with the standalone ladder on the total', () {
      for (final total in <int>[
        512,
        3 * _kib,
        (45.5 * _mib).round(),
        152 * _gib,
        (9.31 * _tib).round(),
      ]) {
        final label = formatBytes(total);
        expect(formatBytesOfTotal(0, total), endsWith(' of $label'));
      }
    });
  });
}
