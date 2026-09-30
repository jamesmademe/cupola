# AppErrorState

The two failure leaves beneath the FaultBand: `AppErrorState`, the centred full-page state for a cold open with nothing retained, and `InlineErrorRetry`, the one-line notice for a single section.

Rendered from `lib/core/widgets/app_error_state.dart` and `lib/core/widgets/inline_error_retry.dart` by `test/design_catalog/app_error_state_catalog_test.dart`; routing from `async_value_widget.dart`. The inline messages are Unraid's.

## How the four relate

`AsyncValueWidget` on error: a *not configured* error → NotConfiguredPlaceholder; an error over a retained value → `FaultBand.unreachable` above the last-known data at full ink; nothing retained → `AppErrorState`. A section that fails inside an otherwise loaded page → `InlineErrorRetry`. A failure whose retry already lives elsewhere → `FaultNote`.

## AppErrorState

- Centred column, padding `space-xl`.
- A 32px glyph (26px in `.compact` — the only difference) with **no well behind it** — the Presence Rule: no red fill behind a fault. The glyph is the reason's own (`failureIcon`: `cloud_off`, `key_off`, `timer_off`, `report`, `code_off`, …) and **its tone follows the cause** (`failureTone`): nothing answered → red; everything else → amber — a refused key, a 5xx, a timeout after connecting, a reply nobody can read, a certificate, a redirect, and a failure nobody can attribute, which is no evidence the host is silent. Walked against `surface`.
- `space-lg`, headline *Couldn't load &lt;Service&gt;* (or *Couldn't load this*) in `title-medium` 600; `space-xs`; **the state in its tone**, `label-medium` 600 — `failureLabel`: *Did not answer* (red, the only red words), *Refused the key*, *Timed out*, *Answered with an error*, *Did not complete* (amber); `space-xs`; the detail in `label-small` `dim-text`, three lines max — **a plain sentence from the classification (`connectionFailureSentence`), never `error.toString()`**: *Nothing answered at the saved address. …*, *The server answered and refused the saved credentials. Check them in Settings.*, *The request did not complete.* A failure that carries its own verbatim sentence (`HasFailureDetail`) keeps it. `space-xl`; *Retry* with an 18px `refresh` glyph when `onRetry` is set (`FilledButton.tonalIcon`, which the theme renders as the filled primary button).

## InlineErrorRetry

- Full width, margin `space-lg` × `space-sm`, padding `space-sm` vertical. No fill, no border.
- A 16px glyph walked against `surface`: pass the `error` that failed and it takes the classification's glyph and tone (`failureIcon`, `failureTone` — red only when nothing answered, amber for a refusal or any other failure that answered); without it, `error_outline` in red, which assumes silence; `space-sm`; the message `body-small` `on-surface-variant`; `space-sm`; text button *Retry* in `primary`, minimum 56 × 44, horizontal padding `space-sm`.
- `.fixedHeight` locks the slot to 120px so a carousel row does not jump between loading, loaded and failed.
- A live region announced on appearance; Retry stays its own control.

## The consumer provides

For `AppErrorState`: the error, optionally `serviceName` and `onRetry`. For `InlineErrorRetry`: the message and `onRetry`, and the `error` whenever the caller holds it (the Discover rails do).

## Do / don't

- Do prefer a FaultBand over retained data whenever there is anything to retain — the last readout is what the operator came for.
- Do keep the recovery verb in `primary`, never red.
- Don't use `AppErrorState` for a section inside a loaded page.
- Don't use either for a service that is not set up.
- Don't print an exception, a class name or a library's message anywhere a person reads it. Where the service is known, prefer `ServiceOfflineState.failure`: it can name the address and open the connection form.
