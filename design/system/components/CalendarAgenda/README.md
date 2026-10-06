# CalendarAgenda

The calendar's agenda, day by day: a row per dated thing (a movie's release, an episode's airing, an album, a book), the days that have something under their headings, and quiet lines for the stretches with nothing.

Rendered from `lib/features/discover/presentation/widgets/calendar_agenda.dart` (`CalendarRow`, `CalendarDayGroup`, `CalendarQuietLine`), with each row's words from `lib/features/discover/domain/library_calendar.dart` (`CalendarEvent`, `CalendarState`, `calendarAgenda`), by `test/design_catalog/calendar_agenda_catalog_test.dart`. The page is `lib/features/discover/presentation/calendar_page.dart`, at `/discover/calendar`.

## CalendarRow

- **The operator's** (`CalendarRow`): a 54pt lead column, then the poster, then the words.
  - The lead: an episode's time in the small figure role (`22:00`, on the device's clock, from Sonarr's `airDateUtc`); anything else what kind of day it is in the label role (`Digital`, `Disc`, `Cinemas`, `Album`, `Book`) over `all day` in the caption role; `Cinemas`, the longest, scales down rather than lose a letter. Movies, albums and books have a date and never a time.
  - The poster: 36 × 54 (an album's cover square), `AppRadius.thumb`, from the arr's own artwork; the title's initials on the plate without one.
  - The title in the row role; under it where the thing stands after a 7pt dot; under that the connections that hold it after the service's glyph, `Radarr · Radarr 4K`, in `inkTertiary`.
- **The requester's** (`CalendarRow.requester`): no lead column and no service name; the poster 44 × 66; her note in the connections' place, `On digital in Italy today`, `You asked for season 3 on Sat 26 Sep`.

While a download moves, a 3pt bar in its tone and `around 21:10` (the requester's `ready around 21:10`) close the row.

### Where a row stands

| Stand | Words | Dot |
| --- | --- | --- |
| Its day has not come | `Not out yet`, `S2 E5 · not aired`, `Jan Morgenstern · not out yet` | a ring, neutral |
| Out, nothing on disk, the queue read whole | `Out today · missing`, `S2 E5 · aired · missing` | neutral |
| Out, the queue not read | `Out today`, `S2 E5 · aired` (never `missing` over a queue nobody read) | neutral |
| In the queue | `Out today · downloading 62%`, `· stuck 62%`, the words in the tone at 600 | blue, amber for a fault |
| On the server | `On your server`, the words quiet | green |

A release still to come reads as one whatever the file says. An episode's mark follows its code: `premiere` for the first of a season, `season finale`, `midseason finale`, `series finale` from Sonarr's `finaleType`. A thing held by two connections is one row naming both, at the furthest on of the two.

## CalendarDayGroup

The day's name in the small figure role, `Today`, `Tomorrow`, `Thu`, beside its date in the meta role (`Tue 29 Sep` beside `Today` and `Tomorrow`, `1 Oct` beside a weekday), over a `slab` with `AppRadius.group`, a hairline edge and a hairline between rows. The day the strip selects rings its slab in `inkSecondary` (320 ms, instant with Reduce Motion). Within a day the things with a date lead, then the episodes by their time.

## CalendarQuietLine

Three empty days or more read as one line, `Nothing until Wed 21 Oct`; fewer are skipped without a word. The thirty days end on `Nothing more in the next 30 days`. The meta role in `inkTertiary`, between dashes in the hairline.

## The consumer provides

A `CalendarEvent` and `now` for a row, with `onTap` (a movie's or a series' page, an artist's or an author's shelf); a day and its rows for a group; a day for a quiet line.

## Semantics

A row is one link and one sentence, its parts silenced: `Today, Sprite Fright, movie out on digital, downloading 62 percent, ready around 21:10, in Radarr and Radarr 4K`; `Friday 2 October at 21:00, Cosmos Laundromat season 3 premiere, not aired yet, in Sonarr`; the requester's `Today, Sprite Fright, out on digital in Italy, downloading 62 percent, ready around 21:10`. A day's name is a heading.

## States in the catalog

Each sheet is drawn in the dark and the light room.

- Today: a movie downloading.
- A day of two: the album before the 21:00 premiere.
- Where a row stands: on the server, stuck, aired and missing.
- The requester's rows.
- The quiet lines.
- Text at 200%: the lead takes a line above the row.

## Do / don't

- Do say `missing` only over a queue read whole, and red only for a calendar that did not arrive, on its own line.
- Don't give a movie, an album or a book a time, or a requester's row a service's name.
