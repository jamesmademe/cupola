# RailArrows

Back and forward for a row of posters, in the row's heading: a mouse cannot swipe.

Rendered from `lib/core/widgets/rail_arrows.dart` by `test/design_catalog/rail_arrows_catalog_test.dart`.

- **When**: where there is a pointer (a desktop, or a tablet with a trackpad or mouse attached, `MouseTracker.mouseIsConnected`) and the row runs past the window. A row that fits has none; a touch screen with nothing pointing at it has none.
- **Where**: at the end of the heading (`SectionHeader.rail`, `HomeModuleFrame.rail`), never over the posters. The row itself runs to the window's edge with no fade: the cut poster says there is more.
- **Look**: two `IconButton`s, `chevron_left_rounded` and `chevron_right_rounded` at 22 in `on-surface`, each a 44pt target (`VisualDensity.standard`). At the start the first is off, at the end the second, drawn in `dimText`; both stay in place so the heading never shifts.
- **Step**: 85% of the visible row (`RailArrows.step`), so the poster cut at the edge comes back whole as the first of the next view; `motion.standard` (320ms), a jump under Reduce Motion.
- **Semantics and focus**: silent, and never focusable. A screen reader walks the row's tiles; Tab reaches each tile and scrolls it into view.

## The consumer provides

A `builder` that lays out the heading and the row: the row's horizontal scroll view takes the `controller`, the heading takes `arrows` (null when there are none). A row built below a heading it does not own (`ServiceOverviewSection.bleed`) reads the controller with `RailArrows.controllerOf(context)`.

Used by `DiscoverCarousel` (the Home's shelves and Discover's rows), the Home's Arrived, and the poster rails of the Radarr, Sonarr, Lidarr, Seerr and stream Overviews.

## States in the catalog

Each sheet is drawn in the dark and the light room.

- Desktop: at the start (‹ off) under a heading that opens the rest; partway along under a heading with a link; at the end (› off); a row that fits (none).
- The phone, with no pointer: none.
- Text at 200%: the title grows, the arrows keep their size and line.

## Do / don't

- Do give every horizontal row of posters its arrows on a page a pointer reaches.
- Don't lay them over the posters, and don't fade the row's edge to hint at more.
- Don't make them focusable: the keyboard walks the tiles.
