import 'package:cupola/core/utils/percent_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatPercent', () {
    test('glues the sign to the figure: `62%`', () {
      expect(formatPercent(62), '62%');
      expect(formatPercent(0), '0%');
      expect(formatPercent(100), '100%');
      // Neither a space nor a no-break space between figure and sign.
      expect(formatPercent(62), isNot(contains(' ')));
      expect(formatPercent(62), isNot(contains('\u00A0')));
    });

    test('rounds to the nearest whole percent, halves up', () {
      expect(formatPercent(62.4), '62%');
      expect(formatPercent(62.5), '63%');
      expect(formatPercent(62.6), '63%');
      expect(formatPercent(0.4), '0%');
      expect(formatPercent(0.5), '1%');
      // A fraction is multiplied by the caller; float noise rounds away.
      expect(formatPercent(0.29 * 100), '29%');
      expect(formatPercent(0.57 * 100), '57%');
    });

    test('100% is a claim: below 100 it never reads 100%', () {
      expect(formatPercent(99.4), '99%');
      expect(formatPercent(99.5), '99%');
      expect(formatPercent(99.6), '99%');
      expect(formatPercent(99.99), '99%');
      expect(formatPercent(100), '100%');
      expect(formatPercent(100.4), '100%');
    });

    test('a hair of floating-point noise under 100 is 100', () {
      expect(formatPercent(99.99999999999999), '100%');
      expect(formatPercent((0.07 + 0.93) * 100), '100%');
    });

    test('a tenth is opt-in, and the ends hold there too', () {
      expect(formatPercent(50, decimals: 1), '50.0%');
      expect(formatPercent(62.54, decimals: 1), '62.5%');
      expect(formatPercent(62.56, decimals: 1), '62.6%');
      expect(formatPercent(100, decimals: 1), '100.0%');
      expect(formatPercent(99.96, decimals: 1), '99.9%');
      expect(formatPercent(99.94, decimals: 1), '99.9%');
      expect(formatPercent(0, decimals: 1), '0.0%');
      expect(formatPercent(-0.04, decimals: 1), '0.0%');
    });

    test('a figure that is not a number reads an em dash, never 0%', () {
      expect(formatPercent(double.nan), '—');
      expect(formatPercent(double.infinity), '—');
      expect(formatPercent(double.negativeInfinity, decimals: 1), '—');
    });

    test('takes an int and a double alike', () {
      expect(formatPercent(7), '7%');
      expect(formatPercent(7.0), '7%');
    });
  });

  group('wholePercent', () {
    test('is the same rule as an int', () {
      expect(wholePercent(62.4), 62);
      expect(wholePercent(62.5), 63);
      expect(wholePercent(99.6), 99);
      expect(wholePercent(100), 100);
      expect(wholePercent(0.4), 0);
    });

    test('formatPercent of a whole percent is unchanged', () {
      for (final value in [0, 1, 50, 99, 100]) {
        expect(formatPercent(wholePercent(value)), '$value%');
      }
    });
  });

  test('percentSign is the one sign', () {
    expect(percentSign, '%');
  });
}
