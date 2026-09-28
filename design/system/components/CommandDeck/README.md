# CommandDeck

The ⌘K panel: one field and every section, connection and recent place behind it, dropping out of the service deck strip rather than appearing mid-window.

Hand-written from `lib/features/shell/presentation/desktop/command_deck.dart`, `lib/features/shell/domain/command_deck_entry.dart` and the `_DeckOverlay` in `desktop_shell.dart`. Connection names and hosts are illustrative.

- Overlay: covers everything right of the rail and below the chrome; scrim `surface-container-lowest` at 62% (click closes), no blur. The panel is centred at the top, max 760 × 520, in its own autofocused focus scope. Entry: 200ms, `easeOutCubic`, a fade plus a slide from 6% above; never a bounce.
- Field: margin `space-sm` / `space-lg`, 34 tall, padding 0 14, `surface-container-highest`, `radius-md`, 2px `primary` border; 16px search glyph `on-surface`, 10pt; input `chrome` 13 `on-surface`, hint *Jump to a service, a title, a screen* in `dim-text`; *esc to close* `chrome` 11 500 `dim-text`.
- Panel: `space-lg` side margins, `surface-container`, 1px `outline-variant`, bottom corners 15, `level-3`. List padding `space-sm`.
- Rows: 38 tall, margin `space-sm` × 1, padding 0 11, `radius-md`. Selected (arrow keys or hover): `surface-container-highest` at 60% with a `primary` border at 50%. 15px glyph, 11pt, label `chrome` 12 500 `on-surface`, then detail `chrome` 11 `dim-text`, `space-sm` after it.
- Glyphs: a section shows its outlined tab glyph, a named screen `article` outlined, a recent `history`, all `dim-text`. A **connection** shows its service mark (`ServiceKey.icon`, a `CupolaServices` glyph) in the service accent walked with `onTint` against the selected row's wash over the panel (`surface-container-highest` at 60% over `surface-container`) — the darker of the two grounds in light theme and the lighter in dark, so the glyph holds AA whether or not its row is selected and does not shift as the selection moves. This, the Dashboard and ServiceRing are the only places every accent may appear.
- Footer: padding 10 × 20, `surface-container-low` at 90%, top `outline-variant` hairline, bottom corners 14; wraps `space-lg` × `space-xs`: *↑↓ move*, *⏎ open*, *⌥⏎ open in inspector*, *⌘1–⌘4 sections* in `chrome` 11 mono `dim-text`, then the stack headline (*13 of 16 answering*) in `chrome` 11 500.

Content and states:

- Empty query: the four sections (detail *Section*), one row per configured connection in registry order (*Radarr*, or *Radarr · 4K* for a named one; detail = the URL's host), then up to five recents as breadcrumb trails (*Dashboard › Radarr › Library*). Named Settings screens (*Connections*, *Trusted certificates*, *Appearance*, *Region*, *Hints*, *Background search*) join only when you type.
- Typed: a substring match on label, detail and service title. Nothing matched: *Nothing by that name.* in `chrome` 12 `dim-text`, padding `space-xl`.
- Keys: ↑/↓ move (wrapping), ⏎ opens, ⌥⏎ opens the inspector instead, esc closes; ⌘K again also closes. Opening a connection moves that service's lens to it first.

Each row is a button that speaks *label, detail*, reports `selected`, and hints *Open label*. The list is drawn here cut at nine rows; at 520 max height about ten rows show before it scrolls.

## Do / don't

- Do keep the footer's keys visible; it is the app's keyboard lesson.
- Don't blur what is behind the panel.
- Rows are 38 tall: the deck is a pointer-and-keyboard surface, only reached from a desktop window.
