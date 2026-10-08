@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/domain/library_calendar.dart';
import 'package:cupola/features/discover/presentation/widgets/calendar_month_grid.dart';

import 'calendar_world.dart';
import 'catalog.dart';

Map<DateTime, List<CalendarEvent>> _byDay(List<CalendarEvent> events) {
  final days = <DateTime, List<CalendarEvent>>{};
  for (final event in events) {
    (days[event.day] ??= []).add(event);
  }
  return days;
}

void main() {
  Widget grid(List<CalendarEvent> events, DateTime selected) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: CalendarMonthGrid(
      weeks: calendarWeeks(CalendarWorld.window),
      now: CalendarWorld.now,
      window: CalendarWorld.window,
      byDay: _byDay(events),
      selected: selected,
      onSelect: (_) {},
    ),
  );
  // Wednesday's evening, four episodes deep.
  final busy = [
    ...CalendarWorld.events,
    for (final (title, hour) in [
      ('Harbour Lights', 20),
      ('The Long Field', 21),
      ('Cosmos Laundromat', 23),
    ])
      CalendarWorld.episode(title, 30, hour, 1, 2),
  ]..sort(compareCalendarEvents);
  catalogCard(
    'CalendarMonthGrid',
    width: 860,
    scenes: [
      CatalogScene(
        'CalendarMonthGrid · the thirty days as weeks: today ringed and '
        'selected, Sprite Fright downloading, the days past the thirty hatched',
        (_) => grid(CalendarWorld.events, CalendarWorld.window.start),
        width: 820,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'Another day selected · Friday, the premiere',
        (_) => grid(CalendarWorld.events, DateTime(2026, 10, 2)),
        width: 820,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'A busy day · two things and how many more; its week grows',
        (_) => grid(busy, CalendarWorld.window.start),
        width: 820,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'The requester\'s · her requests, an episode by its code',
        (_) => grid(CalendarWorld.requester, CalendarWorld.window.start),
        width: 820,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'Text at 200% · the weeks grow, the lines cut',
        (_) => grid(CalendarWorld.events, CalendarWorld.window.start),
        width: 820,
        platform: CatalogPlatform.desktop,
        textScale: catalogTextScale,
      ),
    ],
  );
}
