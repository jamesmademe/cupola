import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/lifecycle/poll_clock.dart';

void main() {
  group('PollClock', () {
    late PollClock clock;
    late DateTime now;

    setUp(() {
      now = DateTime(2026, 8, 25, 12);
      clock = PollClock()..now = () => now;
    });

    test('a poller that has never run is due immediately', () {
      expect(clock.hasRun('a'), isFalse);
      expect(
        clock.timeUntilDue('a', const Duration(seconds: 3)),
        Duration.zero,
      );
    });

    test('reports the remainder while an interval is still running', () {
      clock.note('a');
      now = now.add(const Duration(seconds: 1));

      expect(
        clock.timeUntilDue('a', const Duration(seconds: 3)),
        const Duration(seconds: 2),
      );
    });

    test('is due again once the interval has elapsed', () {
      clock.note('a');
      now = now.add(const Duration(seconds: 3));

      expect(
        clock.timeUntilDue('a', const Duration(seconds: 3)),
        Duration.zero,
      );
    });

    test('a long absence never reports a negative remainder', () {
      clock.note('a');
      now = now.add(const Duration(hours: 2));

      expect(
        clock.timeUntilDue('a', const Duration(seconds: 3)),
        Duration.zero,
      );
    });

    test('ids are independent', () {
      clock.note('a');
      now = now.add(const Duration(seconds: 1));
      clock.note('b');
      now = now.add(const Duration(seconds: 1));

      // 'a' ticked two seconds ago, 'b' one second ago, same interval.
      expect(
        clock.timeUntilDue('a', const Duration(seconds: 3)),
        const Duration(seconds: 1),
      );
      expect(
        clock.timeUntilDue('b', const Duration(seconds: 3)),
        const Duration(seconds: 2),
      );
    });
  });
}
