import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/utils/rating_display.dart';

void main() {
  group('ratingSourceLabel', () {
    test('expands the two-letter badges the parser produces', () {
      // Observed on a real page: `MC 53.0`, `RO 57.0`, `TR 7.1` — three of five
      // labels being abbreviations that appear nowhere else in the app and are
      // not what anyone calls those sources.
      expect(ratingSourceLabel(icon: 'MC', name: 'Metacritic'), 'Metacritic');
      expect(
        ratingSourceLabel(icon: 'RO', name: 'ROTTENTOMATOES'),
        'Rotten Tomatoes',
      );
      expect(ratingSourceLabel(icon: 'TR', name: 'TRAKT'), 'Trakt');
      expect(ratingSourceLabel(icon: 'MB', name: '42500 voti'), 'MusicBrainz');
    });

    test('keeps the sources that already name themselves properly', () {
      expect(ratingSourceLabel(icon: 'IMDb', name: 'IMDb'), 'IMDb');
      expect(ratingSourceLabel(icon: 'TMDB', name: 'TMDB'), 'TMDB');
      expect(ratingSourceLabel(icon: 'TVDB', name: '145000 voti'), 'TVDB');
    });

    test('reads a raw -arr source key in any spelling', () {
      expect(
        ratingSourceLabel(icon: 'rottenTomatoes', name: 'rottenTomatoes'),
        'Rotten Tomatoes',
      );
      expect(
        ratingSourceLabel(icon: 'rotten', name: 'rotten'),
        'Rotten Tomatoes',
      );
    });

    test('shows what the server said for a source it does not know', () {
      // Inventing a brand name for an unknown source would be worse than
      // repeating the server's own answer.
      expect(ratingSourceLabel(icon: 'LE', name: 'LETTERBOXD'), 'LE');
    });
  });

  group('ratingDisplayFor', () {
    ({String value, String denominator}) display(String icon, double value) =>
        ratingDisplayFor(icon: icon, name: icon, value: value);

    test('states the scale each source actually measures on', () {
      // The five-pill row used to read `8.4  8.1  53.0  57.0  7.1` — five numbers
      // presented identically on three different scales.
      expect(display('IMDb', 6.9), (value: '6.9', denominator: '/10'));
      expect(display('Metacritic', 53), (value: '53', denominator: '/100'));
      expect(display('Rotten Tomatoes', 57), (value: '57', denominator: '%'));
      expect(display('Trakt', 7.1), (value: '7.1', denominator: '/10'));
      expect(display('MusicBrainz', 8.1), (value: '8.1', denominator: '/10'));
    });

    test('drops the decimal place on an integer scale', () {
      // `53.0` is most of why a Metacritic score read as comparable to an 8.4.
      expect(display('MC', 53).value, '53');
      expect(display('RT', 57).value, '57');
      expect(display('MC', 53).value, isNot(contains('.')));
    });

    test('keeps the decimal place on a ten-point scale', () {
      expect(display('IMDb', 7.0).value, '7.0');
    });

    test('resolves the scale through the badge as well as the name', () {
      // `MC`/`RO`/`TR` are what the -arr parser's default branch produces.
      expect(ratingDisplayFor(icon: 'RO', name: '145000 votes', value: 57), (
        value: '57',
        denominator: '%',
      ));
    });

    test('asserts no scale for a source it does not know', () {
      // Better to show what the server said than to claim a scale for it.
      expect(display('letterboxd', 3.8), (value: '3.8', denominator: ''));
    });
  });
}
