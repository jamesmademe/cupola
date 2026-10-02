# NotConfiguredPlaceholder

What a service screen shows when that service has no address or credentials saved — a calm empty state with one door to the fix, never alarm chrome.

Rendered from `lib/core/widgets/not_configured_placeholder.dart`, built on `AppEmptyState` (see that card), by `test/design_catalog/not_configured_placeholder_catalog_test.dart`.

- `AppEmptyState` full: 72px circular well in `surface-container-high`, 34px `settings` outlined glyph in `on-surface-variant`, `space-lg`, title `title-medium` 600, `space-sm`, message `body-medium` `on-surface-variant`, `space-xl`, action. Padding `space-xxl` × 40px.
- Title *&lt;Service&gt; is not set up*; message *Add its address and credentials in Settings.* ("credentials", because four services sign in through a WebUI and have no API key).
- Action: the theme's filled button — the row role (15 / 600), `radius-control` (14), padding `space-lg` × `space-md` — with an 18px `add_link` glyph, *Set up &lt;Service&gt;* (`Lexicon.setUp`). The ink button in both forms — `primary` / `on-primary`, the theme's own style, never a service's colour.

Two constructors:

- `.forService(key)` — for a service's own screen; the button opens the service's setup form (`ServiceRoutes.setUp`, `/settings/service/<routeParam>`), where its setup note lives — the one place every *Set up X* in the app goes.
- Generic `(serviceName:)` — for callers that only hold a name: `AsyncValueWidget` routes any `<Service> not configured` error here. The name is resolved back to its service, so the button is the same *Set up X* into the same form; only a name that is no service's keeps *Open Settings* → `/settings`.

**A Seerr account that signed out is set up**, and never reads as not set up: for Seerr the placeholder asks the settings for the signed-out connection the screen stands on (the lens's, else the only one) and draws `AppErrorState` for the ended session instead: the blue `logout` glyph, *Signed out of Seerr*, *Sign in again to keep asking for movies and series.*, and *Sign in again* in the ink fill, opening that connection's own form. No Retry: no request revives a session. Only inside a `ProviderScope`, which the app always has.

A screen checks `isServiceConfigured` **before** reaching its providers and draws this instead, so a missing config never becomes a failing provider that retries. Not configured is a normal condition, not a fault: no error tone, and no dimming beyond this screen. Distinct from ServiceOfflineState (configured, not answering).

## States in the catalog

Each sheet is drawn in the dark and the light room.

- `forService(radarr)`, the generic form with a name, and `forService(seerr)` for a signed-out account (blue).
- Text at 200%: `forService(radarr)` and the signed-out Seerr form.
