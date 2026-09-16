/// What the Radarr Overview reads, and the pure functions that shape it.
///
/// The Overview is the one tab that carries the identity block and the
/// readouts, so everything else on it is derived rather than fetched twice:
/// Coming up and Recently added both fall out of [moviesProvider], which the
/// KPI rail already loads, and Needs attention reads the *raw* queue records
/// rather than [ArrQueueSnapshot] — the snapshot collapses to one headline per
/// media id and drops the titles and timestamps the fault rows are made of.
///
/// Every windowing rule lives in a top-level pure function taking an explicit
/// `now`, so the boundaries are unit-testable without a clock or a container.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/core/utils/release_utils.dart';
import 'package:cupola/features/activity/domain/global_activity_status.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_formatters.dart'
    show formatRelativeDateTime;
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/movies/presentation/movies_provider.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';

/// How far ahead "Coming up" looks.
const int radarrComingUpDays = 7;

/// How many upcoming rows the section draws before the header's count is the
/// only place the rest are reported.
const int radarrComingUpPreviewLimit = 5;

/// Posters on the Recently added rail.
const int radarrRecentlyAddedLimit = 6;

/// One page of history, and deliberately only one.
///
/// `getAllHistory()` walks up to fifty pages of two hundred and fifty records
/// to answer a question about the last few hours.
const int radarrHistoryPageSize = 20;

/// Rows the History today section draws.
const int radarrHistoryTodayLimit = 3;

// ─── Coming up ──────────────────────────────────────────────────────────────

/// Which of a film's three dates an upcoming entry is about.
///
/// Radarr carries all three on the library row, so a film can legitimately
/// appear twice in one week — a digital release on Tuesday and a physical one
/// on Friday are two events, not one row that has to pick a winner.
enum RadarrReleaseKind {
  inCinemas('in cinemas'),
  digital('digital release'),
  physical('physical release');

  const RadarrReleaseKind(this.label);

  /// Sentence case, for the eye and for the ear alike.
  final String label;
}

/// One dated release inside the Coming up window.
@immutable
class RadarrUpcomingRelease {
  const RadarrUpcomingRelease({
    required this.movie,
    required this.date,
    required this.kind,
  });

  final RadarrMovie movie;

  /// Local time. The window is a run of local calendar days, so an entry
  /// compared in UTC would slip a day either side of midnight.
  final DateTime date;

  final RadarrReleaseKind kind;
}

/// The releases falling inside the next [days] local calendar days.
///
/// The window opens at local midnight **today** (inclusive) and closes at local
/// midnight [days] days later (exclusive): a film released earlier today is
/// still "coming up" — the user has not seen it on this screen yet — and one
/// dated exactly seven days out belongs to next week's window, not this one.
///
/// The end is built with `DateTime(y, m, d + days)` rather than
/// `start.add(Duration(days: days))`: a `Duration` is absolute, so across a DST
/// change the added form lands an hour off midnight and admits or drops the
/// boundary day by accident.
List<RadarrUpcomingRelease> radarrUpcomingReleases(
  List<RadarrMovie> movies, {
  required DateTime now,
  int days = radarrComingUpDays,
}) {
  final local = now.toLocal();
  final start = DateTime(local.year, local.month, local.day);
  final end = DateTime(local.year, local.month, local.day + days);

  final releases = <RadarrUpcomingRelease>[];
  for (final movie in movies) {
    for (final (raw, kind) in <(String?, RadarrReleaseKind)>[
      (movie.inCinemas, RadarrReleaseKind.inCinemas),
      (movie.digitalRelease, RadarrReleaseKind.digital),
      (movie.physicalRelease, RadarrReleaseKind.physical),
    ]) {
      final date = _parseLocal(raw);
      if (date == null) continue;
      if (date.isBefore(start) || !date.isBefore(end)) continue;
      releases.add(RadarrUpcomingRelease(movie: movie, date: date, kind: kind));
    }
  }

  releases.sort((a, b) {
    final byDate = a.date.compareTo(b.date);
    return byDate != 0
        ? byDate
        : a.movie.sortTitle.compareTo(b.movie.sortTitle);
  });
  return List.unmodifiable(releases);
}

/// Everything Radarr will release in the next [radarrComingUpDays] days.
///
/// Derived client-side rather than from `/api/v3/calendar`: for Radarr the
/// calendar endpoint answers with library movies whose dates fall in range, and
/// the library is already loaded. (Sonarr and Lidarr genuinely need the
/// endpoint — an episode is not a row of the series list.)
final radarrComingUpProvider =
    FutureProvider.autoDispose<List<RadarrUpcomingRelease>>((ref) async {
      final movies = await ref.watch(moviesProvider.future);
      return radarrUpcomingReleases(movies, now: DateTime.now());
    });

// ─── Recently added ─────────────────────────────────────────────────────────

/// The newest [limit] additions, newest first.
///
/// A film with no parseable `added` is dropped rather than sorted to one end:
/// the rail claims to be ordered by when things arrived, and an entry with no
/// arrival time cannot honour that claim in either direction.
List<RadarrMovie> radarrRecentlyAdded(
  List<RadarrMovie> movies, {
  int limit = radarrRecentlyAddedLimit,
}) {
  final dated = <(DateTime, RadarrMovie)>[];
  for (final movie in movies) {
    final added = _parseLocal(movie.added);
    if (added != null) dated.add((added, movie));
  }
  dated.sort((a, b) => b.$1.compareTo(a.$1));
  return List.unmodifiable(dated.take(limit).map((entry) => entry.$2));
}

final radarrRecentlyAddedProvider =
    FutureProvider.autoDispose<List<RadarrMovie>>((ref) async {
      final movies = await ref.watch(moviesProvider.future);
      return radarrRecentlyAdded(movies);
    });

// ─── Needs attention ────────────────────────────────────────────────────────

/// The three conditions this screen can derive today.
///
/// Each carries its own tone, and that is the whole point of the enum: two of
/// these are faults and the third is backlog, which the five-arm tone rule
/// paints neutral. Collapsing them into one "attention" colour is how a pile of
/// upgrades ends up wearing the same amber as a broken import.
enum RadarrAttentionKind {
  /// Radarr grabbed the release and could not move it into the library.
  importFailed(StatusTone.warning, Icons.file_download_off_rounded),

  /// The transfer is not moving. A fault — the user did not ask for this.
  stalled(StatusTone.warning, Icons.sync_problem_rounded),

  /// Files on disk below the configured quality cutoff. Backlog, so neutral:
  /// nothing is broken, there is simply work outstanding.
  belowCutoff(StatusTone.neutral, Icons.upgrade_rounded);

  const RadarrAttentionKind(this.tone, this.icon);

  final StatusTone tone;
  final IconData icon;
}

/// One row of Needs attention: what happened, to what, and when.
///
/// The per-row cross-service action the board draws ("Open in qBittorrent",
/// "Manual import") is deliberately absent — the bridge those need does not
/// exist in `lib/` yet, and a button that cannot do the thing it names is worse
/// than no button.
@immutable
class RadarrAttentionItem {
  const RadarrAttentionItem({
    required this.kind,
    required this.headline,
    required this.detail,
  });

  final RadarrAttentionKind kind;

  /// The fault and its subject: `Import failed · Nickel Boys`.
  final String headline;

  /// The evidence: the service's own message, the client, the timestamp.
  /// Empty when the record carried none.
  final String detail;

  StatusTone get tone => kind.tone;
  IconData get icon => kind.icon;

  /// The row as a sentence, with the dots the layout uses turned back into
  /// commas — `·` is decoration, and a screen reader either names it or drops
  /// it depending on the user's punctuation setting.
  String get spoken =>
      joinSpokenParts([spokenFromDotted(headline), spokenFromDotted(detail)]);
}

/// Reads the faults out of a page of **raw** `/queue` records.
///
/// Raw, because `ArrQueueSnapshot` folds a queue down to one entry per movie id
/// and keeps neither the release title nor `added` — and this section is
/// entirely made of those two.
///
/// Stalled is tested before import: a transfer that is not moving has not
/// reached the import stage at all, and Radarr marks both with the same
/// `trackedDownloadStatus: warning`.
List<RadarrAttentionItem> radarrQueueFaults(
  List<Map<String, dynamic>> records, {
  required DateTime now,
}) {
  final items = <RadarrAttentionItem>[];
  for (final record in records) {
    final title =
        arrPrimaryMediaTitle(record) ??
        arrReleaseTitle(record) ??
        'Unknown release';
    final when = _parseLocal(stringOrNull(record['added']));
    final age = when == null ? null : formatRelativeDateTime(when, now: now);
    final message =
        stringOrNull(record['errorMessage']) ?? arrQueueWarningMessage(record);

    if (_isStalled(record)) {
      items.add(
        RadarrAttentionItem(
          kind: RadarrAttentionKind.stalled,
          headline: 'Stalled · $title',
          detail: joinDisplayParts([
            stringOrNull(record['downloadClient']),
            message,
            age,
          ]),
        ),
      );
      continue;
    }

    if (_isImportFault(record)) {
      items.add(
        RadarrAttentionItem(
          kind: RadarrAttentionKind.importFailed,
          headline: 'Import failed · $title',
          detail: joinDisplayParts([message, age]),
        ),
      );
    }
  }
  return List.unmodifiable(items);
}

/// The backlog row, or null when there is no backlog to report.
RadarrAttentionItem? radarrBelowCutoffItem(int count) {
  if (count <= 0) return null;
  return RadarrAttentionItem(
    kind: RadarrAttentionKind.belowCutoff,
    headline: count == 1
        ? '1 film below your quality cutoff'
        : '$count films below your quality cutoff',
    // Names the mechanism rather than an instruction: nothing is wrong, Radarr
    // is simply still looking.
    detail: 'Radarr keeps searching for an upgrade',
  );
}

bool _isStalled(Map<String, dynamic> record) {
  final haystack = [
    stringOrNull(record['errorMessage']),
    stringOrNull(record['status']),
    ...extractArrStatusMessages(record['statusMessages']),
  ].whereType<String>().join(' ').toLowerCase();
  return haystack.contains('stall');
}

bool _isImportFault(Map<String, dynamic> record) {
  final state = stringOrNull(record['trackedDownloadState'])?.toLowerCase();
  if (state == 'failed' ||
      state == 'failedpending' ||
      state == 'importfailed' ||
      state == 'importblocked') {
    return true;
  }
  // Radarr's canonical "Unable to Import Automatically" arrives as a pending
  // import carrying a status message, which is how the service says a human has
  // to look at it — see `arrQueueSeverity`.
  return state == 'importpending' &&
      arrQueueSeverity(record) != ArrQueueSeverity.ok;
}

/// The raw `/queue` page, string-keyed.
///
/// The equivalent of the private `_loadServiceQueueItems` in
/// `services_provider.dart`, stopping one step earlier: that one maps straight
/// to `ServiceQueueItem`, which carries title/subtitle/progress/warning and no
/// timestamp at all.
final radarrQueueRecordsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final records = await ref.watch(radarrServiceProvider).getQueue();
      return records.whereType<Map>().map(stringKeyMap).toList(growable: false);
    });

/// How many library files sit below the configured quality cutoff.
///
/// `getAllCutoff()` already swallows its own failures and answers `[]`, so a
/// Radarr that does not serve the endpoint reports no backlog rather than
/// taking the section down.
final radarrCutoffUnmetCountProvider = FutureProvider.autoDispose<int>((
  ref,
) async {
  final records = await ref.watch(radarrServiceProvider).getAllCutoff();
  return records.length;
});

/// Faults first, backlog last.
///
/// The order is the design's: what needs a decision before what is merely
/// outstanding.
final radarrNeedsAttentionProvider =
    FutureProvider.autoDispose<List<RadarrAttentionItem>>((ref) async {
      final records = await ref.watch(radarrQueueRecordsProvider.future);
      final cutoff = await ref.watch(radarrCutoffUnmetCountProvider.future);
      final backlog = radarrBelowCutoffItem(cutoff);
      return [...radarrQueueFaults(records, now: DateTime.now()), ?backlog];
    });

// ─── History today ──────────────────────────────────────────────────────────

/// One history record, resolved into the two lines the row draws.
@immutable
class RadarrHistoryEntry {
  const RadarrHistoryEntry({
    required this.title,
    required this.event,
    required this.tone,
    required this.detail,
    required this.date,
  });

  /// The film.
  final String title;

  /// What happened to it, in the shared history vocabulary — `Imported`,
  /// `Grabbed`, `Failed`.
  final String event;

  final StatusTone tone;

  /// Quality, size and how long ago, as far as the record carried them.
  final String detail;

  final DateTime date;

  String get spoken =>
      joinSpokenParts([title, event, spokenFromDotted(detail)]);
}

/// The records from today, newest first, capped at [limit].
///
/// "Today" is the local calendar day of [now]. A record from 23:50 yesterday is
/// out even though it is twenty minutes old — the section is headed `today`,
/// and a heading is a promise.
List<RadarrHistoryEntry> radarrHistoryToday(
  List<dynamic> records, {
  required DateTime now,
  int limit = radarrHistoryTodayLimit,
}) {
  final local = now.toLocal();
  final entries = <RadarrHistoryEntry>[];

  for (final raw in records) {
    final record = mapOrNull(raw);
    if (record == null) continue;
    final date = _parseLocal(stringOrNull(record['date']));
    if (date == null) continue;
    if (date.year != local.year ||
        date.month != local.month ||
        date.day != local.day) {
      continue;
    }

    final eventType = stringOrNull(record['eventType']) ?? 'unknown';
    final (event, tone) = historyEventDisplay(eventType);
    entries.add(
      RadarrHistoryEntry(
        title:
            arrPrimaryMediaTitle(record) ??
            arrReleaseTitle(record) ??
            'Unknown release',
        event: event,
        tone: tone,
        detail: joinDisplayParts([
          _qualityName(record['quality']),
          _size(record),
          formatRelativeDateTime(date, now: now),
        ]),
        date: date,
      ),
    );
  }

  entries.sort((a, b) => b.date.compareTo(a.date));
  return List.unmodifiable(entries.take(limit));
}

/// Today's history, from one page of twenty.
final radarrHistoryTodayProvider =
    FutureProvider.autoDispose<List<RadarrHistoryEntry>>((ref) async {
      final records = await ref
          .watch(radarrServiceProvider)
          .getHistory(page: 1, pageSize: radarrHistoryPageSize);
      return radarrHistoryToday(records, now: DateTime.now());
    });

// ─── Shared parsing ─────────────────────────────────────────────────────────

/// Parses an \*arr ISO timestamp into local time, or null when it is absent or
/// unreadable.
///
/// Local, always: every window on this screen is a run of local calendar days,
/// and Radarr answers in UTC.
DateTime? _parseLocal(String? raw) {
  final value = raw?.trim();
  if (value == null || value.isEmpty) return null;
  final parsed = DateTime.tryParse(value);
  return parsed?.toLocal();
}

String? _qualityName(dynamic value) {
  final quality = mapOrNull(value);
  if (quality == null) return stringOrNull(value);
  return stringOrNull(mapOrNull(quality['quality'])?['name']) ??
      stringOrNull(quality['name']);
}

String? _size(Map<String, dynamic> record) {
  final bytes =
      intOrNull(record['size']) ??
      intOrNull(mapOrNull(record['data'])?['size']);
  if (bytes == null || bytes <= 0) return null;
  return formatReleaseSize(bytes);
}
