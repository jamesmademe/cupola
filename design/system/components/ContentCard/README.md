# ContentCard

The grid tile's picture: cached artwork in a `radius-md` clip at `level-2`, with an optional badge in the top-right corner.

Rendered from `lib/core/widgets/content_card.dart` by `test/design_catalog/content_card_catalog_test.dart`.

- **Box** — `radius-md` (12), `AppElevation.level2` — the same resting shadow as `MediaPosterCard`, so the shared-element flight between a grid and a detail hero never pops a different shadow — and `Clip.antiAlias`. The image is `BoxFit.cover`, loaded through the pinned image cache (`pinnedImageCacheFor`). It fills its parent: `MediaGrid` and the browse wall give it a 2 : 3 cell.
- **Badge corner** — `badge` (a compact `StatusBadge` in every grid) sits top-right with `space-sm` (8) padding over `AppGradients.serviceGlow(colorScheme.shadow, radius: 1.5)`: shadow ink at 22% fading to nothing from the top-right corner of the badge's own box. `colorScheme.shadow` is black in dark and `on-surface` ink in light. The corner is a legibility aid for the badge over artwork.
- **Loading** — the shared `ShimmerPlaceholder`, `surface-container-high` sweeping to `surface-container` over 1500ms; under Reduce Motion a flat `surface-container-high` block.
- **No URL** (null or empty) — `surface-container` with `Icons.movie_outlined` at 32 in `on-surface-variant`. **Load failed** — `surface-container-highest` with `Icons.broken_image_outlined`, same size and ink. These are theme surfaces, unlike `MediaPosterCard`'s plate.
- **Tap** — `onTap` wraps the card in `PressableScale` (0.97, light haptic, no scale under Reduce Motion); nothing else changes on screen. `MediaGrid` and the browse wall pass none and wrap the tile themselves, so the tap and the spoken name belong to the tile.

The consumer provides `imageUrl` (required, nullable), optional `httpHeaders` and `badge`, and optional `onTap`. The card has no `Hero`: the caller wraps it in one and references `MediaPosterCard.flightOnUserGestures`.

Semantics: the card publishes no label of its own. The enclosing tile names it — in `MediaGrid` one button named by the title with the status as its value — and passes `excludeFromSemantics: true` to the badge so the status is not read twice.

Do: let the tile own the tap and the spoken sentence, and keep the badge compact. Don't: add a second shadow level or a border — the flight between grid and hero relies on this exact `level-2`.
