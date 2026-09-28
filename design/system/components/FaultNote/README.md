# FaultNote

A failure sentence with no recovery verb of its own — the smallest member of the FaultBand family, for places that already offer the retry elsewhere.

Hand-written from `lib/core/widgets/fault_note.dart`.

## Anatomy

- A row sized to its content, top-aligned: 16px glyph, `space-sm` gap, then the sentence (wraps, flexible).
- Sentence `body-small` in `on-surface-variant`. The tone is spent on the glyph alone, never on the words.
- Glyph colour is `statusToneColor(tone, surface:)`, walked against the ground the note sits on (default `surface`).
- No fill, no border, no padding of its own — the host places it.

## Variants

- `FaultNote.unreachable` — `error`, `error_outline`: the source did not answer (a load that never came back).
- `FaultNote.fault` — `warning`, `warning_amber`: the source answered and said no, or the operation failed after it started.

## The consumer provides

`message` and, when the note is not on the scaffold, `surface` — the sheet or card colour it lands on (a request sheet passes `surface-container`).

## Semantics

The glyph is excluded; the sentence is read as plain text. There is no live region — the host control that failed (a submit button, a tier) owns the announcement.

## Do / don't

- Do use it where the retry is already on screen: a form sheet whose submit is the retry, a purchase restarted by tapping a tier.
- Do pass `surface` whenever the note sits on anything but `surface`, or the glyph can fall under contrast.
- Don't colour the sentence red.
- Don't use it for a service that stopped answering above a page — that is `FaultBand`, which carries the verb.
