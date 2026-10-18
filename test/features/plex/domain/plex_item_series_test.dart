import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/plex/domain/models/plex_item_mapper.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';

import '../../../test_helpers/fixtures.dart';

List<StreamItem> _items(String fixture) => plexItemsFromMetadata(
  (jsonFixtureMap(fixture)['MediaContainer'] as Map)['Metadata'] as List,
);

/// A season or an episode names the show it belongs to, and the season it is
/// in: what lets a tap open the show's page on that season.
void main() {
  // The show of `show_children.json`, `season_children.json` and the first
  // deck row.
  const show = '41000';

  test('a season: its show is its parent, its number is its own index', () {
    final seasons = _items('plex/show_children.json');

    expect(
      seasons.map((season) => season.kind),
      everyElement(StreamItemKind.season),
    );
    expect(seasons.map((season) => season.seriesId), [show, show]);
    expect(seasons.map((season) => season.seasonNumber), [1, 2]);
    expect(seasons.map((season) => season.episodeNumber), [null, null]);
  });

  test('an episode: its show is its grandparent, its season is its '
      'parent\'s index', () {
    final episodes = _items('plex/season_children.json');

    expect(episodes.first.kind, StreamItemKind.episode);
    expect(episodes.first.seriesId, show);
    expect(episodes.first.seasonNumber, 1);
    expect(episodes.first.episodeNumber, 1);
  });

  test('an on-deck row names its own show, each its own', () {
    final deck = _items('plex/library_on_deck.json');

    expect(deck.map((episode) => episode.seriesId).toSet(), {show, '42000'});
    expect(deck.first.seasonNumber, 1);
    expect(deck.first.episodeNumber, 4);
  });

  test('the specials are season 0, not nothing', () {
    final specials = plexItemFromJson({
      'ratingKey': '41009',
      'type': 'season',
      'title': 'Specials',
      'index': 0,
      'parentRatingKey': show,
    })!;

    expect(specials.seasonNumber, 0);
    expect(specials.seriesId, show);
  });

  test('a rating key the server sends as a number is still an id', () {
    final episode = plexItemFromJson({
      'ratingKey': 41120,
      'type': 'episode',
      'title': 'Good News About Hell',
      'grandparentRatingKey': 41000,
      'parentIndex': 1,
      'index': 1,
    })!;

    expect(episode.seriesId, '41000');
  });

  test('an episode the server gave no show for names none', () {
    final episode = plexItemFromJson({
      'ratingKey': '9',
      'type': 'episode',
      'title': 'Loose file',
      'parentIndex': 1,
      'index': 2,
    })!;

    expect(episode.seriesId, isNull);
    expect(episode.seasonNumber, 1);
  });

  test('a movie, a show and an album belong to no show', () {
    for (final type in ['movie', 'show', 'artist', 'album', 'track']) {
      final item = plexItemFromJson({
        'ratingKey': '5',
        'type': type,
        'title': 'x',
        // A track's or an album's parent is not a show, whatever it is
        // numbered.
        'parentRatingKey': '4',
        'grandparentRatingKey': '3',
        'parentIndex': 2,
        'index': 7,
      })!;

      expect(item.seriesId, isNull, reason: type);
      expect(item.seasonNumber, isNull, reason: type);
    }
  });
}
