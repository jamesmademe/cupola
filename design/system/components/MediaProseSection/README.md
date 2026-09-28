# MediaProseSection

Running prose on a detail page — an overview, a biography — held to a 640 reading measure and expandable in place.

Rendered from `lib/core/widgets/media_prose_section.dart` by `test/design_catalog/media_prose_section_catalog_test.dart`. Hosted in the `synopsis` region under the *Overview* slot label.

- **Text** — `body-large` (16 / 400 / 1.55) in `on-surface-variant`. No line-height override: the role's own 1.55 is the leading.
- **Measure** — `maxWidth` `MediaDetailMetrics.proseMaxWidth` (640), leading-aligned. It bites inside a wider track because the tight width the slot hands down is loosened with `Align` before the cap; on a phone the column is narrower than the measure and the paragraph runs its full width.
- **Clamp** — `maxLines` lines (6 by default), ellipsised. Whether the text overflows is measured with a `TextPainter` at the current width and reading size, not assumed — a paragraph that fits grows no control.
- **Control** — a `TextButton` under the paragraph, leading-aligned: *Show more*, and *Show less* once open. It takes the theme's text-button style: `label-large` 600 in `colorScheme.primary`, with the button's own padding around the word. The height change animates over `AppAnimation.durationSm` (200ms) on `AppAnimation.emphasizedCurve`; under Reduce Motion the `AnimatedSize` is removed rather than zeroed.
- **State** — expansion is local to the widget, so a refresh or a queue poll never collapses a paragraph mid-read. Blank text (after trimming) renders nothing.

The consumer provides `text` and optionally `maxLines`.

Semantics: the paragraph reads as text; the control is a button labelled with its visible words.

Do: let the spine own the label and the gutter, and pass the paragraph as the service wrote it. Don't: set a line height on the role, or bound the text with a fixed height — it grows downward with reading size like a paragraph.
