# ConnectionBadge

A small tag naming, as the user named it, which of a service's connections a row came from — drawn only when there is more than one to tell apart.

Rendered from `lib/core/widgets/connection_badge.dart` by `test/design_catalog/connection_badge_catalog_test.dart`, as the Activity feed uses it (`features/activity/presentation/widgets/activity_item_tiles.dart`). Connection names and titles are illustrative: the label is the user's own.

## Anatomy

- Padding 6px horizontal, 1px vertical; `radius-xs2` (8); fill the accent (the lamp, for every service) at 14% alpha; 1px border, the accent at 34% alpha.
- Text: the micro role (`AppTheme.chrome`, 11 / 600 / 14, the role's own tracking), in sentence case — the connection's name exactly as the user typed it, never recased. The ink is the accent walked against its own 14% wash over the ground the badge sits on (`ServiceTheme.onTint`, `tintAlpha: 0.14`) — the lamp resolves to the room's primary ink, so the badge is monochrome in both themes.
- An empty `label` renders `SizedBox.shrink()`: a stack with one Radarr never grows a badge naming the only Radarr.

## Placement

On the row, after the `StatusBadge`, `AppSpacing.sm` apart, at every width. On the Activity feed two connections of one service interleave inside a group, so the row has to say which; global search says it once per section heading instead. A compact desktop row (a window under 1100) sheds its figures and its time but keeps the badge: a row without its name cannot say which server it is about.

## The consumer provides

- `label` — the connection's name, or empty to render nothing.
- `accent` — the service's accent (`ServiceKey.accent`, the lamp).
- `surface` — the ground the badge lands on, defaulting to `ColorScheme.surface`; a badge on a card passes `surfaceContainer`.

## Semantics

Plain text in the row's reading order; the tile's own sentence carries the connection name.

## States in the catalog

Each sheet is drawn in the dark and the light room.

- Four services on the page surface, on a card with `surface:` passed, `label: ''` drawing nothing, the Activity row shape.
- A long label in the row shape on a 320pt phone.
- Text at 200%: the pill and the row shape.

## Do / don't

- Do pass the ground the badge lands on, or the ink is measured against the wrong colour.
- Don't draw it for a service with a single connection.
- Don't use it for status — it names a source, it carries no tone.
