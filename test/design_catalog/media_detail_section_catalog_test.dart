@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import 'catalog.dart';

const _overview =
    'Thomas Hutter, a young estate agent in the town of Wisborg, travels to '
    'a remote Carpathian castle to close a property sale with the reclusive '
    'Count Orlok. What he finds there convinces him too late that his host '
    'is no ordinary nobleman: Orlok is a vampire, and he has already booked '
    'passage to Wisborg aboard a merchant ship, carrying his coffins and a '
    'plague of rats below decks.';

const _available = MediaStatusInfo(availability: MediaAvailability.available);

const _profiles = [
  MediaDetailValueOption(value: 1, label: 'HD-1080p'),
  MediaDetailValueOption(value: 2, label: 'Ultra-HD'),
];

Widget _profileRow(
  ServiceKey service, {
  bool editable = true,
  int? value = 1,
}) => MediaDetailValueRow<int>(
  label: 'Quality profile',
  value: value,
  options: _profiles,
  onChanged: editable ? (_) async {} : null,
  accent: service.accent,
  hint: 'Changes it on ${service.title}',
);

/// Radarr's page for a movie on disk, region by region, with the side track
/// Radarr declares.
Widget _radarrPage() {
  final accent = ServiceKey.radarr.accent;
  return MediaDetailView(
    accent: accent,
    heroFallbackIcon: Icons.movie_outlined,
    posterUrl: CatalogArt.poster,
    backdropUrl: CatalogArt.backdrop,
    title: 'Nosferatu',
    staggerSections: false,
    posterRow: MediaDetailPosterRow(
      posterCard: const MediaPosterCard(
        heroTag: 'movie_1_0',
        imageUrl: CatalogArt.poster,
      ),
      statusBadge: const StatusBadge(info: _available),
      title: 'Nosferatu',
      metadataItems: const ['1922', '1h 34m', 'Not Rated'],
      tags: [TagChip(text: '1 file', color: accent)],
    ),
    body: MediaDetailBody(
      sideTrack: const {'Overview', 'Details', 'Genres'},
      deck: LibraryDetailActions(
        service: ServiceKey.radarr,
        status: _available,
        mediaTitle: 'Nosferatu',
        isMonitored: true,
        onSearch: () {},
        onInteractiveSearch: () {},
        onMonitoredChanged: (_) {},
        onDelete: () {},
      ),
      operate: [
        MediaDetailSlot.box(
          label: 'File',
          child: FileInfoSection(
            filename: 'Nosferatu.1922.2160p.BluRay.x265.mkv',
            path: '/data/media/movies/Nosferatu (1922)',
            accent: accent,
          ),
        ),
      ],
      synopsis: [
        MediaDetailSlot.box(
          label: 'Overview',
          child: MediaProseSection(text: _overview, accent: accent),
        ),
      ],
      reference: [
        MediaDetailSlot.box(
          label: 'Details',
          child: AppCard.surfaceOutlined(
            child: MediaInfoCard(
              rows: [_profileRow(ServiceKey.radarr)],
              groups: const [
                MediaInfoGroup(title: 'Monitored', child: Text('Yes')),
                MediaInfoGroup(title: 'In cinemas', child: Text('Mar 4, 1922')),
                MediaInfoGroup(title: 'Studio', child: Text('Prana-Film')),
                MediaInfoGroup(title: 'Language', child: Text('German')),
              ],
            ),
          ),
        ),
        MediaDetailSlot.box(
          label: 'Genres',
          child: const MediaChipSection.neutral(
            values: ['Horror', 'Fantasy', 'Drama'],
          ),
        ),
      ],
    ),
  );
}

const _episodes = [
  'The Dying Detective',
  "The Devil's Foot",
  'A Case of Identity',
  'The Yellow Face',
];

/// A Sonarr page: a lazy season list in the manifest, with a count on its
/// label, and real Sonarr tags under Tags.
Widget _sonarrPage() {
  final accent = ServiceKey.sonarr.accent;
  const partial = MediaStatusInfo(availability: MediaAvailability.partial);
  return MediaDetailView(
    accent: accent,
    heroFallbackIcon: Icons.tv_outlined,
    title: 'The Adventures of Sherlock Holmes',
    staggerSections: false,
    posterRow: MediaDetailPosterRow(
      posterCard: const MediaPosterCard(
        heroTag: 'series_2_0',
        fallbackIcon: Icons.tv_outlined,
      ),
      statusBadge: const StatusBadge(info: partial),
      title: 'The Adventures of Sherlock Holmes',
      metadataItems: const ['1921', '3 seasons'],
      tags: [TagChip(text: '41 of 45 episodes', color: accent)],
    ),
    body: MediaDetailBody(
      deck: LibraryDetailActions(
        service: ServiceKey.sonarr,
        status: partial,
        mediaTitle: 'The Adventures of Sherlock Holmes',
        isMonitored: true,
        partialSummary: '41 of 45 episodes',
        onSearch: () {},
        onInteractiveSearch: () {},
        onMonitoredChanged: (_) {},
        onDelete: () {},
      ),
      operate: [
        MediaDetailSlot.lazy(
          label: 'Seasons',
          count: '41 of 45 on disk',
          sliver: MediaChildGroupSliver(
            groups: const [
              MediaChildGroup(
                id: 1,
                shortLabel: 'S1',
                label: 'Season 1',
                status: partial,
                summary: '13 of 15 episodes',
                progress: 13 / 15,
              ),
              MediaChildGroup(
                id: 2,
                shortLabel: 'S2',
                label: 'Season 2',
                status: _available,
                summary: '15 of 15 episodes',
              ),
              MediaChildGroup(
                id: 3,
                shortLabel: 'S3',
                label: 'Season 3',
                status: partial,
                summary: '13 of 15 episodes',
              ),
            ],
            accent: accent,
            childCount: (_) => _episodes.length,
            childBuilder: (context, group, index) => MediaChildTile.numbered(
              ordinal: 'E0${index + 1}',
              ordinalLabel: 'Episode ${index + 1}',
              title: _episodes[index],
              facts: ['Jan ${1 + index * 7}, 1921'],
              status: _available,
              onTap: () {},
            ),
            emptyState: const SizedBox.shrink(),
            pickerLabel: 'All 3 seasons',
            pickerTitle: 'Seasons',
            childNoun: 'episodes',
          ),
        ),
      ],
      synopsis: [
        MediaDetailSlot.box(
          label: 'Overview',
          child: MediaProseSection(
            text:
                'Fifteen two-reel adaptations of the Conan Doyle stories, '
                'with Eille Norwood as Holmes and Hubert Willis as Watson.',
            accent: accent,
          ),
        ),
      ],
      reference: [
        MediaDetailSlot.box(
          label: 'Tags',
          child: MediaChipSection.accented(
            values: const ['silent-era', 'anthology'],
            accent: accent,
          ),
        ),
      ],
    ),
  );
}

/// A phone screen: its own box and `MediaQuery`, so two stand side by side.
Widget _phone(Widget child, {double height = 1060}) => Builder(
  builder: (context) => SizedBox(
    width: 390,
    height: height,
    child: MediaQuery(
      data: MediaQuery.of(context).copyWith(size: Size(390, height)),
      child: ClipRect(child: child),
    ),
  ),
);

Widget _row(List<Widget> children) => Row(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    for (final (index, child) in children.indexed) ...[
      if (index > 0) const SizedBox(width: 24),
      child,
    ],
  ],
);

Widget _labels(BuildContext context) {
  final bazarr = ServiceKey.bazarr.accent;
  Widget column(Widget child) => SizedBox(width: 358, child: child);
  final refresh = IconButton(
    icon: const Icon(Icons.refresh_rounded, size: 20),
    tooltip: 'Refresh from Bazarr',
    onPressed: () {},
  );
  return Wrap(
    spacing: 24,
    runSpacing: 16,
    children: [
      column(
        MediaDetailSectionLabel(
          label: 'Overview',
          accent: ServiceKey.radarr.accent,
        ),
      ),
      column(
        MediaDetailSectionLabel(
          label: 'Seasons',
          accent: ServiceKey.sonarr.accent,
          count: '41 of 45 on disk',
        ),
      ),
      column(
        MediaDetailSectionLabel(
          label: 'Missing subtitles',
          accent: bazarr,
          action: refresh,
        ),
      ),
      column(
        MediaDetailSectionLabel(
          label: 'Other releases from the same production company',
          accent: ServiceKey.lidarr.accent,
          count: '12 albums',
        ),
      ),
      column(
        MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.5)),
          child: MediaDetailSectionLabel(
            label: 'Missing subtitles',
            accent: bazarr,
            action: refresh,
          ),
        ),
      ),
    ],
  );
}

void main() {
  catalogCard(
    'MediaDetailSection',
    width: 1328,
    scenes: [
      CatalogScene(
        'MediaDetailView.body · Radarr on a phone, then Sonarr · deck, then '
        'the manifest, synopsis and reference in fixed order; space-xl above '
        'each label, space-sm below; a .lazy season list mid-page',
        (_) => _row([_phone(_radarrPage()), _phone(_sonarrPage())]),
      ),
      CatalogScene(
        'MediaDetailSectionLabel · plain, with a count, with a trailing '
        'control, a long label on two lines, and 1.5× reading size · the '
        'page accent (the lamp) resolved to ink; the control drops under '
        'the label past 1.4×, leading-aligned',
        _labels,
      ),
      CatalogScene(
        'MediaDetailValueRow · editable, the source did not answer, no write '
        'behind it · chevron only when it can write; a dash, never a blank',
        (_) => SizedBox(
          width: 358,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _profileRow(ServiceKey.radarr),
              _profileRow(ServiceKey.radarr, value: null),
              _profileRow(ServiceKey.radarr, editable: false),
            ],
          ),
        ),
      ),
      CatalogScene(
        'MediaDetailView.body · Radarr in a 1280 desktop window · two tracks '
        'past 1140: the slots named in sideTrack stand in the 380 column, '
        'deck and manifest stay wide',
        (_) => _radarrPage(),
        width: 1280,
        height: 1000,
        platform: CatalogPlatform.desktop,
      ),
    ],
  );
}
