# FaultBand

The quiet line above a page's content that says something is wrong (glyph, sentence, recovery verb) while the last readout below it stays at full ink.

Rendered from `lib/core/widgets/fault_band.dart` by `test/design_catalog/fault_band_catalog_test.dart`.

## Anatomy

- A line, not a card: no fill, no border. Padding `AppSpacing.xs` top and bottom, `AppSpacing.lg` leading, `AppSpacing.sm` trailing; glyph-to-text gap `AppSpacing.sm`.
- Glyph 16px, the only coloured thing on the line (**the presence rule**), centred on the sentence's first line. Its tone is walked against `colorScheme.surface` through `statusToneColor`, because with no fill behind it the glyph is the whole signal.
- Sentence in `textTheme.bodySmall`, coloured `onSurfaceVariant`, filling what the verbs leave.
- **Beside or under.** The verbs sit beside the sentence, centred on it, while the sentence keeps sixteen of its own em (about thirty characters a line); once it would not, they go under it, `space-xs` below, at the trailing edge where they sat beside (so they keep their place whatever the size), and wrap if even that is too narrow (`BesideOrBelow`, `lib/core/widgets/beside_or_below.dart`, `InlineErrorRetry`'s layout too). The measure is in the sentence's own type, so text at 200% on a phone always puts them under; at 100% on a 390pt phone one or two short verbs stay beside, and a long remedy with Retry goes under. The verbs are `space-xs` apart and `space-xs` from the sentence.
- Verbs are `TextButton`s in `colorScheme.primary`, never red, with `minimumSize: Size(56, 44)`, `AppSpacing.sm` horizontal padding and standard density, pinned. The one exception is an amber fault's remedy, the one fill a fault gets: the compact amber fill (`remedyFillStyle(compact: true)`: `tone.amber-fill` under `tone.amber-ink`, 56 × 44, padding `space-md`).

## Variants

| Constructor | Tone | Glyph | Sentence | Verbs |
|---|---|---|---|---|
| `.unreachable` | error | `cloud_off_rounded` | *TrueNAS did not answer. Everything below is what it said last.*, and with `since` ≥ 1 minute: *TrueNAS has not answered for 6 minutes. …* | Retry · Settings (optional) |
| `.fault` | warning (`failureTone`) | the reason's (`failureIcon`: `key_off`, `report`, `timer_off`, …) | The classified headline in the service's own word for what it refused (*key*, *sign-in*, *token*), then the same consequence: *Radarr answered but refused the key. Everything below is what it said last.* With `gateway:` (an `AccessGatewayAnswer`, which `AsyncValueWidget` reads off the failure) the headline names what answered in front: *Cloudflare Access answered instead of Radarr.* | The remedy first, in the amber fill (*Paste the key again*, *Sign in again*, *Check the address*, *Add a service token*), opening `onOpenSettings` or the lens connection's form (on its Access row for a gateway), then Retry only where retrying can still help (`failureRetryHelps`); with no form remedy, Retry in the amber fill · Settings (optional) |
| `.timedOut` | warning (`failureTone`) | `timer_off_rounded` (`failureIcon`) | The caller's own sentence for the servers reached that never replied, named as the silence names them: *Radarr, Sonarr and 6 others were reached but did not reply in time.* Amber, never red: the host is there and the server is stuck | Retry only, in the amber fill |
| `.section` | error | `link_off_rounded` | The caller's own sentence, naming which source inside the service did not answer and what is missing | Retry · Settings (optional) |
| `.partial` | warning | `playlist_remove_rounded` | The caller's own sentence, saying how much of a paged or merged read arrived: *Seerr returned 50 of 300 users; later pages are unavailable.* Amber, never red: the service just answered | Retry only, in the amber fill: asking again is this fault's remedy |
| `.stale` | warning | `history_toggle_off_rounded` | *These figures are from 6 min ago.* + the caller's `detail`; under a minute, *These figures have stopped updating.* + `detail` | Refresh only, no dismiss |
| `.offlinePush` | error | `cloud_off_rounded` | *Radarr stopped answering while this page was open. Everything here is the last render; a write will fail until it is back.* | Retry · Open Radarr (optional) |

`since` is how long the connection has not answered: since the first probe that did not (`SilenceClock`, `lib/core/status/silence_clock.dart`), kept across every probe that fails after it and ended by any answer, a refused key included. It is held in memory only, so a cold start into a silent service has no span until a minute of its own silence has passed. The client pages (SABnzbd, NZBGet, Transmission, Unraid, Nginx Proxy Manager) pass it through `FaultBand.fromSummary(since:)` from `ref.watchSilence` (`silence_age.dart`), which renews it once a minute while the page is the one on screen; `AsyncValueWidget` reads it itself for a section or for a page that names its service (`silentService:`), for the connection it names or the lens's. A fault carries no span. `since`/`age` go through the shared age vocabulary in `core/utils/sample_age.dart`: `formatElapsedSpan` returns `null` under a minute (the sentence drops the span), and `formatDurationAge` buckets to `just now` / `N min ago` / `N h ago`: hours never roll up into days.

`AsyncValueWidget` chooses between the first two by the classification: an error over a retained value is `.unreachable` only when nothing answered, and `.fault` for a refusal or any other failure that did answer; red is never spent on a service that just replied. The band and the retained data stay up while Riverpod retries or reloads over that error; only a failure with nothing retained shows the loading state while it retries. A read whose own client was closed under it by a settings change gets no band at all: nothing was dialled, and the retained data stays up while the provider reads again.

## The consumer provides

The service name (or, for `.timedOut`, `.section` and `.partial`, the whole sentence), the stale `age` and `detail`, and the callbacks. Actions are a label and a callback (`FaultBandAction`, or `FaultBandAction.remedy` for the amber fill), never a widget, so a caller cannot restyle the verb. `.fault` needs nothing more than a `serviceName` that starts with the service to open the form itself. `primaryAction` is always present: a band with nothing to do about it should not be on screen; `secondaryAction` is `null` on `.stale`.

## Semantics

The band is one container node (`Semantics(container: true, explicitChildNodes: true, liveRegion: true)`) labelled with the sentence, so it is announced when it appears. The glyph and text are excluded from the tree; each verb stays its own reachable control.

## States in the catalog

Each sheet is drawn in the dark and the light room.

- `.unreachable` with and without an age, `.fault` for a refused key, a qBittorrent sign-in, Cloudflare Access and a server error, `.timedOut`, `.section`, `.partial`, `.stale` (6 min and just now), `.offlinePush`.
- A 390pt phone at 100%: two short verbs and one stay beside, a remedy with Retry goes under.
- Text at 200% on a 390pt phone: `.unreachable`, `.fault` with its remedy, and `.partial` with `.stale`, every verb under its sentence.

## Do / don't

- Do keep the page below the band at full ink: nothing is dimmed for being unreachable; dimming means *not configured*.
- Do give it the page's own slot on a detail page, `MediaDetailBody.band`, never a place inside another region. Its `space-lg` leading inset is the screen gutter: the band slot adds only the centring surplus, so the glyph lands on the column edge, where a band inside a region would pay the gutter twice.
- Do pair `.section` with `ServiceKpi.unavailable` so the figures that source owns read `—`, never `0`.
- Don't paint Retry or Refresh red, don't fill anything but an amber fault's remedy, and don't add a dismiss to `.stale`: a stale reading is still true after it is acknowledged.
- Don't use it where the retry lives elsewhere (a form's submit button); that is `FaultNote`.
