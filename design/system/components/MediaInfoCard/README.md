# MediaInfoCard

The Details region's fact sheet: editable fields on full-width rows first, then a two-column grid of label-over-value facts; with `FileInfoSection`, the file row the manifest shows.

Rendered from `lib/core/widgets/media_info_card.dart` and `lib/core/widgets/file_info_section.dart` by `test/design_catalog/media_info_card_catalog_test.dart`. Radarr hosts it in `AppCard.surfaceOutlined` under the *Details* slot label.

- **Host card** — `AppCard.surfaceOutlined`: `surface-container`, 1px `outline-variant`, `radius-md`, padding `space-lg`. The card itself draws no chrome; it is the grid alone when there are no rows, and nothing at all when there are neither rows nor groups.
- **Rows** — each a `MediaDetailValueRow` (at least 44 tall: the same label and value styles as a grid cell, an `Icons.expand_more_rounded` chevron when it can write), `space-sm` apart, then `space-md` before the grid. Editable first: what you can change sits above what you can only read. A row with no `onChanged` or no options is a plain fact with no chevron; a value matching no option reads `—` in the dim ink. On a phone the row opens one `AppBottomSheet` for the field; in the desktop shell, a `MenuAnchor` select anchored to the row.
- **Grid** — cells paired into rows so both columns share a top edge: columns `space-lg` apart, rows `space-sm` apart; an odd last cell leaves its partner empty. Below 320 of content width it becomes one column with `space-md` between cells.
- **Cell** — label in `label-small` 600 `on-surface-variant`, one line, ellipsised (the role's own tracking, not an eyebrow); 2pt; value in `body-small` 600 `on-surface` at 1.3 leading, two lines, ellipsised. `MediaFactsList` builds the same grid from `MediaFact(label, value)` pairs and adds tabular figures to the value.
- **File row** — `surface-container`, 1px `outline-variant`, radius 12, padding 11 × `space-md`. A 38 × 54 well in `surface-container-highest`, radius 6, holding an 18pt glyph (`Icons.storage_rounded`, or `Icons.drive_folder_upload_rounded` for the missing hint) in the page accent walked by `onTint` against the well; without an accent, `on-surface-variant`. `space-sm`, then the filename in `body-small` 600 `on-surface` (one line) over the path in `label-small` `on-surface-variant` (one line). With neither a filename nor a path it draws nothing; with a path alone the title reads *Library path*.
- **`FileInfoSection.missing`** — the same footprint for a tracked title with nothing on disk: *Import a file you already have* over *Manual import is in the actions menu.* (two lines allowed). The region does not jump when a file arrives.

The consumer provides `groups` (`MediaInfoGroup(title:, child:)`, the child usually a `Text`), optional `rows`, and for the file row `filename`, `path` and `accent`. Radarr's cells, in order: *Monitored*, *In cinemas*, *Digital*, *Physical*, *Studio*, *Certification*, *Language* — the quality profile is a row, not a cell.

Semantics: the file row is one node speaking *filename, path*. Grid cells read label then value in order. An editable value row is one button named by its label, with the current value as its value and `hint` as its hint; a read-only row is plain text.

Do: keep edits on rows above the grid. Don't: put a control in a grid cell — half a column wide and labelled by the grid, it would be announced by its value alone.
