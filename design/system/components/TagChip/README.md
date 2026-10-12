# TagChip

Metadata pills: counts, qualities and genres. Pills are metadata, never controls.

Rendered from `lib/core/widgets/tag_chip.dart` by `test/design_catalog/tag_chip_catalog_test.dart`.

## Variants

- **TagChip**: the tone (default `primary`, usually the service's accent: the lamp, so the chip is a neutral wash under the primary ink) at 12% with a 28% border, `radius-full`, padding `space-xs` × `space-sm`, label `label-small` 600, optional 14px leading icon. The label and icon are the tone walked against its own 12% wash over the ground the chip sits on (`ServiceTheme.onTint`, tint 0.12); the wash and hairline keep the raw tone.
- **GenreChip** (neutral): `surface-container`, 1px `outline-variant`, `on-surface-variant` label at 500, padding `space-xs` × `space-md`.

## The consumer provides

The label, optionally a tone and an icon, and `surface` when the chip is not on `surface` (a chip inside a card passes the card's container). Counts are written in sentence case: *3 seasons*, *4 missing*, *All covered*.

## Semantics

Plain text; the chip is never a button.

## States in the catalog

Each sheet is drawn in the dark and the light room.

- `TagChip` with and without an icon, `GenreChip`, and `surface:` on a card container.
- Text at 200%.
- A long label in a 200pt room, for both chips: `TagChip` wraps its title inside the pill rather than running out of it.

## Do / don't

- Do pass the ground the chip lands on so its ink is measured against it.
- Don't make a pill tappable; an interactive pill is a `SelectionPills` choice, and a row of choices keeps its corner in both states: selection is carried by fill and ink, never by the corner.
- Don't colour a chip with a status tone unless it states that status.
