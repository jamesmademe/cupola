import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/media/domain/media_collection.dart';

Map<String, dynamic> _part(int id, [int? status, int? status4k]) => {
  'id': id,
  'title': 'Part $id',
  'mediaType': 'movie',
  if (status != null) 'mediaInfo': {'status': status, 'status4k': ?status4k},
};

void main() {
  test('counts the members Seerr holds, whole or in part', () {
    expect(
      mediaCollectionHeld({
        'id': 1,
        'name': 'Blender Open Movies',
        'parts': [_part(1, 5), _part(2, 4), _part(3, 3), _part(4, 2), _part(5)],
      }),
      (held: 2, total: 5),
    );
  });

  test('a member held only in 4K is on the server', () {
    expect(
      mediaCollectionHeld({
        'parts': [_part(1, 1, 5), _part(2, 1, 1)],
      }),
      (held: 1, total: 2),
    );
  });

  test('none held is a figure, not a missing one', () {
    expect(
      mediaCollectionHeld({
        'parts': [_part(1), _part(2)],
      }),
      (held: 0, total: 2),
    );
  });

  test('no such collection, or one with no members, states nothing', () {
    expect(mediaCollectionHeld(const {}), isNull);
    expect(mediaCollectionHeld(const {'id': 1, 'parts': []}), isNull);
  });
}
