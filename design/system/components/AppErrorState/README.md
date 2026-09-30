# AppErrorState

The two failure leaves beneath the FaultBand: `AppErrorState`, the centred full-page state for a cold open with nothing retained, and `InlineErrorRetry`, the one-line notice for a single section.

Rendered from `lib/core/widgets/app_error_state.dart` and `lib/core/widgets/inline_error_retry.dart` by `test/design_catalog/app_error_state_catalog_test.dart`; routing from `async_value_widget.dart`. The inline messages are Unraid's, as a section that did not answer.

## How the four relate

`AsyncValueWidget` on error: a *not configured* error → NotConfiguredPlaceholder; an error over a retained value → `FaultBand.unreachable` above the last-known data at full ink; nothing retained → `AppErrorState`. A section that fails inside an otherwise loaded page → `InlineErrorRetry`. A failure whose retry already lives elsewhere → `FaultNote`.

## AppErrorState

- Centred column, padding `space-xl`.
- A 32px glyph (26px in `.compact` — the only difference) with **no well behind it** — the Presence Rule: no red fill behind a fault. The glyph is the reason's own (`failureIcon`: `cloud_off`, `key_off`, `timer_off`, `report`, `code_off`, …) and **its tone follows the cause** (`failureTone`): nothing answered → red; everything else → amber — a refused key, a 5xx, a timeout after connecting, a reply nobody can read, a certificate, a redirect, and a failure nobody can attribute, which is no evidence the host is silent. Walked against `surface`.
- `space-lg`, the classification's headline, naming the service the caller's `serviceName` starts with (a page may pass *Seerr issues*; the headline names Seerr), in `title-medium` 600 **in the state's tone** — the fault said once: *Radarr did not answer* (red, the only red words) · *Radarr answered but refused the key* · *Radarr was reached but did not reply in time* · *The request to Radarr did not complete* (amber) — or *the server* when no service is named. Never *Couldn't load Radarr*, and no second line repeating the state; `space-xs`; the detail in `label-small` `dim-text`, three lines max — **why, or what to do, in a plain sentence from the classification (`connectionFailureSentence`), never `error.toString()`**: *Nothing answered at the saved address. …*, *The server answered and refused the saved credentials. Check them in Settings.*, *It may be busy. Retry in a moment.* A failure that carries its own verbatim sentence (`HasFailureDetail`) keeps it; a failure nobody can attribute has nothing to add to its headline and shows no detail. `space-xl`; *Retry* with an 18px `refresh` glyph when `onRetry` is set (`FilledButton.tonalIcon`, which the theme renders as the filled primary button).

## InlineErrorRetry

- Full width, margin `space-lg` × `space-sm`, padding `space-sm` vertical. No fill, no border.
- A 16px glyph walked against `surface`, in the classification's glyph and tone for the `error` that failed (`failureIcon`, `failureTone` — red only when nothing answered, amber for a refusal or any other failure that answered, and amber for a failure nobody can attribute); `space-sm`; the message `body-small` `on-surface-variant`; `space-sm`; text button *Retry* in `primary`, minimum 56 × 44, horizontal padding `space-sm`.
- The message is worded from the same classification (`sectionFailureMessage`): the headline, then what the page is without — *Unraid did not answer, so its virtual machines are not shown.* · *Unraid answered but refused the key, so its shares are not shown.*
- `.fixedHeight` locks the slot to 120px so a carousel row does not jump between loading, loaded and failed.
- A live region announced on appearance; Retry stays its own control.

## The consumer provides

For `AppErrorState`: the error, optionally `serviceName` and `onRetry`. For `InlineErrorRetry`: the message, `onRetry` and the `error` that failed — required, because a section that left it out stayed red for a refused key.

## Do / don't

- Do prefer a FaultBand over retained data whenever there is anything to retain — the last readout is what the operator came for.
- Do keep the recovery verb in `primary`, never red.
- Don't use `AppErrorState` for a section inside a loaded page.
- Don't use either for a service that is not set up.
- Don't print an exception, a class name or a library's message anywhere a person reads it. Where the service is known, prefer `ServiceOfflineState.failure`: it can name the address and open the connection form.
