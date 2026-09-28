# ReelCommandButton

A primary button whose label rolls to its next word instead of being replaced by a spinner, so the control keeps naming what you pressed while it works.

Hand-written from `lib/core/widgets/reel_command_button.dart`, with `lib/core/widgets/reel_line.dart` and the presets in `lib/core/reel_motion.dart`. Labels are the onboarding callers' real strings. The mid-roll frame is a static illustration of motion.

## Values

- A `FilledButton` from the theme: `primary` fill, `on-primary` label, `label-large` 600, `radius-md`, padding `space-xl` × `space-md`. While the future runs the button is disabled (Material: `on-surface` 12% fill, 38% label) and the label keeps moving.
- **Reserved slot**: the label box is as wide as the widest string the button can ever show — rest, busy with its full `...`, failure and every `slotLabels` entry — so the button never resizes and the label never re-centres. The slot clips, so travelling glyphs never paint outside the fill.
- **States**: rest `Test connection` → waiting `Testing` + rolling dots → answered, rolls to `Next service` (or `Finish`) → thrown, rolls to `Test again`. `busyLabel: null` means no waiting state: the action runs and the label rolls when the parent changes it (`Continue` → `Continue with 4`; `Enter Cupola` / `Opening`).
- **Motion** (`ReelMotion.command`): changed glyphs slide down, new faces entering from above; 200ms on the emphasised curve, 20ms between glyphs, each incoming face 30ms behind its outgoing one, bounce 0.15, queued rather than interrupted. The waiting loop (`ReelMotion.waiting`) keeps the clock with 16ms stagger and no bounce; its beat is the 200ms roll plus a 24ms exit offset plus a 160ms rest, one dot every 384ms (about 2.6 a second).
- **Reduce Motion**: no roll and no dot timer — one settled `Testing`, then the new label swaps in place. The reservation stays.

## Consumer provides

The resting label, an optional busy participle (no dots — they are appended), an optional failure label, the other labels to reserve, and an async `onPressed`.

## Semantics

The spoken name is pinned to the settled label (*Testing* while busy), never an ellipsis frame.

## Related

`ReelLine` is the same roll for a line of text or a live figure: it rolls only while the text fits one line and falls back to a plain wrapping `Text` otherwise. Presets: `figure` (18ms, no bounce, never a colour flash), `word` (22ms), `command`, `waiting`.

## Do / don't

- Do list every label the button can show in `slotLabels`, or the button resizes mid-roll.
- Don't swap the label for a spinner: the control keeps naming what was pressed.
- Don't pass dots in the busy label; they are appended.
