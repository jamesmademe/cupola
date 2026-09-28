# DownloadQueueTile

One row of a download client's queue: name, state chip, percentage, a thin bar and a counting-down line, shared by qBittorrent, Transmission, SABnzbd and NZBGet.

Hand-written from `lib/core/widgets/download_queue_tile.dart`; the qBittorrent mapping is `lib/features/qbittorrent/presentation/widgets/torrent_tile.dart`. Torrent names, sizes and rates are illustrative.

## Values

- Outer padding `space-lg` × `space-xs`. Plate: `surface`, 1px `outline-variant`, `radius-md`, inner padding `space-md`. Selected: accent at 8% with a 40% accent border.
- First line: title `body-medium` 600, one line, ellipsized; `space-sm`; state chip (sentence case: *Downloading*, *Seeding*, *Paused*); title and chip are each `Flexible`, so a long label shrinks instead of overflowing; `space-sm`; percentage `label-medium` 600, tabular, in the client accent walked with `onTint` against `surface` (the only accent-coloured text on the row); then the optional trailing menu.
- Chip: padding 7 × 2, `radius-xs`, fill = the tone colour at 12%, label `label-small` 600 walked against that 12% composite. The tone goes through `statusToneColor`; the plate takes a `StatusTone`, never a colour.
- Bar (only when `progress` is non-null): `space-xs` above, 4 tall, `radius-xs`, track `surface-container-highest`, value in the accent.
- Second line: `space-xs` above, `body-small` tabular in `on-surface-variant` — status, ETA and remaining size, counting down.
- Metrics (optional): `space-xs` above, `space-md` apart; an 8px dot plus `label-small` tabular, both in the walked accent when `accented`, else `on-surface-variant`.

## States

As qBittorrent maps them (the tone rule, applied once in `_toneFor`):

- **Downloading** (also *Fetching metadata* and *Checking*) — `info`, bar in the accent, `↓` rate accented and `↑` rate neutral.
- **Stalled** and **Error** — `warning`: a fault the client reported. An errored torrent draws no bar.
- **Paused** and **Queued** — neutral: a deliberate stop and the backlog. Queued draws no bar; qBittorrent's unknown ETA prints `∞`.
- **Seeding** (complete) — `success`, no bar (a full bar would say "finishing").
- **Stale** (`sampleAge` set) — the second line becomes *as of 6 min ago* and the bar keeps its position but drains to `on-surface-variant`.
- Usenet rows (SABnzbd, NZBGet) carry no chip and no metrics: the state sits at the head of the second line (*Downloading · 0:12:00 · 1.2 GB left of 3.4 GB*, SABnzbd passing its raw `timeleft`), and a `more_vert` 18px menu (Pause or Resume, Delete) sits in a 48pt button.

## Consumer provides

Title, subtitle, progress (null = no bar, which is different from 0), percentage (null prints `—`), accent, chip label and tone, metrics, `sampleAge`, selection and the callbacks. 

## Semantics

The row is one container that speaks one sentence — *title, state, 63 per cent, second line, metrics* (metric `spoken` text replaces arrows: *downloading at 25 MB/s*) — reports selection as a state, and carries tap and long-press itself; the menu is the only child left on the reader's path. Long-press starts selection and is never the menu.

## Do / don't

- Do pass `null` progress for a job that has not started.
- Don't pass colours: the plate takes a `StatusTone`.
- Don't put the row's commands behind long-press.
