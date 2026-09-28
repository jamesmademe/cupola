# MotionTokens

The app's whole motion ladder: five durations, two curves, a shimmer cycle and a confirmation hold, raced against each other so the differences are visible rather than read.

Hand-written from `lib/core/app_animation.dart`; the durations are defined in `design/tokens/core.json` and reach the code through the generated `DesignTokens`. Each bar runs 0 → 1 over its duration on the curve you pick; the plot draws both curves from the same evaluator the bars use.

- **Durations**: `durationXs` 100ms, `durationSm` 200ms, `durationMd` 300ms, `durationLg` 400ms, `durationXl` 500ms. The lane captions name where each one is actually used in this group (press dip and nav scale bump; nav pill, badge switcher and reel roll; progress-ring sweep; ring node states; nav spring-back).
- **Curves**: `standardCurve` = `Curves.easeInOutCubicEmphasized`, `emphasizedCurve` = `Curves.easeOutCubic`. The names are the other way round from what they suggest: "emphasized" is the plain ease-out that almost every widget uses, and "standard" is the emphasised curve, used by a handful (the progress-ring sweep, the ambient background, onboarding).
- **shimmerDuration** 1500ms: one sweep of the loading band, on `easeInOutSine`, repeating (see **ShimmerSweep**).
- **confirmationHold** 1600ms: how long a success check replaces a button's glyph. It is a `Timer`, not an animation, so the lane fills linearly and the chip reverts when it ends.

How the curves are rendered here:

- `easeOutCubic` is exact: `cubic-bezier(0.215, 0.61, 0.355, 1)` (Flutter `curves.dart:1669`).
- `easeInOutCubicEmphasized` is a `ThreePointCubic` — two Béziers meeting at (0.166666, 0.4), with control points (0.05, 0), (0.133333, 0.06) | (0.208333, 0.82), (0.25, 1) (`curves.dart:1777`). The scripts evaluate it exactly, porting Flutter's `Cubic.transform` bisection (error bound 0.001). Where CSS needs it, use this 26-stop `linear()`, max error 0.004:
  `linear(0 0%, 0.0079 3.12%, 0.0329 6.25%, 0.0804 9.38%, 0.1158 10.94%, 0.1622 12.5%, 0.2245 14.06%, 0.2644 14.84%, 0.313 15.62%, 0.3749 16.41%, 0.4508 17.19%, 0.5174 17.97%, 0.5711 18.75%, 0.614 19.53%, 0.6488 20.31%, 0.7022 21.88%, 0.7418 23.44%, 0.7728 25%, 0.8192 28.12%, 0.8528 31.25%, 0.8989 37.5%, 0.9293 43.75%, 0.9506 50%, 0.9773 62.5%, 0.9914 75%, 1 100%)`.
  No single `cubic-bezier` fits it: the best one found, `cubic-bezier(0.283, 0.174, 0, 1.288)`, is off by up to 0.07.

**Reduce Motion.** Nothing in `app_animation.dart` reads the setting. What happens is Flutter's own rule: an `AnimationController` driven by `forward`/`animateTo` under `disableAnimations` runs at **5% of its duration** (`animation_controller.dart:651`, Flutter 3.38.7). That covers every implicit animation (`AnimatedContainer`, `AnimatedScale`, `AnimatedSwitcher`, …): 100 → 5ms, 200 → 10ms, 300 → 15ms, 400 → 20ms, 500 → 25ms — about one frame. The switch shows those numbers. A `repeat()` loop is **not** scaled, so each looping widget has to stop itself; the shimmer does, so its lane stops. A spring started with `animateWith` is not scaled either (see **ServicePortalPhysics**). The 1600ms hold is a timer and is unchanged.

Web rendition limits: bars are driven by `requestAnimationFrame`, not Flutter's vsync ticker, so a frame can land a few ms either side of Flutter's; the shape of each curve is exact.

Do reach for a token before writing a literal. Don't read "emphasized" as "the emphasised curve".
