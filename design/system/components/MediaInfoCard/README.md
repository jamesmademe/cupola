# MediaInfoCard

The Details region's fact sheet: editable fields on full-width rows first, then a two-column grid of label-over-value facts; with `FileInfoSection`, the file row the manifest shows.

Hand-written from `lib/core/widgets/media_info_card.dart` and `lib/core/widgets/file_info_section.dart`. Radarr hosts it in `AppCard.surfaceOutlined` under the `Details` label.

- **Host card** — `AppCard.surfaceOutlined`: `surface-container`, 1px `outline-variant`, `radius-md`, padding `space-lg`.
- **Rows** — each a `MediaDetailValueRow` (see MediaDetailSection), `space-sm` apart, then `space-md` before the grid. Editable first: what you can change sits above what you can only read.
- **Grid** — cells paired into rows so both columns share a top edge: columns `space-lg` apart, rows `space-sm` apart. Below 320 of content width it becomes one column with `space-md` between cells.
- **Cell** — label `label-small` 600 `on-surface-variant`, one line, ellipsised (the role's own tracking, not an eyebrow); 2px; value `body-small` 600 `on-surface` at 1.3 leading, two lines. `MediaFactsList` values add tabular figures.
- **File row** — `surface-container`, 1px `outline-variant`, radius 12, padding 11 × `space-md`. A 38 × 54 well in `surface-container-highest`, radius 6, holding an 18px glyph (`storage`, or `drive_folder_upload` for the missing hint) in the page accent, walked by `onTint` against the well's own `surface-container-highest`. `space-sm`, then filename in `body-small` 600 `on-surface` (one line) over the path in `label-small` `on-surface-variant` (one line; two for the hint).
- **`.missing`** — the same footprint for a tracked title with nothing on disk: *Import a file you already have* — *Manual import is in the actions menu.* The region does not jump when a file arrives.

The consumer provides `groups` (`MediaInfoGroup` title + child), optional `rows`, and for the file row `path`, `filename` and `accent`. Real Radarr cell labels: Monitored, Profile, In Cinemas, Digital, Physical, Studio, Certification, Language. Values, filename and path are illustrative.

Semantics: the file row is one node speaking *filename, path*. Grid cells read label then value in order.

Do: keep edits on rows above the grid. Don't: put a control in a grid cell — half a column wide, labelled by the grid, it would be announced by its value alone.
