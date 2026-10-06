@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/features/discover/presentation/discover_details_provider.dart';
import 'package:cupola/features/discover/presentation/widgets/catalog_poster.dart';

import 'catalog.dart';

/// Four titles as Seerr's catalogue answers them: one on the server, one
/// waiting for approval, one downloading, one Seerr holds no record of.
const _row = [
  MediaPreview(
    id: 1,
    title: 'Sintel',
    mediaType: 'movie',
    posterPath: CatalogArt.tmdbPoster,
    voteAverage: 7.4,
    mediaInfo: {'status': 5},
  ),
  MediaPreview(
    id: 2,
    title: 'Charge',
    mediaType: 'movie',
    posterPath: CatalogArt.tmdbPoster,
    voteAverage: 7.6,
    mediaInfo: {'status': 2},
  ),
  MediaPreview(
    id: 3,
    title: 'Sprite Fright',
    mediaType: 'movie',
    posterPath: CatalogArt.tmdbPoster,
    voteAverage: 7.8,
    mediaInfo: {
      'status': 3,
      'downloadStatus': [
        {
          'status': 'downloading',
          'trackedDownloadState': 'downloading',
          'size': 1000,
          'sizeLeft': 380,
        },
      ],
    },
  ),
  MediaPreview(
    id: 4,
    title: 'The Cabinet of Dr. Caligari',
    mediaType: 'movie',
    posterPath: CatalogArt.tmdbPoster,
    voteAverage: 8.0,
  ),
];

Widget _rail() => Builder(
  builder: (context) => SizedBox(
    height: CatalogPoster.heightFor(context, 104),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in _row) ...[
          CatalogPoster(item: item, heroTag: 'poster_${item.id}', width: 104),
          const SizedBox(width: 12),
        ],
      ],
    ),
  ),
);

void main() {
  catalogCard(
    'CatalogPoster',
    overrides: () async => [
      seerrNumberingProvider.overrideWith((ref) async => null),
    ],
    scenes: [
      CatalogScene(
        'CatalogPoster · the operator · on the server, waiting for approval, '
        'downloading at 62%, and a title Seerr holds nothing of (no badge) · '
        'the poster word top-right, two lines of title, TMDB score in dim '
        'ink',
        (_) => _rail(),
        width: 500,
        overrides: [audienceProvider.overrideWithValue(Audience.operator)],
      ),
      CatalogScene(
        'CatalogPoster · the requester · the same four in her words: On the '
        'server, Waiting for approval, Downloading, nothing',
        (_) => _rail(),
        width: 500,
        overrides: [audienceProvider.overrideWithValue(Audience.requester)],
      ),
      CatalogScene(
        'Text at 200% · the words follow the reading size to the compact '
        "tile's ceiling (1.6x) and the tile grows with them; past it they "
        'ellipsise, never breaking inside a word',
        (_) => _rail(),
        width: 500,
        textScale: catalogTextScale,
        overrides: [audienceProvider.overrideWithValue(Audience.operator)],
      ),
    ],
  );
}
