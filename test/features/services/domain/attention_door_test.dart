import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/services/domain/attention_door.dart';
import 'package:cupola/features/services/domain/service_tab.dart';

/// The two pure pieces every Overview folds its faults with, and the door a
/// folded row leads through.
void main() {
  group('AttentionDoor', () {
    test(
      'two doors to the same place are equal, so a fold can be asserted',
      () {
        expect(
          const AttentionDoor.tab(ServiceTab.indexers),
          const AttentionDoor.tab(ServiceTab.indexers),
        );
        expect(
          const AttentionDoor.tab(ServiceTab.indexers),
          isNot(const AttentionDoor.tab(ServiceTab.history)),
        );
        expect(
          const AttentionDoor.download(instanceId: 'qb', key: 'abc'),
          const AttentionDoor.download(instanceId: 'qb', key: 'abc'),
        );
        expect(
          const AttentionDoor.download(instanceId: 'qb', key: 'abc'),
          isNot(const AttentionDoor.download(instanceId: 'qb', key: 'abd')),
        );
        expect(
          const AttentionDoor.page(location: '/a', hint: 'opens a'),
          const AttentionDoor.page(location: '/a', hint: 'opens a'),
        );
      },
    );
  });

  group('attentionNames', () {
    test('spells out up to three and counts the rest', () {
      expect(attentionNames(['Nyaa']), 'Nyaa');
      expect(
        attentionNames(['Nyaa', '1337x', 'Bitsearch']),
        'Nyaa, 1337x, Bitsearch',
      );
      expect(
        attentionNames(['Nyaa', '1337x', 'Bitsearch', 'RARBG', 'Tor']),
        'Nyaa, 1337x, Bitsearch and 2 more',
      );
    });

    test('says a repeated name once and skips an empty one', () {
      expect(
        attentionNames(['Nyaa', ' Nyaa ', '', '  ', '1337x']),
        'Nyaa, 1337x',
      );
      // The cut is over the distinct names, not the rows they came from.
      expect(
        attentionNames(['a', 'a', 'a', 'b', 'c', 'd']),
        'a, b, c and 1 more',
      );
    });
  });

  group('attentionCount', () {
    test('a floor reads 50+, and is spoken as at least', () {
      expect(attentionCount(3), '3');
      expect(attentionCount(200, floor: true), '200+');
      expect(attentionCountSpoken(3), '3');
      expect(attentionCountSpoken(200, floor: true), 'at least 200');
    });
  });

  group('foldAttention', () {
    // A tiny stand-in for any service's row: a kind and a name.
    String fold(List<(String, String)> rows) =>
        foldAttention<(String, String), String>(
          rows,
          kindOf: (row) => row.$1,
          merge: (kind, members) => (kind, '${members.length} folded'),
        ).map((row) => '${row.$1}:${row.$2}').join(' | ');

    test('one of a kind keeps its own row', () {
      expect(fold([('stuck', 'a'), ('failed', 'b')]), 'stuck:a | failed:b');
    });

    test('several of a kind become one row, in the place of the first', () {
      expect(
        fold([('stuck', 'a'), ('failed', 'b'), ('stuck', 'c'), ('stuck', 'd')]),
        'stuck:3 folded | failed:b',
      );
    });

    test('each kind folds on its own', () {
      expect(
        fold([
          ('stuck', 'a'),
          ('failed', 'b'),
          ('stuck', 'c'),
          ('failed', 'd'),
        ]),
        'stuck:2 folded | failed:2 folded',
      );
    });

    test('an empty list folds to an empty list', () {
      expect(fold(const []), '');
    });

    test('members about the same thing count once, so a kind of one thing '
        'keeps its own row', () {
      String foldBy(List<(String, String)> rows) =>
          foldAttention<(String, String), String>(
            rows,
            kindOf: (row) => row.$1,
            identityOf: (row) => row.$2,
            merge: (kind, members) => (kind, '${members.length} folded'),
          ).map((row) => '${row.$1}:${row.$2}').join(' | ');

      // Two records of one download: one fault, its own row, the first record.
      expect(foldBy([('stuck', 'a'), ('stuck', 'a')]), 'stuck:a');
      // Two of three are one thing: two faults.
      expect(
        foldBy([('stuck', 'a'), ('stuck', 'b'), ('stuck', 'a')]),
        'stuck:2 folded',
      );
      // The same identity under another kind is another fault.
      expect(foldBy([('stuck', 'a'), ('failed', 'a')]), 'stuck:a | failed:a');
    });
  });

  group('the words of a folded row', () {
    test('stuck downloads and failed imports, with a floor spoken aloud', () {
      expect(stuckDownloadsWords(3).headline, '3 downloads stuck');
      expect(stuckDownloadsWords(3).spoken, '3 downloads stuck');
      expect(
        stuckDownloadsWords(50, floor: true).headline,
        '50+ downloads stuck',
      );
      expect(
        stuckDownloadsWords(50, floor: true).spoken,
        'at least 50 downloads stuck',
      );
      expect(failedImportsWords(2).headline, '2 imports failed');
      expect(
        failedImportsWords(2, floor: true).spoken,
        'at least 2 imports failed',
      );
    });
  });

  group('an arr queue record as a download', () {
    test('is named by the client\'s id, else by its own', () {
      expect(
        arrQueueRecordDownloadKey({'id': 4, 'downloadId': ' ABC '}),
        'ABC',
      );
      expect(arrQueueRecordDownloadKey({'id': 4, 'downloadId': ' '}), '4');
      expect(arrQueueRecordDownloadKey({'id': 4}), '4');
    });

    test('with neither an id nor a client id has no page', () {
      expect(arrQueueRecordDownloadKey(const {}), isNull);
      expect(arrQueueRecordDownloadKey({'id': 0}), isNull);
      expect(arrQueueRecordDoor(const {}, instanceId: 'radarr'), isNull);
    });

    test('opens on the connection that read it', () {
      expect(
        arrQueueRecordDoor({'id': 4}, instanceId: 'radarr'),
        const AttentionDoor.download(instanceId: 'radarr', key: '4'),
      );
    });
  });
}
