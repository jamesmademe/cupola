# ReelCommandButton

A primary button whose label rolls to its next word instead of being replaced by a spinner, so the control keeps naming what you pressed while it works.

Rendered from `lib/core/widgets/reel_command_button.dart` by `test/design_catalog/reel_command_button_catalog_test.dart`, with the presets in `lib/core/reel_motion.dart`. Labels are the onboarding callers' real strings. The catalog shows settled frames; the roll itself is described under Motion.

## Values

- A `FilledButton` from the theme: `primary` fill (the ink), `onPrimary` label, the row role (15 / 600), `AppRadius.control` (14), padding `AppSpacing.lg` × `AppSpacing.md`. It paints 44pt tall inside Material's padded 48pt target on a phone, and 44pt on a desktop too, where the theme pins standard density.
- While the future runs the button is disabled: Material's `onSurface` 12% fill and 38% label, and the label keeps moving.
- **Reserved slot**: the label box is as wide as the widest string the button can ever show: the resting label, the busy label with its full `...`, the failure label and every `slotLabels` entry, measured in the button's own text style at the current reading size. The button never resizes and the label never re-centres. The slot clips, so travelling glyphs never paint outside the fill.
- **States**: rest `Test connection` → waiting `Testing` + rolling dots → answered, the parent changes `label` and it rolls to `Next service` (or `Finish`) → thrown, rolls to `failureLabel` (`Test again`), falling back to `label`. `busyLabel: null` means no waiting state: the button is not disabled, the action runs, and the label rolls when the parent changes it (`Continue` → `Continue with 4`). `Enter Cupola` / `Opening` is the finish step's pair. `onPressed: null` disables the button like any `FilledButton`. `dimmed: true` draws it as a disabled one is read (`surface-container-highest` fill, the dim text label) and keeps it pressed: what is on screen cannot go yet, and the press brings the reason into view (Connect's address refused for plain http across the internet).
- A thrown action is reported through `FlutterError.reportError` as well as rolled to the failure label; a failed connection test returns a value and does not throw.

## Motion

- `ReelMotion.command`: changed glyphs slide down, new faces entering from above; `AppAnimation.durationSm` (320 ms) on `AppAnimation.emphasizedCurve`, 20 ms between glyphs, each incoming face 30 ms behind its outgoing one, bounce 0.15, and `interrupt: false`, a second change queues rather than snapping the roll in flight.
- `ReelMotion.waiting` (the dots): the same clock with a 16 ms stagger, a 24 ms exit offset and no bounce. Its beat is the 320 ms roll plus the 24 ms exit offset plus a 160 ms rest, one dot every 504 ms (about 2.0 a second).
- **Reduce Motion**: no roll and no dot timer; the button draws a plain `Text`: one settled `Testing`, then the new label swaps in place. The reservation stays.

## The consumer provides

The resting `label`, an optional `busyLabel` (a bare participle, the dots are appended), an optional `failureLabel`, the other labels to reserve in `slotLabels`, and an async `onPressed`.

## Semantics

The spoken name is pinned to the settled label (`busyLabel` while busy, `label` otherwise), never an ellipsis frame.

## Related

`ReelLine` is the same roll for a line of text or a live figure: it rolls only while the text fits one line and falls back to a plain `Text` with the caller's `fallbackMaxLines` otherwise. Presets: `figure` (18 ms stagger, no bounce, never a colour flash), `word` (22 ms), `command`, `waiting`.

## States in the catalog

Each sheet is drawn in the dark and the light room, on the phone and on the desktop.

- Rest, waiting (disabled, dots rolling), answered, failed and settled, `onPressed: null`, dimmed.
- Reduce Motion while waiting; `busyLabel: null`; the finish step's button.
- A long label: the slot holds the widest label it will roll to.
- Text at 200%: rest, waiting and disabled, the slot measured at the reading size.

## Do / don't

- Do list every label the button can show in `slotLabels`, or the button resizes on the transition the slot exists to absorb.
- Do keep one button instance across the answered transition, so the label rolls instead of being replaced.
- Don't swap the label for a spinner: the control keeps naming what was pressed.
- Don't pass dots in the busy label; they are appended.
