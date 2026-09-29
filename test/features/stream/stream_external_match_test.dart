import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/domain/stream_external_match.dart';

StreamItem _item({
  String id = 'x',
  String title = 'The Matrix',
  StreamItemKind kind = StreamItemKind.movie,
  int? year = 1999,
  StreamExternalIds ids = StreamExternalIds.none,
}) => StreamItem(
  id: id,
  title: title,
  subtitle: null,
  kind: kind,
  posterPath: null,
  year: year,
  runtimeMs: null,
  isPlayed: false,
  resumeOffsetMs: null,
  unplayedChildCount: null,
  externalIds: ids,
);

void main() {
  group('streamExternalMatchScore', () {
    const radarr = StreamExternalQuery(tmdbId: '603');

    test('the item’s own id agreeing is the evidence', () {
      expect(
        streamExternalMatchScore(
          _item(ids: const StreamExternalIds(tmdb: '603')),
          radarr,
        ),
        1,
      );
    });

    test('a row naming another title is refused, not trusted', () {
      // What a server that ignored the filter hands back: a real item, with
      // real ids, that are not the ones asked about.
      expect(
        streamExternalMatchScore(
          _item(
            title: 'Alien',
            ids: const StreamExternalIds(tmdb: '348'),
          ),
          radarr,
        ),
        isNull,
      );
    });

    test('a row reporting no id at all proves nothing and is refused', () {
      expect(streamExternalMatchScore(_item(), radarr), isNull);
    });

    test('one disagreeing database refuses the row whatever else agrees', () {
      expect(
        streamExternalMatchScore(
          _item(
            kind: StreamItemKind.series,
            ids: const StreamExternalIds(tmdb: '1396', tvdb: '99999'),
          ),
          const StreamExternalQuery(tmdbId: '1396', tvdbId: '81189'),
        ),
        isNull,
      );
    });

    test('ids compare without case or padding', () {
      expect(
        streamExternalMatchScore(
          _item(ids: const StreamExternalIds(imdb: 'TT0133093 ')),
          const StreamExternalQuery(imdbId: 'tt0133093'),
        ),
        1,
      );
    });

    test('an episode never answers for an arr title', () {
      // An episode carries TVDB and IMDb ids of its own, in the namespaces a
      // series uses, so without the kind rule it is a legitimate hit.
      expect(
        streamExternalMatchScore(
          _item(
            kind: StreamItemKind.episode,
            ids: const StreamExternalIds(tvdb: '81189'),
          ),
          const StreamExternalQuery(tvdbId: '81189'),
        ),
        isNull,
      );
    });

    test('a stated kind refuses the other one', () {
      // TMDB numbers films and shows separately: Breaking Bad is TV 1396, and
      // some film is movie 1396.
      final film = _item(ids: const StreamExternalIds(tmdb: '1396'));
      expect(
        streamExternalMatchScore(
          film,
          const StreamExternalQuery(
            tmdbId: '1396',
            kind: StreamItemKind.series,
          ),
        ),
        isNull,
      );
      expect(
        streamExternalMatchScore(
          film,
          const StreamExternalQuery(tmdbId: '1396'),
        ),
        1,
      );
    });

    group('the title settles only what ids cannot', () {
      const query = StreamExternalQuery(
        tmdbId: '603',
        title: 'The Matrix',
        year: 1999,
      );

      test('exact normalised title and year, with nothing comparable', () {
        expect(
          streamExternalMatchScore(
            _item(
              title: 'the matrix',
              ids: const StreamExternalIds(imdb: 'tt0133093'),
            ),
            query,
          ),
          0,
        );
      });

      test('a different year is a different film', () {
        expect(streamExternalMatchScore(_item(year: 2021), query), isNull);
      });

      test('without a year there is nothing to check against', () {
        expect(
          streamExternalMatchScore(
            _item(),
            const StreamExternalQuery(tmdbId: '603', title: 'The Matrix'),
          ),
          isNull,
        );
      });

      test('a comparable id outranks a matching title', () {
        expect(
          streamExternalMatchScore(
            _item(ids: const StreamExternalIds(tmdb: '604')),
            query,
          ),
          isNull,
        );
      });
    });
  });

  group('bestStreamExternalMatch', () {
    test('skips a wrong first row and takes the verified one', () {
      final wrong = _item(
        id: 'wrong',
        title: 'Alien',
        ids: const StreamExternalIds(tmdb: '348'),
      );
      final right = _item(
        id: 'right',
        ids: const StreamExternalIds(tmdb: '603'),
      );

      expect(
        bestStreamExternalMatch([
          wrong,
          right,
        ], const StreamExternalQuery(tmdbId: '603'))?.id,
        'right',
      );
      expect(
        bestStreamExternalMatch([
          wrong,
        ], const StreamExternalQuery(tmdbId: '603')),
        isNull,
      );
    });

    test('the row more ids agree on wins over a namesake number', () {
      // Sonarr asks with its TVDB id and the show's TMDB id; the OR filter also
      // returns a film that happens to carry the same TMDB number.
      final film = _item(
        id: 'film',
        ids: const StreamExternalIds(tmdb: '1396'),
      );
      final show = _item(
        id: 'show',
        title: 'Breaking Bad',
        kind: StreamItemKind.series,
        year: 2008,
        ids: const StreamExternalIds(tmdb: '1396', tvdb: '81189'),
      );

      expect(
        bestStreamExternalMatch([
          film,
          show,
        ], const StreamExternalQuery(tmdbId: '1396', tvdbId: '81189'))?.id,
        'show',
      );
    });
  });

  test('normaliseStreamTitle folds case, punctuation and spacing only', () {
    expect(normaliseStreamTitle('  Sherlock   Jr. '), 'sherlock jr');
    expect(normaliseStreamTitle('Amélie'), 'amélie');
    expect(normaliseStreamTitle('...'), isNull);
    expect(normaliseStreamTitle(null), isNull);
  });
}
