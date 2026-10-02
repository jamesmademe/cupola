@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/models/service_kpi.dart';
import 'package:cupola/core/widgets/service_kpi_peek.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import 'catalog.dart';

/// Radarr's four figures, as `service_kpi_provider.dart` builds them.
const _radarr = [
  ServiceKpi(label: 'Movies', value: '1,284', icon: Icons.movie_rounded),
  ServiceKpi(
    label: 'Monitored',
    value: '1,192',
    icon: Icons.visibility_rounded,
  ),
  ServiceKpi(
    label: 'Missing',
    value: '37',
    icon: Icons.report_gmailerrorred_rounded,
    tone: StatusTone.neutral,
  ),
  ServiceKpi(label: 'Queue', value: '3', icon: Icons.download_rounded),
];

/// Readarr whose queue walk stopped on a full page with no total: the Queue
/// figure is a floor.
const _readarrFloor = [
  ServiceKpi(label: 'Authors', value: '86', icon: Icons.person_rounded),
  ServiceKpi(label: 'Books', value: '1,240', icon: Icons.menu_book_rounded),
  ServiceKpi(
    label: 'Missing',
    value: '12',
    icon: Icons.report_gmailerrorred_rounded,
    tone: StatusTone.neutral,
  ),
  ServiceKpi(label: 'Queue', value: '200+', icon: Icons.download_rounded),
];

/// The same rail when Radarr did not answer: the same four cards, dashes.
const _radarrSilent = [
  ServiceKpi.unavailable(
    label: 'Movies',
    icon: Icons.movie_rounded,
    note: 'Radarr · Did not answer',
  ),
  ServiceKpi.unavailable(label: 'Monitored', icon: Icons.visibility_rounded),
  ServiceKpi.unavailable(
    label: 'Missing',
    icon: Icons.report_gmailerrorred_rounded,
  ),
  ServiceKpi.unavailable(label: 'Queue', icon: Icons.download_rounded),
];

/// Jellyfin on a household member's token: its own playback counts and says
/// so, and the library list it is refused reads a dash.
const _jellyfinMember = [
  ServiceKpi(
    label: 'Streams',
    value: '1',
    icon: Icons.play_circle_outline_rounded,
    tone: StatusTone.info,
    note: 'yours only',
  ),
  ServiceKpi(label: 'Transcodes', value: '0', icon: Icons.memory_rounded),
  ServiceKpi.unavailable(
    label: 'Libraries',
    icon: Icons.video_library_outlined,
    note: 'admin only',
  ),
];

/// Plex on a shared account's token: who is watching is the owner's to see.
const _plexShared = [
  ServiceKpi.unavailable(
    label: 'Streams',
    icon: Icons.play_circle_outline_rounded,
    note: 'owner only',
  ),
  ServiceKpi.unavailable(label: 'Transcodes', icon: Icons.memory_rounded),
  ServiceKpi(
    label: 'Libraries',
    value: '4',
    icon: Icons.video_library_outlined,
  ),
];

/// qBittorrent: bytes moving is activity (info), not a fault.
const _qbittorrent = [
  ServiceKpi(label: 'Active', value: '4', icon: Icons.bolt_rounded),
  ServiceKpi(
    label: 'Download',
    value: '12.4 MB/s',
    icon: Icons.south_rounded,
    tone: StatusTone.info,
  ),
  ServiceKpi(label: 'Upload', value: '860 KB/s', icon: Icons.north_rounded),
  ServiceKpi(label: 'Seeding', value: '41', icon: Icons.upload_rounded),
  ServiceKpi(label: 'Downloading', value: '2', icon: Icons.download_rounded),
];

/// TrueNAS: a pool past 80% and an active alert are faults (warning).
const _truenas = [
  ServiceKpi(label: 'Pools', value: '2', icon: Icons.dns_rounded),
  ServiceKpi(
    label: 'Used',
    value: '86%',
    icon: Icons.pie_chart_rounded,
    tone: StatusTone.warning,
  ),
  ServiceKpi(
    label: 'Alerts',
    value: '1',
    icon: Icons.warning_amber_rounded,
    tone: StatusTone.warning,
  ),
];

CatalogScene _scene(
  String caption,
  AsyncValue<List<ServiceKpi>> kpis,
  ServiceKey service, {
  double width = 390,
  CatalogPlatform platform = CatalogPlatform.phone,
}) => CatalogScene(
  caption,
  (_) => ServiceKpiPeek(kpis: kpis, accent: service.accent),
  width: width,
  platform: platform,
);

void main() {
  catalogCard(
    'ServiceKpiPeek',
    width: 720,
    scenes: [
      _scene(
        'Radarr, answered · glyphs in the primary ink; Missing is backlog, '
        'neutral, never amber',
        const AsyncValue.data(_radarr),
        ServiceKey.radarr,
      ),
      _scene(
        'qBittorrent · the speed pair reads ↓ 12.4 MB/s ↑ 860 KB/s, Download in '
        'the info tone while bytes move; the rail '
        'scrolls past the edge',
        const AsyncValue.data(_qbittorrent),
        ServiceKey.qbittorrent,
      ),
      _scene(
        'TrueNAS · a pool past 80% and an active alert take the fault tone',
        const AsyncValue.data(_truenas),
        ServiceKey.truenas,
      ),
      _scene(
        'Readarr, a queue walk cut short · the Queue figure is a floor, 200+, '
        'spoken "at least 200"',
        const AsyncValue.data(_readarrFloor),
        ServiceKey.readarr,
      ),
      _scene(
        'ServiceKpi.unavailable · Radarr did not answer · the same four cards, '
        'an em dash in the secondary ink, the note in place of the label',
        const AsyncValue.data(_radarrSilent),
        ServiceKey.radarr,
      ),
      _scene(
        'A narrower token, Jellyfin · a household member\'s own playback says '
        'yours only in place of its label; the library list it is refused '
        'reads a dash, admin only',
        const AsyncValue.data(_jellyfinMember),
        ServiceKey.jellyfin,
      ),
      _scene(
        'A narrower token, Plex · a shared account is refused who is '
        'watching: owner only on the first card it empties, the libraries '
        'still count',
        const AsyncValue.data(_plexShared),
        ServiceKey.plex,
      ),
      _scene(
        'Source failed · one card replaces the rail; a failure nobody can '
        'attribute reads Did not complete, never Did not answer',
        AsyncValue.error(Exception('timeout'), StackTrace.empty),
        ServiceKey.sonarr,
      ),
      _scene(
        'Loading · four skeleton cards, 100 wide, no shadow',
        const AsyncValue.loading(),
        ServiceKey.lidarr,
      ),
      CatalogScene(
        'Not configured, or no figures · the rail collapses to nothing '
        '(the scene is the empty box)',
        (_) => ServiceKpiPeek(
          kpis: AsyncValue.error(
            Exception('Radarr not configured'),
            StackTrace.empty,
          ),
          accent: ServiceKey.radarr.accent,
        ),
        width: 390,
      ),
      CatalogScene(
        'At 2× reading size · the rail grows with the text, clamped at 1.6×',
        (_) => ServiceKpiPeek(
          kpis: const AsyncValue.data(_radarr),
          accent: ServiceKey.radarr.accent,
        ),
        width: 390,
        textScale: catalogTextScale,
      ),
      CatalogScene(
        'At 2× reading size · the cards that read a dash and a note '
        '(Radarr silent, Jellyfin on a member\'s token)',
        (_) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ServiceKpiPeek(
              kpis: const AsyncValue.data(_radarrSilent),
              accent: ServiceKey.radarr.accent,
            ),
            ServiceKpiPeek(
              kpis: const AsyncValue.data(_jellyfinMember),
              accent: ServiceKey.jellyfin.accent,
            ),
          ],
        ),
        width: 390,
        textScale: catalogTextScale,
      ),
      _scene(
        'On a desktop window · the same rail, wide enough for every card',
        const AsyncValue.data(_radarr),
        ServiceKey.radarr,
        width: 672,
        platform: CatalogPlatform.desktop,
      ),
    ],
  );
}
