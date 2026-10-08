@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/domain/library_calendar.dart';
import 'package:cupola/features/discover/presentation/widgets/calendar_week_strip.dart';

import 'calendar_world.dart';
import 'catalog.dart';

Map<DateTime, CalendarDot> _dots(List<DateTime> days) => {
  for (final day in days)
    day: ?calendarDayDot([
      for (final event in CalendarWorld.events)
        if (event.day == day) event,
    ]),
};

void main() {
  final weeks = calendarWeeks(CalendarWorld.window);
  final thisWeek = calendarWeekDays(weeks.first);
  final last = calendarWeekDays(weeks.last);
  Widget page(List<DateTime> days, DateTime selected) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: CalendarWeekStrip(
      days: days,
      now: CalendarWorld.now,
      window: CalendarWorld.window,
      dots: _dots(days),
      selected: selected,
      onSelect: (_) {},
      countOf: (day) =>
          CalendarWorld.events.where((event) => event.day == day).length,
    ),
  );
  catalogCard(
    'CalendarWeekStrip',
    scenes: [
      CatalogScene(
        'CalendarWeekStrip.band · the atrium\'s: letters, today ringed, the '
        'days before it dimmed, a dot in each day\'s most pressing tone',
        (_) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: CalendarWeekStrip.band(
            days: thisWeek,
            now: CalendarWorld.now,
            window: CalendarWorld.window,
            dots: _dots(thisWeek),
          ),
        ),
        width: 390,
      ),
      CatalogScene(
        'CalendarWeekStrip · the page\'s: today selected, filled',
        (_) => page(thisWeek, CalendarWorld.window.start),
        width: 390,
      ),
      CatalogScene(
        'Another day selected · today keeps its ring',
        (_) => page(thisWeek, DateTime(2026, 10, 2)),
        width: 390,
      ),
      CatalogScene(
        'The last week · the days past the thirty dimmed',
        (_) => page(last, last.first),
        width: 390,
      ),
      CatalogScene(
        'Text at 200% · names, dates and disc stop at 1.3x together',
        (_) => page(thisWeek, CalendarWorld.window.start),
        width: 390,
        textScale: catalogTextScale,
      ),
    ],
  );
}
