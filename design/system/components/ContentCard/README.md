# ContentCard

The grid tile's picture: cached artwork in a `radius-md` clip at `level-2`, with an optional badge in the top-right corner.

Rendered from `lib/core/widgets/content_card.dart` by `test/design_catalog/content_card_catalog_test.dart`.

- **Box** — `radius-md` (12), `AppElevation.level2` — the same resting shadow as `MediaPosterCard`, so the shared-element flight between a grid and a detail hero never pops a different shadow — and `Clip.antiAlias`. The image is `BoxFit.cover`, loaded through the pinned image cache (`pinnedImageCacheFor`). It fills its parent: `MediaGrid` and the browse wall give it a 2 : 3 cell.
- **Badge corner** — `badge` (a compact `StatusBadge` in every grid) sits top-right with `space-sm` (8) padding over `AppGradients.serviceGlow(colorScheme.shadow, radius: ContentCard.badgeGlowRadius)` (0.5): shadow ink at 22% fading to nothing from the card's top-right corner, painted across the whole card so it reaches zero at half the card's width — before any edge. It used to be painted in a box the size of the badge, which cut the radial off at a third of its strength and drew a hard-edged grey rectangle round the badge on any ground that was not dark artwork. `colorScheme.shadow` is black in dark and `on-surface` ink in light. The corner is a legibility aid for the badge over artwork.
- **Loading** — the shared `ShimmerPlaceholder`, `surface-container-high` sweeping to `surface-container` over 1500ms; under Reduce Motion a flat `surface-container-high` block.
- **No URL** (null or empty) — the plate, `AppColors.plateSurface`, with `Icons.movie_outlined` at 32 in `plateDimInk`. **Load failed** — the same plate with `Icons.broken_image_outlined`, same size and ink. The same well as `MediaPosterCard`'s fallback in both themes: a missing poster is not palette, and the tile is the source of the Hero flight into a detail hero drawn by `MediaPosterCard`, so a theme surface here turned a white light-theme tile into a dark well mid-flight.
- **Tap** — `onTap` wraps the card in `PressableScale` (0.97, light haptic, no scale under Reduce Motion); nothing else changes on screen. `MediaGrid` and the browse wall pass none and wrap the tile themselves, so the tap and the spoken name belong to the tile.

The consumer provides `imageUrl` (required, nullable), optional `httpHeaders` and `badge`, and optional `onTap`. The card has no `Hero`: the caller wraps it in one and references `MediaPosterCard.flightOnUserGestures`.

Semantics: the card publishes no label of its own. The enclosing tile names it — in `MediaGrid` one button named by the title with the status as its value — and passes `excludeFromSemantics: true` to the badge so the status is not read twice.

Do: let the tile own the tap and the spoken sentence, and keep the badge compact. Don't: add a second shadow level or a border — the flight between grid and hero relies on this exact `level-2`.
