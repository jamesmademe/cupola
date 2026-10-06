import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/domain/catalog_curation.dart';
import 'package:cupola/features/discover/domain/catalog_query.dart';

/// What each catalogue page asks Seerr, in the parameters Seerr 3.4.1
/// answers to (checked on the lab, 06/10).
void main() {
  final today = DateTime(2026, 10, 6);

  group('the question each base asks', () {
    test('a genre, by popularity', () {
      const query = CatalogQuery.genre(CatalogKind.tv, 16, 'Animation');
      expect(query.path, '/api/v1/discover/tv');
      expect(query.parameters(1, today: today), {
        'page': 1,
        'genre': 16,
        'sortBy': 'popularity.desc',
      });
    });

    test('a network is series, a studio is movies', () {
      expect(
        const CatalogQuery.network(213, 'Netflix').path,
        '/api/v1/discover/tv',
      );
      expect(
        const CatalogQuery.network(213, 'Netflix').parameters(2, today: today),
        {'page': 2, 'network': 213, 'sortBy': 'popularity.desc'},
      );
      expect(
        const CatalogQuery.studio(41077, 'A24').path,
        '/api/v1/discover/movies',
      );
    });

    test('a mood is a keyword, a language the original one', () {
      expect(
        const CatalogQuery.keyword(
          CatalogKind.movie,
          4379,
          'Time travel',
        ).parameters(1, today: today),
        {'page': 1, 'keywords': 4379, 'sortBy': 'popularity.desc'},
      );
      expect(
        const CatalogQuery.language(
          CatalogKind.tv,
          'ko',
          'Korean',
        ).parameters(1, today: today),
        {'page': 1, 'language': 'ko', 'sortBy': 'popularity.desc'},
      );
    });

    test('a decade bounds the dates its kind keeps', () {
      expect(
        const CatalogQuery.decade(
          CatalogKind.movie,
          1990,
        ).parameters(1, today: today),
        {
          'page': 1,
          'primaryReleaseDateGte': '1990-01-01',
          'primaryReleaseDateLte': '1999-12-31',
          'sortBy': 'popularity.desc',
        },
      );
      expect(
        const CatalogQuery.decade(
          CatalogKind.tv,
          1920,
        ).parameters(1, today: today),
        containsPair('firstAirDateGte', '1920-01-01'),
      );
    });

    test('trending takes its window and nothing else', () {
      const query = CatalogQuery.trending(window: TrendingWindow.day);
      expect(query.path, '/api/v1/discover/trending');
      expect(query.parameters(3, today: today), {
        'page': 3,
        'timeWindow': 'day',
      });
    });

    test('coming soon takes a page and nothing else: Seerr refuses more', () {
      const query = CatalogQuery.upcoming(CatalogKind.movie);
      expect(query.path, '/api/v1/discover/movies/upcoming');
      expect(query.parameters(1, today: today), {'page': 1});
      expect(query.filters, isFalse);
    });
  });

  group('the filters and the order', () {
    const genre = CatalogQuery.genre(CatalogKind.movie, 16, 'Animation');

    test('rated is TMDB 7 or more over a hundred votes', () {
      expect(
        genre.withRated(true).parameters(1, today: today),
        allOf(
          containsPair('voteAverageGte', 7),
          containsPair('voteCountGte', catalogVoteFloor),
        ),
      );
    });

    test('ordered by score, a page always has the vote floor', () {
      // Without it TMDB leads with titles one person rated ten.
      expect(
        genre.withSort(CatalogSort.topRated).parameters(1, today: today),
        allOf(
          containsPair('sortBy', 'vote_average.desc'),
          containsPair('voteCountGte', catalogVoteFloor),
          isNot(contains('voteAverageGte')),
        ),
      );
    });

    test('newest first stops at today, not at films announced for 2029', () {
      expect(
        genre.withSort(CatalogSort.newest).parameters(1, today: today),
        allOf(
          containsPair('sortBy', 'primary_release_date.desc'),
          containsPair('primaryReleaseDateLte', '2026-10-06'),
        ),
      );
      expect(
        genre
            .withKind(CatalogKind.tv)
            .withSort(CatalogSort.newest)
            .parameters(1, today: today),
        allOf(
          containsPair('sortBy', 'first_air_date.desc'),
          containsPair('firstAirDateLte', '2026-10-06'),
        ),
      );
    });

    test('a decade filter over a genre', () {
      expect(
        genre.withDecade(1980).parameters(1, today: today),
        allOf(
          containsPair('primaryReleaseDateGte', '1980-01-01'),
          containsPair('primaryReleaseDateLte', '1989-12-31'),
        ),
      );
      expect(genre.withDecade(1980).withDecade(null).decadeFilter, isNull);
    });

    test('under 100 minutes is a film\'s length, so series drop it', () {
      final short = genre.withShort(true);
      expect(
        short.parameters(1, today: today),
        containsPair('withRuntimeLte', 100),
      );
      expect(short.withKind(CatalogKind.tv).short, isFalse);
      expect(short.withKind(CatalogKind.tv).offersShort, isFalse);
    });
  });

  group('the halves a page can switch between', () {
    test('a genre both halves number the same way offers both', () {
      expect(
        const CatalogQuery.genre(CatalogKind.movie, 16, 'Animation').kinds,
        CatalogKind.values,
      );
    });

    test('a genre the other half numbers differently offers none', () {
      // Movie 28 is Action; series have 10759, Action & Adventure.
      expect(
        const CatalogQuery.genre(CatalogKind.movie, 28, 'Action').kinds,
        isEmpty,
      );
    });

    test('a network, a studio and trending have one half or a mix', () {
      expect(const CatalogQuery.network(213, 'Netflix').kinds, isEmpty);
      expect(const CatalogQuery.studio(41077, 'A24').kinds, isEmpty);
      expect(const CatalogQuery.trending().kinds, isEmpty);
    });

    test('a decade, a mood and a language offer both', () {
      expect(
        const CatalogQuery.decade(CatalogKind.movie, 1990).kinds,
        CatalogKind.values,
      );
      expect(
        const CatalogQuery.keyword(CatalogKind.movie, 4379, 'x').kinds,
        CatalogKind.values,
      );
    });
  });

  group('how many titles a page says it holds', () {
    test('a total under Seerr\'s cap is the total', () {
      expect(catalogCountPhrase(179), '179 titles');
      expect(catalogCountPhrase(2380), '2,380 titles');
      expect(catalogCountPhrase(16713), '16,713 titles');
      expect(catalogCountPhrase(1), '1 title');
    });

    test('a figure at the cap is a floor', () {
      // A whole genre says 20,001 over 1,001 pages; trending 10,000 over 500.
      expect(catalogCountPhrase(20001), '20,000+ titles');
      expect(catalogCountPhrase(10000), '10,000+ titles');
    });

    test('no figure says nothing', () {
      expect(catalogCountPhrase(null), isNull);
      expect(catalogCountPhrase(0), isNull);
    });
  });

  group('the curated lists', () {
    test('the networks your series come from lead', () {
      final ordered = libraryFirst(curatedNetworks, ['HBO', 'Apple TV']);
      expect(ordered.take(2).map((entry) => entry.name), ['HBO', 'Apple TV+']);
      expect(ordered, hasLength(curatedNetworks.length));
    });

    test('with no library the list is as curated', () {
      expect(libraryFirst(curatedStudios, const []), curatedStudios);
    });

    test('the decades run from now back to the 1920s', () {
      final decades = catalogDecades(today: DateTime(2026, 10, 6));
      expect(decades.first, 2020);
      expect(decades.last, 1920);
    });

    test('no id is listed twice', () {
      for (final list in [curatedNetworks, curatedStudios, curatedMoods]) {
        final ids = list.map((entry) => entry.id).toList();
        expect(ids.toSet(), hasLength(ids.length));
      }
    });
  });
}
