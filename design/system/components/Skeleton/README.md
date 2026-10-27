# Skeleton

Loading placeholders in the shape of what is coming, swept by one slow band so a page still loading never looks like a page that loaded empty. The sweep itself is `ShimmerSweep`'s card; this one shows the shapes.

Rendered from `lib/core/widgets/shimmer_placeholder.dart` (`ShimmerPlaceholder`, `ShimmerList`, `ShimmerGrid`), `lib/core/widgets/app_skeleton.dart` (`AppSkeleton`) and `lib/core/widgets/list_rows_shimmer.dart` (`ListRowsShimmer`) by `test/design_catalog/skeleton_catalog_test.dart`.

## Values

- Fill: base `CupolaRoom.fillSkeleton` (`fill.skeleton`: white 8% in the dark room, ink 8% in the day room), highlight `fillSkeletonGlint` (`fill.skeleton-glint`: white 14% · white 55%), alphas so a block reads on the ground, a slab and a lit header alike and the band always passes as light. A linear gradient base / highlight / base from `Alignment(v − 1, 0)` to `Alignment(v, 0)` as `v` runs −1 → 2 on a 1600ms (`AppAnimation.shimmerDuration`) `easeInOutSine` cycle, one `AnimationController` per block.
- **Reduce Motion** (`MediaQuery.disableAnimationsOf`): the controller stops and the block paints the flat base colour, no gradient.
- Shapes: `.card` → `AppRadius.borderRadiusMd`; `.text` → `AppRadius.borderRadiusXs`, 14 tall by default; the bare constructor takes whatever `borderRadius` it is given (none by default, so square).

## Presets

- `AppSkeleton.listRows()` (`ShimmerList`): 5 cards 104pt tall by default (the settled height of an activity tile, so nothing jumps on load), 8pt apart, `AppSpacing.lg` padding. `ShimmerList.page` is the scrolling twin for a skeleton that is the whole page.
- `ListRowsShimmer()`: dashboard section rows: 4 rows 60pt tall by default, `AppSpacing.lg` side padding, `AppSpacing.sm` below each; the card's `AppRadius.md` corners (`ShimmerPlaceholder.card`), the radius of the rows it stands in for.
- `AppSkeleton.posterRow()`: 168pt tall at 2:3 (112 wide), `AppSpacing.md` apart, `AppSpacing.lg` side padding, 6 posters by default, not scrollable.
- `AppSkeleton.posterGrid()` (`ShimmerGrid`): 3 columns at 2:3, 12pt gaps, `AppSpacing.lg` padding, 9 cells by default. Needs a bounded height from its host; it is a plain `GridView.builder`, not shrink-wrapped.
- `AppSkeleton.detailBody()`: a 220pt backdrop band (no radius), then a 96 × 144 `AppRadius.borderRadiusMd` poster beside lines of 200 × 22, 120 and 160, then after `AppSpacing.xl` two full-width lines and one of 240.

## Consumer provides

Only counts and heights: `AppSkeleton`'s presets take no colour or shape parameters.

## Semantics

The blocks carry no semantics, so the loading state is silent unless the surrounding screen announces it.

## States in the catalog

Each sheet is drawn in the dark and the light room.

- The bare shapes, `listRows`, `ListRowsShimmer`, `posterRow`, `posterGrid`, `detailBody`.
- Reduce Motion: the flat base colour, no gradient.
- Text at 200%: the list rows and the poster row.

## Do / don't

- Do match the preset to the row it stands in for; a skeleton shorter than its content makes the page jump on settle.
- Don't show a motionless grey block as a loading state outside Reduce Motion: that shape means an empty well in this app.
