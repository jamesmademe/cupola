# DiscoverDoor

A way into the catalogue: one of the Discover atrium's six doors, or a tile of an index (a genre, a network, a studio, a mood, a language, a decade).

Rendered from `lib/features/discover/presentation/widgets/discover_door.dart` by `test/design_catalog/discover_door_catalog_test.dart`.

## Variants

- **Lobby** (`DiscoverDoor.lobby`) — at least 104 tall, three to a row on a phone and all six on one row once each would still be 104 wide (664 between the gutters: a tablet on its side, a desktop window; never a phone or a tablet's list beside a title). The name in the row role (Onest 15/20, 600) in ink and a line under it in the caption role in `dimText`, at the head. In the corner, what the door leads to: up to two posters leaning out of the bottom edge (38 wide, 2 : 3, `radius-thumb`, 6° and −8°, a soft `shadow` drop), or up to three names stacked and fading (the label role in `ink-secondary`, each a step dimmer: the networks).
- **Index** (`DiscoverDoor.index`) — two to a row on a phone, and a column more wherever another fits at 160, the tile of the narrowest phone: six across a tablet on its side. The name in the section role (Bricolage 21/24) in ink. Lit, at least 104 tall, the name sits at the foot under one poster leaning in from the top edge; plain, at least 92 tall, at the head.

Both are the room's door fill (`door`) with a 1px `hair` edge and `radius-door` (20). A door with artwork is lit by it: the picture decoded 24 pixels wide and laid over the whole door at 55% (60% on an index tile), which reads as the board's blur and costs no filter. Without artwork the fill and the name carry it.

## Reading size

The words follow the reading size up to the compact ceiling (`TextScaleMetrics.clampedScalerOf`) and the door grows with them: the height is a floor, never a box. A grid of doors lays them out row by row, each row as tall as its tallest door. Past 1.3x (`DiscoverDoor.largeTextScale`) a door drops its corner, the posters and the names being decoration that would sit on its name, and the atrium lays its doors two to a row instead of three (three instead of six in a wide window), where narrow doors would cut every name short.

## The consumer provides

The `title`, the line under it on a lobby door (`subtitle`), `onTap`, and what lights it: `lightUrl`, `posterUrls`, `names`. A small TMDB size for the light (`w92`) is enough: it is drawn 24 pixels wide.

## Semantics

One button named by the title and its line (`Networks, Series`); the artwork, the leaning posters and the stacked names are silenced.

## States in the catalog

Each sheet is drawn in the dark and the light room.

- The six doors of the lobby: lit with posters, lit alone, with names, plain.
- The lobby on a tablet on its side: all six on one row.
- Index tiles: genres lit by a backdrop with a poster leaning in, plain tiles for networks and decades.
- Text at 200%: two to a row, the doors grow with their words and drop their corners.

## Do / don't

- Do give a door the artwork of what it leads to: trending posters on Trending, a genre's backdrop on its tile.
- Don't count what a door leads to unless the list is whole: Genres can say 19, Networks cannot say how many series Netflix has.
- Don't fix a door's height: it is a floor, so the words never clip.
