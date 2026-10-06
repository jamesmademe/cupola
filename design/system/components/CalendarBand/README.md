# CalendarBand

The calendar's way in from the top of the Discover atrium, full width above the doors: the one live object there. It names the next thing of the household's, shows its poster, and dots this week; the whole band opens the calendar.

Rendered from `lib/features/discover/presentation/widgets/calendar_band.dart` (`CalendarBand`), with its words from `lib/features/discover/domain/library_calendar.dart` (`CalendarDigest`), by `test/design_catalog/calendar_band_catalog_test.dart`. The atrium mounts it through `DiscoverCalendarBand` (`lib/features/discover/presentation/discover_calendar_band.dart`).

## Variants

- **The band** (`CalendarBand`): `Calendar` in the section role with the chevron of a shelf's header (`chevron_right_rounded` in the primary); under it one line, its first words in the label role at 600 in ink and the rest at 400 in `inkSecondary`: `Today · Sprite Fright · on digital`. A movie says its release, never a time; an episode its code and time (`Tomorrow · Night Shift · S2 E5 at 22:00`). The next thing's poster sits at the right, 36 × 54, `AppRadius.thumb`, with the poster shadow in its light. Under them the week ([CalendarWeekStrip](../CalendarWeekStrip/README.md), `.band`).
- **Loading** (`CalendarBand.loading`): the same frame with a plate where the line will be and the week without dots, so the atrium does not jump when the calendars arrive.

The slab is `slab` under a wash of the next release's light (`titleLightProvider`, read from the poster the band drew), the neutral lamp when there is none; `AppRadius.door`, a hairline edge, padding `AppSpacing.lg` × `AppSpacing.md`.

## The line

- Something today: `Today · …`; else the next day this week: `Tomorrow · …`, `Thu · …`.
- Nothing this week while the month has something: `Nothing this week · Wed 21 Oct · Night Shift`.
- Nothing in the thirty days: `Nothing of yours in the next 30 days`, and `See what’s coming out` under it in the primary: the band still opens the calendar, whose last shelf is what is coming out.
- A calendar that did not arrive is one more line under it, a glyph in the tone of its cause and its words: `Lidarr did not answer at 20:53` for the operator, `Can't reach the server since 20:41` for the requester. Retry lives on the page: the band is one target and holds no second one. With no rows and a calendar that did not arrive, the band says only that.

## Whose calendar

The operator's comes from every Radarr, Sonarr, Lidarr and Readarr connection, and stands whatever Seerr says: it is in the atrium even when Seerr is silent, and above the `The catalogue comes from Seerr` slab when there is no Seerr. The requester's comes from her own requests, through her Seerr, and names no service.

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

## Do / don't

- Do keep the band where the household has a calendar, whatever Seerr says.
- Don't put a second target in it, a Retry or a chip: it is one link.
