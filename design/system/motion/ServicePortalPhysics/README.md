# ServicePortalPhysics

The Portal, live: drag the floating bar up and the page recedes into a card over the service matrix; release, and a spring decides whether it opens. The physics is the controller's, ported as written.

Hand-written from `lib/features/shell/presentation/service_portal.dart` (`PortalPhysics`, `ServicePortalController`, `PortalStage`), `portal_coach_mark.dart` and `shell_screen.dart`. Frame 304 × 580pt, so the card's final bottom is 34 + 0.42 × 580 = 277.6 and the travel 302.4. Poses and anatomy are on the **ServicePortal** card; this one reuses its classes.

The literals — hand-tuned on a device and signed off; they are not motion tokens and are not normalised:

| | value | line |
|---|---|---|
| `threshold` (trigger, and the bar's ceiling) | 75 | :59 |
| `baseResistance`, `falloff` (bar elastic: 0.60 ÷ (1 + lift ÷ 7)) | 0.60, 7 | :63, :66 |
| `cardAnticipation` (card follows 80% of the finger before the trigger) | 0.80 | :70 |
| `safeZone` (release beyond it opens) | 140 | :73 |
| `springStiffness`, `springDampingRatio` (mass 1) | 520, 0.95 | :76–77 |
| `flickGate` (px/s) | 700 | :81 |
| `cardTopInset`, `cardScale`, `cardCornerRadius` | 34, 0.42, 22 | :85–87 |
| `engageBlend`, `disengageBlend` | 160, 220ms | :90–91 |
| `barHome` (easeOutCubic), `barSpringBack` (elasticOut) | 260, 500ms | :94, :98 |

What happens, as `onBarDragStart/Delta/End` (:219–316) do it:

- **Before the trigger** the bar rises against the elastic and the card anticipates, `t = 0.8 × finger ÷ travel`. Moving down while lifted gives the bar back 1:1.
- **At 75** a light haptic (:246); the bar eases home over 260ms and the card's bottom edge leaps onto the finger over a 160ms `easeOutCubic` blend, then stays glued: `t = (H − clamp(startY − finger, 277.6, H)) ÷ travel`. Coming back below the height the bar had reached re-grabs it with a selection click (:253), blended over 220ms.
- **Release**: nothing opens unless the drag engaged (passed 75). Once engaged, an upward flick ≥ 700 px/s opens wherever the finger is, a downward one ≤ −700 always cancels, and otherwise it opens only beyond 140. Dragging the bar of an open Portal moves `t` 1:1 with the travel and releases on the same gate, with 0.6 as the position test. Commit fires a medium haptic (:312). The portal then runs a `SpringSimulation` (k 520, ζ 0.95, underdamped, started with the release velocity ÷ travel, :385–411), clamped to 0–1 by the controller and snapped exactly onto its target once it settles within 0.05. Velocity is estimated as Flutter's `VelocityTracker` does (quadratic least squares over the last 100ms, zero after 40ms still, fling only past 50 px/s), clamped to ±8000.
- **Card, backdrop, floor** per frame from `t` (:616–685, :488–613): top 34t, scale = height ÷ H (≥ 0.42) from the top centre, radius 0 → 22 over the first third, border and level-3 at `t`; ambient backdrop and floor fade in by (t − 0.08) ÷ 0.5; the floor takes touches from t ≥ 0.7; a tap on the card closes above t 0.9, as does the gap above the matrix, a matrix cell, or a tab.
- **The bar's own `dx`** keeps the nav bar's elastic (0.15 ÷ (1 + |x| ÷ 30), ±15, 520ms `elasticOut` back — see **NavPillTransition**).
- **Coach mark pose** at rest: 8pt above the bar, opacity `1 − 3t` (`portal_coach_mark.dart`); it arrives and leaves with a 320ms slide of 0.35 of its height and a 320ms fade (the slide is dropped under Reduce Motion); its close button fires a selection click.
- **Demo bounce** (`playDemoBounce`, :322): the bar lifts 12 over 240ms `easeOutCubic` while the card anticipates 9pt (t ≈ 0.030, capped at 0.05), holds 140ms, then returns with the real 500ms bar spring-back and the release spring. *Demo bounce* runs the shell's path (700ms after the first frame, `shell_screen.dart`); *Coach mark arrives* runs the coach mark's: a 320ms fade plus a slide up from 35% on `emphasizedCurve`, then the bounce on the next frame.

**Reduce Motion**, exactly as the app behaves:

- The gesture is untouched and the release **spring is not scaled** — `animateWith` ignores the setting — so the card still springs open and shut at full physics.
- Everything driven by `forward`/`animateTo` runs at 5% (`animation_controller.dart:651`): the engage/disengage blends (8 / 11ms), bar home (13ms), bar spring-back (25ms), the coach fade (16ms), and the demo bounce's own 240ms steps (12ms). The bar therefore snaps rather than eases.
- The shell's demo bounce is skipped (`shell_screen.dart`), and so is the coach mark's: when the pill arrives it only fades, in place, with no slide and no bounce. *Coach mark arrives* shows it with the switch on. A screen reader skips both bounces too.

Web rendition limits: no haptics (the three chips light instead); pointer events and `requestAnimationFrame` instead of Flutter's gesture arena and ticker; the floor's scroll and its 64pt over-scroll-to-close, the page snapshot (`SnapshotWidget`) and route-change closing are not ported; the matrix is stand-in cells. The page inside the card is the same stand-in as the ServicePortal card.

Do re-tune a constant only by hand on a device. Don't route `t` through a curve, and don't blur the floor.
