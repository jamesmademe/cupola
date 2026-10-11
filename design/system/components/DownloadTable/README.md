# DownloadTable

Activity's downloads as a desktop window reads them: a table of Title, Progress, Speed and Left, sortable by each from its header, a row a download, the chosen one in the inspector.

Rendered from `lib/features/activity/presentation/widgets/download_table.dart` (`DownloadTable`, `DownloadTable.queued`) by `test/design_catalog/download_table_catalog_test.dart`. What each cell says and how a column sorts come from `lib/features/activity/domain/download_table.dart`, never from the widget; the choice is `selectedDownloadProvider` (`lib/features/activity/data/selected_download.dart`); Stop, Resume and Remove are `download_actions.dart`'s, the same the download's page uses.

## Where it is drawn

On Activity's All and Downloads (Downloads also lists the downloads stopped on purpose, last, `Stopped at 62%` with Resume under the pointer), in a desktop window (the desktop shell, from 720): `Downloads` as a `DownloadTable` inside its slab, `Up next` as a `DownloadTable.queued`. A touch build, at any width, keeps the rows ([ActivityRows](../ActivityRows/README.md)). The page stands in the content well (1140) on the desktop, not the reading well: the table wants the width.

## Anatomy

- **The header**: the columns' names in `AppType.meta` `inkSecondary`, 36 tall, Title over the titles (after the art's 36 and `space-md`). Each sorts the table: a click sorts by it the way it sorts first (the furthest along and the fastest first, the soonest done first, A to Z), a second the other way, a third back to the queue's own order (the stuck last). The chosen column is in the ink, w600, with a 14px arrow. The order is kept while the app runs, the same on All and Downloads, never written down.
- **A row**, `space-row` above and below, a hairline between:
  - the art, 36×54 (`HomeRowArt`);
  - Title (flex): the title in `AppType.row` the ink, one line; the release in `AppType.mono` `inkSecondary`, one line that fades; the route and who asked in `AppType.meta` `inkSecondary` (`Radarr → qBittorrent · Anna asked`; a stuck one `Radarr → qBittorrent · nothing for 3 h`);
  - Progress (150): `62%` in `AppType.meta` w600 tabular in the stand's tone, a 4pt bar under it; `Stopped at 62%` in the neutral, `Stuck at 47%` and `Failed` in amber;
  - Speed (84): `4.2 MB/s` in `AppType.meta` tabular the ink, the dash when it does not move or its client measured nothing;
  - Left (96): `11 min` the same, `around 21:10` under it in `AppType.caption` `inkTertiary`; the dash without an estimate;
  - the end (80): `⋯` (`More`) and, on the row under the pointer, `Stop` (a square; `Resume` with a play glyph once stopped) with its tooltip `Stop · keeps what has arrived`; both 36 × 44 in `inkSecondary`. They lie over the row, never inside its target.
- Columns `space-lg` apart.
- **Up next** (`DownloadTable.queued`): no header; `Queued · starts in about 6 min` in blue across Progress, Speed and Left.
- **A compact window** (under 1100), and any window at a large reading size: Speed and Left leave their columns and join the line under the title (`Radarr → qBittorrent · 4.2 MB/s · 11 min left · Anna asked`).

## Choosing

- In a full window a click chooses the download: the row sits on the room's strong fill, as a selected row does on a tablet, and the inspector opens on it (`Selected download`, [InspectorPane](../InspectorPane/README.md)). A second click on the chosen row within the double-click time, or Return, opens its page ([DownloadDetail](../DownloadDetail/README.md)).
- The arrow keys walk the rows, choosing as they go; Escape lets go, and the inspector shows the queue again.
- In a compact window, where the inspector is never laid out, a click opens the page, as on a phone.
- `⋯` and a secondary click offer `Open download`, `Stop` (`Resume`) while a connected client moves it, and `Remove` while an \*arr asked for it and nothing is wrong with it (a fault's Remove is its remedy's, in Needs you). Remove asks the neutral question Needs you asks; a removed chosen download lets go.

## Semantics

- Each row is one node, a button: the title, then `62 percent, Radarr → qBittorrent · Anna asked, 4.2 megabytes per second, 11 min left, ready around 21:04`; `selected` when chosen; the hint `Shows it in the inspector` in a full window; its menu's actions as the node's own.
- Each header is a button: `Progress`, its value `sorted, highest first` when chosen, the hint `Sorts by progress`.

## States in the catalog

Drawn in the dark and the light room, on the desktop sheet.

- A full window in the queue's order, a stuck one with its dashes; the stuck one chosen; Up next; a compact window; text at 200%.

## Do / don't

- Do keep the figures in their columns, tabular, so a glance down a column compares like with like.
- Do say only what a client said: the dash, never `0 B/s`, for a speed nobody measured.
- Don't put a control inside the row's target: Stop and ⋯ lie over it.
- Don't draw the table on a touch build: a finger has no pointer to choose with and no inspector to show the choice.
