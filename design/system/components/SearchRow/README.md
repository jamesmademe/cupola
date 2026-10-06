# SearchRow

One row of the Discover tab's search, laid out by kind (On your server, Movies, Series, People), and of the atrium's People index: a title with its poster, what it is and where it stands, or a person with their face and what they are known for.

Rendered from `lib/features/discover/presentation/widgets/search_row.dart` by `test/design_catalog/search_row_catalog_test.dart`.

## Anatomy

- Flat on the page, no card: the section name above groups the rows (`label` in the room's secondary ink, `space-md` above it). At least 76 tall (`SearchRow.minHeight`), `space-sm` above and below the picture.
- **Title** (`SearchRow.title`): the poster at 44 × 66, `radius-thumb` (8), decoded at its own size (`ArtworkDecodeBox`); with no artwork, or when it fails to load, the room's quiet fill with a hairline edge and the title's initials in `label` ink, which stop at the compact tiles' reading ceiling (`TextScaleMetrics.clampedScalerOf`) so two letters never fill the plate. `space-md`, then three lines: the title in `row` ink (one line), the meta in `meta` secondary ink (`Movie · 1996 · TMDB 8.0`, one line), and, when there is something to say, where it stands: a 7pt dot in the tone (`statusToneColor`), `space-s`, the word in `caption` at 600 in the secondary ink. The tone is on the dot only, as on `StatusBadge.poster`.
- **The plus**: where the operator may add the title, a second control after the row, `space-sm` from it: a 44 disc in the quiet fill with a hairline edge, `add_rounded` at 20 in the ink. Never a filled disc: adding is a row's action, not the page's one amber fill.
- **Person** (`SearchRow.person`): the face, a 44 circle in the quiet fill with a hairline edge (initials without a picture), the name in `row` ink, one line under it in `meta` secondary ink (up to two lines: `Known for Forrest Gump, Toy Story`, or `Director · Dune` in the atrium), and a trailing chevron in the secondary ink.
- `padding` around the row: none in a search, whose list carries the gutter; the slab's inset (`space-lg`) among the atrium's people.
- With a `heroTag` and artwork, the poster flies into the title's page (`MediaPosterCard.flightOnUserGestures`); with no artwork there is no flight, so an empty plate never flies.

## Where a title stands

The page decides the word, in the reader's vocabulary: on a media server it is `On Jellyfin` (green, the connection's name once there are two); else Seerr's word for its record (`seerrCatalogStatus`, the requester's words for her); else `In Radarr` (neutral) for a library that holds it. No word for a title nobody holds a record of.

## The consumer provides

`title`, `meta`, an optional `status` (label and tone), `poster` and `posterHeaders`, `heroTag`, `onTap`, and `onAdd` with its `addLabel` (`Add Cosmic Voyage to Radarr`) where there is an add to honour. A person: `name`, `line`, `face`, `onTap`.

## Semantics

The row is one button: its label is the title (or the name), its value the meta and the state (`Movie · 1996, Waiting for approval`); its parts are silent. The plus is its own button, named by `addLabel`.

## States in the catalog

Each sheet is drawn in the dark and the light room.

- A search by kind: a title on the server with artwork and its state, one with no artwork and the plus, one waiting for approval, a person with no picture.
- A long title and a long state at 320pt: one line each, the plus whole.
- Text at 200%.

## Do / don't

- Do let the section name say what the rows are; don't add a service's name or colour to a row: the answer is by kind, not by source.
- Don't offer the plus on a title an arr holds, on one whose arr is not set up, or while one of that arr's connections has not answered: a silent server is never one that holds nothing.
