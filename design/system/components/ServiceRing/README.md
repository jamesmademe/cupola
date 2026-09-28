# ServiceRing

The stack as a dial: every service is a dot on one circle around the Cupola mark, and a service that answers draws a spoke in to it.

Hand-written from `lib/core/widgets/service_ring.dart`. The centre is a labelled placeholder: the real widget draws `assets/brand/cupola_mark.png` (see **Logos**) at 42% of the diameter. The node states shown are an illustrative mid-walk.

- **Geometry**: diameter from the caller (268 preferred on the Dashboard's empty state; the onboarding ring interpolates its own), shrunk by the reading size down to 96. Circle radius = diameter/2 − 14. Seventeen slots in four domain arcs (Media, Downloads, Stream, Infrastructure, in registry order), with 1.7 node-widths of gap between arcs; the first node sits half a gap plus half a slot past noon.
- **Track**: 1px circle in `on-surface-variant` at 30%, plus a ±5px tick where each domain arc begins.
- **Progress**: a 1.5px round-capped arc from noon clockwise, the brand indigo (`seerr` byte, fixed in both themes) at 50%.
- **Nodes** — **unlit**: 4px, `on-surface-variant` at 55% (80% light). **Picked**: 5px, accent at 78%. **Connected**: 6px, full accent, a radial halo 3.4 × the radius at 34% (42% light), and a 1.5px spoke from 0.34 × radius out to 9px short of the node, fading from 5% to 55% (70% light) of the accent. **Silent**: 5px in `on-surface-variant` with a 1px collar at 35% — drained, never recoloured. The **active** service (being configured) adds the halo and a collar at accent 60%, radius + 4.
- **Motion**: every node property interpolates over 400ms on the emphasised curve; spokes grow outward. `spin` adds a 96s revolution — the app's one ambient motion, only where the ring is the subject. Reduce Motion stops the sweep and removes the transition.

Accents are confined to each service's own node (the Room Light Rule's sanctioned exception); nothing on the ring borrows a status tone. It paints dots only — the legend's marks (`ServiceKey.icon`, the `CupolaServices` glyph, accent walked against `surface`) are specimen annotation for identification, not part of the widget. The consumer provides `states`, `diameter`, `entrance`, `progress`, `activeService` and `spin`.

The ring speaks one sentence: *8 of 17 chosen, 4 answering, 1 not answering*, or *17 services, none set up yet*.

The same file carries `OnePunchline`, the one-line claim beside the ring on onboarding: `display-medium` by default at the role's own weight (800 for display) with 1.10 leading, the display floor.

## Do / don't

- Do keep every accent on its own node; nothing on the ring borrows a status tone.
- Don't recolour a silent service: drain it, because hue is identity, not health.
- Don't spin the ring anywhere it is not the subject.
