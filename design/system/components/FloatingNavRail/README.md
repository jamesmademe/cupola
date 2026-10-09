# FloatingNavRail

The phone's bar stood on its side, for a tablet: the person's sections in one floating pill of glass at the middle of the leading edge, each its glyph over its name, the one the person is on lit by the room's strong fill. Home, Discover, Activity and Stack for the operator; Home, Discover and Requests for the requester.

Rendered from `lib/core/widgets/floating_nav_rail.dart` by `test/design_catalog/floating_nav_rail_catalog_test.dart`; the shell (`lib/features/shell/presentation/shell_screen.dart`) draws it on a touch window from `AppBreakpoints.touchRail` (840), with the same `FloatingNavDestination`s the bar takes.

## Parts

- **The pill**: 72 wide at the default reading size: the 60pt items, 5pt of glass and the 1pt hairline on each side. It is as tall as its items, `radius-full`, the bar's glass (`glassSurface`), hairline (white at 12% in the dark room, `outline` at 85% in the light one) and lift (`AppElevation.glass`). It sits `FloatingNavRail.margin` (16) from the edge, in the vertical middle of the screen, inside the safe area on the leading side.
- **An item**: 60 × 60, the glyph (20, the bar's outlined and filled poses) over its name in `labelMedium` 500, 600 where lit, 4 between them. Ink: `on-surface` where lit, `on-surface-variant` elsewhere. Never a section's colour.
- **The lit disc**: the room's strong fill (`fill-strong`), no edge, radius 30, so a circle at the default size; it slides to the section on `emphasized`, as the bar's pill does. In Settings, which is no section, nothing is lit.
- **The count**: the bar's ink disc on the glyph's corner (`NavBadgedIcon`), `9+` past nine; only Activity carries one.
- **Larger text**: the names grow to the bar's 1.3 and stop; the pill widens to the longest name and its items grow taller, so no name is cut.
- **Under it** the shell paints the room's own light across the whole screen, so the strip the rail floats in continues the page beside it: the page's glow is centred near the same corner, and the two meet within a shade.

## Semantics

Each item is a button that speaks its name and its place, *Discover, Tab 2 of 4*, with its count when it has one (*Activity, 3 finished searches to look at*), and reports `selected`. There is no gesture: the Portal is the phone's, and on a tablet Stack is one tap away.

## States in the catalog

Each sheet is drawn in the dark and the light room, on the phone sheet.

- The operator on the Home; Activity with three finished searches; the requester on her Requests; in Settings, nothing lit.
- Text at 200%: Discover lit, twelve searches waiting (`9+`), the pill wider.

## Do / don't

- Do keep it the bar's twin: the same glass, inks, disc and count.
- Don't add Settings: it opens from Stack's gear and from the requester's account button, as on the phone.
- Don't frame the page with the rail's strip: it floats in the room, not in a column of its own.
