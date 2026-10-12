/// What finished today and what the last seven days held, in the words of
/// Activity's Finished today and History.
library;

import 'package:cupola/core/utils/date_format.dart';
import 'package:cupola/features/services/domain/arr_import.dart';
import 'package:cupola/features/services/presentation/services_provider.dart'
    show ArrHistoryEntry;

/// One day of History: its name and its records, newest first.
typedef ActivityDay = ({
  DateTime day,
  String label,
  List<ArrHistoryEntry> entries,
});

/// The imports of [now]'s day, newest first: Finished today.
List<ArrHistoryEntry> finishedTodayOf(
  Iterable<ArrHistoryEntry> entries, {
  required DateTime now,
}) {
  final today = _dayOf(now);
  return _newestFirst([
    for (final entry in entries)
      if (entry.outcome == ArrImportOutcome.imported &&
          entry.at != null &&
          _dayOf(entry.at!.toLocal()) == today)
        entry,
  ]);
}

/// When the newest import of [entries] landed, or null with none.
DateTime? lastImportOf(Iterable<ArrHistoryEntry> entries) {
  DateTime? last;
  for (final entry in entries) {
    if (entry.outcome != ArrImportOutcome.imported) continue;
    final at = entry.at;
    if (at != null && (last == null || at.isAfter(last))) last = at;
  }
  return last;
}

/// [entries] by the day they happened, newest day first, each day's newest
/// record first. A record with no date has no day and is left out, and so is
/// one older than [since] (a server that ignored the window); one in the
/// future (a clock ahead of the server's) is today's.
List<ActivityDay> activityDaysOf(
  Iterable<ArrHistoryEntry> entries, {
  required DateTime now,
  DateTime? since,
}) {
  final today = _dayOf(now);
  final days = <DateTime, List<ArrHistoryEntry>>{};
  for (final entry in entries) {
    final at = entry.at;
    if (at == null || entry.outcome == ArrImportOutcome.other) continue;
    if (since != null && at.isBefore(since)) continue;
    var day = _dayOf(at.toLocal());
    if (day.isAfter(today)) day = today;
    (days[day] ??= []).add(entry);
  }
  final order = days.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final day in order)
      (
        day: day,
        label: activityDayLabel(day, now: now),
        entries: _newestFirst(days[day]!),
      ),
  ];
}

/// A day of History by name: `Today`, `Yesterday`, then `Tue 6 Oct`.
String activityDayLabel(DateTime day, {required DateTime now}) {
  final days = calendarDaysBetween(day, now);
  if (days <= 0) return 'Today';
  if (days == 1) return 'Yesterday';
  return formatShortDate(_dayOf(day).toIso8601String(), now: now);
}

/// What a record says beside its time: `Imported 18:52`, `Download failed
/// 14:02`.
String historyEventLine(ArrHistoryEntry entry) {
  final at = entry.at;
  final time = at == null ? null : formatClockTime(at);
  final word = switch (entry.outcome) {
    ArrImportOutcome.imported => 'Imported',
    ArrImportOutcome.failed => 'Download failed',
    ArrImportOutcome.other => 'Recorded',
  };
  return time == null ? word : '$word $time';
}

DateTime _dayOf(DateTime at) => DateTime(at.year, at.month, at.day);

List<ArrHistoryEntry> _newestFirst(List<ArrHistoryEntry> entries) =>
    entries..sort((a, b) {
      final at = a.at;
      final bt = b.at;
      if (at == null || bt == null) return 0;
      return bt.compareTo(at);
    });
