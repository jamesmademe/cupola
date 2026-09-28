# AmbientScaffold

The lit room behind every screen: an opaque floor with two soft radials of the current service's accent, and glass app-bar bands that let the light run through them.

Hand-written from `lib/core/widgets/ambient_scaffold.dart`, `ambient_background.dart` and `glass_app_bar.dart`; the service band from `features/services/presentation/service_home_screen.dart` and `service_tab_scaffold.dart`. Region blocks are placeholders.

## Anatomy

- **Room** (`AmbientBackground`): `surface`, then two `RadialGradient`s of the accent — 16% dark / 10% light (`DesignTokens.opacityAmbientGlow`) at the centre → transparent, radius 1.4 × the box's shortest side. One centred at `Alignment(-0.7, -0.9)`, one at `Alignment(0.95, 0.75)`, same strength. No accent → `primary`.
- **Drift**: an accent change tweens over 300 ms on the standard curve — the same beat as the page transition. Under Reduce Motion the room is simply the new colour.
- **Glass** (`GlassSurface`): a top-down gradient of `surface` at 55% → 28% at 55% of the height → 0 (light 60% → 32% → 0). No blur, no border, no elevation.
- **Service band (touch)**: 56 tall plus the top inset, `space-lg` sides — `chevron_left` in `on-surface-variant` (48 target, tooltip *Back to Dashboard*), 8px accent dot, 6px gap, the service name in `title-large` 700 `on-surface` (ellipsises first), the instance lens badge, then a trailing action (default `monitor_heart` outlined, tooltip *Activity*, the accent walked against `surface`). The tab band (44) is a second `GlassSurface` directly under it.
- **Desktop**: there is no band; the service's whole header is `ServiceTabBar.header`, which is **not** glass — it paints its own opaque band, the accent at 12% over `surface` with a bloom in its lower edge, so its ink can be measured (see ServiceTabBar).
- **GlassAppBar**: a transparent `AppBar` over `GlassSurface` for screens without the service band (TrueNAS hub, Settings pages); title `title-large` 700.
- The Scaffold is transparent; the body sits in the desktop content well (`bp-content-well`), the room and bars never do.

## The consumer provides

The accent (a `ServiceKey` accent, never a status tone), the body and optionally an app bar.

## Do / don't

- Do let the room carry only the service accent; status tones never light a room.
- Do keep bars as glass over the room on touch, so the light runs under them.
- Don't raise the glow: it already sits at the ceiling contrast allows, which is why the desktop header carries the room's identity instead.
- Don't paint the trailing glyph in the raw accent — walk it against the surface.
