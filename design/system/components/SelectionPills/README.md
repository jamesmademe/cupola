# SelectionPills

A horizontally scrolling segment row — one selected at a time — for switching views inside a section; `SelectionPills.wrap` lays the same pills on as many lines as they need, for a choice that must be seen whole.

Rendered from `lib/core/widgets/selection_pills.dart` by `test/design_catalog/selection_pills_catalog_test.dart`.

## Anatomy

- Row: `SingleChildScrollView` scrolling horizontally; `padding` defaults to `SelectionPills.gutter` — `AppSpacing.lg` leading and trailing inside a row that runs edge to edge, so the first pill sits on the screen gutter and a scrolled pill bleeds off the screen — with `AppSpacing.sm` under the row; pills `AppSpacing.sm` apart. A host never wraps the default in a second side padding.
- Wrap (`SelectionPills.wrap`): no scroll; the pills flow onto further lines, `AppSpacing.sm` apart in both directions, with no side inset and `AppSpacing.sm` under (the host is on the gutter). For a setting with a handful of answers, where a pill scrolled off the edge is an answer the user cannot see: the Access row's four choices take a second line on a 320–390pt phone.
- Pill: drawn at least `size.chip` 36 tall, centred in a target at least `size.touch` 44 tall (the area grows, the drawing does not; it was drawn at 48 itself), padding `AppSpacing.lg` horizontal × `AppSpacing.sm` vertical, `AppRadius.borderRadiusPill` (fully rounded) — the same radius the navigation bar's selected state uses. `AppRadius.pill` and `AppRadius.full` resolve to the same value now; `pill` is the name for the interactive one. Sized by its label, not fixed, so a pill grows with the reading size or a long label instead of overflowing.
- Label in `textTheme.labelMedium` at weight 600.
- Unselected: `colorScheme.surfaceContainer` fill, 1px `outlineVariant` border, `onSurfaceVariant` label.
- Selected: the room's strong fill (`fill-strong`: white at 12% dark, ink at 12% light) with a 1px `line-edge` border, the label in `on-surface` (the primary ink) — the nav bar's pill, the same on every screen. Monochrome: no service or section colours it, so there is no hue to walk.
- Press: `PressableScale` (dip, light haptic, Reduce Motion respected).
- Leading (`leading:`, the row only): a control at the head of the row, before the pills and never one of the values: the way back out of the choice, as the Discover atrium's `‹ Discover` in front of its indexes.
- One pill alone (`SelectionPill`): the same drawing for a page's other controls, so a page speaks one language. A toggle (`Under 100 min`, selected while on) or a pill that opens a choice, with a trailing chevron (`trailing: Icons.expand_more_rounded`, 18px, in the label's colour, `space-xxs` after it).

## The consumer provides

`values`, the `selected` value, a `labelBuilder`, `onSelected`, and optionally `padding` and `leading`. A `SelectionPill` takes its `label`, whether it is `selected`, `onTap` and an optional `trailing` glyph. No colour: the pill takes none.

## Semantics

Each pill is one `Semantics` node: `button: true`, `selected: <bool>`, labelled with the pill's text; the press animation and ripple are excluded from the tree so the control reads as one thing, not two.

## States in the catalog

Each sheet is drawn in the dark and the light room.

- Scrolling row: one selected, on a service page, a long label.
- `SelectionPills.wrap` on a 320pt phone.
- A row led by a way back, and the lone pills of a catalogue page: a choice with its chevron, a toggle off and on.

## Do / don't

- Do use it for every "which view" choice, on a service page and an aggregate one alike: one selected language for the app.
- Do use `SelectionPills.wrap` for a choice in a form, whose every answer has to be on screen; keep the scrolling row for a view switcher, where one line is what the section can spare.
- Don't give it a fixed height: the pill is sized by its label on purpose, so it grows instead of overflowing at a large reading size.
- Don't reach for `AppRadius.full` on an interactive pill: use `AppRadius.pill`. The two are the same value now, but the names still tell a reader which shape is a control and which is metadata.
