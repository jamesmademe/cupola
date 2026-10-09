# HomeModule

One module of the Home in the slab every module shares, the operator's modules of content (Continue watching, Coming
up, Arrived, Downloads, Requests, Now playing; Featured, which has no slab, is
[FeaturedPager](../FeaturedPager/README.md)), the three a person adds in Edit Home (Stack health, Storage, Discover
shelf), and the two pieces of the operator's Home that are not modules of content: Needs you at the top and Set up
next at the foot. A module decides its state; the frame draws it,
so no module invents its own way of loading, failing or asking for a service.

Rendered from `lib/features/home/presentation/widgets/home_module_frame.dart` (`HomeModuleFrame`),
`lib/features/home/presentation/widgets/needs_you_banner.dart` (`NeedsYouLine`, its words from
`lib/features/home/domain/needs_you.dart`) and `lib/features/home/presentation/widgets/set_up_next_module.dart`
(`SetUpNextModule`, `EditHomeRow`, its suggestions from `lib/features/home/domain/set_up_next.dart`),
`downloads_module.dart` (`HomeDownloadsModule`, `DownloadRow`, words in `lib/features/home/domain/downloads.dart`),
`requests_module.dart` (`HomeRequestsModule`, its rows `DecisionRow` in
`lib/features/services/presentation/dashboard_sections.dart`), `now_playing_module.dart` (`HomeNowPlayingModule`,
words in `lib/features/home/domain/now_playing.dart`), `continue_watching_module.dart` (`HomeContinueWatchingModule`,
`ContinueWatchingRow`, words in `lib/features/home/domain/continue_watching.dart`, read by
`lib/features/home/data/resume.dart`), `coming_up_module.dart` (`HomeComingUpModule`, its rows `CalendarRow.home`, see
[CalendarAgenda](../CalendarAgenda/README.md), words in `lib/features/home/domain/coming_up.dart`),
`arrived_module.dart` (`HomeArrivedModule`, `ArrivedCard`, words in `lib/features/home/domain/arrived.dart`),
`stack_health_module.dart` (`HomeStackHealthModule`, `StackLightMark`, words in
`lib/features/home/domain/stack_lights.dart`, read by `lib/features/home/data/stack_lights.dart`), `storage_module.dart`
(`HomeStorageModule`, `StoragePoolRow`, words in `lib/features/home/domain/storage.dart`, read by
`lib/features/home/data/storage.dart`), `discover_shelf_module.dart` (`HomeDiscoverShelfModule`, its shelf
`DiscoverCarousel`) and `home_module_parts.dart` (`HomeModuleLink`,
`HomeCoverageNote`, `HomeRowArt`, `HomeRowBar`), by
`test/design_catalog/home_module_catalog_test.dart`. Which modules a person's Home has, in what order, is the registry
`HomeModule` (`lib/features/home/domain/home_module.dart`) read through the person's saved layout; see
[EditHome](../EditHome/README.md).

## The five states

- **Loading** (`HomeModuleFrame.loading`): the module's name in the section role over the shape of its rows (two
  list rows unless the module passes its own skeleton, a poster row for Arrived). Never a spinner in the middle of the
  Home. Spoken `Loading downloads`.
- **Ready** (the default constructor): the name, the line under it in `meta` and `inkSecondary` (`2 wait for you`,
  `3 moving · 1 stuck · 40.4 MB/s`), an optional quiet link at the end of the heading, the rows. Rows are
  rows of the slab, a hairline between them, never cards inside it.
- **Nothing to say**: no frame. The module draws nothing and the next one moves up: the Home has no empty boxes. Only
  when every source answered: a source that did not answer is not an empty one.
- **Its sources did not answer** (`HomeModuleFrame.silent`): the module keeps its place and says which service and why
  through the classification (`coverageFailureSentence`), as a `FaultBand.section` (red, a source did not answer) or
  `FaultBand.partial` (amber, it answered with a fault), with Retry. What was last known may sit above it, dimmed.
- **Its service is not set up** (`HomeModuleFrame.needsService`): no slab yet, a dashed `edge` outline in its place,
  the service's mark in a 36pt tile, its headline (`Set up TrueNAS to see your storage`) over what it would show, and
  `Set up TrueNAS` as a quiet pill at the end, the whole outline one target. At a large reading size the pill goes under
  the words. Only for a module the person switched on in Edit Home; a module on by default whose service is missing is
  not drawn, and Set up next names the service once.

The slab is `slab`, `AppRadius.slab`, a `hair` edge, padding `gutter` × `slabY`, `md` between modules.

## Needs you

One line, one target, first on the operator's Home and absent when nothing is wrong (the header's `12 of 12
answering` already answers) or before anything answered (no space is held for it).

- A service that did not answer leads, the glyph red: `Radarr did not answer at 20:53`, and the line is its Retry
  (`Retry both` for two). Its faults cannot be seen while it is silent.
- Otherwise the largest group of equal faults leads, the glyph amber: `18 downloads need a manual import`; a single
  fault is a sentence about it (`Big Buck Bunny is stuck`, `The media stack stopped`, `The certificate for
  nas.home.arpa expires in 6 days`). The line is Review, which opens the place that fault is fixed today.
- `+2` when more things need the person. A request waiting for approval is not a fault: it is never in Needs you.
- `fillQuiet` under a `hair` edge, `AppRadius.button`, at least 52pt tall. At a large reading size the count and the
  way in go under the sentence.

## Continue watching, Coming up, Arrived

- **Continue watching**: up to three titles started and not finished, on every Jellyfin and Plex. A row is a 112×63
  picture (the episode's still, a movie's art), the series in `row` 600 (a movie's title), `S2 E3 · The Second Cycle`
  (a movie's year), `5 min left` in ink, and an ink bar: how far somebody got is not a status. At a large reading size
  the words go under the picture. The line under the name is the server. A Jellyfin set up with a server key and
  nobody chosen asks once, in an outlined row: `Which Jellyfin user are you?` · `A server key sees every user; pick yours
  once`, to that connection's form where the picker is. Absent when nothing is in progress and every server answered,
  and when its only title is already Featured's first slide (while Featured is on the Home).
- **Coming up**: what comes out or airs from today to three days on, three rows (`CalendarRow.home`: the day leading,
  an episode's time opening its status), then `Calendar` in the heading to the calendar's page. Tones as the calendar
  has them: downloading blue, not out yet and not aired neutral, never amber. Nothing in the window is a calm line,
  `Nothing comes out or airs by Friday` · `The calendar has the rest of the month.`, never an absence; absent only
  without an arr that dates things. A connection that did not answer is named over the rows.
- **Arrived**: one card per title imported in the last seven days, the newest first: a 200 pt card of 16:9 art (the
  title's fanart, else its poster), the title, then `2 h ago · Radarr 4K` (the connection only while the service has
  two). A movie on two Radarrs is one card; a series is a card when it is new to the library, not with each new
  episode; an album is one card. The line under the name is `Last 7 days · 4 new`, never "this week"; with a library
  silent, who the count is from, `Last 7 days · 2 from Radarr`, and the silent one named over the rail. A failed import
  is not an arrival: Needs you has it. Absent when nothing arrived and every library answered.

## Downloads, Requests, Now playing

Each row is the 36×54 art (`HomeRowArt`: the poster, or the service's plate), the title in `row` 600 and a quiet line
under it, a hairline between rows. A 4pt bar (`HomeRowBar`) says how far something got.

- **Downloads**: four rows at most, no sizes. A moving download says `88% · 1 min` beside its title in blue
  (downloading is information), its release under it in mono (a machine string, exactly as named), a blue bar. A
  stalled or failed one is chosen first and drawn last, its value amber (`Stuck at 47%`, `Failed`), its bar amber, and
  under it `Try another download` in the amber fill with a 44pt More (`Open in qBittorrent`, `Remove`); a torrent no
  arr asked for offers `Open in qBittorrent` alone. The line under the name counts `3 moving · 1 stuck` and the clients'
  speed, `—` while a client that is set up did not answer; with no client, `Speeds come from your download client`
  under the rows. A blocked import is not a download: the footnote names it once (`18 need a manual import · in Needs
  you`). Nothing moving is `Nothing is downloading` with `The last download finished at 18:52.`, and the link reads
  `Activity`. At a large reading size the value goes under the title. The module is read again every 30 s while the
  Home is on screen.
- **Requests**: `2 wait for you`, from Seerr's own count. A row says who and when (`Anna · 2 h ago`); under it
  `Approve` in the ink fill and `Decline` outlined, the same width. Neither takes a tone: a request is not a fault.
  Approved or declined here, the row says what happened (`Approved · sent to Radarr`, `Declined`) without its buttons,
  in its place, until the Home is read again. `See all requests` when more wait than the rows show.
- **Now playing**: one row per playback, a disc with the viewer's initial, `Anna · Sintel` (an episode by its code),
  `Living room TV · 9 min left` (`Stopped` while the player holds it), an ink bar: watching is not a status. The line
  under the name is the server (`Jellyfin`). Absent when nobody watches; a server that did not answer keeps it in place.
  Read again every 30 s while the Home is seen.

## Stack health, Storage, Discover shelf

Off until the person switches them on in Edit Home: the header already says how many services answer, and the rest
lives a tab away. Each sits after Now playing.

- **Stack health**: `Stack`, the line `12 of 12 answering · 3 faults` (`Checking 12` before anything answered), then
  every configured service as its monochrome mark (`ServiceKey.icon`) in a 44pt `fillStrong` tile, the Stack's order,
  six to a row on the phone. Each mark has one 9pt light at its corner: green answering, amber a fault (a refused key, a
  connection silent beside one that answered, or a fault Needs you holds for it), red when every connection did not
  answer, a hollow ring while it is asked. A light eases on once (`motion.standard`) and keeps its colour while the
  probe is read again. Faults are counted in groups, as Needs you counts them. Under the marks: a service that did not
  answer, red, with Retry; otherwise `Faults: Sonarr, qBittorrent, TrueNAS` in amber; while nothing has answered,
  `Asking each service`. The marks are one target, to Stack. Switched on, it never steps aside.
- **Storage**: `Storage`, the line `TrueNAS` (the servers it read), then each pool, up to four: its name and share in
  `row` (`tank` · `72%`), a 6pt bar in ink on `fillStrong` (usage is not a state), `31.2 of 43.6 TB` and its state
  (`Healthy · scrubbed Sunday`, `Degraded`, a dot green or amber), and under it each disk in trouble on an amber wash
  with a chevron (`Disk sdd reports 8 errors`, `Disk 3 is disabled`). A pool TrueNAS does not call healthy is read
  again with its topology, the only answer that names the disk. An Unraid array is one pool, `Array`. The pool is one
  target, to its page. Read again every 60 s while the Home is seen. Without TrueNAS or Unraid it asks for TrueNAS.
- **Discover shelf**: no slab. Seerr's `Trending this week` as Discover draws it (`DiscoverCarousel`, its posters
  [CatalogPoster](../CatalogPoster/README.md)), the library's state on every poster, its heading the way into
  Discover. Never a count. Without Seerr it asks for Seerr: `Set up Seerr to discover movies and series`.

## Set up next and Edit Home

- **Set up next** (`SetUpNextModule`): at most three services the stack lacks, each with what it adds (`Set up
  Jellyfin · Play, Continue watching and Now playing`), ordered by how much, then `All services`. A Plex stands for
  Jellyfin, any download client for the four. Absent when nothing it knows of is missing. Each row opens that service's
  setup form in Settings, whose way back leads to the Home.
- **EditHomeRow**: the last thing on the operator's Home, a dashed `edge` around `Edit Home · Reorder and hide
  modules`, opening `/home/edit`.

## Semantics

A module's heading is one header node: its name and the line under it (`Requests, 2 wait for you`). Needs you is one
button whose label is the whole sentence, the way in at its end (`18 downloads need a manual import, and 2 more things
need you. Review`), announced when it appears. Each Set up next row is one button, its line as the value.

## States in the catalog

Each sheet is drawn in the dark and the light room: the frame ready, loading, silent and needing a service; Needs
you led by a group, by one fault and by a silent service; Set up next over Radarr, Sonarr and Seerr; Downloads moving
with one stuck, with qBittorrent silent, and with nothing moving; Requests with one row answered; Now playing with two
playbacks; Continue watching with two titles and asking who you are; Coming up over three days, and with Lidarr silent
and nothing by Friday; Arrived over a week, and with Radarr 4K silent; Stack health with three faults, with Radarr
silent, and checking; Storage with a disk in trouble, and with TrueNAS silent; Storage and Discover shelf asking for
their services; the Edit Home row; text at 200% with Downloads, with Stack health, Storage and Discover shelf asking for
Seerr, and with Continue watching, Coming up and Arrived.

## Do / don't

- Do let a module draw nothing when it has nothing to say, and only then.
- Don't put a card inside the slab, or a second Retry under a silent module.
- Don't paint Approve green or Decline red: neither is a state. Red is a service that did not answer.
- Don't paint a full pool amber: only a state takes colour, and 90% used is a figure.
- Don't say `Set up X` twice on one Home: a missing service is named by Set up next, once.
