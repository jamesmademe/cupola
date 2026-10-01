# ServiceOfflineState

The leaf for a configured service that has never answered in this session: a glyph, a fact, an age, and the recovery.

Rendered from `lib/core/widgets/service_offline_state.dart` by `test/design_catalog/service_offline_state_catalog_test.dart`. The plain leaf is used by TrueNAS, Unraid, SABnzbd, Transmission, NZBGet and Nginx Proxy Manager; `.failure` (below) by the surfaces that hold the error that failed.

## Values

- Centred column, padding `space-xl`. No fill behind the glyph.
- `cloud_off` (`failureIcon` for a host that did not answer) at 32px in that state's tone: red, `statusToneColor` walked against `surface`. The title names the state and the glyph carries its tone; the service's accent is registry data and is not painted.
- `space-lg`, then the title *&lt;Service&gt; did not answer* in `title-medium` at 600.
- `space-sm`, then the body in `body-small`, `on-surface-variant`: *It has not answered for 40 minutes. Anything it holds is missing from this page.* When no first-failure time is known the span is dropped, not invented: *Anything it holds is missing from this page.*
- `space-xl`, then the actions: *Retry* with an 18px `refresh` glyph as a filled button (the theme's `primary` / `on-primary`, `radius-md`), and optionally, `space-sm` after it, a text button *Settings* in `primary` with a 56 × 44 minimum target.

## `.failure` — the same leaf, told why

`ServiceOfflineState.failure(service:, error:, onRetry:)` classifies the error (`classifyConnectionFailure`) and says what the connection form would say, instead of assuming silence:

- **Glyph** from `describeFailure` (`cloud_off`, `key_off`, `timer_off`, `gpp_bad`, `wrong_location`, `alt_route`, `report`, `code_off`, `no_encryption`, `wifi_lock`) at 32px, in the tone walked against `surface`: **red only when nothing answered**, **amber for a fault** — the server answered (or the device would not dial), so there is one thing to fix.
- **Title** — `describeFailure`'s headline, which names who: *Radarr did not answer* for silence; *Radarr answered but refused the key*, *Radarr answered with an error*, *Radarr was reached but did not reply in time* for a fault.
- **Address** — the lens connection's host (`ServiceKey.extractHost`), `space-xs` under the title in `AppTheme.chrome` 12 `on-surface-variant`; dropped when the connection names none.
- **Body** — `connectionFailureDetail(error)` if the failure carries its own sentence, else `connectionFailureMessage(service, reason)`; with a known first-failure age, *It has not answered for 40 minutes.* leads it. Never the exception.
- **Actions** — the way into the connection form is always there, and defaults to the lens connection's form (`ServiceRoutes.settingsForConnection`), because after a failed read the address or the key is the likeliest fix. When the form holds the fault's remedy (`FailureRemedy`: *Paste the key again*, *Sign in again*, *Check the address*, *Check the certificate*, *Change the address*) the remedy is the filled button and *Retry* follows as the text action only where retrying can still help (`failureRetryHelps`); a refused key or an `http://` address has no Retry. Otherwise *Retry* leads, as on the plain leaf, and the text action is *Settings*. The actions wrap and stay centred on a narrow pane.
- Semantics speak *title. address. body* as one sentence.

Used by the library walls (`MediaBrowseScaffold(service:)`), Readarr's author list, the Jellyfin/Plex Overview when the server is dark (one state for the page, not one per region), the Stream tabs that are one read each, and Activity's streaming feed when its only media server is dark.

## Consumer provides

`serviceName`, `accent` (kept for the callers, no longer painted) and `onRetry`; optionally `since` (the age of the first failure, formatted as minutes or hours) and `onOpenSettings`.

## Semantics

The column speaks one sentence (*SABnzbd did not answer. It has not answered for 40 minutes. …*); glyph, title and body are excluded under it, and the buttons remain separate controls.

## Do / don't

- Do prefer `FaultBand.unreachable` wherever any retained readout exists: last-known data at full ink beats an emptied page. This leaf is for the cold open only.
- Don't dim for this state; dimming means not configured.
- Don't paint the recovery in the error tone.
