import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/utils/duration_format.dart';

void main() {
  group('formatElapsed', () {
    test('pads seconds but not minutes', () {
      // A stopwatch, not a timestamp: `0:07`, never `00:07`.
      expect(formatElapsed(const Duration(seconds: 7)), '0:07');
      expect(formatElapsed(const Duration(minutes: 1, seconds: 12)), '1:12');
      expect(formatElapsed(const Duration(minutes: 12, seconds: 4)), '12:04');
    });

    test('rolls over at sixty seconds', () {
      expect(formatElapsed(const Duration(seconds: 59)), '0:59');
      expect(formatElapsed(const Duration(seconds: 60)), '1:00');
      expect(formatElapsed(const Duration(seconds: 61)), '1:01');
    });

    test('renders zero rather than an empty string', () {
      expect(formatElapsed(Duration.zero), '0:00');
    });

    test('keeps counting past an hour instead of wrapping', () {
      // The client timeout is minutes, but a search behind a stalled proxy can
      // sit for far longer, and a readout that silently wrapped to 0:xx would
      // report the opposite of what happened.
      expect(formatElapsed(const Duration(hours: 1, seconds: 5)), '60:05');
    });
  });

  group('formatElapsedForSpeech', () {
    test('spells out seconds only, below a minute', () {
      expect(formatElapsedForSpeech(const Duration(seconds: 7)), '7 seconds');
      expect(formatElapsedForSpeech(Duration.zero), '0 seconds');
    });

    test('singularises one second and one minute', () {
      expect(formatElapsedForSpeech(const Duration(seconds: 1)), '1 second');
      expect(formatElapsedForSpeech(const Duration(minutes: 1)), '1 minute');
      expect(
        formatElapsedForSpeech(const Duration(minutes: 1, seconds: 1)),
        '1 minute 1 second',
      );
    });

    test('drops a zero seconds component', () {
      expect(formatElapsedForSpeech(const Duration(minutes: 2)), '2 minutes');
    });

    test('reads both components when both are present', () {
      expect(
        formatElapsedForSpeech(const Duration(minutes: 1, seconds: 12)),
        '1 minute 12 seconds',
      );
    });

    test('never emits the glyph form, which a screen reader cannot read', () {
      final spoken = formatElapsedForSpeech(
        const Duration(minutes: 1, seconds: 12),
      );
      expect(spoken, isNot(contains(':')));
    });
  });

  group('formatTimeSpan', () {
    test('writes the brand book units, a no-break space before each unit', () {
      expect(formatTimeSpan(const Duration(seconds: 48)), '48\u00A0s');
      expect(
        formatTimeSpan(const Duration(minutes: 12, seconds: 40)),
        '12\u00A0min',
      );
      expect(
        formatTimeSpan(const Duration(hours: 2, minutes: 30)),
        '2\u00A0h 30\u00A0min',
      );
      expect(formatTimeSpan(const Duration(days: 3)), '3\u00A0d');
      expect(
        formatTimeSpan(const Duration(days: 3, hours: 4, minutes: 20)),
        '3\u00A0d 4\u00A0h',
      );
    });

    test('drops the smaller unit when it is zero', () {
      expect(formatTimeSpan(const Duration(hours: 2)), '2\u00A0h');
      expect(formatTimeSpan(const Duration(days: 1, hours: 0)), '1\u00A0d');
      expect(formatTimeSpan(const Duration(minutes: 5)), '5\u00A0min');
    });

    test('truncates and never rounds up into the next unit', () {
      expect(
        formatTimeSpan(const Duration(minutes: 59, seconds: 59)),
        '59\u00A0min',
      );
      expect(
        formatTimeSpan(const Duration(hours: 23, minutes: 59, seconds: 59)),
        '23\u00A0h 59\u00A0min',
      );
    });

    test('shows seconds only under a minute, or under an hour on request', () {
      expect(
        formatTimeSpan(const Duration(minutes: 4, seconds: 30)),
        '4\u00A0min',
      );
      expect(
        formatTimeSpan(const Duration(minutes: 4, seconds: 30), seconds: true),
        '4\u00A0min 30\u00A0s',
      );
      expect(
        formatTimeSpan(const Duration(minutes: 4), seconds: true),
        '4\u00A0min',
      );
      // Above an hour the seconds are noise, asked for or not.
      expect(
        formatTimeSpan(
          const Duration(hours: 1, minutes: 2, seconds: 3),
          seconds: true,
        ),
        '1\u00A0h 2\u00A0min',
      );
    });

    test('is never negative and never a bare number', () {
      expect(formatTimeSpan(Duration.zero), '0\u00A0s');
      expect(formatTimeSpan(const Duration(seconds: -5)), '0\u00A0s');
      for (final span in const [
        Duration(seconds: 1),
        Duration(minutes: 1),
        Duration(hours: 1),
        Duration(days: 1),
      ]) {
        expect(formatTimeSpan(span), matches(RegExp('^[0-9]+\u00A0[a-z]')));
      }
    });
  });

  group('formatWindowRemaining', () {
    test('reads the same units as every other span', () {
      expect(formatWindowRemaining(const Duration(minutes: 29)), '29\u00A0min');
      expect(formatWindowRemaining(const Duration(minutes: 10)), '10\u00A0min');
      expect(formatWindowRemaining(Duration.zero), '0\u00A0s');
    });

    test('counts the seconds under ten minutes', () {
      expect(
        formatWindowRemaining(const Duration(minutes: 4, seconds: 30)),
        '4\u00A0min 30\u00A0s',
      );
      expect(formatWindowRemaining(const Duration(minutes: 4)), '4\u00A0min');
      expect(
        formatWindowRemaining(const Duration(minutes: 9, seconds: 59)),
        '9\u00A0min 59\u00A0s',
      );
      expect(formatWindowRemaining(const Duration(seconds: 30)), '30\u00A0s');
    });
  });
}
