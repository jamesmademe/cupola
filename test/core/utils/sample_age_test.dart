import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/utils/sample_age.dart';

/// These guard the *vocabulary*, not the arithmetic.
///
/// Five surfaces were formatting an age privately and none of them agreed, so
/// what is under test is that one rule now answers for all of them: three
/// buckets, no seconds, and hours that never roll up into days.
void main() {
  group('formatDurationAge', () {
    test('anything under a minute is "just now", not a second count', () {
      // The precision is thrown away on purpose. A live-to-the-second age
      // repaints every second for information nobody acts on, and the
      // difference between four seconds and fifty is not a difference anyone
      // makes a decision on.
      expect(formatDurationAge(Duration.zero), 'just now');
      expect(formatDurationAge(const Duration(seconds: 59)), 'just now');
    });

    test('minutes up to an hour', () {
      expect(formatDurationAge(const Duration(minutes: 1)), '1 min ago');
      expect(formatDurationAge(const Duration(minutes: 59)), '59 min ago');
    });

    test('an hour and beyond reads in hours, and never in days', () {
      // A reading eleven hours old is not "yesterday", it is broken, and
      // rounding it to a day would turn a failure into a habit.
      expect(formatDurationAge(const Duration(minutes: 60)), '1 h ago');
      expect(formatDurationAge(const Duration(hours: 11)), '11 h ago');
      expect(formatDurationAge(const Duration(hours: 40)), '40 h ago');
    });
  });

  group('formatSampleAge', () {
    test('a clock that runs ahead clamps to "just now"', () {
      // Self-hosted hosts produce future timestamps constantly. A negative
      // minute count printed in a band is worse than no age at all.
      final now = DateTime(2026, 9, 16, 12);
      expect(
        formatSampleAge(now.add(const Duration(minutes: 5)), now: now),
        'just now',
      );
    });

    test('measures against the injected clock, not the wall', () {
      final now = DateTime(2026, 9, 16, 12);
      expect(
        formatSampleAge(now.subtract(const Duration(minutes: 6)), now: now),
        '6 min ago',
      );
    });
  });

  group('formatElapsedSpan', () {
    test('is a span, not an age — the two grammars do not share a string', () {
      // "No response for 6 min ago" is not a sentence, which is why this is a
      // separate function rather than a caller stripping the suffix.
      expect(formatElapsedSpan(const Duration(minutes: 6)), '6 minutes');
      expect(formatElapsedSpan(const Duration(minutes: 1)), '1 minute');
      expect(formatElapsedSpan(const Duration(hours: 1)), '1 hour');
      expect(formatElapsedSpan(const Duration(hours: 3)), '3 hours');
    });

    test('returns null under a minute so the caller drops the clause', () {
      expect(formatElapsedSpan(const Duration(seconds: 30)), isNull);
    });
  });
}
