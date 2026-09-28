# RatingChip

A score as a fact: a full-radius pill naming its source and its scale, in a wrapping row under the Scores label.

Hand-written from `lib/core/widgets/rating_chip.dart`, `rating_chips_row.dart` and `lib/core/utils/rating_display.dart`, with `media_metadata_line.dart` (the hero's fact line).

- **Pill** — padding `space-xs` × `space-sm`, `radius-full`, fill accent 12% (the page accent, or `primary` when none is passed). Source name then `space-xs` then the score, both `label-small` 600 in the accent walked against its own 12% wash over `surface` (`ServiceTheme.onTint`, tint 0.12); the score run is tabular. The pill sits centred in a 44-high box so its tap-to-show tooltip (the source name) has a comfortable target without growing the row.
- **Score** — `value + denominator (+ " (votes)")`. Scales are fixed per source: IMDb, TMDB, TVDB, Trakt, MusicBrainz → one decimal and `/10`; Metacritic → integer `/100`; Rotten Tomatoes → integer `%`; an unknown source → one decimal, no denominator. Votes: `1.2M`, `5.1k`, the plain count under 1,000, and nothing at all for zero votes.
- **Row** — `Wrap`, `space-xs` both ways. Sources with no score and no votes are dropped (an unreleased title's `0.0` is not a rating); no scored source, no row. Names go through `legibleRatings` so `MC` / `RO` / `TR` read *Metacritic*, *Rotten Tomatoes*, *Trakt*.
- **MediaMetadataLine** — trimmed, non-empty items joined with ` · ` (the house middot) in `body-medium` `on-surface-variant`; the hero caps it at one line (ellipsis). Empty list, nothing rendered.

Variants shown: a four-source Radarr row, Sonarr's single-source pill, the no-accent primary fallback, the metadata line. The consumer provides `ratings` (`RatingSource`: name, icon, value, votes) and the page `accent`. Scores and counts are illustrative.

Semantics: each pill is one node, not a button — *IMDb rating 8.6 out of 10*, value *512300 votes*; `/100` is spoken *out of 100*, `%` *percent*.

Do: pass the page accent so the row lights with the page. Don't: add an `onTap` — a rating is metadata, which is why it keeps the full radius.
