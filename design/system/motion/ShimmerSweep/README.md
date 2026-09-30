# ShimmerSweep

The loading sweep: every placeholder block carries its own band, crossing it once every 1600ms for as long as the page loads.

Hand-written from `lib/core/widgets/shimmer_placeholder.dart` (`ShimmerPlaceholder`); the shapes are the presets on the **Skeleton** card, here in motion.

- **Loop**: one `AnimationController` per block, `shimmerDuration` 1600ms (:69), `repeat()` (:70) — the one animation in the app that runs forever, so this card loops too.
- **Value**: `Tween(-1.0 → 2.0)` on `Curves.easeInOutSine` (:72–73), exact as `cubic-bezier(0.445, 0.05, 0.55, 0.95)`.
- **Paint**: a linear gradient base → highlight → base from `Alignment(v − 1, 0)` to `Alignment(v, 0)` (:115–116). One alignment unit is half the block, so the band is half the block wide and its leading edge travels from −½ to +1 block width. Base `surfaceContainerHigh` (:86), highlight `surfaceContainer` (:87); outside the band the gradient clamps to base. CSS: a half-width `::after` translating −100% → 200% on the same curve — the same geometry.
- The strip on the right draws the band (the soft bar) against its block (the dashed box) and prints `v`.
- Blocks mounted together start together, as their controllers do; each block's band is its own, so a 14pt text line gets a short band and a 104pt card a long one.

**Reduce Motion** (:92): the controller stops and the block paints the flat base, no gradient. Here the `::after` is removed and the readout says *stopped*.

Web rendition limits: CSS keyframes run on the compositor clock, not Flutter's ticker; phase across blocks is shared rather than per-controller.

## Do / don't

- Do let the sweep run only while something is loading.
- Don't use a shimmer for a figure whose source failed: a failed figure reads `—`, and a shimmer would claim it is still coming.
- Don't show a motionless grey block as a loading state outside Reduce Motion.
