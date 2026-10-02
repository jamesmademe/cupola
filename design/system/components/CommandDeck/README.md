# CommandDeck

The ⌘K panel: one field and every section, connection and recent place behind it, dropping out of the service deck strip rather than appearing mid-window.

Rendered from `lib/features/shell/presentation/desktop/command_deck.dart` and `lib/features/shell/domain/command_deck_entry.dart`, laid out as the `_DeckOverlay` in `desktop_shell.dart` lays it out, by `test/design_catalog/command_deck_catalog_test.dart`. Connection names and hosts are sample data.

- Overlay: covers everything right of the rail and below the chrome (the deck strip included); scrim `surface-container-lowest` at 62% (a click closes), no blur. The panel is centred at the top, capped at 760 × 520, in its own autofocused focus scope. Entry (`CommandDeckTransition`): `duration-sm` (320ms) on `AppAnimation.emphasizedCurve` (`cubic-bezier(0.2, 0.8, 0.2, 1)`), a fade plus a slide from 6% of its height above; never a bounce. The scrim fades on the same controller.
- Field: margin `space-sm` top and bottom, `space-lg` sides; 34 tall, padding 0 14, `surface-container-highest`, `radius-md`, 2px `primary` border; a 16px search glyph in `on-surface`, 10pt; input `chrome` 13 `on-surface`, hint *Jump to a service, a title, a screen* in `chrome` 13 `dim-text`; *esc to close* `chrome` 11 / 500 `dim-text`.
- Panel: `space-lg` side margins, `surface-container`, 1px `outline-variant`, bottom corners 15 (`radius-lg` − 1), `level-3`. List padding `space-sm` top and bottom.
- Rows: 38 tall, margin `space-sm` × 1, padding 0 11, `radius-md`. Selected (arrow keys or hover): `surface-container-highest` at 60% with a `primary` border at 50%. A 15px glyph, 11pt, the label in `chrome` 12 / 500 `on-surface` (one line, ellipsised), then the detail in `chrome` 11 `dim-text`, `space-sm` before it.
- Glyphs: a section shows its tab glyph (`NavTab.icon`, the outlined Material Icon), a named screen `article` outlined, a recent `history`, all `dim-text`. A **connection** shows its service mark (`ServiceKey.icon`, a `CupolaServices` glyph) through `onTint` with the service's accent — the lamp, which resolves to the primary ink — against the selected row's wash over the panel (`surface-container-highest` at 60% over `surface-container`), so the glyph holds AA whether or not its row is selected. Monochrome: the mark's shape and the label say which service.
- Footer: spans the panel's full width (the panel keeps the field's width whatever it holds); padding 20 × 10, `surface-container-low` at 90%, a top `outline-variant` hairline, bottom corners 14; a wrap with `space-lg` × `space-xs` gaps: *↑↓ move*, *⏎ open*, *⌥⏎ open in inspector*, *⌘1–⌘4 sections*, each the key legend in `chrome` 11 mono and then what it does in `chrome` 11 (text face), all `dim-text`, then the stack headline (*13 of 16 answering*) in `chrome` 11 / 500 `dim-text`. It wraps to a second line rather than cut a key off.

Content and states:

- Empty query: the four sections (detail *Section*), one row per configured connection in registry order (*Radarr*, or *Radarr · 4K* for a named one; detail = the URL's host), then up to five recents as breadcrumb trails (*Dashboard › Radarr › Library*); the place the window stands on is left out. Named Settings screens (*Connections*, *Trusted certificates*, *Appearance*, *Region*, *Hints*, *Background search*) join only when you type.
- Typed: a case-insensitive substring match on label, detail and service title; the selection returns to the first row on every keystroke. Nothing matched: *Nothing by that name.* in `chrome` 12 `dim-text`, centred, padding `space-xl`; the panel does not shrink around it.
- Keys: ↑/↓ move (wrapping), ⏎ opens, ⌥⏎ opens the inspector instead, esc closes; ⌘K again also closes. Opening a connection moves that service's lens to it first.

Each row is a button that speaks *label, detail*, reports `selected`, and hints *Open label*. At the 520 cap about ten rows show before the list scrolls.

## States in the catalog

Each sheet is drawn in the dark and the light room, on the desktop sheet.

- An empty query, typed `radarr`, typed `cert`, nothing matched; the field holds focus in each.
- Text at 200%: an empty query and typed `radarr`.

## Do / don't

- Do keep the footer's keys visible; it is the app's keyboard lesson.
- Don't blur what is behind the panel.
- Rows are 38 tall: the deck is a pointer-and-keyboard surface, only reached from a desktop window.
