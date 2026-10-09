/// What finished today and what the last seven days held: Finished today,
/// the day sections of History, and the line each record says beside its
/// time.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/activity/domain/activity_history.dart';
import 'package:cupola/features/services/domain/arr_import.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Friday 9 October 2026, 20:00, on this device's clock.
final _now = DateTime(2026, 10, 9, 20);

ArrHistoryEntry _entry(
  int id, {
  DateTime? at,
  ArrImportOutcome outcome = ArrImportOutcome.imported,
  ServiceKey service = ServiceKey.radarr,
}) => ArrHistoryEntry(
  service: service,
  id: id,
  mediaId: id,
  title: 'Title $id',
  unitId: null,
  detail: null,
  posterUrl: '',
  outcome: outcome,
  at: at,
  reason: null,
);

List<int> _ids(Iterable<ArrHistoryEntry> entries) => [
  for (final entry in entries) entry.id,
];

void main() {
  group('finishedTodayOf', () {
    test('the imports of today, newest first', () {
      final today = finishedTodayOf([
        _entry(1, at: DateTime(2026, 10, 9, 9)),
        _entry(2, at: DateTime(2026, 10, 9, 18, 52)),
        _entry(3, at: DateTime(2026, 10, 9, 12)),
      ], now: _now);

      expect(_ids(today), [2, 3, 1]);
    });

    test('not another day, not a failure, not an event of no outcome, not a '
        'record without a date', () {
      final today = finishedTodayOf([
        _entry(1, at: DateTime(2026, 10, 8, 23, 59)),
        _entry(2, at: DateTime(2026, 10, 10, 0, 1)),
        _entry(
          3,
          at: DateTime(2026, 10, 9, 10),
          outcome: ArrImportOutcome.failed,
        ),
        _entry(
          4,
          at: DateTime(2026, 10, 9, 11),
          outcome: ArrImportOutcome.other,
        ),
        _entry(5),
        _entry(6, at: DateTime(2026, 10, 9, 0, 0)),
      ], now: _now);

      expect(_ids(today), [6]);
    });

    test('a day is the device\'s: a moment in UTC counts on the day it falls '
        'on here', () {
      final utc = DateTime.utc(2026, 10, 9, 12);
      final today = finishedTodayOf([_entry(1, at: utc)], now: _now);

      expect(_ids(today), utc.toLocal().day == _now.day ? [1] : isEmpty);
    });

    test('nothing in, nothing out', () {
      expect(finishedTodayOf(const [], now: _now), isEmpty);
    });
  });

  group('lastImportOf', () {
    test('the newest import, whatever order they come in', () {
      expect(
        lastImportOf([
          _entry(1, at: DateTime(2026, 10, 7, 9)),
          _entry(2, at: DateTime(2026, 10, 9, 18, 52)),
          _entry(3, at: DateTime(2026, 10, 8, 9)),
        ]),
        DateTime(2026, 10, 9, 18, 52),
      );
    });

    test('a failure, another event and an undated record do not count', () {
      expect(
        lastImportOf([
          _entry(
            1,
            at: DateTime(2026, 10, 9, 19),
            outcome: ArrImportOutcome.failed,
          ),
          _entry(
            2,
            at: DateTime(2026, 10, 9, 19),
            outcome: ArrImportOutcome.other,
          ),
          _entry(3),
          _entry(4, at: DateTime(2026, 10, 6, 8)),
        ]),
        DateTime(2026, 10, 6, 8),
      );
    });

    test('with no import there is no moment', () {
      expect(lastImportOf(const []), isNull);
      expect(
        lastImportOf([
          _entry(
            1,
            at: DateTime(2026, 10, 9, 19),
            outcome: ArrImportOutcome.failed,
          ),
          _entry(2),
        ]),
        isNull,
      );
    });
  });

  group('activityDaysOf', () {
    test('a section a day, the newest day first, each day\'s newest record '
        'first', () {
      final days = activityDaysOf([
        _entry(1, at: DateTime(2026, 10, 8, 9)),
        _entry(2, at: DateTime(2026, 10, 9, 8)),
        _entry(3, at: DateTime(2026, 10, 6, 22)),
        _entry(4, at: DateTime(2026, 10, 9, 18)),
        _entry(
          5,
          at: DateTime(2026, 10, 8, 20),
          outcome: ArrImportOutcome.failed,
        ),
      ], now: _now);

      expect(
        [for (final day in days) day.day],
        [DateTime(2026, 10, 9), DateTime(2026, 10, 8), DateTime(2026, 10, 6)],
      );
      expect(
        [for (final day in days) _ids(day.entries)],
        [
          [4, 2],
          [5, 1],
          [3],
        ],
      );
    });

    test('imports and failures share a day; another event has none', () {
      final days = activityDaysOf([
        _entry(1, at: DateTime(2026, 10, 9, 9)),
        _entry(
          2,
          at: DateTime(2026, 10, 9, 10),
          outcome: ArrImportOutcome.failed,
        ),
        _entry(
          3,
          at: DateTime(2026, 10, 9, 11),
          outcome: ArrImportOutcome.other,
        ),
      ], now: _now);

      expect(_ids(days.single.entries), [2, 1]);
    });

    test('a record with no date has no day', () {
      expect(activityDaysOf([_entry(1)], now: _now), isEmpty);
    });

    test('older than the window is left out: a server that ignored it', () {
      final since = DateTime(2026, 10, 2, 20);
      final days = activityDaysOf(
        [
          _entry(1, at: DateTime(2026, 10, 2, 19, 59)),
          _entry(2, at: DateTime(2026, 10, 2, 20)),
          _entry(3, at: DateTime(2026, 9, 1)),
        ],
        now: _now,
        since: since,
      );

      expect(_ids(days.expand((day) => day.entries)), [2]);
    });

    test('without a window nothing is too old', () {
      final days = activityDaysOf([
        _entry(1, at: DateTime(2025, 12, 24, 9)),
      ], now: _now);

      expect(days.single.label, 'Wed 24 Dec 2025');
    });

    test('a record ahead of the clock is today\'s, not a day of its own', () {
      final days = activityDaysOf([
        _entry(1, at: DateTime(2026, 10, 9, 18)),
        _entry(2, at: DateTime(2026, 10, 12, 9)),
      ], now: _now);

      expect(days, hasLength(1));
      expect(days.single.label, 'Today');
      expect(days.single.day, DateTime(2026, 10, 9));
      expect(_ids(days.single.entries), [2, 1]);
    });

    test('each day carries its label', () {
      final days = activityDaysOf([
        _entry(1, at: DateTime(2026, 10, 9, 9)),
        _entry(2, at: DateTime(2026, 10, 8, 9)),
        _entry(3, at: DateTime(2026, 10, 6, 9)),
      ], now: _now);

      expect(
        [for (final day in days) day.label],
        ['Today', 'Yesterday', 'Tue 6 Oct'],
      );
    });

    test('nothing in, no days', () {
      expect(activityDaysOf(const [], now: _now), isEmpty);
    });
  });

  group('activityDayLabel', () {
    test('today, yesterday, then the date as the app says dates', () {
      expect(activityDayLabel(DateTime(2026, 10, 9), now: _now), 'Today');
      expect(
        activityDayLabel(DateTime(2026, 10, 9, 23, 59), now: _now),
        'Today',
      );
      expect(activityDayLabel(DateTime(2026, 10, 8), now: _now), 'Yesterday');
      expect(
        activityDayLabel(DateTime(2026, 10, 8, 23, 59), now: _now),
        'Yesterday',
      );
      expect(activityDayLabel(DateTime(2026, 10, 7), now: _now), 'Wed 7 Oct');
      expect(activityDayLabel(DateTime(2026, 10, 3), now: _now), 'Sat 3 Oct');
    });

    test('a year only when it is another one', () {
      expect(
        activityDayLabel(DateTime(2025, 12, 24), now: _now),
        'Wed 24 Dec 2025',
      );
      expect(activityDayLabel(DateTime(2026, 1, 1), now: _now), 'Thu 1 Jan');
    });

    test('a day ahead is today', () {
      expect(activityDayLabel(DateTime(2026, 10, 12), now: _now), 'Today');
    });
  });

  group('historyEventLine', () {
    test('what happened beside when, on the 24 hour clock', () {
      expect(
        historyEventLine(_entry(1, at: DateTime(2026, 10, 9, 18, 52))),
        'Imported 18:52',
      );
      expect(
        historyEventLine(
          _entry(
            2,
            at: DateTime(2026, 10, 9, 14, 2),
            outcome: ArrImportOutcome.failed,
          ),
        ),
        'Download failed 14:02',
      );
      expect(
        historyEventLine(
          _entry(
            3,
            at: DateTime(2026, 10, 9, 9, 5),
            outcome: ArrImportOutcome.other,
          ),
        ),
        'Recorded 09:05',
      );
    });

    test('with no time the word alone', () {
      expect(historyEventLine(_entry(1)), 'Imported');
      expect(
        historyEventLine(_entry(2, outcome: ArrImportOutcome.failed)),
        'Download failed',
      );
      expect(
        historyEventLine(_entry(3, outcome: ArrImportOutcome.other)),
        'Recorded',
      );
    });
  });
}
