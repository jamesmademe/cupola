# MediaChipSection

A wrapped run of catalogue chips for a detail page's reference region: neutral pills for genres and keywords, accented pills for the tags the user configured on their server — a wash of the page's accent (the lamp) under the primary ink, no hue.

Rendered from `lib/core/widgets/media_chip_section.dart` (composing `GenreChip` and `TagChip` from `lib/core/widgets/tag_chip.dart`) by `test/design_catalog/media_chip_section_catalog_test.dart`.

- **Wrap** — `space-sm` (8) between chips and between runs. Blank values are dropped; with nothing left the section draws nothing (`SizedBox.shrink`). It carries no label: the slot owns the heading, so one list can never reach two differently titled sections.
- **`.neutral`** (`GenreChip`) — padding `space-xs` × `space-md`, `radius-full`, `surface-container` fill with a 1px `outline-variant` border, `label-small` 500 in `on-surface-variant`. For genres and TMDB keywords: a fact about the title, which the service's colour has no opinion on.
- **`.accented`** (`TagChip`) — padding `space-xs` × `space-sm`, `radius-full`, `label-small` 600. The accent is first walked by `ServiceTheme.onTint` against `surface` at a 12% tint; the label, the 12% fill and the 28% border all follow the walked colour, so the recipe stays self-consistent in both themes. The page accent is the lamp, which the walk resolves to the primary ink: the chip is monochrome.

The consumer provides `values` and, for `.accented`, the page `accent` (asserted non-null). The slot label is *Genres* or *Keywords* for `.neutral` and *Tags* for `.accented`, given and drawn in sentence case.

Semantics: each chip is plain text and reads as its text; chips are metadata, not controls, and carry no button role.

Do: use `.accented` only for real Radarr, Sonarr or Bazarr tags. Don't: call genres *Tags* — in this domain a tag targets release profiles and import lists, so the label would assert something false about the server.

## States in the catalog

Each sheet is drawn in the dark and the light room; the column also on the desktop.

- `.neutral` genres and wrapping keywords, `.accented` Radarr, Sonarr and Bazarr tags.
- A keyword wider than the phone column.
- Text at 200%: genres, keywords and tags.
