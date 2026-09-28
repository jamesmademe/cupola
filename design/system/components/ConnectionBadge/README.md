# ConnectionBadge

A small uppercase tag naming which of a service's connections a row came from — drawn only when there is more than one to tell apart.

Rendered from `lib/core/widgets/connection_badge.dart` by `test/design_catalog/connection_badge_catalog_test.dart`, as the Activity feed uses it (`features/activity/presentation/widgets/activity_item_tiles.dart`). Connection names and titles are illustrative: the label is the user's own.

## Anatomy

- Padding 6px horizontal, 1px vertical; `radius-xs2` (6); fill the accent at 14% alpha; 1px border, the accent at 34% alpha.
- Text: the eyebrow style (11px / weight 600, 1.4px letter-spacing, 1.2 line height), uppercased. The ink is the accent walked against its own 14% wash over the ground the badge sits on (`ServiceTheme.onTint`, `tintAlpha: 0.14`) — so Radarr amber darkens on paper and stays itself on the dark surface.
- An empty `label` renders `SizedBox.shrink()`: a stack with one Radarr never grows a badge naming the only Radarr.

## Placement

On the row, after the `StatusBadge`, `AppSpacing.sm` apart (hidden on the compact tile). On the Activity feed two connections of one service interleave inside a group, so the row has to say which; global search says it once per section heading instead.

## The consumer provides

- `label` — the connection's name, or empty to render nothing.
- `accent` — the service accent.
- `surface` — the ground the badge lands on, defaulting to `ColorScheme.surface`; a badge on a card passes `surfaceContainer`.

## Semantics

Plain text in the row's reading order; the tile's own sentence carries the connection name.

## Do / don't

- Do pass the ground the badge lands on, or the ink is measured against the wrong colour.
- Don't draw it for a service with a single connection.
- Don't use it for status — it names a source, it carries no tone.
