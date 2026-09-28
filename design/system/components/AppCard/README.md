# AppCard

The container every panel, tile and settings group is built on.

Hand-written from `lib/core/widgets/app_card.dart`.

- `filled` (default) — `surface-container`, no border, flat.
- `outlined` — transparent with 1px `outline`.
- `surfaceOutlined` — `surface-container` with the softer `outline-variant`.
- `elevated` — `surface-container` with `level-2`.
- All: `radius-md`, padding `space-lg`.
- Optional `accentColor` paints one radial service glow from the top-right at 22% — a single signature card. A grid repeating it drops to about 8%.

Press feedback: `ink` (Material ripple) where a splash reads as touch; `scale` (dip to 0.97 with a light haptic) on dense cards where a ripple would flood the surface.

The consumer provides the child, and for a tappable card a semantic label (the card speaks one sentence). **Don't** give every card a shadow — flat is the default, elevation is earned.
