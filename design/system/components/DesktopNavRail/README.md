# DesktopNavRail

The desktop window's sidebar: the person's sections with their keys, the services with what each needs, and Settings at the foot. Home ⌘1, Discover ⌘2, Activity ⌘3 and Stack ⌘4 for the operator; Home, Discover and Requests for the requester, whose sidebar has no services. Narrower than 1100pt it folds to a 56pt rail of glyphs.

Rendered from `lib/features/shell/presentation/desktop/desktop_nav_rail.dart` by `test/design_catalog/desktop_nav_rail_catalog_test.dart`; the destinations are built from `NavTab` (`lib/features/settings/domain/nav_tab.dart`) exactly as `shell_screen.dart` builds them, and the services by `desktopRailServicesProvider` (`lib/features/shell/presentation/desktop/desktop_rail_services.dart`).

## The sidebar

- `DesktopNavRail.fullWidth` 232, full height under the chrome, no fill of its own (it sits on the window's `surface`); right hairline `outline-variant` at 55%; padding `row` (10) at the sides and `space-sm` top and bottom.
- **A row** is 44 tall (the window's target), `radius-sm`, padding 0 `row`: the glyph (20), `row` (10), the name in `row`, then at its end the section's key (`chrome` 12 mono, `dim-text`) or the service's light. Rest: glyph and name `on-surface-variant`. Hover: `fill-quiet`, ink `on-surface`. Selected: `fill-strong` with no edge, ink `on-surface`. Section glyphs are **Material Symbols Rounded** (`NavTab.railIcon`) at `wght` 300, `FILL` 0, `opsz` 20, always the outline; a service's glyph is its mark.
- **The sections** come first, in the bar's order. Activity's count of finished searches is the ink disc before its key (`primary`, a 2px collar in `surface-container-lowest`, `chrome` 11 / 600 tabular in `on-primary`, `9+` past nine).
- **Services**: under the heading `Services` (`meta`, `dim-text`), every configured service in Stack's order, each a way into its room (`/stack/{key}`). A light of 7pt at its end only where the service needs a look, from Stack health: **amber** for a fault, **red** when every connection of it did not answer, **blue** on Seerr while requests wait for approval. A calm service and one still being asked carry none: sixteen green dots would bury the one amber one. The list scrolls between the sections and Settings when the window is short.
- **In a room**, the room's row is lit in Stack's place, so one row says where the window is.
- **Settings** at the foot with its key, `⌘,`, lit while Settings is open (no section is lit beside it).
- **Larger text**: the names, keys and heading grow to 1.3, the phone bar's limit, and stop: the sidebar's width is fixed, and a name cut short at twice the size says less than a whole one a little smaller.

The deck's own key, ⌘K, is not repeated here: the deck strip carries *Jump to anything ⌘K*. The requester has neither.

## Folded

- Under `AppBreakpoints.desktopCompact` (1100): `DesktopNavRail.compactWidth` 56, the sections then a spacer and Settings, as 40 × 40 buttons `space-sm` apart, `radius-md`, each with a tooltip of its name and key (*Activity, 2 finished searches to look at  ⌘3*); selected is `fill-strong`. The services stay on Stack and the deck.
- The badge's top-left corner sits 12pt right of and 8pt above the glyph's, so a wider count grows away from the glyph, never across it, and stays inside the rail; its numeral grows to 1.2 and no further.

## The consumer provides

The same `FloatingNavDestination` list the phone's bar takes (so badges and their spoken labels are defined once), the selected index (-1 in Settings), `onDestinationSelected`, Settings (`settings`, `settingsSelected`, `onSettings`), `compact`, and for the operator the services (`DesktopRailService`: the service, its light's tone, and what the light says aloud), the room the window is in (`selectedService`) and `onService`.

## Semantics

The sidebar is a semantics container labelled *Section navigation*. Every row is a button that speaks its name with its count or its light (*Activity, 2 finished searches to look at*, *Sonarr, a fault*, *Seerr, 2 requests wait for approval*, *TrueNAS, did not answer*), its key as the hint, and reports `selected`. Keys: ⌘1–⌘4 for the sections in the bar's order (Ctrl+1–4 on Windows and Linux), ⌘, for Settings.

## States in the catalog

Each sheet is drawn in the dark and the light room, on the desktop sheet.

- The operator on the Home, with Seerr blue, Sonarr and qBittorrent amber, TrueNAS red; in Sonarr's room with two finished searches; the requester in Settings.
- Folded: Activity with two finished searches; Settings selected with twelve waiting (`9+`).
- Text at 200%: the sidebar and the folded rail on Activity with twelve waiting.

## Do / don't

- Do teach the keyboard map here: every section keeps its key in sight.
- Don't light a calm service, and don't colour a row by its section or service: the light is the only colour, and it is a tone.
- Don't fill the selected glyph; the selected row already says which one is current.
- Don't give the requester services: she reads no service.
