# MediaChipSection

A wrapped run of catalogue chips for a detail page's reference region: neutral pills for genres and keywords, accent pills for the tags the user configured on their server.

Rendered from `lib/core/widgets/media_chip_section.dart` (composing `GenreChip` and `TagChip` from `lib/core/widgets/tag_chip.dart`) by `test/design_catalog/media_chip_section_catalog_test.dart`.

- **Wrap** — `space-sm` (8) between chips and between runs. Blank values are dropped; with nothing left the section draws nothing (`SizedBox.shrink`). It carries no label: the slot owns the heading, so one list can never reach two differently titled sections.
- **`.neutral`** (`GenreChip`) — padding `space-xs` × `space-md`, `radius-full`, `surface-container` fill with a 1px `outline-variant` border, `label-small` 500 in `on-surface-variant`. For genres and TMDB keywords: a fact about the title, which the service's colour has no opinion on.
- **`.accented`** (`TagChip`) — padding `space-xs` × `space-sm`, `radius-full`, `label-small` 600. The accent is first walked by `ServiceTheme.onTint` against `surface` at a 12% tint; the label, the 12% fill and the 28% border all follow the walked colour, so the recipe stays self-consistent in both themes and an amber accent still clears contrast on the light page.

The consumer provides `values` and, for `.accented`, the page `accent` (asserted non-null). The slot label is *Genres* or *Keywords* for `.neutral` and *Tags* for `.accented`, given in sentence case — the slot uppercases it for the eye.

Semantics: each chip is plain text and reads as its text; chips are metadata, not controls, and carry no button role.

Do: use `.accented` only for real Radarr, Sonarr or Bazarr tags. Don't: call genres *Tags* — in this domain a tag targets release profiles and import lists, so the label would assert something false about the server.
