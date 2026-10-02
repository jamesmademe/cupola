# DownloadQueueTile

One row of a download client's queue: name, state chip, percentage, a thin bar and a counting-down line, shared by qBittorrent, Transmission, SABnzbd and NZBGet.

Rendered from `lib/core/widgets/download_queue_tile.dart`, with the qBittorrent mapping in `lib/features/qbittorrent/presentation/widgets/torrent_tile.dart`, by `test/design_catalog/download_queue_tile_catalog_test.dart`. Release names, sizes and rates in the catalog are illustrative.

## Values

- Outer padding `AppSpacing.lg` (16) horizontal × `AppSpacing.xs` (4) vertical. Plate: a `Material` in `surface` with a 1px `outlineVariant` side, `AppRadius.md`, inner padding `AppSpacing.md` (12). Selected: the client's accent — the lamp — at 8% with a 40% lamp side. The ink splash exists only when the row has a tap or long-press.
- First line: title in `bodyMedium` w600, one line, ellipsised; `AppSpacing.sm` (8); the state chip; 8; the percentage (glued, `62%`, through `formatPercent`: nearest whole percent, never `100%` before 100) in `labelMedium` w600 with tabular figures, in the primary ink (the client's accent is the lamp, which `ServiceTheme.onTint` resolves to ink), or `—` when the percentage is null; then the optional trailing `actions`. The title is the line's one `Expanded` child and takes the free width; the chip keeps its natural width up to `DownloadQueueTile.chipMaxFraction` (40%) of the line and ellipsises past it, so chip and percentage sit on the trailing edge and a long label never starves the name.
- Chip: padding 7 × 2, `AppRadius.xs`, fill the tone's `statusToneColor` at 12%, label in `labelSmall` w600 walked against that 12% composite. The row takes a `StatusTone`, never a colour.
- Bar (only when `progress` is non-null): 4 above, a 4pt `LinearProgressIndicator` clipped to `AppRadius.xs`, track `surfaceContainerHighest`, value in the blue tone (in progress: `statusToneColor(info)` walked against the track); a stale sample (`sampleAge`) drains it to `onSurfaceVariant`.
- Second line: 4 above, `bodySmall` with tabular figures in `onSurfaceVariant`, one line, ellipsised — whatever the client counts down (status, ETA, remaining size).
- Metrics (optional): 4 above, 12 apart; an 8pt dot, 4, and the value in `labelSmall` tabular, both in the primary ink when `accented`, else `onSurfaceVariant`.
- Menu (`DownloadQueueActionsMenu`, the Usenet pair): a `PopupMenuButton` with an 18pt `more_vert_rounded`, tooltip *Job actions*, offering *Pause* or *Resume*, then *Delete job*.

## States

As qBittorrent maps them (the tone rule, applied once in `_toneFor`):

- **Downloading**, **Fetching metadata**, **Checking** — `info`; the bar in blue, `↓` rate accented (ink) and `↑` rate neutral.
- **Stuck** and **Error** — `warning`: a fault the client reported. An errored torrent draws no bar.
- **Stopped** and **Queued** — neutral: a deliberate stop and the backlog. Stopped keeps its bar and prints no ETA; Queued draws no bar, and qBittorrent's unknown ETA prints `∞`.
- **Seeding** (complete) — `success`, no bar (a full bar would say "finishing").

Across clients:

- **Stale** (`sampleAge` set) — the second line becomes *as of 6 min ago* (`formatDurationAge`) and the bar keeps its position but drains to `onSurfaceVariant`.
- **Transmission** prints the remaining size while downloading and *Ratio …* while seeding, and a blocking error (the client's own error string) or *Stuck* replaces the chip's label.
- **Usenet rows** (SABnzbd, NZBGet) carry no chip and no metrics: the state heads the second line (SABnzbd *Downloading · 0:12:00 · 1.2 GB left of 3.4 GB*, passing its raw `timeleft`; NZBGet *status · category · remaining*, or *progress unknown* with a null percentage and no bar), and `DownloadQueueActionsMenu` trails the first line.

## Consumer provides

`title`, `subtitle`, `progress` (null draws no bar, which is different from 0), `percentage` (null prints `—`), `accent`, `statusLabel` and `statusTone`, `metrics` (`DownloadQueueMetric`: `label`, `accented`, `spoken`), `sampleAge`, `selected`, `actions` and the `onTap` / `onLongPress` callbacks.

## Semantics

The row is one container that speaks one sentence — *title, state, 63 per cent, second line, metrics* (a null percentage says *progress unavailable*; a metric's `spoken` text replaces the arrow: *downloading at 25.0 MB/s*) — reports selection as a state when it is interactive, and carries tap and long-press itself; `actions` is the only child left on the reader's path. Long-press starts selection and is never the menu.

## Do / don't

- Do pass `null` progress for a job that has not started.
- Don't pass colours: the chip takes a `StatusTone`, a metric takes a flag.
- Don't put the row's commands behind long-press.
