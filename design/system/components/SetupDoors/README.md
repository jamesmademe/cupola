# SetupDoors

The ways in, in the order they save work: what the Welcome and the Home at zero offer, in the same words.

Rendered from `lib/core/widgets/setup_doors.dart` by `test/design_catalog/setup_doors_catalog_test.dart`.

## Anatomy

- The primary door, `Set up a service`: the theme's `FilledButton` (the ink fill), stretched to the column.
- Under it, `AppSpacing.sm` below, the hint in `textTheme.bodySmall` and `dimText`: *Start with Seerr: it already knows your Radarr and Sonarr, keys included.*
- `AppSpacing.lg` below it, the household member's door, `I have a Seerr account`: the theme's `OutlinedButton`, stretched to the column, pinned to `VisualDensity.standard` and 44pt; under it the same way, *Sign in to ask for movies and series.*
- Last and quietest, `AppSpacing.md` below (`AppSpacing.sm` without the lines), the way for whoever has another device already set up, `Copy from another device`: a centred `TextButton` in ink (`retryInkStyle`), no icon, 44pt: a link under the two buttons, so the Welcome keeps one fill and one outline. Whoever copies already has Cupola, and the camera pointed at the other device's code opens the copy without passing here, so this door is mostly a computer's, which pastes the link. Under it, `AppSpacing.xs` below and centred, *Point the camera at the code on your other device*.
- Past the reading size where two buttons stop sharing a line (`scale(14) > 20`, `OnboardingFooter`'s), the lines are not drawn and the doors sit `AppSpacing.sm` apart: on the Welcome they are pinned under the ring, and three doors with their lines overflowed a short phone at 200%. Each line is still spoken, as its door's hint.
- **The Welcome decides from the room it has.** The doors are pinned under the claim and the claim scrolls above them, so a sentence that does not fit slides under the doors and shows only after scrolling. `OnboardingWelcome.roomForDoorLines` asks whether the beat, less its gutters and the gap above the doors, holds the claim (152pt, headline to the end of its sentence) and the doors with their lines (268pt), both grown with the reading size, and one more line of the sentence to spare: 516pt at the default size. A 402 by 874pt phone's beat is 450pt, so its doors keep their verbs; a 440 by 956pt phone's is 532pt, and has the lines. The doors then measure 160pt where they would measure 268pt, and the sentence ends 16pt above them. The Home at zero scrolls, and draws the lines until the reading size where two buttons stop sharing a line.

## The consumer provides

`showLines`, when it knows how much room the doors have (the Welcome); left out, the lines follow the reading size alone.

`onSetUp`: the Welcome opens Connect with Seerr proposed; the Home at zero pushes `/welcome/connect`, past the claim.

`onCopy`: both push `/welcome/pair`, where the other device's code is scanned or its link pasted.

`onSignIn`: both push `/welcome/sign-in`, where the Seerr is and then the account on it.

## Semantics

Each button speaks its label with its hint attached to it (on the label, which the button merges: a hint wrapped around a button is dropped). The visible hints are excluded, so each is said once.

## States in the catalog

The three doors at the default reading size with their lines, without them (`showLines: false`, as the Welcome draws them on a 402 by 874pt phone) and at 200%, each in the dark and the light room.

## Do / don't

- Do keep the copy door a link in ink under the two buttons: one fill on the Welcome, and it is the one that sets up a service. A third button, or a row with an icon between the two, made three shapes compete on the first screen.
- Do say each door's line as its hint when the line is not drawn.
- Don't draw a door the app cannot keep.
