# SelectionPills

A horizontal segment row — one selected at a time — for switching views inside a section.

Hand-written from `lib/core/widgets/selection_pills.dart`.

- Pill: min height 48px, padding `space-sm` × `space-lg`, `radius-pill` (the selected-affordance radius, shared with the nav bar), label `label-medium` at 600, pills `space-sm` apart.
- Unselected: `surface-container`, 1px `outline-variant`, `on-surface-variant` label.
- Selected: the accent at 16% (dark) / 13% (light) with a 27% accent border; the label is the accent walked by `ServiceTheme.onTint` against that composite so it clears AA in both themes.
- Press: `PressableScale` dip with a light haptic.

The consumer provides labels, the selected index and an accent (the section's or the service's). Each pill is announced as a button with its selected state.
