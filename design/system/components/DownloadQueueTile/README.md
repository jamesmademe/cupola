# DownloadQueueTile

One row of a download client's queue: name, state chip, percentage, a thin bar and a counting-down line, shared by qBittorrent, Transmission, SABnzbd and NZBGet.

Rendered from `lib/core/widgets/download_queue_tile.dart`, with the qBittorrent mapping in `lib/features/qbittorrent/presentation/widgets/torrent_tile.dart`, by `test/design_catalog/download_queue_tile_catalog_test.dart`. Release names, sizes and rates in the catalog are illustrative.

## Values

- Outer padding `AppSpacing.lg` (16) horizontal × `AppSpacing.xs` (4) vertical. Plate: a `Material` in `surface` with a 1px `outlineVariant` side, `AppRadius.md`, inner padding `AppSpacing.md` (12). Selected: the client's accent (the lamp) at 8% with a 40% lamp side. The ink splash exists only when the row has a tap or long-press.
- First line: title in `bodyMedium` w600, one line, ellipsised; `AppSpacing.sm` (8); the state chip; 8; the percentage (glued, `62%`, through `formatPercent`: nearest whole percent, never `100%` before 100) in `labelMedium` w600 with tabular figures, in the primary ink (the client's accent is the lamp, which `ServiceTheme.onTint` resolves to ink), or `—` when the percentage is null; then the optional trailing `actions`. The title takes the free width while it keeps ten of its own em; past that, the chip and the percentage go under it at the trailing edge (`BesideOrBelow`), so a long label, or any label at a large text size, never starves the name. Under it, a label longer than the whole line ellipsises before the percentage does.
- Chip: padding 7 × 2, `AppRadius.xs`, fill the tone's `statusToneColor` at 12%, label in `labelSmall` w600 walked against that 12% composite. The row takes a `StatusTone`, never a colour.
- Bar (only when `progress` is non-null): 4 above, a 4pt `LinearProgressIndicator` clipped to `AppRadius.xs`, track `surfaceContainerHighest`, value in the blue tone (in progress: `statusToneColor(info)` walked against the track); a stale sample (`sampleAge`) drains it to `onSurfaceVariant`.
- Second line: 4 above, `bodySmall` with tabular figures in `onSurfaceVariant`, one line, ellipsised: whatever the client counts down (status, ETA, remaining size). A time is `formatTimeSpan`'s, the brand book's units with a no-break space: *12 min*, *2 h 10 min*, *1 d 5 h*, never *12m*; at 390 the longest of them fits beside a size (the long-wait scene), and it is the title that ellipsises.
- Metrics (optional): 4 above, 12 apart; an 8pt dot, 4, and the value in `labelSmall` tabular, both in the primary ink when `accented`, else `onSurfaceVariant`.
- Menu (`DownloadQueueActionsMenu`, the Usenet pair): a `PopupMenuButton` with an 18pt `more_vert_rounded`, tooltip *Actions for* and the job's name (`subject`), offering *Pause* or *Resume*, then *Delete job*.

## States

As qBittorrent maps them (the tone rule, applied once in `_toneFor`):

- **Downloading**, **Fetching metadata**, **Checking**: `info`; the bar in blue, `↓` rate accented (ink) and `↑` rate neutral.
- **Queued**: `info`, as queued is blue in every queue the app draws (an arr's, SABnzbd's, NZBGet's, Transmission's): in line, waiting its turn. No bar, and qBittorrent's unknown ETA prints `∞`.
- **Stuck** and **Error** (`warning`): a fault the client reported. An errored torrent draws no bar.
- **Stopped** (neutral): a deliberate stop. It keeps its bar and prints no ETA.
- **Seeding** (complete), `success`, no bar (a full bar would say "finishing").

Across clients:

- **Stale** (`sampleAge` set): the second line becomes *as of 6 min ago* (`formatDurationAge`) and the bar keeps its position but drains to `onSurfaceVariant`. The four client queue pages pass it while they show their last read under a fault band, as the time since that read came back (`ReadClock`, `lib/core/status/read_clock.dart`), and nowhere else.
- **Transmission** prints the remaining size while downloading and *Ratio …* while seeding, and a blocking error (the client's own error string) or *Stuck* replaces the chip's label.
- **Usenet rows** (SABnzbd, NZBGet) carry no chip and no metrics: the state heads the second line (SABnzbd *Downloading · 0:12:00 · 1.2 GB left of 3.4 GB*, passing its raw `timeleft`; NZBGet *status · category · remaining*, or *progress unknown* with a null percentage and no bar), and `DownloadQueueActionsMenu` trails the first line.

## Consumer provides

`title`, `subtitle`, `progress` (null draws no bar, which is different from 0), `percentage` (null prints `—`), `accent`, `statusLabel` and `statusTone`, `metrics` (`DownloadQueueMetric`: `label`, `accented`, `spoken`), `sampleAge`, `selected`, `actions` and the `onTap` / `onLongPress` callbacks.

## Semantics

The row is one container that speaks one sentence: *title, state, 63 percent, second line, metrics* (a null percentage says *progress unavailable*; a metric's `spoken` text replaces the arrow: *downloading at 25.0 MB/s*), reports selection as a state when it is interactive, and carries tap and long-press itself; `actions` is the only child left on the reader's path. Long-press starts selection and is never the menu.

## States in the catalog

Each sheet is drawn in the dark and the light room; the torrent tile also on the desktop.

- `TorrentTile`: downloading, stalled, paused, queued, seeding; a long wait; error, fetching metadata and checking; selected; stale (`sampleAge`).
- Usenet rows for SABnzbd and NZBGet; a long name with a long state label.
- Text at 200%: a downloading, a selected, a Usenet and a long-label tile.

## Do / don't

- Do pass `null` progress for a job that has not started.
- Don't pass colours: the chip takes a `StatusTone`, a metric takes a flag.
- Don't put the row's commands behind long-press.
