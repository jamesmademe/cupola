# DesktopNavRail

The desktop window's 56pt section rail: a glyph for each tab of the person's bar (Home, Discover, Activity and Stack for the operator; Home, Discover and Requests for the requester), and at its foot Settings and the ⌘K key.

Rendered from `lib/features/shell/presentation/desktop/desktop_nav_rail.dart` by `test/design_catalog/desktop_nav_rail_catalog_test.dart`; the destinations are built from `NavTab` (`lib/features/settings/domain/nav_tab.dart`) exactly as `shell_screen.dart` builds them.

- `DesktopNavRail.width` 56, full height under the chrome, with no fill of its own (it sits on the window's `surface`); right hairline `outline-variant` at 55%; padding `space-md` top and bottom.
- Items: 40 × 40 buttons, `space-sm` apart, `radius-md`. Glyph 20px from **Material Symbols Rounded** (`material_symbols_icons`, `NavTab.railIcon`: `view_list`, `monitor_heart`, `search`, `settings`) at `wght` 300, `FILL` 0, `opsz` 20 — always the outline, because the pill already says which one is current. Material Icons has one stroke weight and at rail size it read heavier than the type beside it; the phone bar and the touch rail keep Material Icons. Rest: glyph `on-surface-variant`. Hover: `on-surface` at 6% and the glyph `on-surface`. Selected: the room's strong fill (`fill-strong`) with no edge, glyph `on-surface` — the phone bar's pill. The rail is monochrome: never a section's or a service's colour.
- Badge: at least 18 tall and 18 wide (a floor, not a height: the numeral grows with the reading size up to 1.2×, `_RailBadge.maxScale`, and the disc with it; a fixed 18 cut `9+` at 200%), padding 0 3, `radius-full`, the ink disc — filled with `primary` (the primary ink), never a status tone and never a section's colour — a 2px collar in `surface-container-lowest`, the count in `chrome` 11 / 600 tabular in `on-primary` (a figure: text face, never mono). Its top-left corner sits 12pt right of and 8pt above the glyph's, so a wider count grows away from the glyph, never across it: the badge only ever covers the glyph's top-right corner and stays inside the 56pt rail. The count is capped at `9+` (`FloatingNavDestination.badgeLabel`, the phone bar's rule too). Only Activity carries a count: finished release searches nobody has opened.
- Foot: a spacer, Settings (the same item as a section, its tooltip *Settings  ⌘,*, selected while Settings is open), 8pt, a 26 × 1 `outline-variant` rule, 10pt, then the ⌘K hint — a 40 × 40 button whose face is the key in `chrome` 11 mono, `dim-text` (hover `on-surface`). It opens **CommandDeck**, and speaks *Jump to anything, ⌘K* with the hint *Open the command deck*.

The consumer provides the same `FloatingNavDestination` list the phone's bar takes (so badges and their spoken labels are defined once), the selected index (-1 in Settings, which is no section), `onDestinationSelected`, Settings (`settings`, `settingsSelected`, `onSettings`) and `onCommandDeck`. Every item is a real button with a tooltip of its name and key (*Activity, 2 finished searches to look at  ⌘2*); the rail is a semantics container labelled *Section navigation*, and each item speaks its label and badge and reports `selected`. Keys: ⌘1–⌘4 for the sections in the bar's order (Ctrl+1–4 on Windows and Linux), ⌘, for Settings, ⌘K for the deck.

## States in the catalog

Each sheet is drawn in the dark and the light room, on the desktop sheet.

- Home selected, Activity selected with two finished searches, Settings selected at the foot with twelve waiting (`9+`) and no section lit.
- Text at 200%: Activity with the `9+` badge, whole, short of the rail's hairline.

## Do / don't

- Do teach the keyboard map here: every item keeps its tooltip with the key.
- Don't colour the rail by section or service; it is always the app's ink.
- Don't fill the selected glyph; the selected container already says which one is current.
- Items are 40 × 40, the shell's pointer size: the rail is only drawn in a desktop window.
