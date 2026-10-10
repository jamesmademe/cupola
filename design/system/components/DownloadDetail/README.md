# DownloadDetail

One download's own page: who it is, where it stands and how fast, the steps from the grab to the server, what can be done, and the facts. A download's row on Activity opens it, and so does the Home's Downloads row.

Rendered from:

- `lib/features/activity/presentation/download_page.dart` (`DownloadPage`);
- `lib/features/activity/presentation/widgets/download_parts.dart` (`DownloadHero`, `DownloadReadout`, `DownloadSteps`, `DownloadFacts`).

The catalog test is `test/design_catalog/download_detail_catalog_test.dart`. The words come from `lib/features/activity/domain/download_page.dart`, never from a widget; what the \*arr's record says about the title (the year, the profile, the folder, the episode) from `QueueTitle` (`lib/features/services/domain/queue_title.dart`), read with the queue.

## Where it is drawn

| place | how it opens |
|---|---|
| `/activity/download?i=&id=`, under Activity | a row of Downloads or Up next (`openDownload`); the Home's Downloads row (`go`, Activity behind it); a link |
| beside the list, on a touch window from 1024 (`MediaSplitLayout`) | the same row; the row wears the selection ([ActivityRows](../ActivityRows/README.md)) |

`i` is the connection the download was read from: its \*arr's, or its client's when no \*arr asked for it. `id` is the client's id for the transfer (the torrent hash, the usenet job's id), which the client's own row shares, so a link made before an \*arr claimed a torrent still finds it (`downloadAt`). The page is read from the address alone.

The desktop draws the same page until the inspector takes it.

## The page

It stands in the title's room ([MediaRoom](../MediaPage/README.md), shared with a title's page): the ground washed with the poster's light, the clock legible over what scrolls, and in a pane the light rising from the list's side. The column stops at `AppBreakpoints.readingWell`. The back plate reads `Back`, or `Close` in a pane.

- **The hero**: the poster (88 × 132 on a phone, 120 × 180 from a 520 column; the plate with the service's glyph without one), and beside it, on its foot, the title in `AppType.room` (a header to a screen reader) and the line under it in `AppType.meta` `inkSecondary`: `2021 · out on digital today · Anna asked for it`. A Sonarr download reads its episode: `S2 E4 · The Second Cycle`. A release is named only on its day (`out on digital today`, `out on disc today`, `in cinemas today`). At a large reading size the title goes under the poster.
- **The readout**: one `ActivitySlab`, 16 inset.
  - `62%` in `AppType.figureHero`, the page's one readout, and beside it the stand in its tone, `AppType.label` w600: `Downloading` and `Queued` blue, `Stopped` in the neutral, `Stuck`, `Failed` and `Needs you` amber.
  - Under it, the pace in `AppType.meta` tabular: `4.2 MB/s · 11 min left · ready around 21:10`; `Starts in about 6 min` (SABnzbd) or `Waits its turn in qBittorrent`; `1.2 of 2.0 GB arrived` when stopped; `Nothing for 3 h` when stuck.
  - **The speed since the page was opened**: a line in the stand's tone over a wash fading down, its last reading a dot, time left to right, the fastest reading near the top. Under it, in `AppType.caption` `inkTertiary`, `since you opened this · 4 min`. A reading is taken each time the queue is read while the download moves and its client measures it; an hour of them at most. Drawn from the second reading: beside the figure (160 × 40) from a 480 slab, under it the slab's width (36 tall) on a phone. Silent to a screen reader.
  - A 6pt bar in the stand's tone over the track.
  - **The steps** (an \*arr's download only): `Grabbed` (`Radarr → qBittorrent`), `Downloading` (`qBittorrent · 62%`), `Import` (`Radarr, when it finishes`), and `On Jellyfin` (`around 21:10`, `once imported`) when a media server is set up (Jellyfin, else Plex; none for Readarr). Each a tile with a hairline, `AppRadius.md`: the glyph, the name in `AppType.label` w600, the detail in `AppType.meta`. Done is a green tick; now, a blue ring; stopped, a pause in `inkSecondary`; to come, an empty ring in `inkTertiary`; the step a fault stopped on, the amber warning with its detail amber (`qBittorrent · stuck at 47%`, `Radarr needs you`). Four side by side when each gets 116, two to a line on a phone, one to a line at a large reading size.
- **A fault's remedy** takes the lead's place, under the readout: a stall or a failure is Needs you's card reduced to its cause and its ways out (`StuckDownloadCard.remedy`: `Nothing has arrived for 3 hours, and nobody sharing it has the whole file any more.`, `Try another download` in the amber fill, `Remove`, `Keep waiting`), on a slab; an import that needs you, the group's card with its `Review`.
- **What can be done**:
  - the lead, `Open Sprite Fright`, lit by the title (`mediaLeadStyle`), at 52: the title's page under Activity, on this connection's copy; an artist or an author on its \*arr; `Open in qBittorrent` in the ink for a transfer no \*arr asked for. Under a fault's remedy it is outlined: the remedy is the page's one fill.
  - under it, side by side (one to a line at a large reading size): `Stop` (a square; `Resume` with a play glyph once stopped) and `Remove`. Stop asks the client moving the bytes to stop and keeps what arrived (qBittorrent's stop, Transmission's `torrent-stop`, SABnzbd's and NZBGet's pause of the one job); it is offered while a connected client moves the download and it has not finished or failed. The page says `Stopped` as soon as the client answers, until the queue says the same or, after two reads that do not, the queue's word stands. Remove asks the neutral question Needs you asks (`Remove Sprite Fright's download?`), goes through the \*arr's queue and never the client alone, and the title stays wanted; then the page closes and says `Removed · Sprite Fright stays in your wanted list`. A download with a fault has its Remove in the remedy.
- **The facts**: one `ActivitySlab`, a row each with a hairline: the label in `AppType.body` `inkSecondary` on the left, the value in the ink on the right. `Release` and `Folder` are a machine's strings, in `AppType.mono`, breaking after their dots (`machineNameWithBreaks`); `Profile` reads the profile with its \*arr (`HD-1080p · Radarr`), once the \*arr has listed its profiles; `Client` the client, and its address in mono (`qBittorrent · nas.home.arpa:8080`). At a large reading size the value goes under its label.
- **Gone**: `This download is no longer in the queue` in `AppType.section`, with its import of today under it when one landed (`ActivityHistoryRow`). When the connection did not answer, the coverage note says who, never that it is gone.
- **While reading**: the back plate over `AppSkeleton.detailBody()`.

The page is read again with Activity's downloads (`activityLivePollProvider(downloads)`, every 15 seconds while it is on screen), and on a pull.

## Semantics

- The title is the page's header.
- The readout is one node: `62 percent, Downloading, 4.2 megabytes per second, 11 min left, ready around 21:04`. The speed's line is silent.
- Each step is one node: `Grabbed, Radarr → qBittorrent, done`; `Import, Radarr, when it finishes, to come`.
- Each fact is one node: `Client, qBittorrent, nas.home.arpa:8080`.
- `Stop` is heard as `Stop, keeps what has arrived`, `Resume` as `Resume, picks up where it stopped`; each has the same words in its tooltip.

## States in the catalog

Each sheet is drawn in the dark and the light room, on the phone and on the desktop.

- The page over Sprite Fright: the hero lit by the poster, 62% Downloading, the steps to Jellyfin, Open, Stop and Remove, the facts.
- The hero alone.
- The readout downloading with four minutes of speed under the figure; queued; stopped; stuck; finished and waiting for an import.
- The facts.
- Text at 200%: the steps one to a line, the facts stacked.
- Beside the list on a tablet (620): the steps side by side, the speed beside the figure.

## Do / don't

- Do read a download from its address: the queue the page reads is the one Activity reads, nothing more.
- Do say only what a source said: no `ready around` without the client's estimate, no profile before the \*arr listed it, no speed before a second reading.
- Do send Remove through the \*arr's queue, so the \*arr stops waiting for the bytes.
- Don't offer Stop for a download its client was not matched to: the \*arr cannot stop a transfer.
- Don't light two fills: under a fault the remedy is the one.
