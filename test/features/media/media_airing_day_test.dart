/// The day a card or a graph row says the next episode airs: `Today`,
/// `Tomorrow`, the weekday within the week, the date beyond it.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/media/domain/media_series.dart';
import 'package:cupola/features/media/presentation/media_series_sections.dart';

void main() {
  // Monday 12 Oct 2026, mid-afternoon.
  final now = DateTime(2026, 10, 12, 15);

  MediaNextAiring airing(DateTime at, {bool timed = false}) =>
      MediaNextAiring(season: 2, number: 3, at: at, timed: timed);

  group('mediaAiringDay', () {
    test('says Today for a day that is today or already past', () {
      expect(mediaAiringDay(airing(DateTime(2026, 10, 12)), now), 'Today');
      expect(mediaAiringDay(airing(DateTime(2026, 10, 10)), now), 'Today');
    });

    test('says Tomorrow for the next calendar day', () {
      expect(mediaAiringDay(airing(DateTime(2026, 10, 13)), now), 'Tomorrow');
    });

    test('names the weekday alone within the week', () {
      expect(mediaAiringDay(airing(DateTime(2026, 10, 14)), now), 'Wed');
      expect(mediaAiringDay(airing(DateTime(2026, 10, 18)), now), 'Sun');
    });

    test('names the date from a week on, with the year only in another', () {
      expect(mediaAiringDay(airing(DateTime(2026, 10, 19)), now), '19 Oct');
      expect(mediaAiringDay(airing(DateTime(2026, 12, 3)), now), '3 Dec');
      expect(mediaAiringDay(airing(DateTime(2027, 1, 7)), now), '7 Jan 2027');
    });

    test('puts a timed instant on the device\'s day', () {
      final local = DateTime(2026, 10, 14, 21, 30);
      expect(
        mediaAiringDay(airing(local.toUtc(), timed: true), now),
        mediaAiringDay(airing(local), now),
      );
      expect(mediaAiringDay(airing(local.toUtc(), timed: true), now), 'Wed');
    });
  });
}
