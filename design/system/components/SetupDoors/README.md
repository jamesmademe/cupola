# SetupDoors

The ways in, in the order they save work: what the Welcome and the Home at zero offer, in the same words.

Rendered from `lib/core/widgets/setup_doors.dart` by `test/design_catalog/setup_doors_catalog_test.dart`.

## Anatomy

- The primary door, `Set up a service`: the theme's `FilledButton` (the ink fill), stretched to the column.
- Under it, `AppSpacing.sm` below, the hint in `textTheme.bodySmall` and `dimText`: *Start with Seerr: it already knows your Radarr and Sonarr, keys included.*
- One door today. Copying everything from another device and signing in with a Seerr account join it when the app can keep them: a door the app cannot keep is not drawn.

## The consumer provides

`onSetUp`: the Welcome opens Connect with Seerr proposed; the Home at zero pushes `/welcome/connect`, past the claim.

## Semantics

The button speaks its label with the hint attached to it (on the label, which the button merges: a hint wrapped around a button is dropped). The visible hint is excluded, so it is said once.

## States in the catalog

The door at the default reading size and at 200%, each in the dark and the light room.
