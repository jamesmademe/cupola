# ServiceKpiPeek

A horizontal rail of instrument readouts under a service's app bar: glyph, figure, word.

Hand-written from `lib/core/widgets/service_kpi_peek.dart`.

## Values

- Rail: 78 tall (grown with reading size through `TextScaleMetrics`, text scale clamped), padding `space-lg` / `space-xs` / `space-lg` / `space-md`, tiles `space-sm` apart, scrolling horizontally.
- Tile: min 92 wide, `surface-container`, 1px `outline-variant`, `radius-md`, `level-1`, padding `space-md` × `space-sm`, content centred vertically.
- Figure row: a 14px glyph, `space-xs`, then the figure in `title-medium` at 700, tabular, 1.1 leading, in `on-surface`. The figure rolls on change (`ReelLine`, `ReelMotion.figure`).
- Glyph colour: the service accent walked for `surface-container`; a status figure takes `statusToneColor(tone, surface: surface-container)` instead.
- Label: 3 below, `eyebrow` in `on-surface-variant`, uppercased, one line, ellipsized.

## States

- **Loading** — four skeleton tiles, 100 wide with no shadow: a 44 × 16 and a 64 × 9 shimmer line, 6 apart.
- **Unavailable figure** — `ServiceKpi.unavailable`: the figure is an em dash in `on-surface-variant`, the glyph goes `on-surface-variant`, and the label becomes its note. Never `0`.
- **Source failed** — one unavailable tile replaces the rail: label "Figures", note "not answering", glyph `remove`.
- **Not configured** or **no figures** — the rail collapses to nothing.

## Consumer provides

An `AsyncValue<List<ServiceKpi>>` (label, value, icon, optional tone, optional note, semantic label) and the service accent. Real labels include Movies, Monitored, Missing, Queue, Series, Episodes, Streams, Transcodes, Seeding, Requests, Pending.

## Semantics

Each tile is one container node speaking `ServiceKpi.semanticLabel`; the glyph, figure and eyebrow are excluded.

## Do / don't

- Do state an unanswered figure as a dash.
- Don't count inside a capped or paged response and present the result as a total.
- Don't tint a backlog figure (Missing) with a fault tone: it is neutral.
