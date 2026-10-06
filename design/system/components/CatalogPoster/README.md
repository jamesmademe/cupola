# CatalogPoster

One title of Seerr's catalogue as a tile: the poster with what Seerr holds of it in the corner, the title under it and TMDB's score.

Rendered from `lib/features/discover/presentation/widgets/catalog_poster.dart` by `test/design_catalog/catalog_poster_catalog_test.dart`.

- **Poster** — a `ContentCard` in a 2 : 3 box the tile's width wide, inside the `Hero` the title's page flies from (`MediaPosterCard.flightOnUserGestures`), with the tile's hero tag as its `paneTag` so the poster whose title a tablet's pane shows wears the ring.
- **State** — the poster word (`StatusBadge.poster`: a dot in the tone and the word, or the percentage while bytes arrive) in the card's corner, from the catalogue's own answer (`mediaInfo`) through `seerrCatalogStatus`, in the words of whoever reads it: the operator's (Available, Waiting for approval, `62%` while it downloads, Stuck) or the requester's (On the server, Waiting for approval, Downloading, On its way; never a fault). A title Seerr holds no record of wears no badge, which is most of a catalogue: its page says it can be asked for, with its Request. Seerr's own `Unknown` states no fact and wears none either.
- **Title** — the body role at 600 in `on-surface`, two lines then an ellipsis.
- **Score** — `TMDB 7.4` in the caption role (`bodySmall`) and `dimText`, the source glued to its figure (`unitSpace`). TMDB's zero is a title nobody rated: no score is drawn.
- **Reading size** — the words follow the reading size up to the compact tile's ceiling (`TextScaleMetrics.defaultMaxScaleFactor`, 1.6x) and the tile grows with them (`CatalogPoster.heightFor`, which a rail uses for its height and a grid for its row); past it they ellipsise, never breaking inside a word.
- **Tap** — `PressableScale`; it opens the title's page under the tab it is in (`openSeerrTitle`).

The consumer provides the `MediaPreview`, the hero tag, the tile's width, and the kind when the row fixes it (a movie rail).

Semantics: one button named by the title, with the state and the score as its value (`Available, TMDB 7.4`); the badge and the words under the poster are silenced.

## States in the catalog

Each sheet is drawn in the dark and the light room.

- The operator: on the server, waiting for approval, downloading at 62%, and a title Seerr holds nothing of.
- The requester: the same four in her words.
- Text at 200%: the words at the ceiling, the long title ellipsised.

Do: give a rail or a grid the height `heightFor` answers; lay a grid out with `MediaGrid.columnsFor`. Don't: put a badge on every poster to say it can be requested, or draw a 0 for an unrated title.
