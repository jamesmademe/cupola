# Skeleton

Loading placeholders in the shape of what is coming, swept by one slow band so a page still loading never looks like a page that loaded empty.

Hand-written from `lib/core/widgets/shimmer_placeholder.dart` (`ShimmerPlaceholder`, `ShimmerList`, `ShimmerGrid`), `lib/core/widgets/app_skeleton.dart` (`AppSkeleton`) and `lib/core/widgets/list_rows_shimmer.dart` (`ListRowsShimmer`). The preview freezes the sweep; the frames are static.

## Values

- Base `surface-container-high`, highlight `surface-container`. The fill is a linear gradient base / highlight / base (stops 0, 0.5, 1) from `Alignment(v − 1, 0)` to `Alignment(v, 0)`: the band is half the block wide and travels left to right as `v` runs −1 → 2.
- Motion: one `AnimationController` per block, repeating every 1500ms (`AppAnimation.shimmerDuration`) on `easeInOutSine`. The strip at the right shows four instants of one cycle.
- **Reduce Motion** (`MediaQuery.disableAnimations`): the controller stops and the block paints the flat base, no gradient.
- Shapes: `.card` → `radius-md`; `.text` → `radius-xs`, 14 tall by default; `.circle`; the bare constructor takes whatever radius it is given (none by default).

## Presets

- `AppSkeleton.listRows` — `ShimmerList`: 5 cards 104 tall (the settled height of an activity tile, so nothing jumps), 8 apart, padding `space-lg`. `ShimmerList.page` is the scrolling twin for a skeleton that is the whole page.
- `ListRowsShimmer` — dashboard sections: 4 rows 60 tall, `space-lg` side padding, `space-sm` below each; square corners.
- `AppSkeleton.posterRow` — 168 tall at 2:3 (112 wide), `space-md` apart, `space-lg` side padding, 6 posters, not scrollable.
- `AppSkeleton.posterGrid` — `ShimmerGrid`: 3 columns at 2:3, 12 gaps, padding `space-lg`, 9 cells (not drawn here).
- `AppSkeleton.detailBody` — a 220 backdrop band (no radius), then a 96 × 144 `radius-md` poster beside lines of 200 × 22, 120 and 160, then after `space-xl` two full-width lines and one of 240.
- The Interactive Search sheet uses six 104 `radius-md` blocks under its status line (see **ReleaseRow**).

## Consumer provides

Only counts and heights.

## Semantics

The blocks carry no semantics, so the loading state is silent unless the surrounding screen announces it.

## Do / don't

- Do match the preset to the row it stands in for; a skeleton shorter than its content makes the page jump on settle.
- Don't show a motionless grey block as a loading state: that shape means an empty well in this app.
