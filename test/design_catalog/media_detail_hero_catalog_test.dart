@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/ambient_background.dart';
import 'package:cupola/core/widgets/media_detail_figure_plate.dart';
import 'package:cupola/core/widgets/media_detail_header_metrics.dart';
import 'package:cupola/core/widgets/media_detail_poster_row.dart';
import 'package:cupola/core/widgets/media_detail_view.dart';
import 'package:cupola/core/widgets/media_poster_card.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/core/widgets/tag_chip.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import 'catalog.dart';

/// The collapse range at the default reading size: 236 − 52.
const _range =
    MediaDetailHeaderMetrics.baseExpandedHeight -
    MediaDetailHeaderMetrics.baseCollapsedHeight;

/// The hero as a detail page hosts it: the lit room, a transparent Material,
/// the pinned header sliver, and a stretch of body under it so the page can be
/// scrolled to [offset].
Widget _page({
  required Color accent,
  required Widget posterRow,
  required String title,
  IconData fallbackIcon = Icons.movie_outlined,
  String? backdropUrl,
  String? posterUrl,
  double offset = 0,
  double topInset = 0,
}) => Builder(
  builder: (context) {
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(padding: EdgeInsets.only(top: topInset)),
      child: AmbientBackground(
        accent: accent,
        child: Material(
          type: MaterialType.transparency,
          child: CustomScrollView(
            controller: ScrollController(initialScrollOffset: offset),
            slivers: [
              Builder(
                builder: (context) => mediaDetailHeaderSliver(
                  context,
                  backdropUrl: backdropUrl,
                  posterUrl: posterUrl,
                  posterRow: posterRow,
                  title: title,
                  accent: accent,
                  heroFallbackIcon: fallbackIcon,
                ),
              ),
              const SliverToBoxAdapter(child: _Body()),
            ],
          ),
        ),
      ),
    );
  },
);

/// A representative first region, so the collapsed states have content
/// scrolling under the bar.
class _Body extends StatelessWidget {
  const _Body();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < 6; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Count Orlok, a vampire of the Carpathians, takes an interest '
                'in a new house and in the wife of the estate agent who sold '
                'it to him.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
        ],
      ),
    );
  }
}

Widget _radarrRow({
  String tag = 'nosferatu',
  String title = 'Nosferatu',
  MediaStatusInfo status = const MediaStatusInfo(
    availability: MediaAvailability.missing,
  ),
  String chip = 'No file',
  List<String> metadata = const ['1922', '1h 34m'],
}) => MediaDetailPosterRow(
  statusBadge: StatusBadge.animated(info: status),
  title: title,
  metadataItems: metadata,
  tags: [TagChip(text: chip, color: ServiceKey.radarr.accent)],
  posterCard: MediaPosterCard(heroTag: tag, imageUrl: CatalogArt.poster),
);

void main() {
  catalogCard(
    'MediaDetailHero',
    width: 1008,
    scenes: [
      CatalogScene(
        'Expanded, t = 0 · Radarr, backdrop and poster · the room light sits '
        'top-right on the art; the scrim carries the copy',
        (_) => _page(
          accent: ServiceKey.radarr.accent,
          backdropUrl: CatalogArt.backdrop,
          title: 'Nosferatu',
          posterRow: _radarrRow(tag: 'a'),
        ),
        width: 390,
        height: 320,
      ),
      CatalogScene(
        'Expanded under a 47pt top safe area · the stage grows by the inset, '
        'the back button rides below it',
        (_) => _page(
          accent: ServiceKey.radarr.accent,
          backdropUrl: CatalogArt.backdrop,
          title: 'Nosferatu',
          topInset: 47,
          posterRow: _radarrRow(
            tag: 'b',
            status: const MediaStatusInfo(
              pipeline: MediaPipeline.downloading,
              progress: 0.42,
            ),
            chip: 'No file',
          ),
        ),
        width: 390,
        height: 360,
      ),
      CatalogScene(
        'Mid-collapse, t = 0.5 · the art parallaxes at 0.35, the scrim '
        'deepens, the poster scales down and slides under the body',
        (_) => _page(
          accent: ServiceKey.radarr.accent,
          backdropUrl: CatalogArt.backdrop,
          title: 'Nosferatu',
          offset: _range * 0.5,
          posterRow: _radarrRow(tag: 'c'),
        ),
        width: 390,
        height: 320,
      ),
      CatalogScene(
        'Collapsed, t = 1 · the 52pt glass bar: centred title, the back '
        'glyph with its plate released',
        (_) => _page(
          accent: ServiceKey.radarr.accent,
          backdropUrl: CatalogArt.backdrop,
          title: 'Nosferatu',
          offset: _range + 40,
          posterRow: _radarrRow(tag: 'd'),
        ),
        width: 390,
        height: 200,
      ),
      CatalogScene(
        'Long title · two lines, then an ellipsis; metadata holds one line',
        (_) => _page(
          accent: ServiceKey.radarr.accent,
          backdropUrl: CatalogArt.backdrop,
          title: 'The Cabinet of Dr. Caligari',
          posterRow: _radarrRow(
            tag: 'e',
            title:
                'The Cabinet of Dr. Caligari: A Restoration of the Original '
                'Tinted Print',
            status: const MediaStatusInfo(
              availability: MediaAvailability.available,
            ),
            chip: '1 file',
            metadata: const ['1920', '1h 16m', 'Not Rated', 'Expressionism'],
          ),
        ),
        width: 390,
        height: 320,
      ),
      CatalogScene(
        'No backdrop, with a poster · Seerr · the fallback stage shows the '
        'poster at 22% instead of a glyph',
        (_) => _page(
          accent: ServiceKey.seerr.accent,
          posterUrl: CatalogArt.poster,
          title: 'Metropolis',
          posterRow: MediaDetailPosterRow(
            statusBadge: StatusBadge.animated(
              info: const MediaStatusInfo(
                labelOverride: 'Waiting for approval',
                toneOverride: StatusTone.info,
              ),
            ),
            title: 'Metropolis',
            metadataItems: const ['1927', '2h 33m'],
            tags: [TagChip(text: 'Requested', color: ServiceKey.seerr.accent)],
            posterCard: const MediaPosterCard(
              heroTag: 'f',
              imageUrl: CatalogArt.poster,
            ),
          ),
        ),
        width: 390,
        height: 320,
      ),
      CatalogScene(
        'No backdrop, no poster · Bazarr, MediaDetailFigurePlate in the '
        'poster slot · the fallback stage draws the page glyph at 22%',
        (_) => _page(
          accent: ServiceKey.bazarr.accent,
          fallbackIcon: Icons.subtitles_outlined,
          title: 'Nosferatu',
          posterRow: MediaDetailPosterRow(
            statusBadge: StatusBadge.animated(
              info: const MediaStatusInfo(
                availability: MediaAvailability.available,
                labelOverride: 'Monitored',
              ),
            ),
            title: 'Nosferatu',
            metadataItems: const ['1922'],
            tags: [
              TagChip(text: '12 missing', color: ServiceKey.bazarr.accent),
            ],
            posterCard: MediaDetailFigurePlate(
              value: '12',
              label: 'Missing',
              accent: ServiceKey.bazarr.accent,
            ),
          ),
        ),
        width: 390,
        height: 320,
      ),
      CatalogScene(
        'MediaDetailPosterRow.circular · Lidarr artist · the 92 × 92 lead, '
        'same summary beside it',
        (_) => _page(
          accent: ServiceKey.lidarr.accent,
          backdropUrl: CatalogArt.backdrop,
          fallbackIcon: Icons.person_outline,
          title: 'Max Schreck',
          posterRow: MediaDetailPosterRow.circular(
            statusBadge: StatusBadge.animated(
              info: const MediaStatusInfo(
                availability: MediaAvailability.available,
              ),
            ),
            title: 'Max Schreck',
            metadataItems: const ['4 albums', '38 tracks'],
            tags: [
              TagChip(text: '38 of 38 tracks', color: ServiceKey.lidarr.accent),
            ],
            posterCard: const MediaPosterCard.circular(
              heroTag: 'g',
              imageUrl: CatalogArt.poster,
              fallbackIcon: Icons.person_outline,
            ),
          ),
        ),
        width: 390,
        height: 320,
      ),
      CatalogScene(
        'MediaDetailLoadingView · the same header geometry with a shimmer '
        'poster, badge and title, so the swap to data moves nothing',
        (_) => MediaDetailLoadingView(accent: ServiceKey.radarr.accent),
        width: 390,
        height: 420,
      ),
      CatalogScene(
        'Expanded on the desktop · the stage runs the route width; the '
        'poster row keeps its 16pt inset',
        (_) => _page(
          accent: ServiceKey.radarr.accent,
          backdropUrl: CatalogArt.backdrop,
          title: 'Nosferatu',
          posterRow: _radarrRow(
            tag: 'h',
            status: const MediaStatusInfo(
              availability: MediaAvailability.available,
            ),
            chip: '1 file',
          ),
        ),
        width: 960,
        height: 300,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'Collapsed on the desktop · the glass bar over the body',
        (_) => _page(
          accent: ServiceKey.radarr.accent,
          backdropUrl: CatalogArt.backdrop,
          title: 'Nosferatu',
          offset: _range + 40,
          posterRow: _radarrRow(tag: 'i'),
        ),
        width: 960,
        height: 160,
        platform: CatalogPlatform.desktop,
      ),
    ],
  );
}
