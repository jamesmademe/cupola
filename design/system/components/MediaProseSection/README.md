# MediaProseSection

Running prose on a detail page — an overview, a biography — held to a 640 reading measure and expandable in place.

Hand-written from `lib/core/widgets/media_prose_section.dart`. Hosted in region 4 (`synopsis`) under the `Overview` label.

- Text: `body-large` (16 / 400 / 1.55) in `on-surface-variant`. No leading override — the role's own 1.55 is the Leading Ladder.
- Measure: `maxWidth` 640 (`proseMaxWidth`), leading-aligned; it bites even inside a wider track because the block is loosened with `Align` before the cap.
- Clamp: six lines by default (`maxLines`), ellipsised. Whether it overflows is measured, not assumed — a two-line overview grows no control.
- Control: a text button under the paragraph, leading-aligned — *Show more* / *Show less* (`label-large` 600, theme `primary`). The height change animates over 200ms on the emphasized curve; under Reduce Motion the animator is removed, not zeroed.
- Expansion is local state, so a refresh or queue poll never collapses a paragraph mid-read. Blank text renders nothing.

The consumer provides `text` and optionally `maxLines`. The paragraph shown is illustrative.

Semantics: the paragraph reads as text; the control is a button labelled with its visible word.

Do: let the spine own the label and gutter. Don't: set a line height on the role, or bound the text with a fixed height — it grows downward with reading size like a paragraph.
