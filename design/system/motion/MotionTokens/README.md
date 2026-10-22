# MotionTokens

The app's whole motion ladder: five durations, the one ease under its two names, a shimmer cycle and a confirmation hold, raced against each other so the differences are visible rather than read.

Hand-written from `lib/core/app_animation.dart`; the durations are defined in `design/tokens/core.json` and reach the code through the generated `DesignTokens`. Each bar runs 0 → 1 over its duration on the curve you pick; the plot draws both curves from the same evaluator the bars use.

- **Durations**: `durationXs` 180ms, `durationSm` 320ms, `durationMd` 320ms, `durationLg` 420ms, `durationXl` 520ms. The lane captions name where each one is actually used in this group (press dip and nav scale bump; nav pill, badge switcher and reel roll; progress-ring sweep; ring node states; nav spring-back).
- **Curves**: `standardCurve` and `emphasizedCurve` are the same ease, `Cubic(0.2, 0.8, 0.2, 1)`: a fast start and a long settle, one curve for press, state, pager and entrance. Both names are kept so the call sites stand, which is why the two plots coincide.
- **shimmerDuration** 1600ms: one sweep of the loading band, on `easeInOutSine`, repeating (see **ShimmerSweep**).
- **confirmationHold** 1600ms: how long a success check replaces a button's glyph. It is a `Timer`, not an animation, so the lane fills linearly and the chip reverts when it ends.

How the curves are rendered here:

- `Cubic(0.2, 0.8, 0.2, 1)` is exact in CSS: `cubic-bezier(0.2, 0.8, 0.2, 1)`. The scripts evaluate it by porting Flutter's `Cubic.transform` bisection (error bound 0.001).
- The shimmer's `easeInOutSine` is exact too: `cubic-bezier(0.445, 0.05, 0.55, 0.95)`.

**Reduce Motion.** Nothing in `app_animation.dart` reads the setting. What happens is Flutter's own rule: an `AnimationController` driven by `forward`/`animateTo` under `disableAnimations` runs at **5% of its duration** (`animation_controller.dart:651`, Flutter 3.47.7). That covers every implicit animation (`AnimatedContainer`, `AnimatedScale`, `AnimatedSwitcher`, …): 180 → 9ms, 320 → 16ms, 420 → 21ms, 520 → 26ms, about one frame. The switch shows those numbers. A `repeat()` loop is **not** scaled, so each looping widget has to stop itself; the shimmer does, so its lane stops. A spring started with `animateWith` is not scaled either (see **ServicePortalPhysics**). The 1600ms hold is a timer and is unchanged.

Web rendition limits: bars are driven by `requestAnimationFrame`, not Flutter's vsync ticker, so a frame can land a few ms either side of Flutter's; the shape of each curve is exact.

Do reach for a token before writing a literal. Don't read a difference into `standardCurve` and `emphasizedCurve`: they are the one ease.
