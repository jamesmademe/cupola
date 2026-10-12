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

  test('what is kept is the window and a day more, capped', () {
    final events = [
      dated('Yesterday', 28),
      dated('Today', 29),
      dated('Friday', 32),
      dated('Saturday', 33),
      dated('Sunday', 34),
    ];
    expect(comingUpKept(events, now).map((event) => event.title), [
      'Today',
      'Friday',
      'Saturday',
    ]);
    final many = [for (var i = 0; i < 30; i++) dated('Today $i', 29)];
    expect(comingUpKept(many, now), hasLength(comingUpKeptLimit));
  });

  group('a drawing at a later time', () {
    CalendarEvent episode(int day, int hour, CalendarState state) =>
        CalendarEvent(
          identity: 'e$day',
          kind: CalendarKind.episode,
          day: DateTime(2026, 9, day),
          airsAt: DateTime(2026, 9, day, hour),
          title: 'Cosmos Laundromat',
          season: 3,
          episode: 1,
          mark: CalendarMark.premiere,
          poster: (url: 'https://x.test/p.jpg', headers: null),
          sources: const ['Sonarr'],
          note: 'a note',
          state: state,
        );

    test('cuts the window again, a day gone by is gone', () {
      final events = [dated('Today', 29), dated('Wednesday', 30)];
      expect(
        comingUpAsDrawn(events, DateTime(2026, 9, 30, 8)).map((e) => e.title),
        ['Wednesday'],
      );
      expect(comingUpAsDrawn(events, DateTime(2026, 10, 8)), isEmpty);
    });

    test('a thing that had not come when it was read, and has since, is out '
        'with nothing said of what became of it', () {
      final before = episode(29, 21, const CalendarState.notYet());
      final after = comingUpAsDrawn([before], DateTime(2026, 9, 29, 21, 30));
      expect(after.single.state.stand, CalendarStand.out);
      expect(after.single.state.missingKnown, isFalse);
      expect(
        after.single.statusLine(DateTime(2026, 9, 29, 21, 30)),
        contains('aired'),
      );
      // Everything else of the event stays.
      expect(after.single.identity, before.identity);
      expect(after.single.airsAt, before.airsAt);
      expect(after.single.mark, before.mark);
      expect(after.single.poster, before.poster);
      expect(after.single.sources, before.sources);
      expect(after.single.note, before.note);
      // Before its time it is still not aired.
      expect(
        comingUpAsDrawn([
          before,
        ], DateTime(2026, 9, 29, 20, 59)).single.state.stand,
        CalendarStand.notYet,
      );
    });

    test('what the read said of where it stands is left as it said', () {
      for (final state in [
        const CalendarState.onServer(),
        const CalendarState.out(missingKnown: true),
        const CalendarState.out(missingKnown: false),
      ]) {
        final events = comingUpAsDrawn([
          episode(29, 21, state),
        ], DateTime(2026, 9, 29, 21, 30));
        expect(events.single.state, same(state));
      }
    });
  });
}
