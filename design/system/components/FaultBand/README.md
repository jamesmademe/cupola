# FaultBand

The quiet line above a page's content that says something is wrong — glyph, sentence, recovery verb — while the last readout below it stays at full ink.

Rendered from `lib/core/widgets/fault_band.dart` by `test/design_catalog/fault_band_catalog_test.dart`.

## Anatomy

- A line, not a card: no fill, no border. Padding `AppSpacing.xs` top and bottom, `AppSpacing.lg` leading, `AppSpacing.sm` trailing; glyph-to-text gap `AppSpacing.sm`.
- Glyph 16px, the only coloured thing on the line (**the presence rule**). Its tone is walked against `colorScheme.surface` through `statusToneColor`, because with no fill behind it the glyph is the whole signal.
- Sentence in `textTheme.bodySmall`, coloured `onSurfaceVariant`, filling the row.
- Verbs are `TextButton`s in `colorScheme.primary` — never red — with `minimumSize: Size(56, 44)`, `AppSpacing.sm` horizontal padding and standard density, pinned. The one exception is an amber fault's remedy, the one fill a fault gets: the compact amber fill (`remedyFillStyle(compact: true)`: `tone.amber-fill` under `tone.amber-ink`, 56 × 44, padding `space-md`), `space-xs` from the sentence.

## Variants

| Constructor | Tone | Glyph | Sentence | Verbs |
|---|---|---|---|---|
| `.unreachable` | error | `cloud_off_rounded` | *TrueNAS did not answer. Everything below is what it said last.* — with `since` ≥ 1 minute: *TrueNAS has not answered for 6 minutes. …* | Retry · Settings (optional) |
| `.fault` | warning (`failureTone`) | the reason's (`failureIcon`: `key_off`, `report`, `timer_off`, …) | The classified headline in the service's own word for what it refused (*key*, *sign-in*, *token*), then the same consequence: *Radarr answered but refused the key. Everything below is what it said last.* | The remedy first, in the amber fill (*Paste the key again*, *Sign in again*, *Check the address*), opening `onOpenSettings` or the lens connection's form, then Retry only where retrying can still help (`failureRetryHelps`); with no form remedy, Retry in the amber fill · Settings (optional) |
| `.section` | error | `link_off_rounded` | The caller's own sentence, naming which source inside the service did not answer and what is missing | Retry · Settings (optional) |
| `.partial` | warning | `playlist_remove_rounded` | The caller's own sentence, saying how much of a paged or merged read arrived: *Seerr returned 50 of 300 users; later pages are unavailable.* Amber, never red — the service just answered | Retry only, in the amber fill: asking again is this fault's remedy |
| `.stale` | warning | `history_toggle_off_rounded` | *These figures are 6 min ago.* + the caller's `detail`; under a minute, *These figures have stopped updating.* + `detail` | Refresh only, no dismiss |
| `.offlinePush` | error | `cloud_off_rounded` | *Radarr stopped answering while this page was open. Everything here is the last render; a write will fail until it is back.* | Retry · Open Radarr (optional) |

`since`/`age` go through the shared age vocabulary in `core/utils/sample_age.dart`: `formatElapsedSpan` returns `null` under a minute (the sentence drops the span), and `formatDurationAge` buckets to `just now` / `N min ago` / `N h ago` — hours never roll up into days.

`AsyncValueWidget` chooses between the first two by the classification: an error over a retained value is `.unreachable` only when nothing answered, and `.fault` for a refusal or any other failure that did answer — red is never spent on a service that just replied. The band and the retained data stay up while Riverpod retries or reloads over that error; only a failure with nothing retained shows the loading state while it retries.

## The consumer provides

The service name (or, for `.section` and `.partial`, the whole sentence), the stale `age` and `detail`, and the callbacks. Actions are a label and a callback (`FaultBandAction`, or `FaultBandAction.remedy` for the amber fill), never a widget, so a caller cannot restyle the verb. `.fault` needs nothing more than a `serviceName` that starts with the service to open the form itself. `primaryAction` is always present — a band with nothing to do about it should not be on screen; `secondaryAction` is `null` on `.stale`.

## Semantics

The band is one container node (`Semantics(container: true, explicitChildNodes: true, liveRegion: true)`) labelled with the sentence, so it is announced when it appears. The glyph and text are excluded from the tree; each verb stays its own reachable control.

## Do / don't

- Do keep the page below the band at full ink: nothing is dimmed for being unreachable — dimming means *not configured*.
- Do give it the page's own slot on a detail page, `MediaDetailBody.band`, never a place inside the deck. Its `space-lg` leading inset is the screen gutter: the band slot adds only the centring surplus, so the glyph lands on the column edge over the actions, where a band inside the deck paid the gutter twice.
- Do pair `.section` with `ServiceKpi.unavailable` so the figures that source owns read `—`, never `0`.
- Don't paint Retry or Refresh red, don't fill anything but an amber fault's remedy, and don't add a dismiss to `.stale`: a stale reading is still true after it is acknowledged.
- Don't use it where the retry lives elsewhere (a form's submit button) — that is `FaultNote`.
