# ActivityRows

The rows Activity draws on its slabs: `ActivityDownloadRow` (one download, moving or stuck), `ActivityDownloadRow.queued` (one that waits its turn, in Up next), `ActivityHistoryRow` (one record of what happened: an import or a failed download) and `EveryoneRequestRow` (one of the household's requests). They share one frame, `ActivityRowFrame`: the art at the start, the lines beside it, one sentence to a screen reader, the whole row a target, and what else it offers on a long press.

Rendered from `lib/features/activity/presentation/widgets/activity_download_row.dart` (`ActivityDownloadRow`, `ActivityRowFrame`, `openArrTitle`) `lib/features/activity/presentation/widgets/activity_history_row.dart` (`ActivityHistoryRow`) and `lib/features/activity/presentation/widgets/everyone_request_row.dart` (`EveryoneRequestRow`), with their words from `lib/features/activity/domain/activity_download.dart`, `lib/features/activity/domain/activity_history.dart` and `lib/features/activity/domain/everyones_requests.dart` (`everyonesLine`, `everyonesTone`), by `test/design_catalog/activity_rows_catalog_test.dart`. The slab they sit on is the [`ActivitySection`](../ActivitySection/README.md) card.

## Where they are drawn

| place | row |
|---|---|
| Activity All and Downloads, Downloads | `ActivityDownloadRow`: what moves as its queue orders it, the stuck ones last |
| Activity All and Downloads, Up next | `ActivityDownloadRow.queued` |
| Activity All, Finished today; History, a section a day | `ActivityHistoryRow` |
| Activity All, Everyone's requests (the latest three); Activity Requests and Seerr's Requests tab (`RequestsBoard`), every request that does not wait for you | `EveryoneRequestRow` |

The remedy of a stuck download is in Needs you, once: the row only shows where it stopped. In a desktop window the downloads and Up next are a table instead ([DownloadTable](../DownloadTable/README.md)); the rows are a touch build's, at every width.

## Anatomy

- Frame: `AppSpacing.md` above and below, the art (`HomeRowArt.large`, 44 × 66: the title's poster, or the plate of the service when there is none), `AppSpacing.md`, then the lines. A hairline over the row when it follows another (`divided`).
- Title: `AppType.row` in the ink: one line on a download (three at a large reading size), two on a history record.
- Machine line: the release a download is, or the file an import became, in `AppType.mono` in `inkSecondary`, one line that fades rather than ellipsising. Only when it is not the title again. It is a machine's spelling and keeps the mono face.
- **Download, moving**: the route (`Radarr → qBittorrent`, `Radarr 4K → SABnzbd` on a second connection of the arr, the client alone for a transfer no arr asked for) in `AppType.meta` in `inkSecondary`, and at the end of the same line the value in the info tone (`88% · 1 min`, weight 600, tabular). Under it a 4pt bar in the same tone over the track fill; under the bar, at its end, the speed (`12.1 MB/s`) in `meta`.
- **Download, stopped on purpose** (Downloads only, after the moving and the stuck ones; All leaves it out): `Stopped at 62%` in the neutral at the end of the route line, the bar in the neutral, no speed. Its Resume is on its page. Without the row a download stopped from its page had nowhere left to be resumed from.
- **Download, stuck**: the value is `Stuck at 47%` in amber (the warning tone), the bar amber, and where the speed would be, the proof: `nothing for 3 h` (minutes under an hour, then hours, then days from the second day). A client that dates nothing claims nothing: no proof line.
- **Download, queued**: no bar and no figure. A dot and `Queued · starts in about 6 min` in blue (just `Queued` when the client estimates nothing, or the time has come), then the route.
- **Whose request**: when Seerr holds a request for the title, a last line in `meta` in `inkSecondary`: `Anna's request · ready around 21:10` (`tomorrow 09:00` past midnight, the weekday later in the week; just `Anna's request` with no estimate or while it waits its turn). A request that was declined or failed asked for nothing that is coming, and a title with no id matches none.
- **History, imported**: a dot and `Imported 18:52` in green (the success tone, weight 600, tabular), the file under the title, the arr and its connection at the end in `meta` (`Radarr 4K`).
- **History, failed**: `Download failed 14:02` in amber, the reason in `meta` (two lines at most), the arr at the end. An event with no outcome of its own reads `Recorded 09:05`.
- **A request**: the poster (the title's, never the wide artwork), the title in `AppType.row` (two lines) with who asked at its end in `meta`, and under it where it stands and when in its tone, weight 600: `Downloading 62% · ready around 21:10` and `On its way · being fetched` in blue, `Ready to watch since 18:40` and `On the server since 12 Sep` in green, `Declined yesterday`, `Removed from the server` and `Blocked` neutral, `Didn't go through on Tuesday` in amber, the operator's to mend. The owner's words: an answer says when it was given, never the requester's `Declined by the server's owner`. A list that holds two Seerrs adds a third line in `meta`, the row's own (`Seerr Cabin`).

Tones go through `statusToneColor(colorScheme, tone, surface: room.slab)`: the rows sit on the slab, and the contrast is walked against it. Green is a completed import, amber a fault, blue what is queued or on its way. Never red: red is an unreachable service and nothing else.

At a large reading size (a text scale of 1.3 and over) a download's route and its value each take a line, so neither is squeezed; the route may take two.

## What a row opens

- A download opens its own page ([DownloadDetail](../DownloadDetail/README.md), `openDownload`), pushed over the view it was opened from, so Back returns to it; from there the title's page, or a transfer's client. On a tablet the page opens beside the list, and the row it was opened from wears the selection: the room's strong fill behind it, reaching `AppSpacing.sm` into the slab's inset with `AppRadius.md` corners, as a selected search row's, and `selected` to a screen reader (`ActivityRowFrame(selected:)`).
- A history record opens the title's page in its arr, the same way.
- A request opens the title's page (`openMyRequest`).

## What else a row offers

`ActivityRowFrame(actions:)`: nothing drawn on the row. A long press on a phone, a secondary click with a pointer, opens the theme's menu under the finger (`showRowActions`), each action with its glyph; a screen reader finds the same actions among the row's own (`CustomSemanticsAction`). A row with none opens on a long press as on a tap. A request's row offers `Delete request` to the key and to an account that manages requests, `Cancel request` to one that takes back only its own while it waits, and to an account of the operator's that may not, the item says why when chosen.

## The consumer provides

A download row: the `ServiceQueueItem`, the clock it reads its `nothing for` and `ready around` by (`now`), the request that asked for it when there is one, and `divided`. A history row: the `ArrHistoryEntry` and `divided`. The words are computed in the domain files and never in the row.

## Semantics

A row speaks one sentence and silences its parts. The frame is one button labelled with the title and carrying the rest as its value: for a download the state, the route, the speed in words (`12.1 megabytes a second`), the proof, whose request it is; for a history record the event, the file, the reason and the arr. The poster, the bar and the dot are decorative.

## States in the catalog

Each sheet is drawn in the dark and the light room, on the phone and on the desktop.

- A moving download with its request; two moving rows with a second connection named and a hairline between them.
- A row selected beside the open pane on a tablet, on the room's strong fill.
- A stuck download with its proof; a queued download in Up next with its request; a transfer no arr asked for; a download stopped on purpose.
- A history record: an import with its file and its connection, then a second; a download that failed with its reason.
- Text at 200%: a moving row and a stuck one; Up next and the client's own row; an import with its file and a failure with its reason.
- The desktop: downloads and an import on one slab in the page well.

## Do / don't

- Do put a row's words in the domain (`downloadRoute`, `nothingForWords`, `queuedWords`, `requestLine`, `historyEventLine`) so a test can hold them without drawing.
- Do keep the machine's spelling in the mono face and nothing else.
- Do say nothing rather than guess: no proof line for a client that dates nothing, no `ready around` for a queued download.
- Don't colour a row from a constant or from the scheme's green role: `statusToneColor`, held by `tone_paint_guard_test`.
- Don't give a row a button of its own. The remedy is Needs you's, and the row is one target.
