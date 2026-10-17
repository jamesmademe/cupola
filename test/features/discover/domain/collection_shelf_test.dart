import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/features/discover/domain/collection_shelf.dart';
import 'package:cupola/features/discover/domain/models/collection_detail.dart';
import 'package:cupola/features/discover/domain/seerr_status.dart';

/// A collection as its page shows it: release order, and where each movie
/// stands by Seerr's record of it.
void main() {
  MediaPreview part(
    int id,
    String title, {
    String? date,
    Map<String, dynamic>? info,
  }) => MediaPreview(
    id: id,
    title: title,
    mediaType: 'movie',
    releaseDate: date,
    mediaInfo: info,
  );

  final shelf = CollectionShelf.of(
    CollectionDetail(
      id: 1,
      name: 'Blender Open Movies',
      parts: [
        part(4, 'Charge', date: '2022-01-01', info: {'status': 2}),
        part(1, 'Elephants Dream', date: '2006-03-24', info: {'status': 5}),
        part(9, 'Untitled', info: null),
        part(
          3,
          'Spring',
          date: '2019-04-04',
          info: {'status': 1, 'status4k': 5},
        ),
        part(2, 'Sprite Fright', date: '2021-10-29', info: {'status': 3}),
      ],
    ),
  );

  test('oldest first, a movie with no date yet last', () {
    expect(
      [for (final p in shelf.parts) p.media.title],
      ['Elephants Dream', 'Spring', 'Sprite Fright', 'Charge', 'Untitled'],
    );
  });

  test('on the server in either copy, on its way, waiting, missing', () {
    expect(shelf.count(CollectionPartStand.onServer), 2);
    expect(shelf.count(CollectionPartStand.onTheWay), 1);
    expect(shelf.count(CollectionPartStand.waiting), 1);
    expect(shelf.count(CollectionPartStand.missing), 1);
  });

  test('the line under the name', () {
    expect(shelf.summary, 'Collection\u00A0· 5 movies\u00A0· 2006–2022');
    expect(
      CollectionShelf.of(
        CollectionDetail(id: 1, name: 'One', parts: [part(1, 'A')]),
      ).summary,
      'Collection\u00A0· 1 movie',
    );
  });

  test('worth completing while a movie is missing or waits for approval, '
      'not once the rest is only on its way', () {
    CollectionShelf of(List<Map<String, dynamic>?> infos) => CollectionShelf.of(
      CollectionDetail(
        id: 1,
        name: 'C',
        parts: [
          for (final (i, info) in infos.indexed)
            part(i + 1, 'P$i', date: '200$i-01-01', info: info),
        ],
      ),
    );

    expect(shelf.invitesCompletion, isTrue);
    expect(
      of([
        {'status': 5},
        {'status': 2},
      ]).invitesCompletion,
      isTrue,
    );
    expect(
      of([
        {'status': 5},
        {'status': 3},
      ]).invitesCompletion,
      isFalse,
    );
    expect(
      of([
        null,
        {'status': 2},
      ]).invitesCompletion,
      isFalse,
    );
    expect(
      of([
        {'status': 5},
      ]).invitesCompletion,
      isFalse,
    );
  });

  test('a title held in 4K alone is held', () {
    expect(seerrHolds({'status': 1, 'status4k': 5}), isTrue);
    expect(seerrHolds({'status': 3, 'status4k': 1}), isFalse);
  });
}
