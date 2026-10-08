/// The words of the Home's Coming up: what comes out or airs from today to
/// three days on, read off the calendar Discover's band and page read.
library;

import 'package:cupola/core/utils/string_utils.dart';
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

/// The calm line when nothing is dated in the window: `Nothing comes out or
/// airs by Friday`.
String comingUpCalmLine(DateTime now) =>
    'Nothing comes out or airs by ${weekdayName(comingUpEnd(now))}';
