# MediaPosterCard

The poster as an object: a 2 : 3 rounded plate at `level-2` that flies between the grid and the detail hero as one shared element.

Hand-written from `lib/core/widgets/media_poster_card.dart`, with the grid it lives in from `lib/core/widgets/media_grid.dart` (tiles are `ContentCard`) and the browse tile from `_BrowsePosterTile` in `lib/core/widgets/media_browse_scaffold.dart`.

- **Poster** — fills its parent (the hero slot sizes it 82 × 123), `radius-md`, `level-2`, clipped. No poster, or a failed load: `plate-surface` with the fallback glyph at 48px in `plate-dim-ink` — the plate, not the theme, so a missing poster is the same dark well on paper and the arriving image replaces like with like.
- **`.circular`** — the artist/person treatment, a clipped circle (92 × 92 in the hero). Takes no radius.
- **Hero flight** — the shadow lifts `level-2` → `level-3` mid-flight and settles back (`1 − |2t − 1|`, ease-out), both directions; flat under Reduce Motion. No image cross-fade, so a cached poster flies crisp. `flightOnUserGestures` is true: posters also fly during the iOS swipe-back.
- **Grid** (`MediaGrid`) — padding `space-lg` all round (plus nav clearance at the bottom), `gridGap` 12 both ways, aspect 2 : 3. Columns = `floor((width − 32 + 12) / (130 + 12))`, never fewer than the floor count (3). A tile is never narrower than 130 **unless** the 3-column floor wins: on a 390 phone the width answers 2, the floor answers 3, and the tiles land at **111.3**, not 130 — the code comment claiming 390 "keeps exactly three columns" at the 130 floor is arithmetically wrong.
- **Status in the grid** — a compact `StatusBadge` in the top-right corner over a `colorScheme.shadow` radial (see ContentCard). **In the browse wall** — an 8px dot at 6 / 6 from the bottom-left, then `space-xs`, the title in `label-small` 600 `on-surface` (one line, ellipsised) and the year in `label-small` `on-surface-variant`. Browse rows run 16 apart (`runSpacing`), grid rows 12.

The consumer provides `heroTag` (unique per grid position: `movie_<id>_<index>`), the image URL and headers, and the fallback glyph (`movie_outlined` by default, `person_outline` on Lidarr's circle wall). Content is illustrative: the loaded artwork is the *Nosferatu* (1922) poster, and the other tiles show the loading and no-URL states rather than borrowing that poster under another title.

Semantics: in the hero slot the poster is excluded — the title beside it names the region. In a grid cell with a title, the cell is one button named by the title with the status as its value (*Night of the Undead, Downloading 42%*); the badge's own node is dropped.

Do: size it from outside with a `SizedBox`, and keep one hero tag per visual position. Don't: fade a poster Hero source (it would fly from nothing), or paint a missing poster in a theme surface.
