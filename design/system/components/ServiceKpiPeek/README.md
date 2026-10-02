# ServiceKpiPeek

A horizontal rail of instrument readouts under a service's app bar: glyph, figure, word.

Rendered from `lib/core/widgets/service_kpi_peek.dart` by `test/design_catalog/service_kpi_peek_catalog_test.dart`, with figures shaped like the ones `lib/features/services/presentation/service_kpi_provider.dart` builds.

## Values

- **Rail**: 78 tall at the default reading size, grown by the text share (34pt) of that height up to the 1.6× clamp (`TextScaleMetrics.boxHeight`), and painted under the same clamped scaler so the text never outgrows its box. Padding `AppSpacing.lg` / `AppSpacing.xs` / `AppSpacing.lg` / `AppSpacing.md` (overridable with `padding`), cards `AppSpacing.sm` apart, scrolling horizontally.
- **Card**: at least 92 wide and growing with its figure, `surfaceContainer`, 1px `outlineVariant`, `AppRadius.borderRadiusMd`, `AppElevation.level1`, padding `AppSpacing.md` × `AppSpacing.sm`, content centred vertically.
- **Figure row**: a 14pt glyph, `AppSpacing.xs`, then the figure in `titleMedium` at 600, tabular, 1.1 leading, in `onSurface`. The figure rolls on change (`ReelLine`, `ReelMotion.figure`).
- **Glyph colour**: the primary ink — the service's accent is the lamp, which `ServiceTheme.onTint` resolves to ink against `surfaceContainer`; a figure with a tone takes `statusToneColor(tone, surface: surfaceContainer)` instead, and an unanswered one `onSurfaceVariant`.
- **Label**: 3pt below, the micro role (`AppTheme.chrome`, 11 / 600 / 14, the role's own tracking), in sentence case (*Movies*, *Radarr · Did not answer*), `onSurfaceVariant`, one line, ellipsised. A `note`, when there is one, takes the label's place.

## Tones

The rule is the app's tone rule. A backlog figure (Missing, Waiting for approval) is `StatusTone.neutral`; bytes moving or someone watching is `StatusTone.info`; only a fault — a pool past 80%, an active alert, a transcode — is `StatusTone.warning`. A figure with nothing to say carries no tone and is ink.

## States

- **Loading** — four skeleton cards, 100 wide with no shadow: a 44 × 16 and a 64 × 9 shimmer line, 6 apart.
- **Unavailable figure** — `ServiceKpi.unavailable`: the figure is an em dash in `onSurfaceVariant`, the glyph goes `onSurfaceVariant`, and the note replaces the label — the service and the classified reason, *Radarr · Did not answer*, *Radarr · Refused the key*. The rail keeps the same cards, so a reader sees which figure is missing. Never `0`.
- **Narrower token** — a media server's token that may read only part of what the rail counts. The figures it cannot read are unavailable cards with the reason on the first of them: `owner only` (a shared account's Plex, refused who is watching), `admin only` (a household member's Jellyfin, refused the library list). A figure it reads only in part counts and says whose it is in place of its label: `1` · `yours only` (that member's own playback). Never the server's total.
- **Source failed** — one unavailable card replaces the rail: glyph `remove_rounded`, label *Figures*, note the classified reason (`failureLabel`): *Did not answer* only when nothing answered, *Refused the key*, *Timed out*, *Did not complete* otherwise.
- **Not configured** (an error containing `not configured`) or **no figures** — the rail collapses to nothing; the page below answers for it.

## The consumer provides

An `AsyncValue<List<ServiceKpi>>` (label, value, icon, optional tone, optional note) and the service `accent` (the lamp, from `ServiceKey.accent`). Real labels include Movies, Monitored, Missing, Queue; Active, Download, Upload, Seeding, Downloading (a speed card reads the brand book's `↓ 22.4 MB/s` by its south or north glyph beside the rate, and its word names the rate); Streams, Transcodes, Libraries; Requests, Waiting for approval, Processing, Available; Pools, Used, Alerts.

## Semantics

Each card is one container node speaking `ServiceKpi.semanticLabel` — *Movies: 1,284*, *Queue: at least 200* for a floor, or *Movies: unavailable, Radarr · Did not answer*; the glyph, figure and eyebrow are excluded.

## Do / don't

- Do state an unanswered figure as a dash.
- Don't count inside a capped or paged response and present the result as a total. A queue walk that stopped on a full page with no total reads a floor, `200+`.
- Don't tint a backlog figure (Missing) with a fault tone: it is neutral.
