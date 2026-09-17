import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/utils/arr_activity_display.dart';

void main() {
  group('arrPrimaryMediaTitle', () {
    test('names the movie, the series, the album and the artist', () {
      expect(
        arrPrimaryMediaTitle(const {
          'movie': {'title': 'Dune', 'year': 2021},
        }),
        'Dune',
      );
      expect(
        arrPrimaryMediaTitle(const {
          'movie': {'title': 'Dune', 'year': 2021},
        }, includeMovieYear: true),
        'Dune (2021)',
      );
      expect(
        arrPrimaryMediaTitle(const {
          'series': {'title': 'Severance'},
        }),
        'Severance',
      );
      expect(
        arrPrimaryMediaTitle(const {
          'album': {'title': 'Blue Rev'},
        }),
        'Blue Rev',
      );
      expect(
        arrPrimaryMediaTitle(const {
          'artist': {'artistName': 'Alvvays'},
        }),
        'Alvvays',
      );
    });

    test('names the book, and falls back to the author', () {
      // The fifth arm. Readarr writes its records against a `book` and an
      // `author`, and with neither of those read every one of the four lookups
      // above missed: the helper answered null for *every* Readarr queue,
      // history and blocklist record, and its ten call sites fell back to the
      // raw release name — so a Readarr queue row on the Dashboard read
      // `Orbital.2023.RETAIL.EPUB-XYZ` where every other \*arr read a title.
      expect(
        arrPrimaryMediaTitle(const {
          'book': {'title': 'Orbital'},
          'author': {'authorName': 'Samantha Harvey'},
          'title': 'Orbital.2023.RETAIL.EPUB-XYZ',
        }),
        'Orbital',
      );

      // Book before author because the book is the subject of the record;
      // naming the author would name the wrong noun. With no book matched, the
      // author is still a better answer than the release string.
      expect(
        arrPrimaryMediaTitle(const {
          'author': {'authorName': 'Samantha Harvey'},
          'title': 'Orbital.2023.RETAIL.EPUB-XYZ',
        }),
        'Samantha Harvey',
      );
    });

    test('answers null when the record names nothing at all', () {
      // The callers' fallback chain depends on this: null is what lets them
      // reach for the release string, and a non-null empty answer would print
      // a blank row.
      expect(arrPrimaryMediaTitle(const {'title': 'Some.Release-GRP'}), isNull);
    });
  });
}
