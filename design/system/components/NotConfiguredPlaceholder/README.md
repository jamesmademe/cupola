# NotConfiguredPlaceholder

What a service screen shows when that service has no address or credentials saved — a calm empty state with one door to the fix, never alarm chrome.

Hand-written from `lib/core/widgets/not_configured_placeholder.dart`, built on `AppEmptyState` (see that card).

- `AppEmptyState` full: 72px circular well in `surface-container-high`, 34px `settings` outlined glyph in `on-surface-variant`, `space-lg`, title `title-medium` 600, `space-sm`, message `body-medium` `on-surface-variant`, `space-xl`, action. Padding `space-xxl` × 40px.
- Title *&lt;Service&gt; is not set up*; message *Add its address and credentials in Settings.* ("credentials", because four services sign in through a WebUI and have no API key).
- Action: the theme's filled button — `primary`, `on-primary`, `label-large` 600, `radius-md`, padding `space-xl` × `space-md` — with an 18px `settings` outlined glyph, *Open Settings*.

Two constructors:

- `.forService(key)` — for a service's own screen; the button deep-links to `/settings/service/<routeParam>`, where that service's setup note lives.
- Generic `(serviceName:)` — for callers that only hold a name: `AsyncValueWidget` routes any `<Service> not configured` error here. The button lands on `/settings`.

A screen checks `isServiceConfigured` **before** reaching its providers and draws this instead, so a missing config never becomes a failing provider that retries. Not configured is a normal condition, not a fault: no error tone, and no dimming beyond this screen. Distinct from ServiceOfflineState (configured, not answering).
