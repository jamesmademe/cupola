/// The words of the Home's Coming up: what comes out or airs from today to
/// three days on, read off the calendar Discover's band and page read.
library;

import 'package:cupola/core/utils/date_format.dart';
import 'package:cupola/features/discover/domain/library_calendar.dart';

/// The days Coming up looks at after today: Tuesday to Friday.
const comingUpDays = 3;

/// How many rows the module draws before the way to the Calendar.
const comingUpRowLimit = 3;

/// The last day Coming up looks at.
DateTime comingUpEnd(DateTime now) =>
    DateTime(now.year, now.month, now.day + comingUpDays);

/// The things of [events] (in date order) dated from today to
/// [comingUpEnd], soonest first.
List<CalendarEvent> comingUpOf(List<CalendarEvent> events, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final end = comingUpEnd(now);
  return [
    for (final event in events)
      if (!event.day.isBefore(today) && !event.day.isAfter(end)) event,
  ];
}

/// How many things a last drawing of Coming up keeps: the rows the module
/// draws and a margin for the days that go by before it is drawn again.
const comingUpKeptLimit = 12;

/// What Coming up keeps of a read at [now]: [comingUpOf]'s window and one day
/// more, so a drawing a day old still has its whole window, capped at
/// [comingUpKeptLimit].
List<CalendarEvent> comingUpKept(List<CalendarEvent> events, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final end = DateTime(now.year, now.month, now.day + comingUpDays + 1);
  return [
    for (final event in events)
      if (!event.day.isBefore(today) && !event.day.isAfter(end)) event,
  ].take(comingUpKeptLimit).toList(growable: false);
}

/// The things of a last drawing as they are drawn at [now], which is later
/// than the read: the window is cut again ([comingUpOf]: a day gone by is
/// gone), and a thing that had not come yet when it was read, and whose day
/// or time has come since, is out with nothing said of what became of it
/// (`aired`, `out today`): the drawing cannot know.
List<CalendarEvent> comingUpAsDrawn(List<CalendarEvent> events, DateTime now) =>
    [
      for (final event in comingUpOf(events, now))
        if (event.state.stand == CalendarStand.notYet &&
            CalendarEvent.hasCome(event.day, event.airsAt, now))
          event.withState(const CalendarState.out(missingKnown: false))
        else
          event,
    ];

/// The calm line when nothing is dated in the window: `Nothing comes out or
/// airs by Friday`.
String comingUpCalmLine(DateTime now) =>
    'Nothing comes out or airs by ${weekdayName(comingUpEnd(now))}';
