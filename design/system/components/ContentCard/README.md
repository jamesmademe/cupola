# ContentCard

The grid tile's picture: cached artwork in a `radius-md` clip at `level-2`, with an optional status badge in the top-right corner.

Hand-written from `lib/core/widgets/content_card.dart`.

- Box: `radius-md`, `level-2` (the same resting shadow as `MediaPosterCard`, so the shared-element flight never pops a different shadow), `Clip.antiAlias`, the image `BoxFit.cover`. It fills its parent; `MediaGrid` gives it a 2 : 3 cell (130 × 195 here, the preferred tile).
- **Badge corner** — the caller's badge (a compact `StatusBadge` in every grid) sits top-right with `space-sm` padding over `AppGradients.serviceGlow(colorScheme.shadow, radius: 1.5)`: shadow ink at 22% fading to nothing, centred on the corner. `colorScheme.shadow` is black in dark and ink (`ink-on-bright`) in light.
- **Loading** — the shared `ShimmerPlaceholder` (`surface-container-high` sweeping to `surface-container` and back, 1500ms; honours Reduce Motion). Shown here as one static frame.
- **No URL** — `surface-container` with `movie_outlined` at 32px in `on-surface-variant`. **Load failed** — `surface-container-highest` with `broken_image_outlined`, same size and ink.
- **Tap** — optional `onTap` wraps the card in `PressableScale` (0.97, light haptic). `MediaGrid` and the browse wall pass none and wrap it themselves.

Variants shown: image with a stalled compact badge (warning fill at 90%, glyph and label chosen by `foregroundOn`), image alone, loading, no URL, failed load. The consumer provides `imageUrl`, optional `httpHeaders` and `badge`. The card publishes no semantics of its own; the enclosing tile names it. The artwork is illustrative (the *Nosferatu*, 1922, poster).

Do: let the tile own the tap and the spoken sentence. Don't: add a second shadow level or a border — the flight between grid and hero relies on this exact `level-2`.
