# ServiceRing

The stack as a dial: every service is a dot on one circle around the Cupola mark, and a service that answers draws a spoke in to it.

Rendered from `lib/core/widgets/service_ring.dart` by `test/design_catalog/service_ring_catalog_test.dart`. The centre is `assets/brand/cupola_mark.png` (see **Logos**) at `markFraction` of the diameter, 0.42 by default (`ServiceRing.defaultMarkFraction`). Hosts: the Dashboard's empty state (268, spinning) and onboarding (interpolating its own diameter, 0.34 mark at its 132 compact ceiling).

- **Geometry**: the diameter comes from the caller, usually through `serviceRingDiameter(context, preferred:)`, which divides the preferred size by the reading size (clamped 1–1.6×, so 268 becomes 168 at 1.6×) and fits it between 96 and the width available. Circle radius = diameter / 2 − 14. One slot per `ServiceKey` (seventeen) in four domain arcs (Media, Downloads, Stream, Infrastructure, in `ServiceDomain` and registry order), with 1.7 slot-widths of gap between arcs; the first node sits half a gap plus half a slot past noon.
- **Track**: a 1pt circle in `onSurfaceVariant` at 30%, plus a ±5pt tick where each domain arc begins.
- **Progress**: a 1.5pt round-capped arc from noon clockwise, the primary ink (`onSurface`) at 50%. None at 0.
- **Nodes** — **unlit**: 4pt radius, `onSurfaceVariant` at 55% (80% light). **Picked**: 5pt, the primary ink at 78%. **Connected**: 6pt, the full primary ink, a radial halo 3.4 × the radius at 34% (42% light) and a 1.5pt spoke from 0.34 × the circle radius out to 9pt short of the node, fading from 5% to 55% (70% light) — halo and spoke in the service's accent, which is the lamp: the light around an ink node. **Silent**: 5pt in `onSurfaceVariant` with a 1pt collar at 35% — drained, never recoloured. The **active** service (`activeService`, the one being configured) adds the halo and a collar in the primary ink at 60%, at radius + 4, when it is picked, connected or silent (an unlit node stays plain).
- **Entrance**: `entrance` (0–1) places the nodes on a circle of `entrance` × the radius and fades the mark to match; the track stays put.
- **Motion**: every node property, the progress and the track interpolate over 420ms (`AppAnimation.durationLg`) on the emphasised curve when `states`, `activeService` or `progress` change; spokes grow outward. `spin` adds a 96 s revolution — the app's one ambient motion, only where the ring is the subject. Reduce Motion stops the revolution and snaps changes instead of animating them.

Monochrome: every node is the same ink and every halo the same lamp — which service a node is, the chips under the ring say in words — and nothing on the ring borrows a status tone. The consumer provides `states` (a `ServiceKey` → `ServiceRingState` map; a missing key is unlit), `diameter`, and optionally `entrance`, `progress`, `activeService`, `spin` and `markFraction`.

The ring speaks one sentence and excludes everything beneath it: *8 of 17 chosen, 4 answering, 1 did not answer*, or *17 services, none set up yet*.

The same file carries `OnePunchline`, the claim beside the ring on onboarding: *A Cupola over / your lab.* in `displayMedium` (42, w600) at 1.10 leading unless a `style` is passed, all in `onSurface`: the display face and the line break carry the claim, not a hue (it used to set *Cupola* in the brand indigo and the second line in a section cyan). It speaks the sentence once.

## Do / don't

- Do keep the ring monochrome — ink nodes, lamp halos; nothing on the ring borrows a status tone or a brand colour.
- Don't recolour a silent service: drain it, because hue is identity, not health.
- Don't spin the ring anywhere it is not the subject.
