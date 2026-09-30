@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/widgets/app_bottom_sheet.dart';
import 'package:cupola/core/widgets/library_detail_actions.dart';
import 'package:cupola/core/widgets/media_detail_value_row.dart';
import 'package:cupola/core/widgets/media_search_popup_menu.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import 'catalog.dart';

void _noop() {}
void _noopBool(bool _) {}

/// The band with every capability a Radarr movie page wires.
LibraryDetailActions _radarr(
  MediaStatusInfo status, {
  bool isMonitored = true,
  bool isBusy = false,
  bool isConfirmed = false,
}) => LibraryDetailActions(
  service: ServiceKey.radarr,
  status: status,
  mediaTitle: 'Nosferatu',
  isMonitored: isMonitored,
  isBusy: isBusy,
  isConfirmed: isConfirmed,
  onSearch: _noop,
  onInteractiveSearch: _noop,
  onImport: _noop,
  onOpenQueue: _noop,
  onMonitoredChanged: _noopBool,
  onDelete: _noop,
);

/// The body of `showMediaProfileSelector`, which opens on the root navigator
/// and so cannot be drawn inside a bounded scene: the same [AppBottomSheet]
/// header and [MediaValueOptionRow]s that `showMediaValueSheet` builds.
Widget _profileSheet() {
  const profiles = ['Any', 'SD', 'HD-720p', 'HD-1080p', 'Ultra-HD'];
  return AppBottomSheet(
    title: 'Quality profile',
    subtitle: 'Currently HD-1080p',
    icon: Icons.tune_rounded,
    accent: ServiceKey.radarr.accent,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final name in profiles)
          MediaValueOptionRow(
            label: name,
            isSelected: name == 'HD-1080p',
            accent: ServiceKey.radarr.accent,
            onTap: _noop,
          ),
      ],
    ),
  );
}

/// Opens the [PopupMenuButton] inside [child] once it has laid out, on a
/// navigator local to the scene so the menu lands inside the scene's box.
class _OpenMenu extends StatelessWidget {
  const _OpenMenu({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Navigator(
    onGenerateRoute: (_) => PageRouteBuilder<void>(
      pageBuilder: (context, _, _) => _Opener(child: child),
    ),
  );
}

class _Opener extends StatefulWidget {
  const _Opener({required this.child});

  final Widget child;

  @override
  State<_Opener> createState() => _OpenerState();
}

class _OpenerState extends State<_Opener> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      void visit(Element element) {
        if (element is StatefulElement &&
            element.state is PopupMenuButtonState) {
          (element.state as PopupMenuButtonState).showButtonMenu();
          return;
        }
        element.visitChildren(visit);
      }

      if (mounted) (context as Element).visitChildren(visit);
    });
  }

  @override
  Widget build(BuildContext context) =>
      Align(alignment: Alignment.topLeft, child: widget.child);
}

void main() {
  const phone = 358.0; // A 390pt phone less the spine's 16pt gutters.

  catalogCard(
    'LibraryDetailActions',
    width: 776,
    scenes: [
      CatalogScene(
        'Missing · Automatic search promoted as the ink button; '
        'Interactive search takes the one visible disc; the rest overflow',
        (_) => _radarr(
          const MediaStatusInfo(availability: MediaAvailability.missing),
        ),
        width: phone,
      ),
      CatalogScene(
        'Upgradable · Interactive search promoted, Automatic search on the '
        'disc',
        (_) => _radarr(
          const MediaStatusInfo(availability: MediaAvailability.upgradable),
        ),
        width: phone,
      ),
      CatalogScene(
        'Missing and unmonitored · Monitor is the verb; the search is moot '
        'until then',
        (_) => _radarr(
          const MediaStatusInfo(
            availability: MediaAvailability.missing,
            unmonitored: true,
          ),
          isMonitored: false,
        ),
        width: phone,
      ),
      CatalogScene(
        'Import blocked · Finish import, the only rung that promotes Manual '
        'import',
        (_) => _radarr(
          const MediaStatusInfo(pipeline: MediaPipeline.importBlocked),
        ),
        width: phone,
      ),
      CatalogScene(
        'Downloading · every in-flight rung promotes Open queue; the '
        'sentence carries the percentage',
        (_) => _radarr(
          const MediaStatusInfo(
            pipeline: MediaPipeline.downloading,
            progress: 0.42,
          ),
        ),
        width: phone,
      ),
      CatalogScene(
        'Failed · Interactive search, with what the service reported quoted '
        'in the sentence',
        (_) => _radarr(
          const MediaStatusInfo(
            pipeline: MediaPipeline.failed,
            detail: 'Download client reported the release as corrupt',
          ),
        ),
        width: phone,
      ),
      CatalogScene(
        'Available · no primary; both slots go to labelled secondaries, no '
        'glyph',
        (_) => _radarr(
          const MediaStatusInfo(availability: MediaAvailability.available),
        ),
        width: phone,
      ),
      CatalogScene(
        'Busy · the glyph spins and nothing in the band takes a tap',
        (_) => _radarr(
          const MediaStatusInfo(availability: MediaAvailability.missing),
          isBusy: true,
        ),
        width: phone,
      ),
      CatalogScene(
        'Confirmed · the success check holds in place of the glyph',
        (_) => _radarr(
          const MediaStatusInfo(availability: MediaAvailability.missing),
          isConfirmed: true,
        ),
        width: phone,
      ),
      CatalogScene(
        'Sonarr, partial · partialSummary replaces the sentence',
        (_) => const LibraryDetailActions(
          service: ServiceKey.sonarr,
          status: MediaStatusInfo(availability: MediaAvailability.partial),
          mediaTitle: 'Sherlock Jr.',
          isMonitored: true,
          partialSummary: '41 of 48 episodes on disk.',
          onSearch: _noop,
          onInteractiveSearch: _noop,
          onMonitoredChanged: _noopBool,
          onDelete: _noop,
        ),
        width: phone,
      ),
      CatalogScene(
        'Lidarr, not released · consequenceOverride names the date; no '
        'search is promoted',
        (_) => const LibraryDetailActions(
          service: ServiceKey.lidarr,
          status: MediaStatusInfo(availability: MediaAvailability.unavailable),
          mediaTitle: 'Metropolis',
          isMonitored: true,
          consequenceOverride: '10 January 1927',
          onSearch: _noop,
          onMonitoredChanged: _noopBool,
          onDelete: _noop,
        ),
        width: phone,
      ),
      CatalogScene(
        'Only Delete wired · the sentence takes the wide slot beside the '
        'overflow',
        (_) => const LibraryDetailActions(
          service: ServiceKey.radarr,
          status: MediaStatusInfo(availability: MediaAvailability.available),
          mediaTitle: 'Nosferatu',
          onDelete: _noop,
        ),
        width: phone,
      ),
      CatalogScene(
        'Nothing wired · a missing callback withholds its action, so only '
        'the sentence remains',
        (_) => const LibraryDetailActions(
          service: ServiceKey.radarr,
          status: MediaStatusInfo(availability: MediaAvailability.missing),
          mediaTitle: 'Nosferatu',
        ),
        width: phone,
      ),
      CatalogScene(
        'Quality profile sheet body (showMediaProfileSelector) · the selected '
        'row in the primary ink (the page accent is the lamp)',
        (_) => _profileSheet(),
        width: 390,
      ),
      CatalogScene(
        'MediaSearchPopupMenu · idle, then searching (a 20pt, 2pt spinner)',
        (_) => Row(
          children: [
            MediaSearchPopupMenu(
              onAutoSearch: _noop,
              onInteractiveSearch: _noop,
            ),
            const SizedBox(width: 24),
            MediaSearchPopupMenu(
              onAutoSearch: _noop,
              onInteractiveSearch: _noop,
              isLoading: true,
            ),
          ],
        ),
      ),
      CatalogScene(
        'MediaSearchPopupMenu · open, the season and album search menu',
        (_) => const _OpenMenu(
          child: MediaSearchPopupMenu(
            onAutoSearch: _noop,
            onInteractiveSearch: _noop,
          ),
        ),
        width: 280,
        height: 150,
      ),
      CatalogScene(
        'Missing on the desktop · the same band on the compact density, '
        'across the 728pt main track',
        (_) => _radarr(
          const MediaStatusInfo(availability: MediaAvailability.missing),
        ),
        width: 728,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'Available on the desktop · the labelled pair shares the width',
        (_) => _radarr(
          const MediaStatusInfo(availability: MediaAvailability.available),
        ),
        width: 728,
        platform: CatalogPlatform.desktop,
      ),
    ],
  );
}
