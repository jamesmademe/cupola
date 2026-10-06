# MediaInfoCard

The Details region's fact sheet: optional full-width rows first, then a two-column grid of label-over-value facts; with `FileInfoSection`, the file row the manifest shows.

Rendered from `lib/core/widgets/media_info_card.dart` and `lib/core/widgets/file_info_section.dart` by `test/design_catalog/media_info_card_catalog_test.dart`. Radarr hosts it in `AppCard.surfaceOutlined` under the *Details* slot label.

- **Host card** — `AppCard.surfaceOutlined`: `surface-container`, 1px `outline-variant`, `radius-md`, padding `space-lg`. The card itself draws no chrome; it is the grid alone when there are no rows, and nothing at all when there are neither rows nor groups.
- **Rows** — `rows`, full-width widgets `space-sm` apart, then `space-md` before the grid. What you can change sits above what you can only read.
- **Grid** — cells paired into rows so both columns share a top edge: columns `space-lg` apart, rows `space-sm` apart; an odd last cell leaves its partner empty. It folds to one column (`space-md` between cells) when a column would fall under 144pt, i.e. below 304 of grid width: the desktop side track (380 − 32 gutter − 32 card padding = 316, two 150pt columns) and a 375pt phone keep two columns, a 360pt phone (296) takes one.
- **Cell** — label in `label-small` 600 `on-surface-variant`, one line, ellipsised (the role's own tracking, not an eyebrow); 2pt; value in `body-small` 600 `on-surface` at 1.3 leading, two lines, ellipsised. `MediaFactsList` builds the same grid from `MediaFact(label, value)` pairs and adds tabular figures to the value.
- **File row** — `surface-container`, 1px `outline-variant`, radius 12, padding 11 × `space-md`. A 38 × 54 well in `surface-container-highest`, radius 8, holding an 18pt glyph (`Icons.storage_rounded`, or `Icons.drive_folder_upload_rounded` for the missing hint) in the page accent walked by `onTint` against the well — the primary ink, since the accent is the lamp; without an accent, `on-surface-variant`. Then `space-sm` and the shape the constructor names:
  - **`FileInfoSection.file`** — the file the service records (Radarr's `movieFile.relativePath`, never the last part of the folder, which named the folder as though it were the file) as the card's lead, a [`MachineName.fileLead`](../MachineName/README.md): mono, in the ink (`on-surface`, the title role's colour), whole, wrapping after its dots, selectable, with its copy button. The page title already says *what*; this card says *which copy*. Under it, secondary and in the tertiary ink: when the service renamed the file on import, *Released as* and the release (`sceneName`, else `originalFilePath`, exactly as recorded) as a `MachineName.releaseInFull`, nothing when the file kept its release name; last, the folder, a path and so a machine string, in `mono` and `dim-text`, whole. The well is top-aligned with the first line.
  - **`FileInfoSection.folder(path:)`** — the folder as the card's subject, for a page whose service names no single file (a series), under a slot labelled *Library path* (`FileInfoSection.folderLabel`). The heading names it, so the card draws the path alone, leading as a file name does: `mono` in the ink (`on-surface`), whole. It reads the path.
  - **`FileInfoSection(path:)`** — the folder under its own title, for a section whose heading is about something else: Radarr's *File* section when Radarr reports a file and does not name it. *Library path* in `body-small` 600 `on-surface` (the text face) over the path, secondary, in `mono` and `dim-text`, whole. It reads *Library path, path*. Without a path it draws nothing.
- **`FileInfoSection.missing`** — the same row for a tracked title with nothing on disk: *Nothing on disk yet*, a statement and not a way; the page that draws it offers the import beside it (the Media page's `Import a file`).

The consumer provides `groups` (`MediaInfoGroup(title:, child:)`, the child usually a `Text`), optional `rows`, and for the file row `fileName`, `releasedAs`, `path` and `accent` (`FileInfoSection.file`), or `path` and `accent` alone. Radarr's cells, in order: *Monitored*, *In cinemas*, *Digital*, *Physical*, *Studio*, *Certification*, *Language*.

Semantics: `FileInfoSection.file` is three nodes, each read whole after its label: *File name*, the file; *Released as*, the release; *Library path*, the folder. Each name carries the copy action and has its copy button beside it. `FileInfoSection.folder` is one node reading the path, after its slot's heading; the titled folder row and the missing hint are one node each (*Library path, path*; the hint's two lines). Grid cells read label then value in order.

Do: keep a control on a row above the grid. Don't: put a control in a grid cell — half a column wide and labelled by the grid, it would be announced by its value alone.

## States in the catalog

Each sheet is drawn in the dark and the light room; the card also on the desktop side track.

- The Details card, a 360pt phone that folds to one column, a long label and value, `MediaFactsList`, `FileInfoSection`.
- Text at 200%: Details, a long label and value, and the file section.
