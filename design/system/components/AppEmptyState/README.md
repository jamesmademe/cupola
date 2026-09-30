# AppEmptyState

What a list says when it is truly empty — calm, never alarming, and never a disguise for a failure.

Rendered from `lib/core/widgets/app_empty_state.dart` by `test/design_catalog/app_empty_state_catalog_test.dart`.

## Densities

- **Full** (default constructor) — a 72px circular well (`surface-container-high`, or the accent at 14% when `accentColor` is set — a lamp wash for a service, a tone's wash for a state) around a 34px icon, `space-lg`, title `title-medium` 600, `space-sm`, message `body-medium` in `on-surface-variant`, optional action `space-xl` below. Outer padding `space-xxl` horizontal, `space-xxl` vertical.
- **`.compact`** — 52px well, 26px icon, title `title-small` 600, outer padding `space-xl`, action `space-lg` below.
- **`.inline`** — a left-aligned row: a 16px icon optically aligned to the first text line, `space-sm`, then title `body-small` 600 and an optional message, both `on-surface-variant`. Takes no `action` — an absence nobody can act on is the only kind that belongs on a single row.
- With an `accentColor`, the icon is the accent walked through `ServiceTheme.onTint` against the well it sits in (a service's lamp resolves to the primary ink) (tint 0.14 for full/compact, 0 — no well — for inline); without one, `on-surface-variant`.

## The consumer provides

`icon`, `title`, an optional `message` and (full/compact only) `action`.

`AppEmptyState` itself never scrolls or centres beyond its own column — it is a leaf sized to its content, so a full-page caller must wrap it in a viewport that can grow at accessibility text sizes. `AppEmptyStatePage` (built on `AppScrollablePage`) is that wrapper: it centres the state while it fits the viewport and scrolls once it does not, which is also what keeps a long error or message from clipping off the bottom of a short pane.

## Do / don't

- Do reach for `AppEmptyStatePage` from a screen-level caller rather than centring the state by hand.
- Don't use this for a service with no address or credentials saved — that is `NotConfiguredPlaceholder` (built on this widget, but its own state).
- Don't use this for a failed load — that is a `FaultBand` or `AppErrorState`.
