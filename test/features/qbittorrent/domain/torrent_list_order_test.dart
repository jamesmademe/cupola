import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/qbittorrent/domain/models/torrent.dart';
import 'package:cupola/features/qbittorrent/domain/torrent_list_order.dart';

Torrent _t(
  String hash, {
  String name = 'A',
  String state = 'downloading',
  int size = 0,
  int addedOn = 0,
  int eta = 0,
}) => Torrent.fromJson({
  'hash': hash,
  'name': name,
  'state': state,
  'size': size,
  'added_on': addedOn,
  'eta': eta,
});

List<String> _hashes(Iterable<Torrent> torrents) => [
  for (final t in torrents) t.hash,
];

void main() {
  group('a tab holds what the same tab holds in qBittorrent', () {
    // Every state qBittorrent 4.x and 5.x report, and the tabs of its own
    // WebUI each lands in.
    const states = {
      'downloading': {TorrentFilter.downloading},
      'forcedDL': {TorrentFilter.downloading},
      'metaDL': {TorrentFilter.downloading},
      'forcedMetaDL': {TorrentFilter.downloading},
      'stalledDL': {TorrentFilter.downloading},
      'checkingDL': {TorrentFilter.downloading},
      'queuedDL': {TorrentFilter.downloading, TorrentFilter.queued},
      'pausedDL': {TorrentFilter.downloading, TorrentFilter.paused},
      'stoppedDL': {TorrentFilter.downloading, TorrentFilter.paused},
      'uploading': {TorrentFilter.seeding, TorrentFilter.completed},
      'forcedUP': {TorrentFilter.seeding, TorrentFilter.completed},
      'stalledUP': {TorrentFilter.seeding, TorrentFilter.completed},
      'checkingUP': {TorrentFilter.seeding, TorrentFilter.completed},
      'queuedUP': {
        TorrentFilter.seeding,
        TorrentFilter.completed,
        TorrentFilter.queued,
      },
      'pausedUP': {TorrentFilter.completed, TorrentFilter.paused},
      'stoppedUP': {TorrentFilter.completed, TorrentFilter.paused},
      'error': <TorrentFilter>{},
      'missingFiles': <TorrentFilter>{},
      'moving': <TorrentFilter>{},
    };

    for (final MapEntry(key: state, value: tabs) in states.entries) {
      test(state, () {
        final torrent = _t('x', state: state);
        for (final filter in TorrentFilter.values) {
          final expected = filter == TorrentFilter.all || tabs.contains(filter);
          expect(torrentMatches(torrent, filter), expected, reason: '$filter');
        }
      });
    }
  });

  group('the order', () {
    test('largest first when reversed, smallest first when not', () {
      final torrents = [_t('a', size: 2), _t('b', size: 9), _t('c', size: 5)];

      expect(_hashes(sortTorrents(torrents, TorrentSort.size, reverse: true)), [
        'b',
        'c',
        'a',
      ]);
      expect(
        _hashes(sortTorrents(torrents, TorrentSort.size, reverse: false)),
        ['a', 'c', 'b'],
      );
    });

    test('ties keep one order, so equal rows do not trade places', () {
      final torrents = [
        _t('b2', name: 'Beta'),
        _t('a1', name: 'Alpha'),
        _t('b1', name: 'Beta'),
      ];

      for (final reverse in [true, false]) {
        expect(
          _hashes(sortTorrents(torrents, TorrentSort.size, reverse: reverse)),
          ['a1', 'b1', 'b2'],
        );
      }
    });

    test('newest first is the latest added', () {
      final torrents = [_t('old', addedOn: 10), _t('new', addedOn: 99)];

      expect(
        _hashes(sortTorrents(torrents, TorrentSort.addedOn, reverse: true)),
        ['new', 'old'],
      );
    });

    test('an ETA that never ends sorts after every real one', () {
      final torrents = [_t('never', eta: 8640000), _t('soon', eta: 60)];

      expect(_hashes(sortTorrents(torrents, TorrentSort.eta, reverse: false)), [
        'soon',
        'never',
      ]);
    });
  });

  group('names read as a person reads them', () {
    test('a run of digits by its value', () {
      expect(compareNatural('Episode 9', 'Episode 10'), isNegative);
      expect(compareNatural('S02E10', 'S2E9'), isPositive);
      expect(compareNatural('file007', 'file7'), 0);
    });

    test('letters without regard to case', () {
      expect(compareNatural('alpha', 'Beta'), isNegative);
      expect(compareNatural('Ubuntu', 'ubuntu'), 0);
    });

    test('a name that is a prefix of another comes first', () {
      expect(compareNatural('Sintel', 'Sintel 4K'), isNegative);
    });

    test('a run of digits longer than any int', () {
      expect(
        compareNatural('a 123456789012345678901', 'a 99999999999999999999'),
        isPositive,
      );
    });
  });
}
