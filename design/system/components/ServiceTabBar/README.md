# ServiceTabBar

The bar of views belonging to one service: a start-aligned, scrollable row of text tabs with the selected one on a pill, and on a desktop window the service's whole lit header. Monochrome: no service colours it.

Rendered from `lib/core/widgets/service_tab_bar.dart` by `test/design_catalog/service_tab_bar_catalog_test.dart`; tabs from `serviceTabs` in `lib/features/services/domain/service_tab.dart`. On the phone it is hosted on a `GlassSurface` band by `ServiceTabScaffold` (see AmbientScaffold); the catalog draws it on plain `surface`.

## Default bar

- Height 44. Horizontal padding `space-lg`; tabs `space-xs` apart; every tab built (no lazy list). The row scrolls and is aligned to the start — never distributed, never centred.
- Tab: at least 44 wide, padding `space-md` × `space-sm`, `label-large`, one line, growing with the reading size to 1.3× and no further (`FloatingNavBarMetrics.effectiveTextScaler`, the phone bar's ceiling), so it stays whole in the 44pt row every hosted page reserves; at 200% the row used to cut it below its baseline. Unselected: weight 500 in `dim-text` (the tertiary ink). Selected: weight 600 in `on-surface` (the primary ink).
- Pill: the selected tab sits on the room's strong fill (`fill-strong`), 36 tall, `radius-pill`, centred in the 44 cell and positioned behind the label so nothing shifts when it appears. It spans the label plus its `space-md` padding on both sides — the pill of the phone's bar and the desktop rail, never the service's colour.

## `.header` — the desktop service header

Used on a desktop window 720 wide or more, for every tabbed service (TrueNAS draws its own console). It replaces the phone's band and is the one lit surface on a service page.

- **Room light.** A service room has no artwork, so it is lit by the neutral lamp: the band is opaque, the service's accent — the lamp, for every service — at 12% (`roomLightAlpha`) composited over `surface`, across the full 44. A bloom fills its lower 11px (`bloomHeight`), a vertical gradient from the lamp at 0 to the lamp at 30% (`bloomAlpha`), painted under the row so the labels are drawn crisp above it. No border: the selected pill already marks the row.
- **Ink is measured against the lit band.** The labels are the room's inks, and every one clears 4.5:1 on the band in both themes. The composite is published to descendants through `ServiceBandSurface`, so the connection lens and any action placed in the header measure against the band too (`ServiceBandSurface.of(context)`; outside a header it answers `surface`).
- Row: `space-lg`, the identity — the brand book's lit tile: a 24 × 24 well on the room's strong fill with a 1px `line-edge` border, radius `sm2` (10), holding the service mark at 14 in `on-surface` (a step brighter than a mark in a list) — then 10 (`space.scale.row`) and the service name in `AppTheme.rowTitle` (15 / 600 / 20 leading, `on-surface`, capped at 220 and ellipsised); the connection lens when the service has several; `space-sm`; a 1 × 20 `outline-variant` rule; the tabs (padding `space-sm` instead of `space-lg`); the service's own actions; `space-sm`.
- The tabs give way first: they scroll, while the name ellipsises and the actions stay.

## Consumer provides

`service` (a `ServiceKey`), `current` (the selected `ServiceTab`), `onSelected`. For `.header`, optional `lens` and `actions` widgets.

## Semantics

- Each tab is one node: button, its label alone, the `selected` flag. The selected tab has no tap action.
- In `.header` the service name is the page heading (`header: true`); the well is excluded.
- A tap on another tab is router navigation (`goBranch`), not a controller change. Pushed pages cover the bar rather than hiding it.

## Real bars

The four *arr: `Overview · Library · Calendar · Queue · Wanted · History`. Seerr: `Overview · Requests · Issues · Discover · Users`. qBittorrent: `Overview · Queue · RSS`. Transmission: `Overview · Queue · Labels · Session`. Nginx Proxy Manager: `Overview · Proxy hosts · Certificates · Access lists · Audit log`. Every bar starts with Overview and holds at most six. TrueNAS has no bar: `tabsFor` returns null and nothing is drawn.

## States in the catalog

Each sheet is drawn in the dark and the light room.

- `ServiceTabBar.header` on the desktop: Radarr with the instance lens, Transmission without.
- `ServiceTabBar` on the phone: Radarr with Queue selected, Nginx Proxy Manager scrolling from the start.
- Text at 200%: the phone bar and the desktop header, the labels at their 1.3× ceiling.

## Do / don't

- Do resolve any control placed on the header against `ServiceBandSurface.of(context)`, never bare `surface`.
- Don't put the header on glass or add a border along it; the band is opaque so its ink can be measured, and a second line reads as a second selection.
- Don't colour a tab, the pill or the mark with the service's brand colour: the room is monochrome, and the mark's shape and the name say which service this is.
