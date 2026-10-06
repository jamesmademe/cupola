# ShelfPage

The page of a person and their shelf: an artist on Lidarr and their albums, an author on Readarr and their books. Who they are, what the shelf holds and where each work stands, then what the service does for them and the way to it. The Media page's room, without its slab: a person has no backdrop, their works do.

Lidarr's Library opens an artist's page (`/dashboard/lidarr/library/artist/:id`), Readarr's an author's (`/dashboard/readarr/library/author/:id`), each with the connection in `?i=`; every read and every write goes to that connection.

Rendered from `lib/features/media/presentation/shelf_page.dart` (`ShelfPage`, `ShelfIdentity`, `ShelfCover`, `ShelfWorkRow`, `ShelfSliverGroup`, `ShelfFolderRow`, `ShelfOpenIn`), `lib/features/music/presentation/artist_page.dart` (`ArtistPage`, `AlbumTracks`) with the albums' places and words from `lib/features/music/domain/artist_shelf.dart`, and `lib/features/readarr/presentation/author_page.dart` (`AuthorPage`) with the books' from `lib/features/readarr/domain/author_shelf.dart`, by `test/design_catalog/shelf_page_catalog_test.dart`.

- **Room** — `CupolaRoom.ground` under `AppGradients.ambientBackground`, washed with the light of the first cover the page has drawn (else the person's photo; the lamp until one is read). One column, gutter `AppSpacing.lg`, never wider than `breakpoint.reading-well` (720) and centred in a wider window. Whatever scrolls under the clock fades into the room (`StatusBarScrim`).
- **Plates** — the back plate (`MediaBackPlate`) on the left and the page's other actions (`MediaPlate`, `more_horiz`) on the right, each 44, `fillControl`, `AppRadius.control`, the edge.
- **Identity** — a 92 disc: the person's photo, or their initials in the feature role on the light at 18% with its edge at 40% (`fillControl` and the edge, unlit). Beside it the name in the screen role, three lines then an ellipsis, and what the shelf holds in the label role at 400, `inkSecondary`: `3 albums on disk · 1 wanted · 1 announced`, `7 books · 6 on disk · 1 wanted`; a figure keeps its word on its line.
- **Covers** — on the artist's page, up to three album covers under the name, on disk first and newest first: a third of the column each (at most 160), `AppRadius.poster`, glowing with the light. Without artwork the strip is not drawn.
- **Actions** — the artist's: `Search albums` (Lidarr's search for every monitored album) and `Manage` (to Details), outlined, side by side. The more plate opens `Search releases`, `Import files` and `Remove from Lidarr`; the author's, `Search for every wanted book` and `Remove from Readarr`.
- **The albums** — in four places, each a heading and a group (`ShelfSliverGroup`: `AppRadius.group`, `fillQuiet`, hairlines, rows built as they scroll in): **Coming** (announced, the soonest first: `Out Fri 2 Oct · not out yet` and `Lidarr looks for it once it's out`), **Wanted** (out, monitored, nothing on disk), **On disk** (a track or more), and **Unmonitored** behind `Show them`. A row (`ShelfWorkRow`): the 64 cover (`AppRadius.chip`; without one the plate, `plateWell` and a disc in `plateDimInk`, dark in both rooms), the title in the row role, `2010 · 5 tracks · 21 min` in the meta role, and the state after its dot or ring (`MediaStateWord`): `Complete` green, `4 of 5 tracks`, `Wanted`, `Unmonitored` with the ring, the queue's word in its tone (`Downloading 60%`). A word that needs the queue waits for it and reads `Unknown` once it failed.
- **An album open** — the row opens in place on its tracks (`AlbumTracks`), read on opening: the number, the title, the length, 44 tall with hairlines; a track not on disk is quieter when some are. Under them `5 of 5 tracks on disk`, then for an album with a gap `Search for this album` (the primary) and, for any album out, `Search releases`.
- **The books** — `Readarr is no longer maintained; finding new books may not work. Your books, and searching for a wanted one, still work.` once, under the name: a door (`AppRadius.button`, `fillQuiet`, hairline), the info glyph and the first clause in blue. Then **Books** `by year`, three to a row: each cover at 2:3 (`AppRadius.chip`), or a plate with the title and, under a hairline, the author (`plateSurface`, `plateInk`, dark in both rooms: artwork is not palette); a book not on disk has a dashed edge. Under it its state and its year (`Wanted 1863`, `1864`). Then **Wanted**: a card each, the small cover, the title, `Wanted · no file yet`, `1863 · quality profile eBook`, and `Search for this book`.
- **Details** — one group: `Monitored` (`Lidarr keeps these albums up to date`, `Readarr looks for missing books by this author`), the artist's `Monitor new albums` (`New releases are added and searched for on their own`; on writes `all`, off `none`), `Quality profile` (a picker when there is more than one, asked before it is written), and the folder in the mono role (`ShelfFolderRow`). Each switch shows its new state once the service has taken it.
- **Open in Lidarr** — the label role in `inkSecondary` with the open glyph, centred: the same page in the service's own web app.
- **Remove** — through `showAppConfirmDialog`: `Remove Jan Morgenstern from Lidarr?`, `Lidarr stops looking for their albums.` (`None of their albums are on your server yet.` when nothing is on disk), `Also delete 1.1 GB of files` when there are any, `Don't add them again`; Cancel reads `Keep them`.
- **Twice the reading size** — the name goes under the disc in the room role, the two actions one to a line, a setting's value under its label, and the books two to a row. A cover's lettering keeps the cover's size (it is a picture of a cover); the book's title is written under it instead, at the reader's size.

The consumer provides the record's id and, optionally, the connection (`instanceId`), the library's record to stand in while the page reads its own, and a `heroTag` (the disc takes the flight). Everything else is read: the record, the albums or books, the queue of that connection, its quality profiles.

Semantics: the name is the page's header; a work's row speaks one sentence and is one button when it opens (`Sintel, 2010, 5 tracks, 21 minutes, Complete`), a track speaks `Track 3, The Dragon, 5:36, on disk`, a book `Five Weeks in a Balloon, 1863, Wanted`. The disc, the covers and the plates are silent; the more plate says whose actions it holds.

Do: say where every work stands in the lexicon's words, and let a word that needs the queue wait for it. Don't: paint the service's accent, call a person "it", or offer a search for something the service cannot look up (Readarr finds no new book).

## States in the catalog

Each sheet is drawn in the dark and the light room.

- The artist lit by the first cover: announced, on disk, the settings, the way to Lidarr.
- No artwork: the initials, the plates, the lamp; one album wanted.
- An album open on its tracks.
- The author: Readarr retired, the books by year, the wanted one dashed and searched for from its card.
- Text at 200%: the artist and the author.
- Reading the artist; a wide window, the column centred.
