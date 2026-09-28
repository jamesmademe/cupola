# ServiceOfflineState

The leaf for a configured service that has never answered in this session: a glyph, a fact, an age, and the recovery.

Rendered from `lib/core/widgets/service_offline_state.dart` by `test/design_catalog/service_offline_state_catalog_test.dart`. Used by TrueNAS, Unraid, SABnzbd, Transmission, NZBGet and Nginx Proxy Manager.

## Values

- Centred column, padding `space-xl`. No fill behind the glyph.
- `cloud_off` at 32px in the service accent walked against `surface` (`onTint`, tint 0).
- `space-lg`, then the title *&lt;Service&gt; did not answer* in `title-medium` at 600.
- `space-sm`, then the body in `body-small`, `on-surface-variant`: *No response for 40 minutes. Anything it holds is missing from this page.* When no first-failure time is known the span is dropped, not invented: *No response. Anything it holds is missing from this page.*
- `space-xl`, then the actions: *Retry* with an 18px `refresh` glyph as a filled button (the theme's `primary` / `on-primary`, `radius-md`), and optionally, `space-sm` after it, a text button *Settings* in `primary` with a 56 × 44 minimum target.

## Consumer provides

`serviceName`, `accent` and `onRetry`; optionally `since` (the age of the first failure, formatted as minutes or hours) and `onOpenSettings`.

## Semantics

The column speaks one sentence (*SABnzbd did not answer. No response for 40 minutes. …*); glyph, title and body are excluded under it, and the buttons remain separate controls.

## Do / don't

- Do prefer `FaultBand.unreachable` wherever any retained readout exists: last-known data at full ink beats an emptied page. This leaf is for the cold open only.
- Don't dim for this state; dimming means not configured.
- Don't paint the recovery in the error tone.
