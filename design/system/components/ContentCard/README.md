# ContentCard

The grid tile's picture: cached artwork in a `radius-md` clip glowing with its light (`shadow.poster`), with an optional badge in the top-right corner.

Rendered from `lib/core/widgets/content_card.dart` by `test/design_catalog/content_card_catalog_test.dart`.

- **Box** — `radius-md` (14), `AppElevation.poster`: the poster's glow in its light (the lamp until the light is derived; 0 16 30 −12 at 0.8 · day 0.35) — the same resting glow as `MediaPosterCard`, so the shared-element flight between a grid and a detail hero never pops a different shadow — and `Clip.antiAlias`. The image is `BoxFit.cover`, loaded through the pinned image cache (`pinnedImageCacheFor`) and decoded at the size of the card, never the server's (`ArtworkDecodeBox`, `lib/core/widgets/artwork_decode.dart`): a 2 : 3 cell fixes the decode's height at the cell's times the pixel ratio (never under 2x), so an arr's original poster takes under a megabyte rather than 24 and still covers the cell. It fills its parent: `MediaGrid` and the browse wall give it a 2 : 3 cell.
- **Badge corner** — `badge` (a compact `StatusBadge` in every grid, the poster word `StatusBadge.poster` on a catalogue's) sits top-right with `space-sm` (8) padding, held to the card's width so a word longer than the poster is wide wraps inside its badge instead of running off the other edge, over `AppGradients.serviceGlow(colorScheme.shadow, radius: ContentCard.badgeGlowRadius)` (0.5): shadow ink at 22% fading to nothing from the card's top-right corner, painted across the whole card so it reaches zero at half the card's width — before any edge. It used to be painted in a box the size of the badge, which cut the radial off at a third of its strength and drew a hard-edged grey rectangle round the badge on any ground that was not dark artwork. `colorScheme.shadow` is black in dark and `on-surface` ink in light. The corner is a legibility aid for the badge over artwork.
- **Loading** — the shared `ShimmerPlaceholder`, `surface-container-high` sweeping to `surface-container` over 1600ms; under Reduce Motion a flat `surface-container-high` block.
- **No URL** (null or empty) — the plate, `AppColors.plateSurface`, with `Icons.movie_outlined` at 32 in `plateDimInk`. **Load failed** — the same plate with `Icons.broken_image_outlined`, same size and ink. The same well as `MediaPosterCard`'s fallback in both themes: a missing poster is not palette, and the tile is the source of the Hero flight into a detail hero drawn by `MediaPosterCard`, so a theme surface here turned a white light-theme tile into a dark well mid-flight.
- **Beside the pane** — on a tablet, the poster whose title the pane shows (`paneTag`, the tile's hero tag, matched against the one the title's location carries) wears a ring: 2 in the ink (`on-surface`), its centre 3.5 outside the card's edge with the radius grown to match, never over the artwork. When the list reflows into the phone's column and the poster leaves the viewport, it is scrolled back into view. A poster with no tag, or a fallback icon in its place, wears none.
- **Tap** — `onTap` wraps the card in `PressableScale` (0.96, light haptic, no scale under Reduce Motion); nothing else changes on screen. `MediaGrid` and the browse wall pass none and wrap the tile themselves, so the tap and the spoken name belong to the tile.

The consumer provides `imageUrl` (required, nullable), optional `httpHeaders` and `badge`, optional `onTap`, and `paneTag`, the hero tag of the tile, wherever the tile opens a title. The card has no `Hero`: the caller wraps it in one and references `MediaPosterCard.flightOnUserGestures`.

Semantics: the card publishes no label of its own. The enclosing tile names it — in `MediaGrid` one button named by the title with the status as its value — and passes `excludeFromSemantics: true` to the badge so the status is not read twice.

## States in the catalog

Each sheet is drawn in the dark and the light room.

- Artwork with a compact stalled badge, a downloading badge and an icon-only dot.
- Artwork alone, and with `onTap`.
- Loading, no URL and a failed load, with and without a badge.
- Beside the pane: the poster whose title a tablet's pane shows, ringed.
- Text at 200%: the compact badges over artwork.

Do: let the tile own the tap and the spoken sentence, and keep the badge small: compact in a library's grid, the poster word in the catalogue's. Don't: add a second shadow level or a border — the flight between grid and hero relies on this exact glow. The pane's ring is outside the card and only beside a pane, where nothing flies.
