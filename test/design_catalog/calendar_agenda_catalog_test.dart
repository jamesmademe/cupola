@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/features/discover/domain/library_calendar.dart';
import 'package:cupola/features/discover/presentation/widgets/calendar_agenda.dart';

import 'calendar_world.dart';
import 'catalog.dart';

Widget _day(
  DateTime day,
  List<CalendarEvent> events, {
  bool requester = false,
}) => CalendarDayGroup(
  day: day,
  now: CalendarWorld.now,
  children: [
    for (final event in events)
      requester
          ? CalendarRow.requester(
              event: event,
              now: CalendarWorld.now,
              onTap: () {},
            )
          : CalendarRow(event: event, now: CalendarWorld.now, onTap: () {}),
  ],
);

void main() {
  final friday = DateTime(2026, 10, 2);
  catalogCard(
    'CalendarAgenda',
    scenes: [
      CatalogScene(
        'CalendarRow in a CalendarDayGroup · today: a movie out on digital '
        'and downloading, its bar and when it will be done, both Radarrs',
        (_) => _day(CalendarWorld.now, [CalendarWorld.spriteFright()]),
        width: 390,
      ),
      CatalogScene(
        'A day of two · the album, a date with no time, leads the 21:00 '
        'premiere',
        (_) => _day(friday, [
          for (final event in CalendarWorld.events)
            if (event.day == friday) event,
        ]),
        width: 390,
      ),
      CatalogScene(
        'Where a row stands · on the server (green, the words quiet), stuck '
        '(amber), aired and missing (the backlog, neutral)',
        (_) => _day(CalendarWorld.now, [
          CalendarWorld.spriteFright(state: const CalendarState.onServer()),
          CalendarWorld.spriteFright(
            state: CalendarState.inFlight(
              mediaStatusFromQueue(
                availability: MediaAvailability.missing,
                monitored: true,
                queueEntry: const ArrQueueEntry(
                  pipeline: MediaPipeline.stalled,
                  progress: 0.62,
                ),
              ),
            ),
          ),
          CalendarWorld.episode(
            'Night Shift',
            29,
            1,
            2,
            5,
            state: const CalendarState.out(missingKnown: true),
          ),
        ]),
        width: 390,
      ),
      CatalogScene(
        'CalendarRow.requester · no lead column, no service: the poster '
        'larger, her note in its place',
        (_) => Column(
          children: [
            _day(CalendarWorld.now, [
              CalendarWorld.requester.first,
            ], requester: true),
            _day(friday, [CalendarWorld.requester.last], requester: true),
          ],
        ),
        width: 390,
      ),
      CatalogScene(
        'CalendarQuietLine · three empty days or more, and the end of the '
        'thirty days',
        (_) => Column(
          children: [
            CalendarQuietLine.until(DateTime(2026, 10, 21)),
            const CalendarQuietLine.end(),
          ],
        ),
        width: 390,
      ),
      CatalogScene(
        'Text at 200% · the lead takes a line above the row',
        (_) => _day(CalendarWorld.now, [
          CalendarWorld.spriteFright(),
          CalendarWorld.episode('Night Shift', 29, 22, 2, 5),
        ]),
        width: 390,
        textScale: catalogTextScale,
      ),
    ],
  );
}
