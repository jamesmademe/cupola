import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/services/domain/recently_added.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

RecentlyAddedItem _item(
  String title, {
  String? added,
  ServiceKey service = ServiceKey.radarr,
  int id = 1,
}) => RecentlyAddedItem(
  service: service,
  id: id,
  title: title,
  posterUrl: '',
  addedAt: parseAddedTimestamp(added),
);

void main() {
  group('parseAddedTimestamp', () {
    test('parses the ISO 8601 string the arr APIs return', () {
      expect(
        parseAddedTimestamp('2024-03-14T09:26:53Z'),
        DateTime.utc(2024, 3, 14, 9, 26, 53),
      );
    });

    test('returns null for absent, blank or unparseable values', () {
      // Null rather than the epoch: a bad timestamp must not sort an item to the
      // top of a "newest first" rail, and must not take the rail down either.
      expect(parseAddedTimestamp(null), isNull);
      expect(parseAddedTimestamp(''), isNull);
      expect(parseAddedTimestamp('   '), isNull);
      expect(parseAddedTimestamp('not a date'), isNull);
    });
  });

  group('sortRecentlyAdded', () {
    test('orders newest first across services', () {
      // The bug this exists to fix: the two rails it replaced took the first
      // eight items of an unsorted full-library fetch and called them recent.
      final sorted = sortRecentlyAdded([
        _item('Oldest', added: '2023-01-01T00:00:00Z'),
        _item('Newest', added: '2024-06-01T00:00:00Z'),
        _item(
          'Middle',
          added: '2024-01-01T00:00:00Z',
          service: ServiceKey.sonarr,
        ),
      ], limit: 10);

      expect(sorted.map((item) => item.title), ['Newest', 'Middle', 'Oldest']);
    });

    test('sorts undated items last and drops them first at the limit', () {
      final sorted = sortRecentlyAdded([
        _item('No date'),
        _item('Dated', added: '2024-01-01T00:00:00Z'),
      ], limit: 1);

      expect(sorted.single.title, 'Dated');
    });

    test('caps at the limit', () {
      final sorted = sortRecentlyAdded([
        for (var index = 0; index < 30; index++)
          _item('Item $index', added: '2024-01-${(index % 28) + 1}T00:00:00Z'),
      ], limit: 12);

      expect(sorted, hasLength(12));
    });

    test('leaves the caller\'s list untouched', () {
      final input = [
        _item('Oldest', added: '2023-01-01T00:00:00Z'),
        _item('Newest', added: '2024-06-01T00:00:00Z'),
      ];

      sortRecentlyAdded(input, limit: 10);

      expect(input.first.title, 'Oldest');
    });

    test('hero tags are unique per service and id', () {
      // Two libraries can hold the same numeric id, and a collision would make
      // two posters try to fly to the same destination.
      final radarr = _item('A', service: ServiceKey.radarr, id: 7);
      final sonarr = _item('B', service: ServiceKey.sonarr, id: 7);

      expect(radarr.heroTag, isNot(sonarr.heroTag));
    });
  });

  group('groupRecentlyAdded', () {
    RecentlyAddedItem episode(
      String code, {
      int season = 1,
      int series = 4,
      String added = '2024-05-05T22:40:00Z',
      bool failed = false,
    }) => RecentlyAddedItem(
      service: ServiceKey.sonarr,
      id: series,
      title: "Marvel's Daredevil",
      posterUrl: '',
      addedAt: parseAddedTimestamp(added),
      failed: failed,
      unitId: season,
      detail: code,
    );

    test('folds one season into one row that counts its episodes', () {
      final rows = groupRecentlyAdded([
        episode('S01E01', added: '2024-05-05T22:39:00Z'),
        episode('S01E02', added: '2024-05-05T22:40:00Z'),
        episode('S01E03', added: '2024-05-05T22:39:30Z'),
      ]);

      expect(rows, hasLength(1));
      expect(rows.single.count, 3);
      expect(rows.single.subtitle, 'Season 1 · 3 episodes');
      expect(
        rows.single.addedAt,
        DateTime.utc(2024, 5, 5, 22, 40),
        reason: 'a folded row is as recent as its newest record',
      );
    });

    test('a lone episode keeps its code', () {
      final rows = groupRecentlyAdded([episode('S02E05', season: 2)]);
      expect(rows.single.subtitle, 'S02E05');
    });

    test('seasons, series and outcomes stay apart', () {
      final rows = groupRecentlyAdded([
        episode('S01E01'),
        episode('S02E01', season: 2),
        episode('S01E01', series: 9),
        episode('S01E02', failed: true),
      ]);

      expect(rows, hasLength(4));
      expect(
        rows.map((row) => row.heroTag).toSet(),
        hasLength(4),
        reason: 'two rows over one series must not share a hero',
      );
    });

    test('specials are named, not numbered', () {
      final rows = groupRecentlyAdded([
        episode('S00E01', season: 0),
        episode('S00E02', season: 0),
      ]);
      expect(rows.single.subtitle, 'Specials · 2 episodes');
    });

    test('an album folds its tracks under the artist', () {
      RecentlyAddedItem track() => const RecentlyAddedItem(
        service: ServiceKey.lidarr,
        id: 5,
        title: 'Diamond Jubilee',
        posterUrl: '',
        addedAt: null,
        unitId: 9,
        detail: 'Cindy Lee',
      );

      final rows = groupRecentlyAdded([track(), track(), track()]);
      expect(rows.single.subtitle, 'Cindy Lee · 3 tracks');
    });

    test('records that name no library item are never folded', () {
      final rows = groupRecentlyAdded([
        _item('Unknown.Release', id: 0),
        _item('Unknown.Release', id: 0),
      ]);
      expect(rows, hasLength(2));
    });

    test('the eyebrow counts records, not rows', () {
      final rows = groupRecentlyAdded([
        episode('S01E01'),
        episode('S01E02'),
        episode('S01E03', failed: true),
      ]);
      final counts = recentlyAddedEyebrow(rows);
      expect(counts.imported, '2 imported');
      expect(counts.failed, '1 failed');
    });
  });

  _theRegionsOwnStrings();
}

void _theRegionsOwnStrings() {
  group('the eyebrow', () {
    test('counts what landed and what did not, separately', () {
      final counts = recentlyAddedEyebrow([
        _imported('Poor Things', failed: false),
        _imported('Past Lives', failed: false),
        _imported('Nickel Boys', failed: true),
      ]);

      expect(counts.imported, '2 imported');
      expect(counts.failed, '1 failed');
    });

    test('says nothing about failures when there are none', () {
      // A permanent "0 failed" is a counter nobody reads on the day it moves.
      final counts = recentlyAddedEyebrow([
        _imported('Poor Things', failed: false),
      ]);
      expect(counts.failed, isNull);
    });
  });

  group('the tile', () {
    test(
      'is named title, service, time — the three a 60×90 box cannot show',
      () {
        expect(
          recentlyAddedTileLabel(
            _imported('Poor Things', failed: false),
            timeLabel: '08:12',
          ),
          'Poor Things, Radarr, 08:12',
        );
      },
    );

    test('a failed import says so in its name', () {
      expect(
        recentlyAddedTileLabel(
          _imported('Nickel Boys', failed: true),
          timeLabel: '06:58',
        ),
        contains('failed import'),
      );
    });

    test('an undated import has a name, not an empty slot', () {
      expect(
        recentlyAddedTileLabel(
          _imported('Poor Things', failed: false),
          timeLabel: '',
        ),
        'Poor Things, Radarr',
      );
    });
  });

  group('formatImportedAt', () {
    test('is time only, zero-padded', () {
      expect(formatImportedAt(DateTime(2024, 5, 5, 8, 12)), '08:12');
      expect(formatImportedAt(null), isEmpty);
    });
  });
}

RecentlyAddedItem _imported(String title, {required bool failed}) =>
    RecentlyAddedItem(
      service: ServiceKey.radarr,
      id: 1,
      title: title,
      posterUrl: '',
      addedAt: DateTime.utc(2024, 5, 5),
      failed: failed,
    );
