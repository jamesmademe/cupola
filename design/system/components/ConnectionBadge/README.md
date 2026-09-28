# ConnectionBadge

A small uppercase tag naming which of a service's connections a row came from — drawn only when there is more than one to tell apart.

Hand-written from `lib/core/widgets/connection_badge.dart`, as the Activity feed uses it (`features/activity/presentation/widgets/activity_item_tiles.dart`). Connection names and titles are illustrative: the label is the user's own.

## Anatomy

- Padding 6px horizontal, 1px vertical; radius 6px (`radius-xs2`); fill the accent at 14%; 1px border, the accent at 34%.
- Text: `eyebrow` (11px / 600, +1.4px tracking), uppercase. The ink is the accent walked against its own 14% wash over the ground the badge sits on (`ServiceTheme.onTint`, tint 0.14) — so Radarr amber darkens on paper and stays itself on the dark surface.
- An empty label renders nothing: a stack with one Radarr never grows a badge naming the only Radarr.

## Placement

On the row, after the StatusBadge, `space-sm` apart (hidden on the compact tile). On the Activity feed two connections of one service interleave inside a group, so the row has to say which; global search says it once per section heading instead.

## The consumer provides

The label, the service accent, and `surface` when the badge is not on `surface` (a badge on a card passes `surface-container`).

## Semantics

Plain text in the row's reading order; the tile's own sentence carries the connection name.

## Do / don't

- Do pass the ground the badge lands on, or the ink is measured against the wrong colour.
- Don't draw it for a service with a single connection.
- Don't use it for status — it names a source, it carries no tone.
