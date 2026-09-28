# DesktopShell

The whole desktop window assembled: chrome across the top, the section rail down the left, the service deck across the content, the page, and the optional inspector.

Rendered from `lib/features/shell/presentation/desktop/desktop_shell.dart` by `test/design_catalog/desktop_shell_catalog_test.dart`, composing **WindowChrome** (with the deck), **DesktopNavRail**, **CommandDeck** and **InspectorPane**; the page shown is Radarr's Overview under its **ServiceTabBar** `.header`, with sample data. The other cards carry each strip in full.

- Used on macOS, Windows and Linux for any window 720 wide or more (`AppBreakpoints.desktopMobile`). Below 720 — the window narrows to 360 × 450 — the shell screen paints the phone layout under a bare `WindowDragStrip` (trail *Cupola*) that keeps the traffic-light gutter, the caption buttons and the drag region. Compact below 1100 (`desktopCompact`), decided by width alone.
- Regions (full / compact): chrome 44 / 38 across the whole width; rail 56 wide from under the chrome to the bottom; deck 52 / 40 from the rail's edge to the right; below the deck, to the bottom of the window, a row of the page and — when the inspector is open and the window is not compact — the 9pt split handle plus the inspector (360 by default). There is no status bar: its one fact of its own, how fresh the sample is, lives in the deck (*Refreshed 2 min ago*).
- A tabbed service's page opens with `ServiceTabBar.header` — mark, name as the page heading, lens, tabs, the service's action — instead of the phone's 56pt band plus 44pt bar; `ServiceTabScaffold` lifts the screen by the 56pt band it no longer draws. The header is opaque, not glass: it is the room light, the service accent at 12% over `surface` with a 30% bloom in its lower 11pt, and the one lit surface on the page. On such a tab root the deck drops its active chip and carries no service accent; pushed pages and canonical tabs keep the chip. TrueNAS, with no tab row, keeps the band.
- The page is the branch navigator, unmodified: no desktop wrapper, because every screen is also a phone screen. Screens cap themselves with `DesktopContentWell` at 1140 (`bp-content-well`), centred at the top; at 960 the page is 904 wide and the cap never binds.
- Paint order: the page first, then chrome, rail and deck overlaid in a `Stack` — the content does not move, but the chrome comes after the route in semantics order, which keeps it in the macOS accessibility tree. The whole shell is one semantics container with explicit child nodes.
- The ⌘K overlay covers from under the chrome and right of the rail to the bottom, deck strip included; see **CommandDeck**. It opens and closes on one 200ms controller.

Keys (Ctrl for ⌘ and Alt for ⌥ on Windows and Linux): ⌘K deck (again to close) · ⌥I inspector · ⌘1–⌘4 sections · ⌘⌥→ / ⌘⌥← next or previous configured service, wrapping · ⌘R refresh the current section (on Settings it tests every connection and announces it) and stamps the deck's freshness · ⌘F focus this screen's search field, if it has one · ⌥⏎ open the inspector · esc closes the deck and otherwise passes through.

The consumer is the shell screen: it passes the branch navigator (`navigationShell`), the destination list shared with the phone bar, the selected index and `onDestinationSelected`. The shell records each location it sees as a recent for the deck.

## Do / don't

- Do keep the desktop layer an accelerator: nothing may exist only in the chrome, deck or inspector.
- Don't wrap pages in desktop-only containers.
- Don't light the chrome or the deck; the service header is the only lit band.
- The inspector is laid out only at 1100 or wider, so a 960 window never shows it even with its switch on.
