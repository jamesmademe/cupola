# CalendarMonthGrid

The calendar's thirty days as weeks, Monday to Sunday, on a page wide enough to lay them side by side: each day its date and its things, a line or two each, in its tone.

Rendered from `lib/features/discover/presentation/widgets/calendar_month_grid.dart` (`CalendarMonthGrid`), with the lines from `calendarGridLead` and `calendarEventTip` in `lib/features/discover/domain/library_calendar.dart`, by `test/design_catalog/calendar_month_grid_catalog_test.dart`.

## Where it is used

The calendar page (`CalendarPage`) draws it in place of the strip and the agenda when the page is at least 1040pt wide (a tablet on its side, a desktop window), with the selected day read in a 340pt panel beside it: its name, what it holds in a sentence (`calendarDaySummary`), its rows (`CalendarRow`), the rest of a season it airs (`calendarLaterInSeason`), the way to its first title and the next day that has something. The arrow keys move the selected day, a week at a time up and down; Enter opens its first title. Narrower, the page keeps the phone's strip and agenda, centred in the reading well.

## Anatomy

- The weekday names over the columns, in the caption role (`inkTertiary`).
- A day: a slab with a hairline, 100pt tall at the reading size, 8pt between days and weeks. Its date in the label role; the first of a month names it (`1 Oct`). Today's date is ringed (1.5pt in ink) and says `Today` beside it.
- A thing in a day: a quiet fill, a 6pt dot in its tone through `statusToneColor` (a ring in `inkSecondary` while it has not come), its first line in the micro role (`22:00 S2 E5`, `62% · Digital`, `Album`; a download's figure leads, so a narrow day cuts the word and keeps it), its title in the caption role at 600, one line each.
- Past three things a day shows two and counts the rest (`2 more`); a busier day grows its week rather than its type shrinking.
- The selected day is ringed in ink (2pt), drawn over the border so its things do not move.
- Days before today are dimmed and carry nothing; the days of the last week past the thirty are hatched, and the first of them says `Beyond the 30 days`.

## The consumer provides

The `weeks` (the Mondays `calendarWeeks` gives), `now`, the `window`, each day's things (`byDay`, in the agenda's order), the `selected` day and `onSelect`.

## Semantics

A day is one button that selects it: `Friday 2 October, 2 things`, selected when it is. What a day holds is read in the panel beside the grid, so the things inside a day are a picture to the screen reader, and a tip under the pointer (`Sprite Fright · on disc · not out yet · Radarr, Radarr 4K`; the requester's names no service). A day before today reads `Monday 28 September, before today`, one past the window `Friday 30 October, beyond the 30 days`; neither is a button.

## States in the catalog

Each sheet is drawn in the dark and the light room, on the desktop.

- The thirty days, today selected.
- Another day selected.
- A busy day: two things and how many more.
- The requester's: her requests, an episode by its code.
- Text at 200%.

## Do / don't

- Do keep the grid for a page that fits seven readable days and the panel; below that the agenda reads better.
- Don't open a title from a day: a day selects, its rows in the panel open.
- Don't count or name a thing outside the thirty days.
