# ReelLine

The reel roll: when a line of text changes, only the glyphs that changed roll — the old face drops out of the bottom of its slot as the new one drops in from the top — clipped to the line so nothing paints outside it.

Hand-written from `lib/core/widgets/reel_line.dart`, `lib/core/widgets/reel_command_button.dart`, the presets in `lib/core/reel_motion.dart`, and the per-slot plan of `reel_text` 0.4.3 (`reel_text_slot_plan.dart`), re-implemented line for line in the card's script.

Presets (all `durationSm` 320ms on `emphasizedCurve` = `Cubic(0.2, 0.8, 0.2, 1)`, direction down):

| Preset | stagger | exit offset | bounce | interrupt | source |
|---|---|---|---|---|---|
| `figure` (live numbers) | 18ms | 28ms | 0 | yes | `reel_motion.dart:41` |
| `word` (state words) | 22ms | 34ms | 0 | yes | :58 |
| `command` (a button's label) | 20ms | 30ms | 0.15 | **no — queues** | :80 |
| `waiting` (the busy dots) | 16ms | 24ms | 0 | yes | :104 |

How a roll is planned (the package, ported):

- Old and new strings are paired glyph by glyph from the start of the line. A glyph that is the same in both does not move. Each changed slot takes the next stagger step; the outgoing face moves down one line height over the duration, fading only over its last 22% (smoothstep); the incoming face starts `exitOffset` later from one line above. A trailing slot with nothing coming in rolls out in 75% of the time at half the stagger. Slot widths ease linearly from the old glyph's width to the new one's, so the line re-flows as it rolls.
- `bounce` never overshoots here: `Cubic(0.2, 0.8, 0.2, 1)` never passes 1, so the package's overshoot factor never engages. On `command` its only effects are a ±0.45 × 0.15 duration wobble, a ±0.25 × 0.15 stagger wobble and a tilt of up to 0.75° per glyph.
- `interrupt: true` snaps a roll in flight to its target and starts the next; `command`'s `false` queues the latest target instead, so a double tap never flashes the middle label.

The three cells:

- **ReelLine · figure**: a transfer rate re-rolling on each poll.
- **ReelLine · word**: Queued → Downloading → Importing → Available.
- **ReelCommandButton**: *Test connection* → rolls to *Testing* and ticks the dots (`startWaiting`, :162) → *Next service*, or *Test again* when the press fails. The dot step is the package's steady step: 320 × (1 + 0 × 0.45) + 24 + 160 = **504ms**, about 2.0 ticks a second. The label box is reserved at the widest label the button can show (`_slotWidth`, :193), so the button never resizes; the slot clips.

**Reduce Motion**: `ReelLine` renders a plain `Text` (:106), so the new value simply replaces the old. `ReelCommandButton` shows one settled *Testing*, no dot timer (:156–160), then swaps to the result; the reserved width stays (:231). The roll itself would be suppressed by the package, but its frame timer would still hard-swap the dots, which is why the button checks the setting itself.

`ReelLine` rolls only while its text fits on one line; wider text falls back to a wrapping `Text`, so it is for figures and short state words, never prose.

Web rendition limits: glyph widths come from canvas `measureText` per glyph (tabular digits share one width), so kerning pairs are ignored; the package's wobble uses `sin`, so a JS engine can differ in the last bits and shift a stagger by a millisecond. *Slow ×5* stretches the clock only.

Do pick the preset by what changed (a figure, a state word, a command). Don't hand-write `ReelTextOptions`, and don't roll a live percentage.
