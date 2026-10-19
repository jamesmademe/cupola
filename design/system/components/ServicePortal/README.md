# ServicePortal

The phone's service switcher: drag the floating nav bar upward and the current screen recedes into a card at the top, revealing the service matrix underneath; tap a service to travel.

Rendered from `lib/features/shell/presentation/service_portal.dart` (`PortalPhysics`, `ServicePortalController`, `PortalStage`) and `portal_coach_mark.dart` by `test/design_catalog/service_portal_catalog_test.dart`, composed as the phone shell composes them, over Radarr's Overview, at three values of `t` on a 390 × 844 phone. The poses are still frames; the motion is described below. See the ServiceMatrix card for the cells.

Poses, as a function of the portal value `t` (0 closed, 1 open), for a screen `H` tall:

- **Card** (the page, frozen to a texture from the first frame `t > 0`): top = 34·t; bottom edge = H − t·(H − (34 + 0.42·H)); scale = height ÷ H, never below 0.42, from the top centre. Corner radius 0 → 22 over the first third of `t`; a 1px border (white at 14%·t in dark, `outline` at 85%·t in light) and `level-3` with both shadows' alpha × t. Radius and border sit inside the scale, so at `t = 1` they read 9.2 and 0.4. The mapping is linear on purpose: easing belongs to the finger and the spring, never to the map. At `t > 0.9` a tap on the card closes.
- **Backdrop** (under the card): `AmbientBackground` with no accent: `surface` and the neutral lamp (`title-light-fallback`) hung at the top centre, 42% dark / 14% light at its centre (see AmbientScaffold), faded in by (t − 0.08) ÷ 0.5.
- **Floor** (over the card, same fade): a transparent spacer down to the card's live bottom edge + `space-md` (tapping it closes), a 56pt fade from clear to `surface` at 90%, then `surface` at 90% carrying the `ServiceMatrix` in its picker role, padded `space-lg` at the sides and by the nav bar's height at the bottom. It takes touches only from `t ≥ 0.7`; over-scrolling it down past 64pt at `t > 0.9` closes. No blur.
- **At rest** (`t = 0`): nothing is mounted but the page. The coach mark sits `space-sm` above the bar: `surface-container-high`, `radius-lg`, 1px white at 12% (dark) or `outline` (light), `level-2`, `space-lg` leading padding, *Swipe up to open the Portal* in `label-large` at 600 (it wraps inside the mark at a large reading size rather than running off the screen), `space-xs`, then a 16px `close` button (*Turn this hint off*, the same switch as Settings › Hints). It fades out as `t` rises (opacity 1 − 3t). It arrives with a `duration-sm` (320ms) fade and a slide up from 35% of its height (`emphasizedCurve`); under Reduce Motion it only fades, in place.

Physics: hand-tuned on the interactive mock and signed off; these literals are the design and are not motion tokens:

- `threshold` 75.0: finger travel that triggers, and the bar's vertical ceiling.
- `baseResistance` 0.60, `falloff` 7.0: the bar's elastic before the trigger: resistance = 0.60 ÷ (1 + lift ÷ 7.0).
- `cardAnticipation` 0.80: before the trigger the card follows 80% of the finger's travel.
- At the trigger: a light haptic; the bar eases home over `barHome` 260ms (`easeOutCubic`); the card's bottom edge leaps onto the finger over `engageBlend` 160ms and stays glued. Retreating below the bar's height re-grabs it with a selection click, blended over `disengageBlend` 220ms.
- Release: completes only beyond `safeZone` 140.0, or with an upward flick past `flickGate` 700 px/s; a downward flick past the gate always cancels. Medium haptic on commit.
- Spring: `springStiffness` 520.0, `springDampingRatio` 0.95, mass 1; it snaps exactly to its target when it settles within 0.05. The bar springs back over `barSpringBack` 500ms on `elasticOut`. The portal controller's nominal duration is 400ms.
- Demo bounce (once, 700ms after the shell's first frame, and when the coach mark arrives; turning Settings › Hints › Portal back on owes it again at the next launch): the bar lifts 12 and the card anticipates about 9pt over 240ms, holds 140ms, then returns with the real release spring. The one-shot plays only where the Portal is drawn and counts as seen only when it plays: a desktop window between 720 and 839pt draws the desktop shell and leaves it owed, and so does a finger already on the bar.
- Closes from a tab tap, a tap on the card or the spacer, the floor pull-down, a drag down on the bar, a tap on a matrix cell, the system back (Android's button and gesture) or Escape on a keyboard, or any route change under the card (which expands the frozen departure screen before revealing the destination). Back and Escape close the Portal and nothing else: the room it lifted comes back, and the page under it is not popped.

The consumer is the phone shell: it owns the controller, hands it to the nav bar as its `verticalDragDelegate` and wraps the branch navigator in `PortalStage`, with `PortalCoachMark` beside it. While the Portal covers the page, `covering` tells whatever polls under it to stop. The coach mark appears after three manual service switches without the Portal and retires the first time it is opened.

Accessibility: a screen reader never needs the drag. Under one (`accessibleNavigation`) the drag delegate and the coach mark are withheld, and the Stack tab of the bar carries a custom action, *Open the Portal*, that opens it with the release spring from rest (`openFromUi`); Voice Control and Switch Access see the same action. Opening it, by either way, makes one announcement at the commit, counted from the floor's own cells and probes: *Portal open. 12 services, 3 with a fault.*; *1 with a fault*, *none with a fault* only once every probe has answered, *2 checking* while probes are out, never a pending request. A fault is what the picker draws as one: a connection that did not answer, or one that answered but refused. While `t > 0` the card is hidden from the reader as it is inert to the finger, and the spacer above the matrix is a button named *Close the Portal*. The demo bounce is skipped under Reduce Motion and under a screen reader, including the one the coach mark would play on arrival; the gesture itself is not. The announcement goes through `announce()`, and both readers hear it once: VoiceOver as a native announcement; TalkBack, whose engine has no announcement channel, through the app's one polite live region (`AnnouncementHost`, mounted around every route in `MaterialApp.builder`, so hiding the card from the reader does not hide the sentence).

## States in the catalog

Each sheet is drawn in the dark and the light room.

- `PortalStage` at rest with the coach mark, mid-gesture (t = 0.45), open (t = 1) with the picker.
- Text at 200%: at rest with the coach mark, and open.

## Do / don't

- Do re-tune by hand on a device if a constant must change. The physics durations (160, 220, 240, 260, 400, 500ms) sit off the motion ladder deliberately; don't normalise them.
- Don't route `t` through a curve.
- Don't blur the floor.
