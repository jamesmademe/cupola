# CollectionTally

How much of a TMDB collection is on the server: a headline, the strip of its movies with where each stands, and the count of each kind. Under a collection's still on its page, and in the Discover atrium as the invitation to complete it.

Rendered from `lib/features/discover/presentation/widgets/collection_tally.dart` (`CollectionTally`), with the movies' places from `lib/features/discover/domain/collection_shelf.dart` (`CollectionShelf`, `CollectionPartStand`), by `test/design_catalog/collection_tally_catalog_test.dart`.

## Variants

- **Page** (`CollectionTally`): the headline in the section role, `5 of 8 on your server`, or `All 4 on your server` when nothing is missing.
- **Invitation** (`CollectionTally.invitation`): `Complete the collection` in the section role with the chevron of a shelf's header (`chevron_right_rounded` in the primary), and under it the name and the count in the label role at 400, `inkSecondary`: `Blender Open Movies · 5 of 8 on your server`. The whole slab is one button that opens the collection's page, where the movies are added and a request is answered.

Both are a slab: `fillQuiet`, `AppRadius.door`, a hairline edge, padding `AppSpacing.lg`.

**Wide**: once the inside of the slab is `CollectionTally.besideFrom` (776) wide, the strip goes beside the words, at the end of the slab and at its own width (its covers at 44, never more than `CollectionTally.stripMeasure`, 376, the widest phone's strip), with the legend under the words. The atrium's invitation reaches it on a tablet on its side and in a desktop window; a collection's page never does, its column stopping at the reading well.

## The strip

The movies in release order, side by side, each cover at most 44 wide (`w92`, 2:3, `AppRadius.thumb`) over a 3pt bar in the tone of where it stands: green on the server (either copy, 4K included), blue on its way, a blue ring while it waits for approval, the hairline when it is neither. Past ten movies the covers would be too small to read and the bars stand alone, filling the width.

## The legend

`5 on your server · 2 on the way · 1 waiting for approval`, each after a 7pt dot in its tone (a ring for the one waiting), in the label role at 400, `inkSecondary`; a kind with nothing in it is left out. It wraps at any reading size.

## When the atrium invites

Only for the operator with Radarr: of the collections Radarr holds a movie of and misses another, the nearest to whole first (then the one that holds more, then by name). The first three are read from Seerr until one is on the server in part and still has something to do on its page, a movie to add or a request to answer (`CollectionShelf.invitesCompletion`). Movies only on their way leave nothing to do, and no invitation. The atrium does not approve: the request is answered on the collection's page.

## The consumer provides

The `shelf` (a `CollectionShelf` of Seerr's collection); on the invitation, the collection's `name` and `onTap`.

## Semantics

One sentence, its parts silenced. The page's slab: `5 of 8 on your server, 2 on the way, 1 waiting for approval`. The invitation is a button: `Complete the collection, Blender Open Movies, 5 of 8 on your server, 2 on the way, 1 waiting for approval`.

## States in the catalog

Each sheet is drawn in the dark and the light room.

- The page's slab: five on the server, two on the way, one waiting.
- The invitation.
- Whole: all on the server.
- Past ten movies: the bars alone.
- Text at 200%: the invitation.
- The invitation on a tablet on its side: the strip beside the words.

## Do / don't

- Do count by Seerr's word, the same word the rows under it say.
- Don't invite where nothing is left to do, and don't put Approve in the atrium: the page answers the request.
