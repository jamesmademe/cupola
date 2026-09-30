# AmbientScaffold

The lit room behind every screen: an opaque floor with two soft radials of the room's light — the neutral lamp in every room today, a service's included — and glass app-bar bands that let the light run through them.

Rendered from `lib/core/widgets/ambient_scaffold.dart`, `ambient_background.dart` and `glass_app_bar.dart`, with the service band from `lib/features/services/presentation/service_home_screen.dart` and `service_tab_scaffold.dart`, by `test/design_catalog/ambient_scaffold_catalog_test.dart`. The page bodies in the catalog are representative content.

## Anatomy

- **Room** (`AmbientBackground`): `surface`, then two `AppGradients.ambientBackground` radials of the accent — 16% dark / 10% light (`opacityAmbientGlow`) at the centre → transparent, radius 1.4 × the box's shortest side. One centred at `Alignment(-0.7, -0.9)`, one at `Alignment(0.95, 0.75)`, same strength. A service's accent is the lamp (`ServiceKey.accent`, `title-light-fallback` `#8A8A99`), and no accent → the lamp too — never `primary`, which is the near-white ink in the dark room and would light it as fog.
- **Drift**: a change of light tweens over 320ms (`AppAnimation.durationMd`) on the standard curve — the same beat as the page transition. Under Reduce Motion the room is simply the new colour.
- **Scaffold**: a transparent `Scaffold` inside the room, `extendBody` on by default. On the desktop shell the body sits in `DesktopContentWell` (centred, at most `AppBreakpoints.contentWell`, 1140, unless `contentWell: false` or another `contentWellWidth`); the room and the bars never do.
- **Glass** (`GlassSurface`): a top-down gradient of `surface` at 55% → 28% at 55% of the height → 0 (light 60% → 32% → 0). No blur, no border, no elevation.
- **Service band (touch)** (`ServiceHomeScreen`): `kToolbarHeight` (56) plus the top inset, 16 sides, over a `GlassSurface` — `chevron_left_rounded` in `onSurfaceVariant` (48 target, tooltip *Back to Dashboard*), an 8pt dot in `onSurfaceVariant` (monochrome), 6, the service name in the app bar's title style (`titleLarge` w600 `onSurface`, one line, ellipsised), the instance lens badge (name and badge share one `Expanded`, so the name gives way first and the empty width falls after the badge), then the trailing action on the right gutter (default `monitor_heart_outlined`, tooltip *Activity*, in `onSurfaceVariant`). The tab bar (`ServiceTabBar`, 44) is a second `GlassSurface` directly under it (`ServiceTabScaffold`). A tab's body clears both with 100 of top padding.
- **Desktop**: for a tabbed service there is no glass band; the whole header is `ServiceTabBar.header`, which is **not** glass — it paints its own band, the lamp at 12% over `surface` with a bloom in its lower edge, so its ink can be measured (see ServiceTabBar). The branch body is lifted by the 56 the band would have taken.
- **GlassAppBar**: a transparent `AppBar` over `GlassSurface` for screens without the service band (TrueNAS hub, Settings pages); title `titleLarge` w600.

## The consumer provides

`body`, the `accent` (the room's light: a `ServiceKey` accent, which is the lamp, never a status tone) and optionally `appBar`, `floatingActionButton`, `bottomNavigationBar`, `extendBodyBehindAppBar`, `resizeToAvoidBottomInset` and the content-well settings.

## Do / don't

- Do let the room carry only its light — the lamp until a title's light is derived; status tones never light a room, and neither does a service's brand colour.
- Do keep bars as glass over the room on touch, so the light runs under them.
- Don't raise the glow: it already sits at the ceiling contrast allows, which is why the desktop header carries the room's identity instead.
- Don't paint the band's glyphs in a colour: they are the secondary ink.
