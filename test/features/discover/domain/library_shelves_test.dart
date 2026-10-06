import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/domain/library_shelves.dart';
import 'package:cupola/features/movies/domain/models/radarr_collection.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/domain/stream_server_client.dart';

/// Which collection the atrium invites the operator to complete, and which
/// watched title TMDB is asked to recommend from.
void main() {
  RadarrCollection collection(
    int id,
    String title, {
    int held = 0,
    int missing = 0,
    int excluded = 0,
  }) => RadarrCollection(
    tmdbId: id,
    title: title,
    movies: [
      for (var i = 0; i < held; i++)
        RadarrCollectionMovie(
          tmdbId: id * 100 + i,
          title: '',
          isExisting: true,
        ),
      for (var i = 0; i < missing; i++)
        RadarrCollectionMovie(tmdbId: id * 100 + 50 + i, title: ''),
      for (var i = 0; i < excluded; i++)
        RadarrCollectionMovie(
          tmdbId: id * 100 + 80 + i,
          title: '',
          isExcluded: true,
        ),
    ],
  );

  test('the nearest to whole first, then the one that holds more', () {
    final ranked = collectionsToComplete([
      collection(1, 'Alien', held: 1, missing: 3),
      collection(2, 'Toy Story', held: 3, missing: 1),
      collection(3, 'Blender', held: 6, missing: 2),
      collection(4, 'Whole', held: 3),
      collection(5, 'None yet', missing: 4),
      // An excluded movie is a choice, not a gap.
      collection(6, 'Excluded', held: 2, excluded: 1),
    ]);

    expect(
      [for (final c in ranked) c.title],
      ['Blender', 'Toy Story', 'Alien'],
    );
  });

  test('a tie goes by name, so two reads agree', () {
    final ranked = collectionsToComplete([
      collection(1, 'Matrix', held: 1, missing: 1),
      collection(2, 'Bourne', held: 1, missing: 1),
    ]);
    expect([for (final c in ranked) c.title], ['Bourne', 'Matrix']);
  });

  StreamWatched watched(
    String title,
    int day, {
    StreamItemKind kind = StreamItemKind.movie,
    String? tmdb,
  }) => (
    item: StreamItem(
      id: title,
      title: title,
      subtitle: null,
      kind: kind,
      posterPath: null,
      year: null,
      runtimeMs: null,
      isPlayed: true,
      resumeOffsetMs: null,
      unplayedChildCount: null,
      externalIds: StreamExternalIds(tmdb: tmdb),
    ),
    playedAt: DateTime.utc(2026, 10, day),
  );

  test('the latest watched across the servers that TMDB knows', () {
    final latest = latestRecommendable([
      [watched('Sintel', 2, tmdb: '45745')],
      [
        // A home movie has nothing to recommend from.
        watched('Holiday', 5),
        watched('The Expanse', 3, kind: StreamItemKind.series, tmdb: '63639'),
      ],
    ]);

    expect(latest?.item.title, 'The Expanse');
    expect(latest?.mediaType, 'tv');
    expect(latest?.tmdbId, 63639);
  });

  test('nothing watched that TMDB knows: nothing to recommend from', () {
    expect(
      latestRecommendable([
        [watched('Holiday', 5)],
        const [],
      ]),
      isNull,
    );
  });
}
