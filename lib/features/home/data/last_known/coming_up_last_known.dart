/// Coming up's last drawing: the things the calendar dates from today to
/// three days on, as the module drew them.
library;

import 'package:cupola/features/discover/domain/library_calendar.dart';
import 'package:cupola/features/discover/presentation/library_calendar_provider.dart'
    show LibraryCalendar;
import 'package:cupola/features/home/data/home_last_known.dart';
import 'package:cupola/features/home/data/last_known/calendar_event_codec.dart';
import 'package:cupola/features/home/domain/coming_up.dart';
import 'package:cupola/features/home/domain/home_module.dart';

/// The window and a day more, capped (`comingUpKept`): the module cuts it
/// again when it draws (`comingUpAsDrawn`), so a thing whose day went by is
/// gone and `airs today at 21:00` is said against the time of the drawing.
///
/// Only the events are kept. Which connection did not answer is a fault, and a
/// fault of an old read is a false alarm today (a drawing never says it); the
/// pictures keep no key (`calendarEventToJson`); a download is a word and no
/// figure. Not kept when every connection was silent: the drawing before is
/// better. A read that answered with nothing in the window is kept as an empty
/// drawing, so the one before it is not drawn in its place, and an empty
/// drawing is never drawn as "nothing comes out" (the module waits for the
/// live answer instead).
final comingUpLastKnown = HomeLastKnownSlot<LibraryCalendar>(
  id: 'comingUp',
  schema: 1,
  services: HomeModule.comingUp.services.toSet(),
  encode: (calendar) {
    if (calendar.answered.isEmpty && calendar.silent.isNotEmpty) return null;
    return {
      'readAt': calendar.readAt.toUtc().toIso8601String(),
      'events': [
        for (final event in comingUpKept(calendar.events, calendar.readAt))
          calendarEventToJson(event),
      ],
    };
  },
  decode: (data, image) {
    if (data is! Map || data['events'] is! List) return null;
    final readAt = switch (data['readAt']) {
      final String raw => DateTime.tryParse(raw)?.toLocal(),
      _ => null,
    };
    if (readAt == null) return null;
    final events = [
      for (final json in data['events'] as List)
        ?calendarEventFromJson(json, image),
    ];
    return LibraryCalendar(
      window: CalendarWindow.from(readAt),
      events: events,
      answered: const [],
      silent: const [],
      kinds: {for (final event in events) event.kind},
      readAt: readAt,
    );
  },
);
