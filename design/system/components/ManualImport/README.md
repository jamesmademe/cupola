# ManualImport

The manual import wizard of one arr's connection (Radarr, Sonarr, Lidarr): three stations in one flow, Locate → Review → Track. A title's room, a queue row's ⋮ menu and Activity's `More` → `Manual import…` open it. Readarr has none.

Rendered from:

- `lib/features/import/presentation/manual_import_locate_screen.dart` (`ManualImportLocateScreen`);
- `lib/features/import/presentation/manual_import_review_screen.dart` (`ManualImportReviewScreen`) and `manual_import_review_rows.dart`;
- `lib/features/import/presentation/manual_import_progress_screen.dart` (`ManualImportProgressScreen`);
- `lib/features/import/presentation/manual_import_provider.dart` (`ManualImportFlowNotifier`, the flow's state).

The catalog test is `test/design_catalog/manual_import_catalog_test.dart`. The blocked downloads' Review, which Needs you opens, is its own card: `ImportReview`.

## Locate

- **The station bar**: `1 Locate · 2 Review · 3 Track`.
- **The root folders** of the arr, each with its free space, as the quick way in.
- **`Folder path`**: a field that goes to the folder typed, with `Go to this folder`.
- **The folder's subfolders**, one row each (the name, the path, when it changed); a tap opens the folder and chooses it. `No subfolders here` when there are none, with `You can still scan this folder as the import source.`
- **The foot**: `Scanning parses and probes every file on the server, large folders take minutes.`, then `Cancel` and the primary, `Scan "<folder>"` for the chosen folder.
- **Opening without a path**, the top of the server is listed to browse and nothing is chosen: the primary reads `Choose a folder`, disabled. `/` holds the system's folders, and scanning it would probe every file on the server. A path that came with the link (a queue row's download, a title's folder) is chosen as it opens.
- **A Review reached with no folder chosen** (an old link, a flow that started over) goes to Locate instead of scanning anything.

## Review

- The folder scanned, `Choose another folder`, the filters (`3 ready`, `1 needs a match`, `2 other`).
- **Matched files**, grouped by title, each file with its checkbox, its identity and `Ready`. A sample reads `Sample`: the scan does not tick it, and neither do `Select all ready files` (the icon button in the bar) nor a title's own checkbox. It is ticked by hand, on its row.
- **Needs attention**: the files without an identity (`No match`, `Needs match`), each opening the match sheet.
- **Other files**: what the arr does not import, hidden by default.
- **The foot**: `Import N files` in the service's ink, the mode (`Auto`, `Move`, `Copy`), and a confirmation `Import N files into <Service>?`.

## Track

The command as the arr runs it: `Queued`, `Running`, `Completed`, `Failed`; `Started`, `Duration`, `Files`; `Per-file results appear in Activity → History.` once done; `Back to review` and `Retry` when it failed, `Done` otherwise.
