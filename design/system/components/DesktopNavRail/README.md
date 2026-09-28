# DesktopNavRail

The desktop window's 56pt section rail: four glyphs for Dashboard, Activity, Search and Settings, and the ⌘K key at its foot.

Hand-written from `lib/features/shell/presentation/desktop/desktop_nav_rail.dart`; destinations come from `nav_tab.dart` through `shell_screen.dart`.

- 56 wide, full height under the chrome, on the window's `surface`; right hairline `outline-variant` at 55%; padding `space-md` top and bottom.
- Items: 40 × 40 buttons, `space-sm` apart, `radius-md`. Glyph 20px from **Material Symbols Rounded** (`material_symbols_icons`, `NavTab.railIcon`: `view_list`, `monitor_heart`, `search`, `settings`) at `wght` 300, `FILL` 0, `opsz` 20 — always the outline (the pill already says which one is current). Material Icons has one stroke weight and at rail size it read heavier than the type beside it; the phone bar and the touch rail keep Material Icons. Rest: glyph `on-surface-variant`. Hover: `on-surface` at 6% and the glyph `on-surface`. Selected: `primary` at 16% with a 42% `primary` border, glyph `on-surface`. The rail is always the app's indigo, never a service accent.
- Badge: 18 tall, min 18 wide, padding 0 3, `radius-full`, filled with the destination's own accent (Activity → `nav-activity`, never a status tone), a 2px collar in `surface-container-lowest`, count in `chrome` 11 600 mono tabular, coloured by `foregroundOn`. Pinned 2pt outside the glyph's top-right corner. Only Activity carries a count: finished release searches nobody has opened.
- Foot: a spacer, a 26 × 1 `outline-variant` rule, 10pt, then the ⌘K hint — a 40 × 40 button whose face is the key in `chrome` 11 mono, `dim-text` (hover `on-surface`). It opens **CommandDeck**.

The consumer provides the same `FloatingNavDestination` list the phone's bar takes (so badges and their spoken labels are defined once), the selected index and two callbacks. Every item is a real button with a tooltip of its name and key (*Activity, 2 finished searches to look at  ⌘2*); the rail is a semantics container labelled *Section navigation*, each item speaks its label and badge and reports `selected`. Keys: ⌘1–⌘4 for the sections (Ctrl+1–4 on Windows and Linux), ⌘K for the deck.

## Do / don't

- Do teach the keyboard map here: every item keeps its tooltip with the key.
- Don't colour the rail by section or service; it is always the app's indigo.
- Don't fill the selected glyph; the selected container already says which one is current.
- Items are 40 × 40, the shell's pointer size: the rail is only drawn in a desktop window.
