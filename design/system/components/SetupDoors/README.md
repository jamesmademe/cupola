# SetupDoors

The ways in, in the order they save work: what the Welcome and the Home at zero offer, in the same words.

Rendered from `lib/core/widgets/setup_doors.dart` by `test/design_catalog/setup_doors_catalog_test.dart`.

## Anatomy

- The primary door, `Set up a service`: the theme's `FilledButton` (the ink fill), stretched to the column.
- Under it, `AppSpacing.sm` below, the hint in `textTheme.bodySmall` and `dimText`: *Start with Seerr: it already knows your Radarr and Sonarr, keys included.*
- `AppSpacing.lg` below it, the way for whoever has another device that is already set up, `Copy from another device`: a `TextButton` in ink with an 18pt `qr_code_scanner_rounded` before its label, pinned to `VisualDensity.standard` and 44pt, in the middle on purpose: a text door, so the Welcome keeps its one fill. Under it, `AppSpacing.xs` below, *Point the camera at the code on your other device*, the same way.
- `AppSpacing.lg` below that, the household member's door, `I have a Seerr account`: the theme's `OutlinedButton`, stretched to the column, pinned to `VisualDensity.standard` and 44pt; under it the same way, *Sign in to ask for movies and series.*
- Past the reading size where two buttons stop sharing a line (`scale(14) > 20`, `OnboardingFooter`'s), and on a portrait frame shorter than 800pt (`SetupDoors.minHeightForLines`), the lines are not drawn and the doors sit `AppSpacing.sm` apart: on the Welcome they are pinned under the ring, and the three doors with their lines are 268pt tall, which a 6.3" phone (844pt) leaves room for and a 667pt one does not, nor does 200% text. Each line is still spoken, as its door's hint.

## The consumer provides

`onSetUp`: the Welcome opens Connect with Seerr proposed; the Home at zero pushes `/welcome/connect`, past the claim.

`onCopy`: both push `/welcome/pair`, where the other device's code is scanned or its link pasted.

`onSignIn`: both push `/welcome/sign-in`, where the Seerr is and then the account on it.

## Semantics

Each button speaks its label with its hint attached to it (on the label, which the button merges: a hint wrapped around a button is dropped). The visible hints are excluded, so each is said once.

## States in the catalog

The three doors at the default reading size on a tall phone, on a short one (390 by 667, no lines) and at 200%, each in the dark and the light room.

## Do / don't

- Do keep the copy door a text button: one fill on the Welcome, and it is the one that sets up a service.
- Do say each door's line as its hint when the line is not drawn.
- Don't draw a door the app cannot keep.
