@Tags(['catalog'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/features/discover/presentation/widgets/calendar_band.dart';

import 'calendar_world.dart';
import 'catalog.dart';

void main() {
  catalogCard(
    'CalendarBand',
    // Wide enough for the scene of a tablet on its side.
    width: 1160,
    scenes: [
      CatalogScene(
        'CalendarBand · the operator\'s week: today\'s release named, its '
        'poster, a dot for each day that has something',
        (_) => CalendarBand(
          events: CalendarWorld.events,
          window: CalendarWorld.window,
          now: CalendarWorld.now,
          onTap: () {},
        ),
        width: 390,
      ),
      CatalogScene(
        'The requester\'s · only her requests: Sprite Fright today, the '
        'premiere on Friday',
        (_) => CalendarBand(
          events: CalendarWorld.requester,
          window: CalendarWorld.window,
          now: CalendarWorld.now,
          onTap: () {},
        ),
        width: 390,
      ),
      CatalogScene(
        'Nothing of yours · the neutral lamp, and the way to what is coming '
        'out',
        (_) => CalendarBand(
          events: const [],
          window: CalendarWorld.window,
          now: CalendarWorld.now,
          onTap: () {},
        ),
        width: 390,
      ),
      CatalogScene(
        'One source down · the others\' rows stand, the silent one named in '
        'the tone of its cause',
        (_) => CalendarBand(
          events: CalendarWorld.events,
          window: CalendarWorld.window,
          now: CalendarWorld.now,
          onTap: () {},
          silent: const [
            (
              words: 'Lidarr did not answer at 20:53',
              error: ClassifiedFailure(ServiceFailureReason.unreachable),
            ),
          ],
        ),
        width: 390,
      ),
      CatalogScene(
        'CalendarBand.loading · its place kept while the calendars are read',
        (_) => CalendarBand.loading(
          window: CalendarWorld.window,
          now: CalendarWorld.now,
          onTap: () {},
        ),
        width: 390,
      ),
      CatalogScene(
        'A tablet on its side · the week beside the words, at the widest '
        'phone\'s measure, the band one line tall',
        (_) => CalendarBand(
          events: CalendarWorld.events,
          window: CalendarWorld.window,
          now: CalendarWorld.now,
          onTap: () {},
        ),
        width: 1100,
      ),
      CatalogScene(
        'Text at 200% · the line wraps, the strip scales its dates',
        (_) => CalendarBand(
          events: CalendarWorld.events,
          window: CalendarWorld.window,
          now: CalendarWorld.now,
          onTap: () {},
        ),
        width: 390,
        textScale: catalogTextScale,
      ),
    ],
  );
}
