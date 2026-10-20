# CalendarBand

The calendar's way in from the top of the Discover atrium, full width above the doors: the one live object there. It names the next thing of the household's, shows its poster, and dots this week; the whole band opens the calendar.

Rendered from `lib/features/discover/presentation/widgets/calendar_band.dart` (`CalendarBand`), with its words from `lib/features/discover/domain/library_calendar.dart` (`CalendarDigest`), by `test/design_catalog/calendar_band_catalog_test.dart`. The atrium mounts it through `DiscoverCalendarBand` (`lib/features/discover/presentation/discover_calendar_band.dart`).

## Variants

- **The band** (`CalendarBand`): `Calendar` in the section role with the chevron of a shelf's header (`chevron_right_rounded` in the primary); under it one line, its first words in the label role at 600 in ink and the rest at 400 in `inkSecondary`: `Today · Sprite Fright · on digital`. A movie says its release, never a time; an episode its code and time (`Tomorrow · Night Shift · S2 E5 at 22:00`). The next thing's poster sits at the right, 36 × 54, `AppRadius.thumb`, with the poster shadow in its light. Under them the week ([CalendarWeekStrip](../CalendarWeekStrip/README.md), `.band`).
- **Loading** (`CalendarBand.loading`): the same frame with a plate where the line will be and the week without dots, so the atrium does not jump when the calendars arrive.
- **Wide**: the same parts, the week of dots beside the words at the end of the band instead of under them, and the band one line tall. It goes beside once the inside of the band is `CalendarBand.besideFrom` (776) wide, where the words keep at least the week's own measure: a tablet upright's list beside a title, a narrow window.
- **Wider still, the week in posters** (`W-Desk-Discover`), from `CalendarBand.postersFrom` (about 940 inside the band: a desktop window, a tablet on its side): the words (the heading, the line, the silent connections) in a 220 column, `space-xl`, then seven days from today, `space-sm` apart, each a cell (`radius-control`, `space-row` padding) of `fill-quiet`, today's `fill-control` with a `line-edge`: its day (`Today · 29`, `Wed 30`) in `meta` 600, in the ink when it has something and the secondary ink when not; under it, its things' posters 34 × 51 (`radius-thumb`, the plate while they draw); a day of one thing names it in `meta` 600, beside its poster where the cell is 120 wide and under it where it is not (two lines, a long word stepped down rather than broken); a day with more than its cell holds ends on `+2` in the secondary ink. The cells are 136 tall (a last line that does not fit is cut at the cell's edge) and grow with the words to the single-line ceiling (1.3), as the week of dots does. A picture, still: the band is one link and speaks one sentence. The lead's poster at the end of the line is not drawn there, the days carrying it.

The week is never wider than the widest phone draws it (`CalendarBand.weekMeasure`, 376: `breakpoint.split-list` less the band's margins and padding, about 54 to a day); between that and the wide band it keeps its measure under the words, at their start. Spread across a window, its seven days stop reading as one week.

The slab is `slab` under a wash of the next release's light (`titleLightProvider`, read from the poster the band drew), the neutral lamp when there is none; `AppRadius.door`, a hairline edge, padding `AppSpacing.lg` × `AppSpacing.md`.

## The line

- Something today: `Today · …`; else the next day this week: `Tomorrow · …`, `Thu · …`.
- Nothing this week while the month has something: `Nothing this week · Wed 21 Oct · Night Shift`.
- Nothing in the thirty days: `Nothing of yours in the next 30 days`, and `See what’s coming out` under it in the primary: the band still opens the calendar, whose last shelf is what is coming out.
- A calendar that did not arrive is one more line under it, a glyph in the tone of its cause and its words: `Lidarr did not answer at 20:53` for the operator, `Can't reach the server since 20:41` for the requester (the time her server first did not answer, `Can't reach the server` when the app did not see it stop). Retry lives on the page: the band is one target and holds no second one. With no rows and a calendar that did not arrive, the band says only that.

## Whose calendar

The operator's comes from every Radarr, Sonarr, Lidarr and Readarr connection, and stands whatever Seerr says: it is in the atrium even when Seerr is silent, and above the `The catalog comes from Seerr` slab when there is no Seerr. The requester's comes from her own requests, through her Seerr, and names no service.

## The consumer provides

The `events` (sorted, inside the `window`), `now`, `onTap`, and the calendars that did not arrive (`silent`, each its words and its failure) with the kinds they may be missing (`silentKinds`).

## Semantics

One link, one sentence, its parts silenced: `Calendar: today Sprite Fright, on digital, and 3 more days this week have something`; `Calendar: nothing of yours comes out in the next 30 days. See what is coming out`; a silent connection adds `albums may be missing`.

## States in the catalog

Each sheet is drawn in the dark and the light room.

- The operator's week.
- The requester's.
- Nothing of yours.
- One source down.
- Loading.
- Text at 200%: the line wraps, the strip scales its dates.
- A tablet upright with the list beside a title (860): the week of dots beside the words.
- A tablet on its side (1100): the week in posters. A desktop window: the requester's week in posters; one source down; text at 200%.

## Do / don't

- Do keep the band where the household has a calendar, whatever Seerr says.
- Don't put a second target in it, a Retry or a chip: it is one link.
