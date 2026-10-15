# SetupDoors

The ways in, in the order they save work: what the Welcome and the Home at zero offer, in the same words.

Rendered from `lib/core/widgets/setup_doors.dart` by `test/design_catalog/setup_doors_catalog_test.dart`.

## Anatomy

- The primary door, `Set up a service`: the theme's `FilledButton` (the ink fill), stretched to the column.
- Under it, `AppSpacing.sm` below, the hint in `textTheme.bodySmall` and `dimText`: *Start with Seerr: it already knows your Radarr and Sonarr, keys included.*
- `AppSpacing.lg` below it, the household member's door, `I have a Seerr account`: the theme's `OutlinedButton`, stretched to the column, pinned to `VisualDensity.standard` and 44pt; under it the same way, *Sign in to ask for movies and series.*
- Past the reading size where two buttons stop sharing a line (`scale(14) > 20`, `OnboardingFooter`'s), the lines are not drawn and the doors sit `AppSpacing.sm` apart: on the Welcome they are pinned under the ring, and two doors with their lines overflowed a short phone at 200%. Each line is still spoken, as its door's hint.
- Two doors today. Copying everything from another device joins them when the app can keep it: a door the app cannot keep is not drawn.

## The consumer provides

`onSetUp`: the Welcome opens Connect with Seerr proposed; the Home at zero pushes `/welcome/connect`, past the claim.

`onSignIn`: both push `/welcome/sign-in`, where the Seerr is and then the account on it.

## Semantics

Each button speaks its label with its hint attached to it (on the label, which the button merges: a hint wrapped around a button is dropped). The visible hints are excluded, so each is said once.

## States in the catalog

The two doors at the default reading size and at 200%, each in the dark and the light room.
