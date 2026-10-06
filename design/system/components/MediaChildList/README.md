# MediaChildList

The dense child row: an episode or a track, carrying its status as a tone and, when it matters, as a word.

Rendered from `lib/core/widgets/media_child_list.dart` (`MediaChildTile`, `mediaStatusWord`) by `test/design_catalog/media_child_list_catalog_test.dart`.

- **Rows** — `AppCard.filled` (`surface-container`, `radius-md`), padding `space-sm` × `space-md`, `space-xs` apart, dipping to 0.96 on press instead of flooding a ripple. Title in `body-medium` 600, two lines; `facts` through `MediaMetadataLine` in `body-medium` `on-surface-variant`, joined with ` · `, two lines. Then `space-sm` and the status, then `space-xs` and the `trailing` control.
- **`MediaChildTile.numbered`** — ordinal (*E5*, the episode half of `S2 E5`, from `formatEpisodeOrdinal`) in `label-small` 600 tabular `on-surface-variant`, in a column at least 30 wide that grows with the clamped reading size, then `space-sm`. The status is an 8px `StatusBadge(iconOnly: true)` dot. `status` may be null — a Seerr episode has no status of its own — and then no dot is drawn.
- **Status word** — `mediaStatusWord` returns the pipeline state with its percentage (*Downloading 42%*), otherwise the status label (*Missing*, *Not released*) for anything not plainly available, and null for an available row — a wall of green dots carries no text.

The consumer provides `ordinal` and `ordinalLabel`, `title`, `facts`, the resolved `status` (or null), and optionally `onTap`, `trailing` and `semanticHint`.

Semantics: a row is one button named *ordinalLabel, title, facts* (*Episode 7, A Scandal in Bohemia, Feb 15, 1921, Missing*) with the status's `semanticLabel` as its value; the ordinal, texts and badge are silenced, and `trailing` keeps its own node. `ordinalLabel: ''` drops the ordinal from the name, for a row whose title already says what it is.

Do: resolve the status in the feature's domain layer, and pass a status word in `facts` for anything not available.

## States in the catalog

Each sheet is drawn in the dark and the light room; the rows also on the desktop.

- `MediaChildTile.numbered` for episodes with an air date, one downloading and one missing with its search menu; with no status, a two-line title and a stalled row.
- Text at 200%: the episode rows and the loose episodes.
