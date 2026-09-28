# ServicePortal

The phone's service switcher: drag the floating nav bar upward and the current screen recedes into a card at the top, revealing the service matrix underneath; tap a service to travel.

Hand-written from `lib/features/shell/presentation/service_portal.dart` (`PortalPhysics`, `ServicePortalController`, `PortalStage`) and `portal_coach_mark.dart`. The three poses are static; the page inside the card and the matrix are stand-in blocks (see the ServiceMatrix card for the cells). Geometry is resolved for a 304 × 580pt frame.

Poses, as a function of the portal value `t` (0 closed, 1 open):

- **Card** (the page, frozen to a texture from the first frame `t > 0`): top = 34·t; bottom edge = H − t·(H − (34 + 0.42·H)); scale = height ÷ H, never below 0.42, from the top centre. Corner radius 0 → 22 over the first third of `t`; a 1px border (white at 14%·t in dark, `outline` at 85%·t in light) and `level-3` with both shadows' alpha × t. Radius and border sit inside the scale, so at `t = 1` they read 9.2 and 0.4. The mapping is linear on purpose: easing belongs to the finger and the spring, never to the map. At `t > 0.9` a tap on the card closes.
- **Backdrop** (under the card): the ambient ground — `surface` plus two `primary` glows at 16% dark / 10% light, radius 1.4 × the short side, at (−0.7, −0.9) and (0.95, 0.75) — faded in by (t − 0.08) ÷ 0.5.
- **Floor** (over the card, same fade): a transparent spacer down to the card's live bottom edge + `space-md` (tapping it closes), a 56pt fade from clear to `surface` at 90%, then `surface` at 90% carrying the `ServiceMatrix` in its picker role, padded `space-lg`. It takes touches only from `t ≥ 0.7`; over-scrolling it down past 64pt at `t > 0.9` closes. No blur.
- **At rest** (`t = 0`): nothing is mounted but the page. The coach mark sits `space-sm` above the bar: `surface-container-high`, `radius-lg`, 1px white at 12% (dark) or `outline` (light), `level-2`, `space-lg` leading padding, *Swipe up to open the Portal* in `label-large` at 600, a `close` 16px button (*Turn this hint off*). It fades out as `t` rises (opacity 1 − 3t). It arrives with a 200ms fade and a slide up from 35% of its height (`emphasizedCurve`); under Reduce Motion it only fades, in place.

Physics — hand-tuned on the interactive mock and signed off; these literals are the design and are not motion tokens:

- `threshold` 75.0 — finger travel that triggers, and the bar's vertical ceiling.
- `baseResistance` 0.60, `falloff` 7.0 — the bar's elastic before the trigger: resistance = 0.60 ÷ (1 + lift ÷ 7.0).
- `cardAnticipation` 0.80 — before the trigger the card follows 80% of the finger's travel.
- At the trigger: a light haptic; the bar eases home over `barHome` 260ms (`easeOutCubic`); the card's bottom edge leaps onto the finger over `engageBlend` 160ms and stays glued. Retreating below the bar's height re-grabs it with a selection click, blended over `disengageBlend` 220ms.
- Release: completes only beyond `safeZone` 140.0, or with an upward flick past `flickGate` 700 px/s; a downward flick always cancels. Medium haptic on commit.
- Spring: `springStiffness` 520.0, `springDampingRatio` 0.95, mass 1; it snaps exactly to its target when it settles within 0.05. The bar springs back over `barSpringBack` 500ms on `elasticOut`. The portal controller's nominal duration is 400ms.
- Demo bounce (once on first run, when the coach mark arrives, or from Settings › Hints): the bar lifts 12 and the card anticipates about 9pt over 240ms, holds 140ms, then returns with the real release spring.
- Closes from a tab tap, a tap on the card or the spacer, the floor pull-down, a drag down on the bar, or any route change under the card (which expands the frozen departure screen before revealing the destination).

The consumer is the phone shell: it owns the controller, hands it to the nav bar as its vertical-drag delegate and wraps the branch navigator in `PortalStage`. The coach mark appears after three manual service switches without the Portal and retires the first time it is opened.

Accessibility: under a screen reader (`accessibleNavigation`) the drag delegate and the coach mark are withheld and switching stays on the accessible paths. The demo bounce is skipped under Reduce Motion and under a screen reader — including the one the coach mark would play on arrival; the gesture itself is not.

## Do / don't

- Do re-tune by hand on a device if a constant must change. The physics durations (160, 220, 240, 260, 400, 500ms) sit off the motion ladder deliberately; don't normalise them.
- Don't route `t` through a curve.
- Don't blur the floor.
