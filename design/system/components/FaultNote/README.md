# FaultNote

A failure sentence with no recovery verb of its own — the smallest member of the `FaultBand` family, for places that already offer the retry elsewhere.

Rendered from `lib/core/widgets/fault_note.dart` by `test/design_catalog/fault_note_catalog_test.dart`.

## Anatomy

- A row sized to its content, top-aligned: 16px glyph, `AppSpacing.sm` gap, then the sentence in a `Flexible` (wraps).
- Sentence in `textTheme.bodySmall`, coloured `onSurfaceVariant`. The tone is spent on the glyph alone, never on the words.
- Glyph colour is `statusToneColor(colorScheme, tone, surface: surface)`, walked against the ground the note sits on (default `colorScheme.surface`).
- No fill, no border, no padding of its own — the host places it.

## Variants

- `FaultNote.unreachable` — error tone, `error_outline_rounded`: the source did not answer (a load that never came back).
- `FaultNote.fault` — warning tone, `warning_amber_rounded`: the source answered and said no, or the operation failed after it started.

## The consumer provides

`message` and, when the note is not on the scaffold, `surface` — the sheet or card colour it lands on (a request sheet passes `surfaceContainer`).

## Semantics

The glyph is excluded; the sentence is read as plain text. There is no live region — the host control that failed (a submit button, a tier) owns the announcement.

## Do / don't

- Do use it where the retry is already on screen: a form sheet whose submit is the retry, a purchase restarted by tapping a tier.
- Do pass `surface` whenever the note sits on anything but `surface`, or the glyph can fall under contrast.
- Don't colour the sentence red.
- Don't use it for a service that stopped answering above a page — that is `FaultBand`, which carries the verb.
