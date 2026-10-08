# CalendarWeekStrip

A week of the calendar, Monday to Sunday: each day's name and date, and a dot under every day that has something.

Rendered from `lib/features/discover/presentation/widgets/calendar_week_strip.dart` (`CalendarWeekStrip`), with the dots from `calendarDayDot` in `lib/features/discover/domain/library_calendar.dart`, by `test/design_catalog/calendar_week_strip_catalog_test.dart`.

## Variants

- **On the band** (`CalendarWeekStrip.band`): the days' letters (`M T W T F S S`), today ringed (1.5pt in ink). A picture: nothing to tap, nothing for a screen reader, since the band speaks one sentence.
- **On the page** (`CalendarWeekStrip`): the short names (`Mon Tue …`); the selected day filled in ink with its date in `onInk`, today ringed while another day is selected. Each day is a toggle that selects it; the page then says what the day holds under the strip and brings its rows into view.

## Anatomy

Seven equal columns: the name in the caption role (`inkTertiary`), a 34pt disc with the date in the label role, and a 6pt dot under it. Days before today and past the thirty days are dimmed (`inkDisabled`) and carry no dot. The dot is the most pressing tone of the day's rows (a fault, then something on its way, then on the server, then the backlog) through `statusToneColor`; a ring in `inkSecondary` when nothing of the day has come yet.

Seven days cannot reflow, so the names, the dates and the disc follow the reading size together to the single-line ceiling (1.3×, `TextScaleMetrics.singleLineChromeMaxScaleFactor`) and stop: a name never outgrows the date under it. Past that a name scales down rather than lose letters, and a date scales down inside its disc.

## The consumer provides

The seven `days`, `now`, the `window`, the `dots`; on the page also the `selected` day, `onSelect` and `countOf` (how many things a day has, for its spoken name).

## Semantics

On the page each day is a toggle: `Friday 2 October, 2 things`, pressed when selected. A day before today reads `Monday 28 September, before today`, one past the window `Friday 30 October, beyond the 30 days`; neither is a button.

## States in the catalog

Each sheet is drawn in the dark and the light room.

- The band's week.
- The page's, today selected.
- Another day selected: today keeps its ring.
- The last week: the days past the thirty dimmed.
- Text at 200%.

## Do / don't

- Do dot a day in its most pressing tone, and only a day inside the window.
- Don't make the band's strip tappable: the band is one link.
