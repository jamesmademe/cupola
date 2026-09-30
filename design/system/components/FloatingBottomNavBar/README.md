# FloatingBottomNavBar

The detached glass bar that carries the four canonical tabs on phones: Dashboard, Activity, Search, Settings.

Rendered from `lib/core/widgets/floating_bottom_nav_bar.dart` by `test/design_catalog/floating_bottom_nav_bar_catalog_test.dart`, with the destinations of `lib/features/settings/domain/nav_tab.dart` as `lib/features/shell/presentation/shell_screen.dart` builds them.

## The bar

- Height `FloatingNavBarMetrics.barHeight` (60) at the default reading size, growing to fit its pill at larger ones. Outer padding `AppSpacing.lg` at the sides, `AppSpacing.sm` above, `AppSpacing.xs` plus the bottom safe area below.
- The surface is only as wide as its items want — the widest selected pill plus 52pt per other item and the gaps — centred, and never wider than the space it is given.
- `AppRadius.borderRadiusXl` (30), `CupolaThemeColors.glassSurface` fill (the enamel step, `#1A1A1F`, at 95% dark / white at 95% light — a semi-opaque tint, deliberately not a backdrop blur, because every screen scrolls under it), `AppElevation.glass` shadow, a 1px border (white at 12% on dark, `outline` at 85% on light), 6pt inner padding.

## Items

- **Selected**: a pill at least 36pt tall, `AppRadius.pill` (fully rounded), at least 84pt wide, 14pt horizontal padding, `selectedIcon` + label with a 6pt gap. **Monochrome**: the pill is the room's strong fill (`CupolaRoom.fillStrong` — white at 12% dark, ink at 12% light) with no edge, and the icon and label are the primary ink (`onSurface`), the same in every section — no section has a colour of its own. Label `labelMedium` at 600, one line. The pill slides between items over `AppAnimation.durationSm` on the emphasised curve, and the item scales to 1.02.
- **Unselected**: `icon` only (the outlined variant), 20pt, `onSurfaceVariant`, on a 48 × 48 minimum target; the item slot is 52pt, tightening to 48 when space runs out.
- Gap between items: 6pt, or 4pt when the bar's inner width is under `breakpointNavCompact` (360).
- **Badge**: at least 15 × 15 at the default reading size and growing with the bar's clamped scaler (1.3×) rather than clipping inside a fixed height, `radius-full`, 4pt horizontal padding; its top-right corner 4pt above and 6pt beyond the icon's, and while the item is selected the label moves right by the same 6pt so it keeps its own 6pt gap from the badge's ring. The **ink disc**: filled with `primary` (the primary ink), never a status tone and never a section's colour, a 1.5pt `surface` ring, the count in `labelSmall` 600 tabular figures in `onPrimary` (the on-ink), capped at `9+`. Only Activity carries one: finished searches nobody has opened.

## Reading size and clearance

The bar clamps its text scale at 1.3× (`maxTextScaleFactor`). `FloatingNavBarMetrics.getScrollViewBottomPadding(context)` is the clearance a scroll view reserves so its last row can scroll above the bar; it follows the reading size and the safe area, and is 0 on a desktop window drawing the desktop shell.

## Motion

A horizontal drag rubber-bands the bar up to 15pt with growing resistance and springs back on `Curves.elasticOut` over `AppAnimation.durationXl`. When the shell attaches a `FloatingNavBarVerticalDragDelegate` (the service Portal), the vertical axis belongs to it; with a screen reader running none is attached.

## Where it is not used

At `AppBreakpoints.touchRail` (840) and wider on a touch device, a `NavigationRail` takes over with the same destinations, labels and badges on `surfaceContainerLow` with the theme's `secondaryContainer` indicator. A desktop window drawing the desktop shell navigates from `DesktopNavRail` instead.

## The consumer provides

`selectedIndex`, `onDestinationSelected`, the `FloatingNavDestination`s (icon, selected icon, label, badge count and its spoken sentence, and any custom semantics actions — no colour: a destination has none), and optionally the vertical drag delegate.

## Semantics

One node per item: button, selected state, and the label *Dashboard*, a new line, *Tab 1 of 4*. A badge joins the label as a sentence (*Activity, 3 finished searches to look at*); the painted count is excluded. A destination's custom semantics actions ride on its node: the phone shell gives the Dashboard tab *Open the Portal*, the reader's way to the switcher the drag opens. The rails carry none.

## Do / don't

- Do keep the pill and the badge monochrome: the strong fill under the primary ink, the ink disc under the on-ink.
- Don't add a backdrop blur to the bar.
- Don't paint a badge in a status tone, or give a section a colour of its own — a hue in permanent chrome reads as a signal.
