import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/utils/arr_overview.dart';

void main() {
  group('isStalledRecord', () {
    test('reads the substring in the error or the status', () {
      expect(
        isStalledRecord({'errorMessage': 'The download is stalled'}),
        isTrue,
      );
      expect(isStalledRecord({'status': 'Stalled'}), isTrue);
      expect(isStalledRecord({'status': 'downloading'}), isFalse);
    });
  });

  group('isImportFaultRecord', () {
    test('a failed import is one, a healthy one is not', () {
      expect(
        isImportFaultRecord({'trackedDownloadState': 'importFailed'}),
        isTrue,
      );
      expect(
        isImportFaultRecord({'trackedDownloadState': 'importing'}),
        isFalse,
      );
      expect(isImportFaultRecord({}), isFalse);
    });
  });

  group('historyRecordBytes', () {
    test('a size that is not one is none', () {
      expect(historyRecordBytes({'size': 0}), isNull);
      expect(
        historyRecordBytes({
          'data': {'size': 2048},
        }),
        2048,
      );
    });
  });

  group('overviewHistoryToday', () {
    final now = DateTime(2026, 9, 16, 12);
    Map<String, dynamic> record(DateTime date, String name) => {
      'eventType': 'grabbed',
      'date': date.toUtc().toIso8601String(),
      'name': name,
    };

    test('keeps the local day, newest first, capped, by the given subject', () {
      final entries = overviewHistoryToday(
        [
          record(DateTime(2026, 9, 15, 23, 50), 'yesterday'),
          record(DateTime(2026, 9, 16, 8), 'early'),
          record(DateTime(2026, 9, 16, 11), 'late'),
        ],
        now: now,
        limit: 1,
        subjectOf: (record) => record['name'] as String,
      );
      expect(entries.map((e) => e.subject), ['late']);
      expect(entries.single.tone, StatusTone.neutral);
    });

    test('a record with no date, or not a map, is skipped', () {
      expect(
        overviewHistoryToday(
          [
            {'eventType': 'grabbed'},
            'nope',
          ],
          now: now,
          limit: 3,
          subjectOf: (_) => 'x',
        ),
        isEmpty,
      );
    });
  });
}
