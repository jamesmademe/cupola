# MediaMetadataLine

The facts of a title on one line: year, runtime, genre.

Rendered from `lib/core/widgets/media_metadata_line.dart` by `test/design_catalog/media_metadata_line_catalog_test.dart`.

- **Line** — trimmed, non-empty items joined with ` · ` (the house middot) in `body-medium` `on-surface-variant`; a caller sets `maxLines` to clamp it, and a clamped line ends in an ellipsis (the hero caps it at one line, the child list at two). An empty or all-blank list renders `SizedBox.shrink()`, not an empty gap. The text takes the full width it is given and aligns to the start unless the caller passes `textAlign`.

The consumer provides `items` (already worded: `1922`, `1 h 34 min`, `Horror`) and, where the row is short, `maxLines`. It is used by the hero summary (`MediaDetailHero`) and by the rows of `MediaChildList`. Items are illustrative.

## Semantics

One line of text, read in order as a single run: *1922 · 1 h 34 min · Horror*.

## States in the catalog

Each sheet is drawn in the dark and the light room.

- The fact line; the same line clamped to one line, ending in an ellipsis.
- Text at 200%: the fact line on a 390pt phone, free and clamped to two lines.

## Do / don't

- Do hand it the words as they should read: it joins and trims, it does not format a year or a runtime.
- Don't put a status or an action in it: it is facts, in the quiet ink, and nothing in it is tappable.
