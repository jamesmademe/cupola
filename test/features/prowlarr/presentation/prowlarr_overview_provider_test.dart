import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/prowlarr/domain/models/prowlarr_models.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_overview_provider.dart';

void main() {
  final now = DateTime(2026, 9, 16, 15, 0);

  group('prowlarrDisabledLabel', () {
    test('a block still in force names the hour it lifts', () {
      expect(
        prowlarrDisabledLabel(
          DateTime(2026, 9, 16, 15, 40).toIso8601String(),
          now: now,
        ),
        'disabled until 15:40',
      );
    });

    test('the boundary is the instant it lifts, not a minute either side', () {
      // One second before: still disabled.
      expect(
        prowlarrDisabledLabel(
          now.add(const Duration(seconds: 1)).toIso8601String(),
          now: now,
        ),
        'disabled until 15:00',
      );
      // Exactly now, and after: Prowlarr has already gone back to it.
      expect(
        prowlarrDisabledLabel(now.toIso8601String(), now: now),
        'retrying now',
      );
      expect(
        prowlarrDisabledLabel(
          now.subtract(const Duration(seconds: 1)).toIso8601String(),
          now: now,
        ),
        'retrying now',
      );
    });

    test('an absent or unreadable block says nothing at all', () {
      expect(prowlarrDisabledLabel(null, now: now), isNull);
      expect(prowlarrDisabledLabel('', now: now), isNull);
      expect(prowlarrDisabledLabel('not a date', now: now), isNull);
    });
  });

  group('prowlarrIndexerFaultRows', () {
    test('a failing indexer is AMBER — red is for a Prowlarr that is dark', () {
      final rows = prowlarrIndexerFaultRows(
        [
          ProwlarrIndexerStatus(
            indexerId: 4,
            disabledTill: DateTime(2026, 9, 16, 15, 40).toIso8601String(),
            mostRecentFailure: now
                .subtract(const Duration(minutes: 12))
                .toIso8601String(),
          ),
        ],
        const [ProwlarrIndexer(id: 4, name: 'Nyaa')],
        now: now,
      );

      final row = rows.single;
      expect(row.tone, StatusTone.warning);
      expect(row.headline, 'Nyaa');
      expect(
        row.detail,
        'failing · disabled until 15:40 · last failed 12\u00A0min ago',
      );
      expect(
        row.spoken,
        'Nyaa, failing, disabled until 15:40, last failed 12\u00A0min ago',
      );
    });

    test('an indexer the list does not name is still identified', () {
      final rows = prowlarrIndexerFaultRows(
        const [ProwlarrIndexerStatus(indexerId: 7)],
        const [],
        now: now,
      );
      expect(rows.single.headline, 'Indexer 7');
    });
  });

  group('prowlarrNeedsAttention', () {
    test('drops the health checks the indexer rows already say', () {
      final section = prowlarrNeedsAttention(
        const [ProwlarrIndexerStatus(indexerId: 4)],
        const [ProwlarrIndexer(id: 4, name: 'Nyaa')],
        const [
          ProwlarrHealthIssue(
            source: 'IndexerStatusCheck',
            type: 'warning',
            message: 'Indexers unavailable due to failures: Nyaa',
          ),
          ProwlarrHealthIssue(
            source: 'ApplicationLongTermStatusCheck',
            type: 'error',
            message: 'Applications unavailable: Lidarr',
          ),
        ],
        now: now,
      );

      expect(section.total, 2);
      expect(section.rows.map((row) => row.headline), [
        'Nyaa',
        'ApplicationLongTermStatusCheck',
      ]);
      // Amber throughout — nothing on this page paints red.
      expect(
        section.rows.every((row) => row.tone == StatusTone.warning),
        isTrue,
      );
    });
  });

  group('prowlarrIndexerRows', () {
    test('sorted by the window\'s queries, busiest first', () {
      final section = prowlarrIndexerRows(
        const [
          ProwlarrIndexer(id: 1, name: 'Quiet', enable: true),
          ProwlarrIndexer(id: 2, name: 'Busy', enable: true),
        ],
        const ProwlarrIndexerStats(
          indexers: [
            ProwlarrIndexerStat(indexerId: 1, numberOfQueries: 60),
            ProwlarrIndexerStat(indexerId: 2, numberOfQueries: 298),
          ],
        ),
        const [],
      );

      expect(section.rows.map((row) => row.headline), ['Busy', 'Quiet']);
      expect(section.rows.first.trailing, '298 queries');
      expect(section.total, 2);
    });

    test('an indexer with no sample in the window reads —, never 0 ms', () {
      final section = prowlarrIndexerRows(
        const [
          ProwlarrIndexer(
            id: 1,
            name: 'Idle',
            enable: true,
            protocol: 'torrent',
            privacy: 'private',
          ),
        ],
        const ProwlarrIndexerStats(),
        const [],
      );

      final row = section.rows.single;
      expect(row.detail, 'torrent · private · —');
      expect(row.trailing, '—');
      expect(row.detail, isNot(contains('0\u00A0ms')));
    });

    test('a failing indexer is amber, a healthy one neutral', () {
      final section = prowlarrIndexerRows(
        const [
          ProwlarrIndexer(id: 1, name: 'Broken', enable: true),
          ProwlarrIndexer(id: 2, name: 'Fine', enable: true),
        ],
        const ProwlarrIndexerStats(
          indexers: [
            ProwlarrIndexerStat(
              indexerId: 1,
              numberOfQueries: 10,
              averageResponseTime: 1900,
            ),
            ProwlarrIndexerStat(
              indexerId: 2,
              numberOfQueries: 10,
              averageResponseTime: 210,
            ),
          ],
        ),
        const [ProwlarrIndexerStatus(indexerId: 1)],
      );

      final broken = section.rows.firstWhere((r) => r.headline == 'Broken');
      final fine = section.rows.firstWhere((r) => r.headline == 'Fine');
      expect(broken.tone, StatusTone.warning);
      expect(broken.detail, contains('failing'));
      expect(fine.tone, StatusTone.neutral);
    });

    test('a deliberately disabled indexer is stated, not flagged', () {
      final section = prowlarrIndexerRows(
        const [ProwlarrIndexer(id: 1, name: 'Parked', enable: false)],
        const ProwlarrIndexerStats(),
        const [],
      );
      expect(section.rows.single.detail, contains('disabled'));
      expect(section.rows.single.tone, StatusTone.neutral);
    });

    test('the total counts every indexer, the rows stop at the limit', () {
      final section = prowlarrIndexerRows(
        [for (var i = 0; i < 14; i++) ProwlarrIndexer(id: i, name: 'I$i')],
        const ProwlarrIndexerStats(),
        const [],
        limit: 6,
      );
      expect(section.rows, hasLength(6));
      expect(section.total, 14);
    });
  });

  group('prowlarrRecentRows', () {
    test('a grab is green, a refused query is amber, never red', () {
      final rows = prowlarrRecentRows([
        ProwlarrHistoryItem(
          id: 1,
          eventType: 'releaseGrabbed',
          successful: true,
          date: now.subtract(const Duration(minutes: 4)).toIso8601String(),
          data: const {'source': 'TorrentLeech'},
        ),
        ProwlarrHistoryItem(
          id: 2,
          eventType: 'indexerQuery',
          successful: false,
          date: now.subtract(const Duration(minutes: 12)).toIso8601String(),
          data: const {'query': 'Severance'},
        ),
      ], now: now);

      expect(rows.first.tone, StatusTone.success);
      expect(rows.first.detail, 'TorrentLeech · 4\u00A0min ago');
      expect(rows.last.tone, StatusTone.warning);
      expect(rows.last.headline, 'Severance · query failed');
    });

    test('cuts at the preview limit', () {
      final rows = prowlarrRecentRows(
        [
          for (var i = 0; i < 9; i++)
            ProwlarrHistoryItem(
              id: i,
              eventType: 'indexerQuery',
              successful: true,
            ),
        ],
        now: now,
        limit: 3,
      );
      expect(rows, hasLength(3));
    });
  });
}
