# MediaChipSection

A wrapped run of catalogue chips for region 5: neutral pills for genres and keywords, accent pills for the tags the user configured on their server.

Hand-written from `lib/core/widgets/media_chip_section.dart`, composing `GenreChip` and `TagChip` from `tag_chip.dart`.

- **Wrap** — `space-sm` between chips and between runs. Blank values are dropped; nothing left, nothing rendered. Label-less: the slot owns the heading, so one list can never reach two differently titled sections.
- **`.neutral`** (`GenreChip`) — padding `space-xs` × `space-md`, `radius-full`, `surface-container`, 1px `outline-variant`, `label-small` 500 in `on-surface-variant`. For genres and TMDB keywords: a fact about the title, which the service's colour has no opinion on.
- **`.accented`** (`TagChip`) — padding `space-xs` × `space-sm`, `radius-full`, `label-small` 600. The accent is first walked by `onTint` against `surface` at a 12% tint; the label, the 12% fill and the 28% border all follow the walked colour, so the recipe stays self-consistent in both themes.

The consumer provides `values` and, for `.accented`, the page `accent`. The slot label must be `Genres` / `Keywords` for neutral and `Tags` for accented. Values shown are illustrative.

Semantics: each chip reads its text; chips are metadata, not controls, and carry no button role.

Do: use `.accented` only for real Radarr / Sonarr / Bazarr tags. Don't: call genres "Tags" — in this domain a tag targets release profiles and import lists, so the label would assert something false about the server.
