# DesktopShell

The whole desktop window assembled: chrome across the top, the section rail down the left, the service deck across the content, the page, and the optional inspector.

Hand-written from `lib/features/shell/presentation/desktop/desktop_shell.dart`, composing **WindowChrome** (with the deck), **DesktopNavRail**, **CommandDeck** and **InspectorPane**; the page's own header is **ServiceTabBar** `.header`. The page body is a labelled region; the other cards carry each strip in full.

- Used on macOS, Windows and Linux for any window 720 wide or more; below 720 (the window now narrows to 360 × 450) it paints the phone layout under a bare drag strip that keeps the traffic-light gutter, the caption buttons and the drag region. Compact below 1100, decided by width alone.
- Regions (full / compact): chrome 44 / 38 across the whole width; rail 56 wide from under the chrome to the bottom; deck 52 / 40 from the rail's edge to the right; below the deck, to the bottom of the window, a row of the page and, when open and not compact, the 9pt split handle plus the inspector (360 by default). There is no status bar: everything it printed is on screen elsewhere, and its one fact of its own — how fresh the sample is — moved into the deck (*Refreshed 2 min ago*).
- A tabbed service's page opens with `ServiceTabBar.header` — mark, name as the page heading, lens, tabs, the service's action — instead of the phone's 56pt band plus 44pt bar; the screen is lifted by the band it no longer draws. The header is opaque, not glass: it is the room light, the service accent at 12% over `surface` with a 30% bloom in its lower 11px, and the one lit surface on the page. On such a tab root the deck drops its active chip and carries no service accent; pushed pages and canonical tabs keep the chip. TrueNAS, with no tab row, keeps the band.
- The page is the branch navigator, unmodified: no desktop wrapper, because every screen is also a phone screen. Screens cap themselves with `DesktopContentWell` at 1140 (`bp-content-well`), centred at the top; at 960 the page is 904 wide and the cap never binds.
- Paint order: the page first, then chrome, rail and deck overlaid in a `Stack` — the content does not move, but the chrome comes after the route in semantics order, which keeps it in the macOS accessibility tree. The whole shell is one semantics container with explicit child nodes.
- The ⌘K overlay covers from under the chrome and right of the rail to the bottom; see **CommandDeck**.

Keys (Ctrl for ⌘ and Alt for ⌥ on Windows and Linux): ⌘K deck · ⌥I inspector · ⌘1–⌘4 sections · ⌘⌥→ / ⌘⌥← next or previous configured service · ⌘R refresh (on Settings it tests every connection and announces it) · ⌘F focus this screen's search field, if it has one · ⌥⏎ open in inspector · esc closes the deck and otherwise passes through.

The consumer is the shell screen: it passes the branch navigator, the destination list shared with the phone bar, the selected index and the selection callback.

## Do / don't

- Do keep the desktop layer an accelerator: nothing may exist only in the chrome, deck or inspector.
- Don't wrap pages in desktop-only containers.
- Don't light the chrome or the deck; the service header is the only lit band.
- The inspector is laid out only at 1100 or wider, so a 960 window never shows it even with its switch on.
