# SelectionPills

A horizontally scrolling segment row — one selected at a time — for switching views inside a section.

Rendered from `lib/core/widgets/selection_pills.dart` by `test/design_catalog/selection_pills_catalog_test.dart`.

## Anatomy

- Row: `SingleChildScrollView` scrolling horizontally, padding `AppSpacing.lg` leading and trailing, `AppSpacing.sm` trailing under the row; pills `AppSpacing.sm` apart.
- Pill: minimum height 48 (the stricter of the two platform minimums), padding `AppSpacing.lg` horizontal × `AppSpacing.sm` vertical, `AppRadius.borderRadiusPill` — the same radius the navigation bar's selected state uses, and deliberately not `AppRadius.full`, which means metadata elsewhere in this system. Sized by its label, not fixed, so a pill grows with the reading size or a long label instead of overflowing.
- Label in `textTheme.labelMedium` at weight 600.
- Unselected: `colorScheme.surfaceContainer` fill, 1px `outlineVariant` border, `onSurfaceVariant` label.
- Selected: the accent at 16% alpha (dark theme) / 13% (light) fill, a 27%-alpha accent border. The label is the accent walked through `ServiceTheme.onTint` against that tint-over-surface composite, so it clears AA in both themes instead of falling back to a neutral in daylight.
- Press: `PressableScale` (dip, light haptic, Reduce Motion respected).

## The consumer provides

`values`, the `selected` value, a `labelBuilder`, `onSelected`, and optionally `accent` — the section's or the service's colour. `accent` defaults to `colorScheme.primary`: an aggregate surface showing several services at once is lit by primary rather than by whichever service happens to be first.

## Semantics

Each pill is one `Semantics` node: `button: true`, `selected: <bool>`, labelled with the pill's text; the press animation and ripple are excluded from the tree so the control reads as one thing, not two.

## Do / don't

- Do pass the page's own accent on a single-service screen; leave it unset on an aggregate one.
- Don't give it a fixed height: the pill is sized by its label on purpose, so it grows instead of overflowing at a large reading size.
- Don't reach for `AppRadius.full` on an interactive pill — that radius means metadata in this system.
