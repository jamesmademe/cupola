import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/domain/library_calendar.dart';
import 'package:cupola/features/home/domain/coming_up.dart';

/// The words of the Home's Coming up.
void main() {
  // Tuesday 29 September: the window runs to Friday 2 October.
  final now = DateTime(2026, 9, 29, 20, 41);

  test('the window is today to three days on', () {
    expect(comingUpEnd(now), DateTime(2026, 10, 2));
  });

  test('nothing in the window is said calmly, naming its last day', () {
    expect(comingUpCalmLine(now), 'Nothing comes out or airs by Friday');
  });

  CalendarEvent dated(String title, int day) => CalendarEvent(
    identity: title,
    kind: CalendarKind.movie,
    day: DateTime(2026, 9, day),
    title: title,
    state: const CalendarState.notYet(),
  );

  test('the things dated today to Friday, in their order, and no other', () {
    final events = [
      dated('Yesterday', 28),
      dated('Today', 29),
      dated('Wednesday', 30),
      // 2 October is the 32nd of September to `DateTime`.
      dated('Friday', 32),
      dated('Saturday', 33),
    ];
    expect(comingUpOf(events, now).map((event) => event.title), [
      'Today',
      'Wednesday',
      'Friday',
    ]);
    expect(comingUpOf(const [], now), isEmpty);
  });
}
