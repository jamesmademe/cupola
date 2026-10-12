# StatusBadge

The one way a media item's state is shown: a tone glyph plus a word, so colour is never the only channel.

Rendered from `lib/core/widgets/status_badge.dart` by `test/design_catalog/status_badge_catalog_test.dart`. The status arrives resolved as `MediaStatusInfo` (from a per-service resolver in the feature's `domain/` layer); the badge never derives it.

## Variants

- **Full** (`StatusBadge(info:)`): `surface` at 80% (`opacityStatusBadge`) with a 1px `on-surface` 12% border, `radius-sm`, padding `space-xs` × `space-sm`. A 12px glyph in the tone colour, `space-xs`, the label in `label-small` at 600 in `on-surface`, then an optional tabular percentage (glued, `62%`, through `formatPercent`: nearest whole percent, never `100%` while the transfer is still copying). While bytes are moving the glyph becomes a 12px determinate ring (2px stroke, track at 25% of the tone).
- **Compact** (`compact: true`), poster overlay: the default badge's plate and edge, padding `space-xs` × 2px. A 10px glyph in the tone and, when known, the percentage in the plate's ink (2px apart). Never a tone fill: only an amber fault's remedy is filled (brand book, *The tone rule*); it used to be the tone at 90%.
- **Poster** (`StatusBadge.poster`): the word on a catalogue poster: the default badge's plate and edge, `radius-thumb`, padding 2px × `space-s` leading, `space-sm` trailing. A 7px dot in the tone, `space-xs`, then the label in `label-small` at 600 in the plate's ink, or, while bytes arrive, the percentage alone (tabular, `62%`). The tone is on the dot only, as on every badge's glyph. A word too long for the poster wraps to a second line inside the plate; it is never cut. At a large reading size a word wider than the corner, or words that need more than the two lines, step down until they fit whole (`TextScaleMetrics.wholeWordScaler`), never under the default size: "Avail / able" and a state with its last word cut off both lose the state. Between Compact, a glyph a reader has to learn, and Full, whose icon a poster corner has no room for.
- **Icon only** (`iconOnly: true`): an 8px tone dot with a 1.5px `shadow` ring at 35%, so it survives artwork of its own tone.
- **Animated** (`StatusBadge.animated`), for the detail hero only. A new status cross-fades glyph, label and percentage together (`durationSm`, emphasized curve); the ring sweeps to each new value (`durationMd`, standard curve). No colour is tweened. Renders exactly like Full under Reduce Motion.

The tone colour is always `statusToneColor(colorScheme, tone)`: success, warning, info and error are the tones of the room the scheme belongs to (each room has its own five), walked against `surface` until they read at 4.6:1, and neutral is `on-surface-variant`. No status reads `primary`, the ink.

## Tone mapping (five arms)

| Arm | States |
| --- | --- |
| `success` | Available |
| `info` | Downloading, Importing, Queued, Waiting to import, Partial |
| `warning` (a fault) | Stuck, Import blocked, Failed |
| `error` (unreachable only) | Client unavailable |
| neutral (the backlog, and the resting state) | Missing, Upgrade available, Deleted, Not released, Stopped, Unmonitored, Unknown, Not requested |

A Seerr request reads the same five arms, in the lexicon's words: Available and Completed are `success`; Waiting for approval, Approved, Processing and Partially available are `info`; a request awaiting approval is in line, not broken; Failed is `warning`; Declined and Deleted are neutral, a closed decision.

Labels are sentence case and come from the lexicon (`core/status/lexicon.dart`): "Waiting to import", "Client unavailable", "Not requested", "Upgrade available". A service may override the label with its own wording (for example Seerr's "Available to request").

## Consumer provides

The `MediaStatusInfo`. Set `excludeFromSemantics: true` when the enclosing tile already speaks the status.

## Semantics

Every variant speaks `MediaStatusInfo.semanticLabel` as one container node and silences its painted children. The badge is not a button: the tap belongs to the enclosing tile.

## States in the catalog

Each sheet is drawn in the dark and the light room.

- Every arm of the tone rule: green, blue, amber, red, primary, neutral.
- `compact: true`, `StatusBadge.poster` and `iconOnly: true` over artwork.
- Text at 200%: every state.
- A long label and a figure, each in a 150pt room: the label wraps inside the badge (a state word cut short loses the state), the figure stays whole.

## Do / don't

- Do use `.animated` only where one badge changing state is the point of the surface.
- Don't paint the backlog amber or red: missing is neutral.
- Don't roll the label or the percentage; the percentage is tabular because it changes every poll.
