# DesktopShell

The whole desktop window assembled: one strip across the top (on a Mac, beside a full-height sidebar), the sidebar down the left, the page, and the inspector when a download is chosen.

Rendered from `lib/features/shell/presentation/desktop/desktop_shell.dart` by `test/design_catalog/desktop_shell_catalog_test.dart`, composing **WindowChrome**, **DesktopNavRail**, **CommandDeck** and **InspectorPane**; the page shown is Radarr's Overview under its **ServiceTabBar** `.header`, with sample data. The other cards carry each strip in full.

- Used on macOS, Windows and Linux for any window 720 wide or more (`AppBreakpoints.desktopMobile`). Below 720, where the window narrows to 360 × 450, the shell screen paints the phone layout under a bare `WindowDragStrip` (trail *Cupola*) that keeps the traffic-light gutter, the caption buttons and the drag region. Compact below 1100 (`desktopCompact`), decided by width alone.
- Regions (full / compact): on Windows and Linux the strip 44 / 38 across the whole width and the sidebar 240 wide (the folded rail 56, by width or by its switch) from under the strip to the bottom. On a Mac the strip is the unified toolbar's 52 at every width, and a full sidebar runs the window's height, the traffic lights and its switch in its 52pt head (`SidebarHead`), the strip starting at its edge, as a Mac's own windows with a sidebar are drawn; folded, the strip spans the window over the rail as elsewhere. The catalog draws no traffic lights: the OS does; right of the sidebar, from under the strip to the bottom of the window, a row of the page and, when a download is chosen, the inspector is switched on and the window is not compact, the 9pt split handle plus the inspector (360 by default). With nothing chosen the inspector is not laid out and its switch is dimmed: the queue sits at the foot of the sidebar as In flight. There is no deck strip and no status bar: the room is the sidebar's lit row and the page's header, the stack's health the sidebar's counts and Stack, and on Activity the strip says who answered and when.
- A tabbed service's page opens with `ServiceTabBar.header` (mark, name as the page heading, lens, tabs, the service's action) instead of the phone's 56pt band plus 44pt bar; `ServiceTabScaffold` lifts the screen by the 56pt band it no longer draws. The header is opaque, not glass: it is the room light, the lamp (the service's accent is the lamp) at 12% over `surface` with a 30% bloom in its lower 11pt, and the one lit surface on the page. TrueNAS, with no tab row, keeps the band.
- The page is the branch navigator, unmodified: no desktop wrapper, because every screen is also a phone screen. Screens cap themselves with `DesktopContentWell` at 1140 (`bp-content-well`), centred at the top; at 960 the page is 904 wide and the cap never binds. A page read as one column, the requester's Requests, stops at the reading well, 720 (`AppBreakpoints.wellInset`), centred, as it does on a tablet; the Home pairs its short modules from 780 and goes to two columns from 960 (**HomeModule**).
- **The requester's window** is her sections and nothing of the stack's: her three sections and Settings in the sidebar, no services, no In flight, no inspector and no ⌥I, no ⌘⌥→, and no command deck: ⌘K does nothing, since the deck reaches every room and connection by name.
- Paint order: the page first, then the strip and the sidebar overlaid in a `Stack`; the content does not move, but the chrome comes after the route in semantics order, which keeps it in the macOS accessibility tree. The whole shell is one semantics container with explicit child nodes.
- The ⌘K overlay covers from under the strip and right of the sidebar to the bottom; see **CommandDeck**. It opens and closes on one 320ms controller.

Keys (Ctrl for ⌘ and Alt for ⌥ on Windows and Linux; the full list in **WindowChrome**'s ShortcutsSheet, ⌘/): ⌘K deck (again to close) · ⌥I inspector, when a download is chosen · ⌘[ / ⌘] back and forward (Alt+← / Alt+→) · ⌃⌘S the sidebar (Ctrl+Shift+S) · ⌘1–⌘4 sections · ⌘⌥→ / ⌘⌥← next or previous configured service, wrapping · ⌘R refresh the current section (on Settings it tests every connection and announces it; on Activity the strip's answer line does the same on a click) · ⌘F focus this screen's search field, if it has one · ⌘/ every key · esc closes the deck and otherwise passes through.

The consumer is the shell screen: it passes the branch navigator (`navigationShell`), the destination list shared with the phone bar, the selected index and `onDestinationSelected`. The shell records each location it sees as a recent for the deck and as a step of the window's history for back and forward.

## States in the catalog

Each sheet is drawn in the dark and the light room, on the desktop sheet.

- A 1280 × 800 window with nothing chosen (no inspector, its switch dimmed), and a 960 × 640 window with the folded rail.
- Text at 200%: the 1280 × 800 window.

## Do / don't

- Do keep the desktop layer an accelerator: nothing may exist only in the strip or the inspector.
- Don't wrap pages in desktop-only containers.
- Don't light the strip; the service header is the only lit band.
- The inspector is laid out only at 1100 or wider and only on a choice, so a 960 window never shows it, and a wide one shows it only beside the download you chose.
