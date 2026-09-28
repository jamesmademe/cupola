@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/widgets/ambient_background.dart';
import 'package:cupola/core/widgets/ambient_scaffold.dart';
import 'package:cupola/core/widgets/download_queue_tile.dart';
import 'package:cupola/core/widgets/glass_app_bar.dart';
import 'package:cupola/core/widgets/section_header.dart';
import 'package:cupola/core/widgets/service_record_row.dart';
import 'package:cupola/core/widgets/service_tab_bar.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/services/presentation/service_home_screen.dart';
import 'package:cupola/features/services/presentation/service_tab_scaffold.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../test_helpers/settings_scope.dart';
import 'catalog.dart';

/// Room the service band and the tab bar take above a tab's content — the
/// router's `_serviceTabTopPadding`.
const _tabTop = kToolbarHeight + ServiceTabBar.height;

/// A phone's top safe area, so the bands sit where they do on a device.
Widget _phone(Widget child) => Builder(
  builder: (context) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(padding: const EdgeInsets.only(top: 47)),
    child: child,
  ),
);

/// A Radarr tab body, scrolled part-way so artwork runs under the glass.
Widget _radarrBody({double offset = 72}) => SafeArea(
  child: ListView(
    controller: ScrollController(initialScrollOffset: offset),
    padding: const EdgeInsets.only(top: _tabTop, bottom: AppSpacing.xl),
    children: [
      const SectionHeader(title: 'Recently added'),
      SizedBox(
        height: 165,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          itemCount: 5,
          separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
          itemBuilder: (_, _) => ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image(
              image: CatalogArt.posterImage,
              width: 110,
              height: 165,
              fit: BoxFit.cover,
            ),
          ),
        ),
      ),
      const SizedBox(height: AppSpacing.lg),
      const SectionHeader(title: 'Queue'),
      for (final (name, progress) in const [
        ('Nosferatu.1922.1080p.BluRay.x264-GROUP', 0.63),
        ('Metropolis.1927.2160p.Restored.BluRay.x265-GROUP', 0.18),
        ('Sherlock.Jr.1924.720p.BluRay.x264-GROUP', 0.91),
      ])
        DownloadQueueTile(
          title: name,
          subtitle: 'Downloading · 12m left',
          progress: progress,
          percentage: (progress * 100).round(),
          accent: ServiceKey.radarr.accent,
          statusLabel: 'Downloading',
          statusTone: StatusTone.info,
        ),
    ],
  ),
);

/// Radarr's service home as the router builds it: the band over the shell,
/// the tab bar over the branch, the lit room under the branch's body.
Widget _radarrHome({double offset = 72}) => ServiceHomeScreen(
  service: ServiceKey.radarr,
  child: ServiceTabScaffold(
    service: ServiceKey.radarr,
    tab: tabsFor(ServiceKey.radarr)!.first,
    child: AmbientScaffold(
      accent: ServiceKey.radarr.accent,
      body: _radarrBody(offset: offset),
    ),
  ),
);

Widget _truenasHub() => AmbientScaffold(
  accent: ServiceKey.truenas.accent,
  appBar: const GlassAppBar(title: Text('TrueNAS')),
  body: ListView(
    padding: const EdgeInsets.all(AppSpacing.lg),
    children: const [
      ServiceRecordRow(
        icon: Icons.storage_rounded,
        tone: StatusTone.success,
        title: 'tank',
        detail: 'RAIDZ2 · 6 disks · 41% used',
        trailing: 'Online',
        semanticLabel: 'tank, Online, RAIDZ2, 6 disks, 41% used',
      ),
      SizedBox(height: AppSpacing.sm),
      ServiceRecordRow(
        icon: Icons.warning_amber_rounded,
        tone: StatusTone.warning,
        title: 'archive',
        detail: 'Mirror · 2 disks · one disk reporting errors',
        trailing: 'Degraded',
        semanticLabel:
            'archive, Degraded, Mirror, 2 disks, one disk reporting '
            'errors',
      ),
    ],
  ),
);

Widget _room(Color? accent, String label) => SizedBox(
  width: 170,
  height: 300,
  child: AmbientBackground(
    accent: accent,
    child: Builder(
      builder: (context) => Center(
        child: Text(label, style: Theme.of(context).textTheme.labelMedium),
      ),
    ),
  ),
);

void main() {
  catalogCard(
    'AmbientScaffold',
    width: 1328,
    overrides: () async => [
      ...await settingsScopeOverrides(
        configured: const [ServiceKey.radarr, ServiceKey.truenas],
      ),
      initialActiveInstancesProvider.overrideWithValue(const {}),
    ],
    scenes: [
      CatalogScene(
        'Radarr service home on touch · two GlassSurface bands (the 56pt '
        'service band, the 44pt tab bar) over the lit room, content mid-scroll',
        (_) => _phone(_radarrHome()),
        width: 390,
        height: 640,
      ),
      CatalogScene(
        'AmbientScaffold(appBar: GlassAppBar) · the TrueNAS hub at rest over '
        'the bare room',
        (_) => _phone(_truenasHub()),
        width: 390,
        height: 420,
      ),
      CatalogScene(
        'AmbientBackground alone · no accent (primary), Radarr, Sonarr, '
        'Jellyfin · two radials, top left and bottom right, same strength',
        (_) => Wrap(
          spacing: 12,
          children: [
            _room(null, 'primary'),
            _room(ServiceKey.radarr.accent, 'Radarr'),
            _room(ServiceKey.sonarr.accent, 'Sonarr'),
            _room(ServiceKey.jellyfin.accent, 'Jellyfin'),
          ],
        ),
      ),
      CatalogScene(
        'Radarr service home on the desktop · no glass band: '
        'ServiceTabBar.header paints its own lit band; the body sits in the '
        'content well, the room runs the full width',
        (_) => _radarrHome(offset: 0),
        width: 1280,
        height: 560,
        platform: CatalogPlatform.desktop,
      ),
    ],
  );
}
