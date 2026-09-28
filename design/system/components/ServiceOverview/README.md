# ServiceOverview

The furniture every service's Overview tab is built from: identity line, section frame, two-line row, empty note and skeleton, all derived from one `ServiceKey`.

Hand-written from `lib/core/widgets/service_overview.dart`, composed as `lib/features/movies/presentation/radarr_overview_screen.dart` composes it (sixteen Overviews build on it). Titles, hosts, sizes and figures are illustrative (the one loaded poster in Recently added is *Nosferatu*, 1922; the tiles after it show `MediaPosterCard`'s no-poster plate); section names, subtitles, links and empty copy are Radarr's real strings. The dashed outlines and region tags are specimen annotations, not UI.

- **Page order** (Radarr): `ServiceOverviewIdentity` → `ServiceKpiPeek` (see that card; composed by the screen, not this file) → Coming up → Needs attention → Recently added → History. One scroll view. On the phone the app bar and tab bar float above as glass bands and the page reserves `56 + 44` at the top; in a desktop window the lit `ServiceTabBar.header` replaces both.
- **Identity**: padding `space-sm` top, `space-lg` sides, `space-md` bottom; a wrap with `space-sm` × `space-xs` gaps. Facts `host · version` at 12px/500 in `on-surface-variant`; a figure the service did not give reads `—` (version is `—` whenever the probe did not answer — never the `v3 API` fallback). Then the status word: 13px glyph, `space-xs`, 12px/600, both in the connection tone walked against `surface` (`cloud_done` Answering, `cloud_off` Unreachable, `cloud_sync` Checking). A lens chip (padding 2 × `space-sm`, `surface-container`, 1px `outline-variant`, `radius-sm`, 11px/600 in the accent walked for `surface`) appears only when the service has more than one connection.
- **Section**: `SectionHeader` (`title-large` 600, subtitle `body-small` tabular in `on-surface-variant`), `space-sm`, body inset `space-lg`, then `space-lg` of air. `.bleed` drops the inset so a poster rail runs to the window edge. Radarr's rail tile is 96 wide: a `MediaPosterCard` in a 96 × 138 box (`radius-md`, `level-2`, `BoxFit.cover`; no poster → `plate-surface` with `movie_outlined` 48 in `plate-dim-ink`), `space-xs`, title `label-small` 600 `on-surface`, year `label-small` `on-surface-variant`. A section with a destination tab draws `Calendar →` in `label-medium` 600, the accent walked against `surface`, one line; the whole header is the tap target, at least 44 tall, and switches branch with `goBranch`.
- **Row**: leading mark, `space-sm`, title in `data` (13/500) — `on-surface`, or the row's tone when it states one — then 2px and a detail at 11px/500 `on-surface-variant`; optional trailing figure 11px/600, capped at 132px and ellipsised. Rows are `space-md` apart. Leading marks in use: a 58px day column (11px/600), an 18px tone glyph, an 8px tone dot (5px down). Tones walk against `surface-container-low`.
- **Empty**: `AppEmptyState.inline` — a row, not a well: nothing failed. **Skeleton**: `rows` × (180 × 14 then 120 × 10 bars, `radius-xs`, `surface-container-high` shimmering to `surface-container`), `space-md` apart. A subtitle count reads `—` while loading or failed.
- **Tone**: stalled and import failed are faults (`warning`); films below cutoff are backlog (neutral). Grabbed is neutral; imported is `success`.

Nothing takes a colour: callers pass the `ServiceKey`, so the raw accent can never become text. Each row speaks one sentence with `·` turned into commas and silences its parts; the identity speaks `Radarr, host, version, Answering[, lens]`; a linked header speaks its title and subtitle with the hint *opens the Radarr Calendar tab*. Sections load and fail independently — a failed one falls back in its own slot (FaultBand / AppErrorState) and never takes the page.

## Do / don't

- Do pass the `ServiceKey` and let the furniture resolve every ink; never hand it a colour.
- Do let a section fail in its own slot; a retry re-asks every source that section depends on.
- Don't count inside a capped or paged response and state it as a total; a figure that did not arrive reads `—`, never 0.
- Don't paint the backlog amber: cutoff unmet and wanted are neutral.
