@Tags(['catalog'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/features/discover/domain/collection_shelf.dart';
import 'package:cupola/features/discover/domain/models/collection_detail.dart';
import 'package:cupola/features/discover/presentation/widgets/collection_tally.dart';

import 'catalog.dart';

/// Blender's open movies as the lab's household holds them: five on the
/// server, two on their way, one waiting for approval.
const _blender = [
  (1, 'Elephants Dream', 2006, 5),
  (2, 'Big Buck Bunny', 2008, 3),
  (3, 'Sintel', 2010, 5),
  (4, 'Tears of Steel', 2012, 5),
  (5, 'Spring', 2019, 5),
  (6, 'Coffee Run', 2020, 5),
  (7, 'Sprite Fright', 2021, 3),
  (8, 'Charge', 2022, 2),
];

CollectionShelf _shelf(List<(int, String, int, int?)> parts) =>
    CollectionShelf.of(
      CollectionDetail(
        id: 1,
        name: 'Blender Open Movies',
        parts: [
          for (final (id, title, year, status) in parts)
            MediaPreview(
              id: id,
              title: title,
              mediaType: 'movie',
              releaseDate: '$year-04-10',
              posterPath: CatalogArt.tmdbPoster,
              mediaInfo: status == null ? null : {'status': status},
            ),
        ],
      ),
    );

void main() {
  catalogCard(
    'CollectionTally',
    scenes: [
      CatalogScene(
        'CollectionTally · on the collection\'s page: how much is on the '
        'server, the strip of its movies, the count of each kind',
        (_) => CollectionTally(shelf: _shelf(_blender)),
        width: 390,
      ),
      CatalogScene(
        'CollectionTally.invitation · the atrium\'s Complete the collection: '
        'the name and the count under the title, the slab one button',
        (_) => CollectionTally.invitation(
          shelf: _shelf(_blender),
          name: 'Blender Open Movies',
          onTap: () {},
        ),
        width: 390,
      ),
      CatalogScene(
        'Whole · all on the server, the legend one word',
        (_) => CollectionTally(
          shelf: _shelf(_blender.take(4).map(_held).toList()),
        ),
        width: 390,
      ),
      CatalogScene(
        'Past ten movies · the covers would be too small to read, the bars '
        'stand alone',
        (_) => CollectionTally(
          shelf: _shelf([
            for (var i = 0; i < 14; i++)
              (
                i + 1,
                'Part ${i + 1}',
                1990 + i,
                i < 9 ? 5 : (i < 11 ? 3 : null),
              ),
          ]),
        ),
        width: 390,
      ),
      CatalogScene(
        'Text at 200% · the invitation grows with its words; the legend wraps',
        (_) => CollectionTally.invitation(
          shelf: _shelf(_blender),
          name: 'Blender Open Movies',
          onTap: () {},
        ),
        width: 390,
        textScale: catalogTextScale,
      ),
    ],
  );
}

(int, String, int, int?) _held((int, String, int, int) part) =>
    (part.$1, part.$2, part.$3, 5);
