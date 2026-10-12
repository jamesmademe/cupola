# DomainSectionHeader

The small label that heads a group of services from the same domain: Media, Downloads, Stream, Infrastructure.

Rendered from `lib/core/widgets/domain_section.dart` by `test/design_catalog/domain_section_header_catalog_test.dart`; domain labels and membership come from `ServiceDomain` / `ServiceKey.domain` in `lib/features/settings/domain/service_key.dart`. It currently heads the groups in Settings › Connections.

## Values

- Label: the micro role (`AppTheme.chrome`, 11 / 600 / 14, the role's own tracking), in sentence case (*Media*, never *MEDIA*), `onSurfaceVariant`, `Expanded` across the row; the optional trailing widget sits at the row's end.
- Default padding: `AppSpacing.md` (12) top, `AppSpacing.lg` (16) sides, `AppSpacing.sm` (8) bottom. Settings › Connections passes `AppSpacing.lg` top, `AppSpacing.xs` (4) sides and `AppSpacing.sm` bottom, because its page already carries the 16 inset and the header only needs to sit a hair inside the group card's edge.
- Order is the pipeline, `ServiceDomain` declaration order: Media (Seerr, Radarr, Sonarr, Lidarr, Bazarr, Readarr) → Downloads (qBittorrent, Transmission, Prowlarr, SABnzbd, NZBGet) → Stream (Jellyfin, Plex) → Infrastructure (TrueNAS, Dockge, Unraid, Nginx Proxy Manager).

## Consumer provides

The `label` (the domain's `label`, as written), an optional `trailing` widget (meant for a live count) and, where the host already carries the page inset, its own `padding`.

## Semantics

One header container whose label is the word as drawn (*Media*); the drawn text is excluded beneath it. The trailing widget stays audible as its own node.

## States in the catalog

Each sheet is drawn in the dark and the light room; Settings › Connections also on the desktop.

- The four domains, a header with a trailing widget, Settings › Connections with its padding.
- Text at 200%: the domains, the trailing widget and Connections.

## Do / don't

- Do let a domain with nothing to list draw no header; the host skips the group, header and all.
- Don't reuse it for a region inside a page; that is `SectionHeader` / `AppTheme.panelHeader`.
