# ServiceKpiPeek

A service room's readout under its status line: one hero figure, then a rail of tiles, each a figure over its word.

Rendered from `lib/core/widgets/service_kpi_peek.dart` by `test/design_catalog/service_kpi_peek_catalog_test.dart`, with figures shaped like the ones `lib/features/services/presentation/service_kpi_provider.dart` builds.

## Values

- **Hero** (the room's one readout: `412 movies`): the figure a download client leads with is its download rate, every other service's its first figure. The figure in `figure-hero` (Bricolage 44, tabular) in the ink, an em dash in the secondary ink; beside it on its foot what it counts in the section role (Bricolage 21) in the secondary ink, a noun in lower case (*movies*, *download*), and one of it is one (*1 stream*, *1 library*); padding `space-lg` sides, `space-sm` top, `space-md` bottom; one node, the figure's sentence. The rest of the figures are the rail.
- **Rail**: 94 tall at the default reading size, grown by the text share (41pt) of that height up to the 1.6× clamp (`TextScaleMetrics.boxHeight`), and painted under the same clamped scaler so the text never outgrows its box. Padding `AppSpacing.lg` / `AppSpacing.xs` / `AppSpacing.lg` / `AppSpacing.md` (overridable with `padding`), cards `AppSpacing.sm` apart, scrolling horizontally.
- **Tile**: at least 104 wide and growing with its figure, `room.slab`, 1px `line-hair`, `radius-door` (20), padding 16 sides, 14 top, 12 bottom, content centred vertically, no shadow.
- **Figure**: the `figure` role (Bricolage 24, tabular) in the ink; an em dash in the secondary ink. It rolls on change (`ReelLine`, `ReelMotion.figure`).
- **Label**: 5pt below, the meta role (13) in the secondary ink, sentence case (*Monitored*, *Radarr · Did not answer*), one line, ellipsised; a figure with a tone draws a 7pt dot of it before the label (`statusToneColor`), as a legend does. A `note`, when there is one, takes the label's place.

## Tones

The rule is the app's tone rule. A backlog figure (Missing, Waiting for approval) is `StatusTone.neutral`; bytes moving or someone watching is `StatusTone.info`; only a fault (a pool past 80%, an active alert, a transcode) is `StatusTone.warning`. A figure with nothing to say carries no tone and is ink.

## States

- **Loading**: four skeleton tiles, 104 wide: a 44 × 22 and a 64 × 11 shimmer line, 8 apart. Only the first load: when a poll asks a source again, the rail keeps its last figures until the new ones arrive (`skipLoadingOnReload`), so it neither blinks every tick nor goes blank while a client that stopped answering times out.
- **Unavailable figure** (`ServiceKpi.unavailable`): the figure is an em dash in `onSurfaceVariant`, the glyph goes `onSurfaceVariant`, and the note replaces the label: the service and the classified reason, *Radarr · Did not answer*, *Radarr · Refused the key*. The rail keeps the same cards, so a reader sees which figure is missing. Never `0`. A download client's Queue tab under the stale band (`FaultBand.stale`) draws its rates this way, noted *not updating*: `↓ —` · *not updating*.
- **Narrower token**: a media server's token that may read only part of what the rail counts. The figures it cannot read are unavailable cards with the reason on the first of them: `owner only` (a shared account's Plex, refused who is watching), `admin only` (a household member's Jellyfin, refused the library list). A figure it reads only in part counts and says whose it is in place of its label: `1` · `yours only` (that member's own playback). Never the server's total.
- **Source failed**: one unavailable card replaces the rail: glyph `remove_rounded`, label *Figures*, note the classified reason (`failureLabel`): *Did not answer* only when nothing answered, *Refused the key*, *Timed out*, *Did not complete* otherwise.
- **Not configured** (an error containing `not configured`) or **no figures**, the rail collapses to nothing; the page below answers for it.

## The consumer provides

An `AsyncValue<List<ServiceKpi>>` (label, value, icon, optional tone, optional note) and the `service` (`ServiceKey`): its accent is the lamp (`ServiceKey.accent`), and its word for a refused credential (`key`, `token`, `sign-in`, `refusedCredentialOf`) is the note of a rail it could not read (*Refused the token*). Real labels include Movies, Monitored, Missing, Queue; Active, Download, Upload, Seeding, Downloading (a speed card reads the brand book's `↓ 22.4 MB/s` by its south or north glyph beside the rate, and its word names the rate); Streams, Transcodes, Libraries; Requests, Waiting for approval, Processing, Available; Pools, Used, Alerts.

## Semantics

Each card is one container node speaking `ServiceKpi.semanticLabel`: *Movies: 1,284*, *Queue: at least 200* for a floor, or *Movies: unavailable, Radarr · Did not answer*; the glyph, figure and eyebrow are excluded.

## States in the catalog

Each sheet is drawn in the dark and the light room; the wide rail also on the desktop.

- Radarr answered, qBittorrent (the speed pair, scrolling), TrueNAS (fault tones), Readarr with a floor figure (`200+`).
- `ServiceKpi.unavailable` (Radarr silent), a household member's Jellyfin and a shared Plex account.
- Source failed, loading, and no figures (the rail collapses).
- Text at 200%: the answered rail, and the cards that read a dash and a note.

## Do / don't

- Do state an unanswered figure as a dash.
- Don't count inside a capped or paged response and present the result as a total. A queue walk that stopped on a full page with no total reads a floor, `200+`.
- Don't tint a backlog figure (Missing) with a fault tone: it is neutral.
