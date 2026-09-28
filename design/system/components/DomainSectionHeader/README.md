# DomainSectionHeader

The uppercase kicker that heads a group of services from the same domain — Media, Downloads, Stream, Infrastructure.

Hand-written from `lib/core/widgets/domain_section.dart`; domain labels and membership from `ServiceDomain` / `ServiceKey.domain` in `features/settings/domain/service_key.dart`. The group cards in the preview are labelled placeholders. It currently heads the groups in Settings › Connections.

## Values

- Label: `eyebrow` (11px/600, +1.4px, 1.2 leading), set uppercase, `on-surface-variant`, filling the row; optional trailing widget after it.
- Default padding: `space-md` top, `space-lg` sides, `space-sm` bottom. Settings › Connections passes `space-lg` top, `space-xs` sides, `space-sm` bottom, because its group card already carries the page inset.
- Order is the pipeline: Media (Seerr, Radarr, Sonarr, Lidarr, Bazarr, Readarr) → Downloads (qBittorrent, Transmission, Prowlarr, SABnzbd, NZBGet) → Stream (Jellyfin, Plex) → Infrastructure (TrueNAS, Dockge, Unraid, Nginx Proxy Manager). A domain with nothing to list draws no header.

## Consumer provides

The label and an optional trailing widget (meant for a live count).

## Semantics

One header node whose label is the word as written — *Media*, not the uppercase string, so VoiceOver does not spell it; the trailing widget stays audible as its own node.

## Do / don't

- Do let a domain with nothing to list draw no header.
- Don't reuse it for a region inside a page — that is `SectionHeader` / `panel-header`.
