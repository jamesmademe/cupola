# DesktopNavRail

The desktop window's sidebar: the person's sections, the services in Stack's domains with what each needs, what is in flight, and Settings at the foot. Home ⌘1, Discover ⌘2, Activity ⌘3 and Stack ⌘4 for the operator; Home, Discover and Requests for the requester, whose sidebar has no services and nothing in flight. Narrower than 1100pt it folds to a 56pt rail of glyphs.

Rendered from `lib/features/shell/presentation/desktop/desktop_nav_rail.dart` by `test/design_catalog/desktop_nav_rail_catalog_test.dart`; the destinations are built from `NavTab` (`lib/features/settings/domain/nav_tab.dart`) exactly as `shell_screen.dart` builds them, the services by `desktopRailServicesProvider` and Stack's figure by `desktopStackFigureProvider` (`lib/features/shell/presentation/desktop/desktop_rail_services.dart`), and In flight by `InFlightGlance` (`lib/features/shell/presentation/desktop/in_flight_glance.dart`).

## The sidebar

- `DesktopNavRail.fullWidth` 240, full height under the chrome, no fill of its own (it sits on the window's `surface`); right hairline `outline-variant` at 55%; padding `row` (10) at the sides and `space-sm` top and bottom.
- **A row** is 44 tall (the window's target), `radius-sm`, padding 0 `row`: the glyph (20), `row` (10), the name in `row`, then at its end what the row has to say: a count, Stack's figure, a light, or, while the pointer is on it, its key (`chrome` 12 mono, `dim-text`). The key is always the row's hint; printed on every row it was a keyboard map nobody had asked to read. Rest: glyph and name `on-surface-variant`. Hover: `fill-quiet`, ink `on-surface`. Selected: `fill-strong` with no edge, ink `on-surface`. Section glyphs are **Material Symbols Rounded** (`NavTab.railIcon`) at `wght` 300, `FILL` 0, `opsz` 20, always the outline; a service's glyph is its mark.
- **The sections** come first, in the bar's order. Activity's count of finished searches is the ink disc (`primary`, a 2px collar in `surface-container-lowest`, `chrome` 11 / 600 tabular in `on-primary`, `9+` past nine). Stack carries how many services answer, `10/11` (`chrome` 12 tabular, `dim-text`), as the Home's header counts them; nothing while every light is still being asked.
- **Services**: every configured service in Stack's order under its domain's heading (`Media`, `Downloads`, `Stream`, `Infrastructure`; `meta`, `dim-text`; a domain with no service set up has no heading), each a way into its room (`/stack/{key}`). At its end, what waits on the person: **a count** where there is one, the things to fix in that service (the fault decisions Needs you counts, each group by its size: `18` beside Sonarr for eighteen imports; a floor, `50+`, when the queue walk stopped short) in **amber**, and on Seerr the requests waiting for approval in **blue**; the count is the tone on an 18% wash of it (`chrome` 11 / 600 tabular, 20 tall, `radius-full`). A fault with no count (a refused key, a server reached that never replied) keeps the 7pt **amber** light. A service whose every connection did not answer says *Did not answer* under its name in **red** (`meta`), its name in `dim-text`. A calm service and one still being asked carry nothing: sixteen green dots would bury the one amber one. The list scrolls between the sections and In flight when the window is short.
- **In a room**, the room's row is lit in Stack's place, so one row says where the window is.
- **In flight** above Settings (`InFlightGlance`): the Home's Downloads folded to two lines, so the downloads stay a glance away without an inspector held open for them. How many move and their summed rate, in the readout's words (`3 moving`, `40.4 MB/s`; `Nothing moving` beside a stuck one), one 4pt bar per transfer up to six (blue moving, amber stuck, `+3` past six), and under them `1 stuck` in amber; `Nothing in flight` with `2 queued` when nothing moves; `Reading downloads…`; `Downloads could not be read`. `fill-quiet` at half, hairline `outline-variant` 45%, `radius-md`, 44 at least; hover `fill-quiet`. A press opens Activity; on Activity it is not drawn, the page being the whole of it. Read again every 30s while on screen (`sidebarInFlightPollProvider`, the Home's sources and clock).
- **Settings** at the foot, its key `⌘,` in its hint and under the pointer, lit while Settings is open (no section is lit beside it).
- **Larger text**: the names, keys and heading grow to 1.3, the phone bar's limit, and stop: the sidebar's width is fixed, and a name cut short at twice the size says less than a whole one a little smaller.

The deck's own key, ⌘K, is not repeated here: the window's strip carries *Jump to… ⌘K*. The requester has neither.

## Folded

- Under `AppBreakpoints.desktopCompact` (1100): `DesktopNavRail.compactWidth` 56, the sections then a spacer and Settings, as 40 × 40 buttons `space-sm` apart, `radius-md`, each with a tooltip of its name and key (*Activity, 2 finished searches to look at  ⌘3*); selected is `fill-strong`. The services stay on Stack and the deck.
- The badge's top-left corner sits 12pt right of and 8pt above the glyph's, so a wider count grows away from the glyph, never across it, and stays inside the rail; its numeral grows to 1.2 and no further.

## The consumer provides

The same `FloatingNavDestination` list the phone's bar takes (so badges and their spoken labels are defined once), the selected index (-1 in Settings), `onDestinationSelected`, Settings (`settings`, `settingsSelected`, `onSettings`), `compact`, and for the operator the services (`DesktopRailService`: the service, its light's tone, and what the light says aloud), the room the window is in (`selectedService`) and `onService`.

## Semantics

The sidebar is a semantics container labelled *Section navigation*. Every row is a button that speaks its name with what it says (*Activity, 2 finished searches to look at*, *Stack, 10 of 11 answering*, *Sonarr, 18 need you*, *qBittorrent, a fault*, *Seerr, 2 requests wait for approval*, *TrueNAS, did not answer*), its key as the hint, and reports `selected`. In flight is one button: *3 moving, at 40.4 megabytes a second, 1 stuck. Open Activity*. Keys: ⌘1–⌘4 for the sections in the bar's order (Ctrl+1–4 on Windows and Linux), ⌘, for Settings.

## States in the catalog

Each sheet is drawn in the dark and the light room, on the desktop sheet.

- The operator on the Home: Stack's figure, Seerr's 2 in blue, Sonarr's 18 in amber, qBittorrent's light, TrueNAS silent, In flight with one stuck; in Sonarr's room with two finished searches; on Activity, with no In flight; In flight empty, reading and unread; the requester in Settings.
- Folded: Activity with two finished searches; Settings selected with twelve waiting (`9+`).
- Text at 200%: the sidebar and the folded rail on Activity with twelve waiting.

## Do / don't

- Do keep every key in its row's hint and under the pointer: the map is there to learn, without a column of it.
- Don't light a calm service, and don't colour a row by its section or service: the count and the light are the only colour, and they are tones.
- Don't print a count the stack does not hold: a fault with no number keeps its light.
- Don't fill the selected glyph; the selected row already says which one is current.
- Don't give the requester services: she reads no service.
