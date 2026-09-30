# AppErrorState

The two failure leaves beneath the FaultBand: `AppErrorState`, the centred full-page state for a cold open with nothing retained, and `InlineErrorRetry`, the one-line notice for a single section.

Rendered from `lib/core/widgets/app_error_state.dart` and `lib/core/widgets/inline_error_retry.dart` by `test/design_catalog/app_error_state_catalog_test.dart`; routing from `async_value_widget.dart`. The inline messages are Unraid's.

## How the four relate

`AsyncValueWidget` on error: a *not configured* error → NotConfiguredPlaceholder; an error over a retained value → `FaultBand.unreachable` above the last-known data at full ink; nothing retained → `AppErrorState`. A section that fails inside an otherwise loaded page → `InlineErrorRetry`. A failure whose retry already lives elsewhere → `FaultNote`.

## AppErrorState

- Centred column, padding `space-xl`.
- A circular well with `space-lg` padding around a 32px `error_outline` (26px in `.compact` — the only difference). **The tone follows the cause** (`failureIsFault`, the split `describeConnection` makes): nothing answered, or the failure cannot be attributed → red, an `error-container` well with the glyph walked against it; the server answered (a rejected key, a 5xx, a timeout, a certificate, a redirect) → amber, the warning tone washed over `surface` at 16% with the glyph walked against that wash.
- `space-lg`, headline *Couldn't load &lt;Service&gt;* (or *Couldn't load this*) in `title-medium` 600; `space-xs`; the detail in `label-small` `dim-text`, three lines max — **a plain sentence from the classification (`connectionFailureSentence`), never `error.toString()`**: *Nothing answered at the saved address. …*, *The server answered and rejected the saved credentials.*, *The request did not complete.* A failure that carries its own verbatim sentence (`HasFailureDetail`) keeps it. `space-xl`; *Retry* with an 18px `refresh` glyph when `onRetry` is set (`FilledButton.tonalIcon`, which the theme renders as the filled primary button).

## InlineErrorRetry

- Full width, margin `space-lg` × `space-sm`, padding `space-sm` vertical. No fill, no border.
- 16px `error_outline`, red walked against `surface`; `space-sm`; the message `body-small` `on-surface-variant`; `space-sm`; text button *Retry* in `primary`, minimum 56 × 44, horizontal padding `space-sm`.
- `.fixedHeight` locks the slot to 120px so a carousel row does not jump between loading, loaded and failed.
- A live region announced on appearance; Retry stays its own control.

## The consumer provides

For `AppErrorState`: the error, optionally `serviceName` and `onRetry`. For `InlineErrorRetry`: the message and `onRetry`.

## Do / don't

- Do prefer a FaultBand over retained data whenever there is anything to retain — the last readout is what the operator came for.
- Do keep the recovery verb in `primary`, never red.
- Don't use `AppErrorState` for a section inside a loaded page.
- Don't use either for a service that is not set up.
- Don't print an exception, a class name or a library's message anywhere a person reads it. Where the service is known, prefer `ServiceOfflineState.failure`: it can name the address and open the connection form.
