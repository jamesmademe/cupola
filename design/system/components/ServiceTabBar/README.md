# ServiceTabBar

The bar of views belonging to one service: a start-aligned, scrollable row of text tabs with an accent rule under the selected one, and on a desktop window the service's whole lit header.

Hand-written from `lib/core/widgets/service_tab_bar.dart`; tabs from `serviceTabs` in `lib/features/services/domain/service_tab.dart`. On the phone it is hosted on a `GlassSurface` band by `ServiceTabScaffold` (see AmbientScaffold); the preview shows it on a plain `surface` frame.

## Default bar

- Height 44. Horizontal padding `space-lg`; tabs `space-xs` apart; every tab built (no lazy list). The row scrolls and is aligned to the start — never distributed, never centred.
- Tab: at least 44 wide, padding `space-md` × `space-sm`, `label-large`, one line. Unselected: weight 500 in `on-surface-variant`. Selected: weight 600 in the service accent walked against `surface` (`ServiceTheme.onTint`, tint 0).
- Rule: 2px, `radius-pill`, in the same walked accent, positioned at the bottom of the padded cell so nothing shifts when it appears. It spans the label plus its `space-md` padding on both sides.

## `.header` — the desktop service header

Used on a desktop window 720 wide or more, for every tabbed service (TrueNAS draws its own console). It replaces the phone's band and is the one lit surface on a service page.

- **Room light.** The band is opaque: the service accent at 12% (`roomLightAlpha`) composited over `surface`, across the full 44. A bloom fills its lower 11px (`bloomHeight`), a vertical gradient from the accent at 0 to the accent at 30% (`bloomAlpha`), painted under the row so labels and the selected rule are drawn crisp above it. No border: the selected rule already draws the accent edge.
- The 30% bloom is the strongest at which every tabbed accent keeps its selected rule at 3:1 or better against the bloom, in both themes; Transmission in light theme is the floor case.
- **Ink resolves against the lit band.** Tab labels and the rule are walked with `onTint` against `surface` at tint 0.12. The composite is published to descendants through `ServiceBandSurface`, so the connection lens and any action placed in the header measure against the band too (`ServiceBandSurface.of(context)`; outside a header it answers `surface`).
- Row: `space-lg`, the identity — a 24 × 24 well (accent at 14%, 1px border at 40%, radius `radius-sm` − 1) holding the service mark at 14 in the accent walked against the band at 0.14 — then `space-sm` + 2 and the service name in `AppTheme.rowTitle` (15 / 600 / 1.30, `on-surface`, capped at 220 and ellipsised); the connection lens when the service has several; `space-sm`; a 1 × 20 `outline-variant` rule; the tabs (padding `space-sm` instead of `space-lg`); the service's own actions; `space-sm`.
- The tabs give way first: they scroll, while the name ellipsises and the actions stay.

## Consumer provides

`service` (a `ServiceKey`), `current` (the selected `ServiceTab`), `onSelected`. For `.header`, optional `lens` and `actions` widgets.

## Semantics

- Each tab is one node: button, its label alone, the `selected` flag. The selected tab has no tap action.
- In `.header` the service name is the page heading (`header: true`); the well is excluded.
- A tap on another tab is router navigation (`goBranch`), not a controller change. Pushed pages cover the bar rather than hiding it.

## Real bars

The four *arr: `Overview · Library · Calendar · Queue · Wanted · History`. Seerr: `Overview · Requests · Issues · Discover · Users`. qBittorrent: `Overview · Queue · RSS`. Transmission: `Overview · Queue · Labels · Session`. Nginx Proxy Manager: `Overview · Proxy hosts · Certificates · Access lists · Audit log`. Every bar starts with Overview and holds at most six. TrueNAS has no bar: `tabsFor` returns null and nothing is drawn.

## Do / don't

- Do resolve any control placed on the header against `ServiceBandSurface.of(context)`, never bare `surface`.
- Don't put the header on glass or add an accent border; the band is opaque so its ink can be measured, and a second accent line reads as a second selection.
- Don't raise the bloom: above 30% the selected rule stops reading against it.
