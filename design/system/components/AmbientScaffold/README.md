# AmbientScaffold

The lit room behind every screen: an opaque floor, the room's light at the top of it (the leading title's picture, or the neutral lamp) and glass bands that paint the room again so the light runs through them.

Rendered from `lib/core/widgets/ambient_scaffold.dart`, `ambient_background.dart` and `glass_app_bar.dart`, with the service band from `lib/features/services/presentation/service_home_screen.dart` and `service_tab_scaffold.dart`, by `test/design_catalog/ambient_scaffold_catalog_test.dart`. The page bodies in the catalog are representative content.

## Anatomy

- **Room** (`AmbientBackground`, painted by `paintRoom`): `surface`, then either the **picture** (`art`, the title's light baked by `bakeRoomArt`: one texture scaled into a box 630 wide or 0.64 of a wider room, 60 above the top, 640 tall, at 0.72, under a scrim of `surface` at 12% → 50% at 300 (60% on paper) → 94% at 540 → whole at 640) or the **lamp** (an ellipse of the accent hung 40 below the top centre, 230 tall and 0.42 × (width + 160) wide up to 480, `opacityAmbientGlow` 0.42 dark / 0.14 light at its centre → transparent at its rim). No accent → the lamp (`title-light-fallback` `#8A8A99`), never `primary`, which is the near-white ink in the dark room and would light it as fog. A room with no light of its own inside a `RoomLightScope` (a service's tabs) takes the scope's.
- **Drift**: a change of the lamp's colour tweens over 320ms (`AppAnimation.durationMd`, or `accentDuration`) on the standard curve; a new picture comes up over `motion.light` (1500ms) and the old one fades under it. Under Reduce Motion the room is simply the new light.
- **Scaffold**: a transparent `Scaffold` inside the room, `extendBody` on by default. On the desktop shell the body sits in `DesktopContentWell` (centred, at most `AppBreakpoints.contentWell`, 1140, unless `contentWell: false` or another `contentWellWidth`); the room and the bars never do.
- **Glass** (`GlassSurface`): the room painted again (`AmbientRoom.paint`) at 55% → 28% at 55% of the height → 0 (light 60% → 32% → 0), so at rest it cannot be seen; outside a room, the flat ground. No blur, no border, no elevation.
- **Under the bar** (the fade): with an `appBar`, a vertical scroll view whose top is the body's top is covered, once scrolled, by the room itself (`AmbientRoom`: ground, picture and lamp, laid out across the room's whole box) over the 24 (`AppSpacing.xl`) below the bar's edge, whole at the edge, 55% at 45% of the strip, gone at its foot; its strength follows the first 24 scrolled, so a list at rest is drawn whole. What passes the edge melts into the light around it, with no line where the body starts and no step where the glow is. A list under a fixed field or header is left alone, unless the header fades it too: a body that is not a list sits under the page's name in `TitledBody`, whose `ScrollEdgeFade` is the same strip at the name's foot. No blur; the one layer is the strip itself.
- **A page's name** (`GlassAppBar.inPage`, `PageTitle`): a pushed page and Settings say their name at the top of their content in the `room` role (30 / 31) in the ink, `space-xs` above, `space-lg` below, with a line under it in the meta role in the secondary ink when there is one (`space-s` between). The bar holds the way back and the actions only; once the body's own vertical scroll view has gone 40 under the bar, the name comes into the bar in the `section` role and goes when it comes back (`PageScrollScope`, fed from above the bar and the body).
- **Under the clock** (`StatusBarScrim`): for a page that scrolls under the status bar with no bar of its own (the tab roots: Home, Discover, Activity, Stack, Requests; the media page, a person's page), the room painted again at 92% to 72% across the top inset, then to 0 over `AppSpacing.lg` below it, so a lit room keeps its light up to the top edge. No blur; nothing without a top inset. The bars' glyphs follow the room everywhere (`ThemedSystemBars` around the app): light over the dark room, dark over the light one.
- **Service band (touch)** (`ServiceHomeScreen`): `kToolbarHeight` (56) plus the top inset, 16 sides, over a `GlassSurface`: the 44 back plate (`MediaPlate`, `fill-control` under `line-edge`, `radius-control`, `chevron_left_rounded` 26 in the ink, tooltip *Back to Stack*), 12, the service's mark in a 36 tile (`ServiceMarkTile`: `fill-strong` under `line-edge`, the mark in the ink), 8, the service name in the feature role (Bricolage 26, one line, ellipsised), the instance lens badge (name and badge share one `Expanded`, so the name gives way first and the empty width falls after the badge), then the trailing action on the right gutter (default `vital_signs` from Material Symbols, Activity's glyph, tooltip *Activity*, in `onSurfaceVariant`). The tab bar (`ServiceTabBar`, 44) is a second `GlassSurface` directly under it (`ServiceTabScaffold`). A tab's body clears both with 100 of top padding.
- **Desktop**: for a tabbed service there is no glass band; the whole header is `ServiceTabBar.header`, which is **not** glass: it paints its own band, the lamp at 12% over `surface` with a bloom in its lower edge, so its ink can be measured (see ServiceTabBar). The branch body is lifted by the 56 the band would have taken.
- **GlassAppBar**: a transparent `AppBar` over `GlassSurface` for screens without the service band (TrueNAS hub, Settings pages); title in the feature role (Bricolage 26) in the ink. On the desktop shell over a welled body the glass stays full-bleed and the bar's leading, title, actions and bottom move in by the well's margin (`ContentWellScope`, which `AmbientScaffold` puts around every page), so the title lines up with the body under it; on touch and over a body with `contentWell: false` it is the plain bar.

## The consumer provides

`body`, the `accent` (the room's light: a `ServiceKey` accent, which is the lamp, never a status tone) and optionally `appBar`, `floatingActionButton`, `bottomNavigationBar`, `extendBodyBehindAppBar`, `resizeToAvoidBottomInset` and the content-well settings.

## States in the catalog

Each sheet is drawn in the dark and the light room; the home also on the desktop.

- Radarr's service home on touch with its two glass bands, the TrueNAS hub with `GlassAppBar`, a list scrolled under a `GlassAppBar` melting into the room at its edge, `AmbientBackground` alone with and without an accent.
- The TrueNAS hub on a 1328pt desktop window: the glass full width, the title over the well.
- Text at 200%: the Radarr home and the TrueNAS hub.

## Do / don't

- Do let the room carry only its light: the leading title's picture, else the lamp; status tones never light a room, and neither does a service's brand colour.
- Do keep bars as glass over the room on touch, so the light runs under them.
- Don't cover content under a bar with a flat colour: the room has a glow, and a flat patch reads as a step against it. Paint the room again (`AmbientRoom.paint`).
- Don't blur anything live to light a room: the picture is baked once, small, and only scaled here (the No-Blur-Under-Scroll Rule).
- Don't paint the band's glyphs in a colour: they are the secondary ink.
