# RatingChip

A score as a fact: a full-radius pill naming its source and its scale, in a wrapping row under the Scores label.

Rendered from `lib/core/widgets/rating_chip.dart`, `rating_chips_row.dart` and `lib/core/utils/rating_display.dart`, with `media_metadata_line.dart` (the hero's fact line), by `test/design_catalog/rating_chip_catalog_test.dart`.

- **Pill** — padding `space-xs` × `space-sm`, `radius-full`, fill accent 12% (the page accent — the lamp — or `primary` when none is passed). `sourceIcon` (after `legibleRatings`, the legible name itself — 'IMDb', 'TMDB' — not a badge) then `space-xs` then the score, both `label-small` 600 through `ServiceTheme.onTint` against the 12% wash over `surface` (tint 0.12) — the primary ink, since the accent is the lamp; the score run is tabular. The pill sits centred in a box floored at 44pt so its tap-to-show tooltip (`sourceName`) has a comfortable target without growing the row.
- **Score** — `value + denominator (+ " (votes)")`. Scales are fixed per source: IMDb, TMDB, TVDB, Trakt, MusicBrainz → one decimal and `/10`; Metacritic → a rounded integer and `/100`; Rotten Tomatoes → a rounded integer and `%`; an unknown source → one decimal, no denominator. Votes: `1.2M` at a million and above, `5.1k` at a thousand and above, the plain count under 1,000, and nothing at all for zero votes.
- **Row** (`RatingChipsRow`) — `Wrap`, `space-xs` both ways. Sources with a zero value *and* zero votes are dropped (an unreleased title's `0.0` is not a rating); no scored source, no row (`SizedBox.shrink`). The row itself does not relabel sources — call sites pass `ratings: legibleRatings(...)` so `mc` / `ro` / `tr` read *Metacritic*, *Rotten Tomatoes*, *Trakt* before the row ever sees them.
- **MediaMetadataLine** — trimmed, non-empty items joined with ` · ` (the house middot) in `body-medium` `on-surface-variant`; a caller sets `maxLines` to clamp it (the hero caps it at one line with an ellipsis). An empty or all-blank list renders `SizedBox.shrink()`, not an empty gap.

The consumer provides `ratings` (`RatingSource`: name, icon, value, votes) — already passed through `legibleRatings` — and the page `accent`. Scores and counts are illustrative.

## Semantics

Each pill is one node, not a button — *IMDb rating 8.6 out of 10*, value *512300 votes*; `/100` is spoken *out of 100*, `%` *percent*, an unrecognised denominator spoken as written.

## Do / don't

- Do pass the page accent (the lamp) so the row matches the rest of the page: monochrome.
- Do run raw source data through `legibleRatings` before handing it to `RatingChipsRow` — the row trusts the names it is given.
- Don't add an `onTap` — a rating is metadata, which is why it keeps the full radius.
