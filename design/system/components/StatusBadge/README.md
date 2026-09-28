# StatusBadge

The one way a media item's state is shown: a tone glyph plus a word, so colour is never the only channel.

Hand-written from `lib/core/widgets/status_badge.dart`. The status arrives resolved as `MediaStatusInfo` (from a per-service resolver in the feature's `domain/` layer); the badge never derives it.

## Variants

- **Full** (`StatusBadge(info:)`) — `surface` at 80% (`opacityStatusBadge`) with a 1px `on-surface` 12% border, `radius-sm`, padding `space-xs` × `space-sm`. A 12px glyph in the tone colour, `space-xs`, the label in `label-small` at 600 in `on-surface`, then an optional tabular percentage. While bytes are moving the glyph becomes a 12px determinate ring (2px stroke, track at 25% of the tone).
- **Compact** (`compact: true`) — poster overlay: filled with the tone colour at 90%, 1px border in the tone, padding `space-xs` × 2px. A 10px glyph and, when known, the percentage (2px apart). The ink is `foregroundOn(tone)`, never white by default.
- **Icon only** (`iconOnly: true`) — an 8px tone dot with a 1.5px `shadow` ring at 35%, so it survives artwork of its own tone.
- **Animated** (`StatusBadge.animated`) — for the detail hero only. A new status cross-fades glyph, label and percentage together (`durationSm`, emphasized curve); the ring sweeps to each new value (`durationMd`, standard curve). No colour is tweened. Renders exactly like Full under Reduce Motion.

The tone colour is always `statusToneColor(colorScheme, tone)`: success, warning, info and error are walked against `surface` until they read at 4.6:1, `primary` is walked the same way, and neutral is `on-surface-variant`.

## Tone mapping (five arms)

| Arm | States |
| --- | --- |
| `success` | Available |
| `info` | Downloading, Importing, Queued, Import pending, Partial |
| `warning` (a fault) | Stalled, Import blocked, Failed |
| `error` (unreachable only) | Client unavailable |
| neutral (the backlog) | Missing, Upgrade available, Deleted, Not released, Paused, Unmonitored, Unknown |
| `primary` | Not requested |

Labels are sentence case: "Import pending", "Client unavailable", "Not requested", "Upgrade available". A service may override the label with its own wording (for example Seerr's "Available to request").

## Consumer provides

The `MediaStatusInfo`. Set `excludeFromSemantics: true` when the enclosing tile already speaks the status.

## Semantics

Every variant speaks `MediaStatusInfo.semanticLabel` as one container node and silences its painted children. The badge is not a button: the tap belongs to the enclosing tile.

## Do / don't

- Do use `.animated` only where one badge changing state is the point of the surface.
- Don't paint the backlog amber or red: missing is neutral.
- Don't roll the label or the percentage; the percentage is tabular because it changes every poll.
