# SelectionPills

A horizontally scrolling segment row — one selected at a time — for switching views inside a section.

Rendered from `lib/core/widgets/selection_pills.dart` by `test/design_catalog/selection_pills_catalog_test.dart`.

## Anatomy

- Row: `SingleChildScrollView` scrolling horizontally; `padding` defaults to `SelectionPills.gutter` — `AppSpacing.lg` leading and trailing inside a row that runs edge to edge, so the first pill sits on the screen gutter and a scrolled pill bleeds off the screen — with `AppSpacing.sm` under the row; pills `AppSpacing.sm` apart. A host already on the gutter (a detail slot, a padded header) passes `SelectionPills.flush` (no side inset, `AppSpacing.sm` under), never wraps the default in a second side padding.
- Pill: minimum height 48 (the stricter of the two platform minimums), padding `AppSpacing.lg` horizontal × `AppSpacing.sm` vertical, `AppRadius.borderRadiusPill` (fully rounded) — the same radius the navigation bar's selected state uses. `AppRadius.pill` and `AppRadius.full` resolve to the same value now; `pill` is the name for the interactive one. Sized by its label, not fixed, so a pill grows with the reading size or a long label instead of overflowing.
- Label in `textTheme.labelMedium` at weight 600.
- Unselected: `colorScheme.surfaceContainer` fill, 1px `outlineVariant` border, `onSurfaceVariant` label.
- Selected: the room's strong fill (`fill-strong`: white at 12% dark, ink at 12% light) with a 1px `line-edge` border, the label in `on-surface` (the primary ink) — the nav bar's pill, the same on every screen. Monochrome: no service or section colours it, so there is no hue to walk.
- Press: `PressableScale` (dip, light haptic, Reduce Motion respected).

## The consumer provides

`values`, the `selected` value, a `labelBuilder`, `onSelected`, and optionally `padding`. No colour: the pill takes none.

## Semantics

Each pill is one `Semantics` node: `button: true`, `selected: <bool>`, labelled with the pill's text; the press animation and ripple are excluded from the tree so the control reads as one thing, not two.

## Do / don't

- Do use it for every "which view" choice, on a service page and an aggregate one alike: one selected language for the app.
- Don't give it a fixed height: the pill is sized by its label on purpose, so it grows instead of overflowing at a large reading size.
- Don't reach for `AppRadius.full` on an interactive pill: use `AppRadius.pill`. The two are the same value now, but the names still tell a reader which shape is a control and which is metadata.
