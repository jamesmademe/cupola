# FloatingBottomNavBar

The detached glass bar that carries a person's tabs on phones: the operator's Home, Discover, Activity, Stack, and the requester's Home, Discover, Requests (`NavTab.barFor`). Settings has no tab: it opens from Stack's gear and from the requester's account button.

Rendered from `lib/core/widgets/floating_bottom_nav_bar.dart` by `test/design_catalog/floating_bottom_nav_bar_catalog_test.dart`, with the destinations of `lib/features/settings/domain/nav_tab.dart` as `lib/features/shell/presentation/shell_screen.dart` builds them.

## The bar

- Height `FloatingNavBarMetrics.barHeight` (62, `size.tabbar`) at every reading size the bar allows (it would grow only if a glyph over its name did not fit). Outer padding `AppSpacing.lg` at the sides, `AppSpacing.sm` above, `AppSpacing.xs` plus the bottom safe area below.
- The surface is as wide as the page less its two margins: a stadium (`AppRadius.full`), `CupolaThemeColors.glassSurface` fill (the enamel step, `#1A1A1F`, at 95% dark / white at 95% light, a semi-opaque tint, deliberately not a backdrop blur, because every screen scrolls under it), lit from the room in front: a 14% sheen of its light at the top, gone by 70% of the height (`RoomSheen`, `FrontRoomLight`; a lamp room casts none), drifting to a new room's over `motion.light`, `AppElevation.glass` shadow, a 1px border (white at 12% on dark, `outline` at 85% on light), 5pt inner padding.
- **Columns of one width**, one per destination: four for the operator, three for the requester. A 320pt window narrows them and every name still fits.

## Items

- **Every destination says its name**: the glyph (20pt, the rail's size) over its name with 2pt between (`AppSpacing.xxs`), centred in its column, the name `labelMedium`, one line, ellipsised only if a column could not hold it.
- **Selected**: the pill is the whole column, edge to edge inside the 5pt padding, fully rounded; the `selectedIcon`, the name at 600, both in the primary ink (`onSurface`). **Monochrome**: the pill is the room's strong fill (`CupolaRoom.fillStrong`: white at 12% dark, ink at 12% light) with no edge, tinted in a lit room by its light (the light at 18% in the dark room, the title's day primary at 18% on paper); no section has a colour of its own. The pill slides between columns over `AppAnimation.durationSm` on the emphasised curve.
- **Unselected**: the outlined `icon`, the name at 500, both in the secondary ink (`onSurfaceVariant`); the whole column is the target.
- **Badge**: at least 15 × 15 at the default reading size and growing with the bar's clamped scaler (1.3×) rather than clipping inside a fixed height, `radius-full`, 4pt horizontal padding; its top-right corner 4pt above and 6pt beyond the icon's, clear of the name under the glyph. Filled in its tone (`navBadgeColors`): amber is `tone.amber.fill` under `tone.amber.ink` (the amber remedy's fill and ink), blue the info tone under the on-ink; a 2pt `surface` collar (the bar's ground), the count in `labelSmall` 600 tabular figures, capped at `9+`. Only Activity carries one (`activityBadgeProvider`, `lib/features/shell/presentation/activity_badge.dart`): **amber** with the faults Needs you counts, each group weighing its own count (eighteen imports blocked alike are eighteen), the operator's alone; with no fault, **blue** with the requests waiting for an answer this account may give plus the finished searches nobody has opened; nothing when nothing waits (downloads in progress ask for nothing, and a service that did not answer is the sidebar's red, not a number). A floor prints `5+`. On Activity itself the number goes: the page says it, larger. The spoken label says both counts whichever colour wins (*Activity, 3 need you, 2 requests wait for you*).

## Reading size and clearance

The bar clamps its text scale at 1.3× (`maxTextScaleFactor`). `FloatingNavBarMetrics.getScrollViewBottomPadding(context)` is the clearance a scroll view reserves so its last row can scroll above the bar; it follows the reading size and the safe area, and is 0 on a desktop window drawing the desktop shell.

## Motion

A horizontal drag rubber-bands the bar up to 15pt with growing resistance and springs back on `Curves.elasticOut` over `AppAnimation.durationXl`. When the shell attaches a `FloatingNavBarVerticalDragDelegate` (the service Portal), the vertical axis belongs to it; with a screen reader running none is attached.

## Where it is not used

At `AppBreakpoints.touchRail` (840) and wider on a touch device, the bar stands on its side: [FloatingNavRail](../FloatingNavRail/README.md), the same destinations, glyphs over names, glass and badge at the middle of the leading edge. A desktop window drawing the desktop shell navigates from [DesktopNavRail](../DesktopNavRail/README.md) instead.

## The consumer provides

`selectedIndex`, `onDestinationSelected`, the `FloatingNavDestination`s (icon, selected icon, label, badge count and its spoken sentence, and any custom semantics actions, with no colour since a destination has none), and optionally the vertical drag delegate.

## Semantics

One node per item: button, selected state, and the label *Home*, a new line, *Tab 1 of 4*. In Settings no tab is selected. A badge joins the label as a sentence (*Activity, 3 finished searches to look at*); the painted count is excluded. A destination's custom semantics actions ride on its node: the phone shell gives the Stack tab *Open the Portal*, the reader's way to the switcher the drag opens. The rails carry none.

## States in the catalog

Each sheet is drawn in the dark and the light room.

- The operator's bar with Home, Discover and Stack selected; Activity amber (3), blue (2 requests and a finished search), and 9+ past nine; on Activity itself, no number.
- Settings on screen: no tab selected, every item at rest.
- The requester's bar: Home, Discover, Requests.
- A 320pt window, where the columns narrow and every name still fits.
- Over artwork, where the glass is a tint.
- Text at 200%: Activity amber, and blue at 9+.

## Do / don't

- Do keep the pill monochrome: the strong fill under the primary ink. The number is the one hue in the bar, and only in a tone that says what it counts.
- Don't add a backdrop blur to the bar.
- Don't give a section a colour of its own, or paint a number green: a hue in permanent chrome reads as a signal, so it is only ever amber (something needs you) or blue (answers wait).
