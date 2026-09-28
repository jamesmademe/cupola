# NotConfiguredPlaceholder

What a service screen shows when that service has no address or credentials saved — a calm empty state with one door to the fix, never alarm chrome.

Rendered from `lib/core/widgets/not_configured_placeholder.dart`, built on `AppEmptyState` (see that card), by `test/design_catalog/not_configured_placeholder_catalog_test.dart`.

- `AppEmptyState` full: 72px circular well in `surface-container-high`, 34px `settings` outlined glyph in `on-surface-variant`, `space-lg`, title `title-medium` 600, `space-sm`, message `body-medium` `on-surface-variant`, `space-xl`, action. Padding `space-xxl` × 40px.
- Title *&lt;Service&gt; is not set up*; message *Add its address and credentials in Settings.* ("credentials", because four services sign in through a WebUI and have no API key).
- Action: the theme's filled button — `label-large` 600, `radius-md`, padding `space-xl` × `space-md` — with an 18px `settings` outlined glyph, *Open Settings*. On a service's own screen (`.forService`) it takes that service's light: the soft container (the accent at `opacityServiceSoftContainer`) as its fill and the label walked with `ServiceTheme.onTint` against it, 4.5:1 for every service in both themes; a solid accent fill cannot reach that for Seerr, Sonarr or Jellyfin. The generic form keeps `primary` / `on-primary`.

Two constructors:

- `.forService(key)` — for a service's own screen; the button deep-links to `/settings/service/<routeParam>`, where that service's setup note lives.
- Generic `(serviceName:)` — for callers that only hold a name: `AsyncValueWidget` routes any `<Service> not configured` error here. The button lands on `/settings`.

A screen checks `isServiceConfigured` **before** reaching its providers and draws this instead, so a missing config never becomes a failing provider that retries. Not configured is a normal condition, not a fault: no error tone, and no dimming beyond this screen. Distinct from ServiceOfflineState (configured, not answering).
