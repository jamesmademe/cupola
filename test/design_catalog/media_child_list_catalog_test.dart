@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/utils/episode_code.dart';
import 'package:cupola/core/widgets/widgets.dart';

import 'catalog.dart';

/// The Stoll series of 1921, fifteen two-reelers — public domain, and a real
/// season-shaped list of titles.
const _titles = [
  'The Dying Detective',
  "The Devil's Foot",
  'A Case of Identity',
  'The Yellow Face',
  'The Red-Headed League',
  'The Resident Patient',
  'A Scandal in Bohemia',
  'The Man with the Twisted Lip',
  'The Beryl Coronet',
  'The Noble Bachelor',
  'The Copper Beeches',
  'The Empty House',
  'The Tiger of San Pedro',
  'The Priory School',
  'The Solitary Cyclist',
];

const _available = MediaStatusInfo(availability: MediaAvailability.available);

MediaStatusInfo _episodeStatus(int index) => switch (index) {
  4 => const MediaStatusInfo(
    pipeline: MediaPipeline.downloading,
    progress: 0.42,
  ),
  6 => const MediaStatusInfo(availability: MediaAvailability.missing),
  _ => _available,
};

const _months = ['Jan', 'Feb', 'Mar', 'Apr'];

String _airDate(int index) =>
    '${_months[index ~/ 4]} ${1 + (index % 4) * 7}, 1921';

Widget _search(String tooltip) => MediaSearchPopupMenu(
  onAutoSearch: () {},
  onInteractiveSearch: () {},
  iconSize: 18,
  tooltip: tooltip,
);

Widget _episode(int index) {
  final status = _episodeStatus(index);
  final searchable = !status.isAvailable && !status.isInPipeline;
  return MediaChildTile.numbered(
    ordinal: formatEpisodeOrdinal(index + 1),
    ordinalLabel: 'Episode ${index + 1}',
    title: _titles[index],
    facts: [_airDate(index), ?mediaStatusWord(status)],
    status: status,
    onTap: () {},
    trailing: searchable ? _search('Search episode ${index + 1}') : null,
  );
}

Widget _loose() => Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    // A Seerr episode: availability is per season, so the row has no status.
    MediaChildTile.numbered(
      ordinal: 'E8',
      ordinalLabel: 'Episode 8',
      title: 'The Man with the Twisted Lip',
      facts: const ['Feb 15, 1921'],
    ),
    const SizedBox(height: 4),
    MediaChildTile.numbered(
      ordinal: 'E13',
      ordinalLabel: 'Episode 13',
      title:
          'The Tiger of San Pedro, being a reminiscence of Mr. Sherlock '
          'Holmes in two parts',
      facts: const ['Apr 1, 1921', 'Not released'],
      status: const MediaStatusInfo(
        availability: MediaAvailability.unavailable,
      ),
      onTap: () {},
    ),
    const SizedBox(height: 4),
    MediaChildTile.numbered(
      ordinal: 'E14',
      ordinalLabel: 'Episode 14',
      title: 'The Priory School',
      facts: const ['Apr 8, 1921', 'Stuck 61%'],
      status: const MediaStatusInfo(
        pipeline: MediaPipeline.stalled,
        progress: 0.61,
      ),
      onTap: () {},
    ),
  ],
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

/// A run of the Stoll series' episodes: one downloading, one missing with the
/// search menu on it, the rest on disk.
Widget _episodes() => Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    for (var index = 2; index < 8; index++) ...[
      if (index > 2) const SizedBox(height: 4),
      _episode(index),
    ],
  ],
);

/// A phone column: the rows on the page gutter.
Widget _phone(Widget child) => SizedBox(
  width: 390,
  child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: child,
  ),
);

void main() {
  catalogCard(
    'MediaChildList',
    width: 880,
    scenes: [
      CatalogScene(
        'MediaChildTile.numbered · episodes with an air date, the status as a '
        'dot and, when a row is not plainly available, in words · the search '
        'menu stays on the row nobody has',
        (_) => _phone(_episodes()),
      ),
      CatalogScene(
        'MediaChildTile.numbered · no status (a Seerr episode), a two-line '
        'title, and a stalled row',
        (_) => _phone(_loose()),
      ),
      CatalogScene(
        'MediaChildTile.numbered · desktop, the 720 reading column · compact '
        'density, the same rows',
        (_) => SizedBox(width: 720, child: _episodes()),
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'Text at 200% · the episode rows and the loose episodes, at twice the '
        'reading size',
        (_) => _row([_phone(_episodes()), _phone(_loose())]),
        textScale: catalogTextScale,
      ),
    ],
  );
}
