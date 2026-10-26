/// What the Radarr Overview reads, and the pure functions that shape it.
///
/// The Overview is the one tab that carries the identity block and the
/// readouts, so everything else on it is derived rather than fetched twice:
/// Coming up and Recently added both fall out of [radarrOverviewMoviesProvider],
/// and Needs attention reads the *raw* queue records
/// rather than [ArrQueueSnapshot], the snapshot collapses to one headline per
/// media id and drops the titles and timestamps the fault rows are made of.
///
/// Every windowing rule lives in a top-level pure function taking an explicit
/// `now`, so the boundaries are unit-testable without a clock or a container.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/utils/parallel_reads.dart';
import 'package:cupola/core/api/base_arr_service.dart';
import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/core/utils/arr_overview.dart';
import 'package:cupola/core/utils/arr_model_helpers.dart';
import 'package:cupola/core/utils/date_format.dart' show formatRelativeDateTime;
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/movies/presentation/movies_provider.dart';
import 'package:cupola/features/services/domain/attention_door.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

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
/// appear twice in one week: a digital release on Tuesday and a physical one
/// on Friday are two events, not one row that has to pick a winner.
enum RadarrReleaseKind {
  inCinemas(Lexicon.inCinemas),
  digital(Lexicon.onDigital),
  physical(Lexicon.onDisc);

  const RadarrReleaseKind(this.label);

  /// Sentence case, for the eye and for the ear alike, and the calendar's own
  /// words: one film on one date is named the same on both screens.
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

  /// The calendar date the release spells, as a local midnight
  /// ([arrCalendarDate]). The window is a run of local calendar days, and a
  /// release date is one of them, not an instant to convert into one.
  final DateTime date;

  final RadarrReleaseKind kind;
}

/// The releases falling inside the next [days] local calendar days.
///
/// The window opens at local midnight **today** (inclusive) and closes at local
/// midnight [days] days later (exclusive): a film released earlier today is
/// still "coming up" (the user has not seen it on this screen yet), and one
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
      // The day the date spells, not the instant it encodes: Radarr sends
      // "12 October" as midnight UTC, and `.toLocal()` showed it on the 11th
      // anywhere west of Greenwich, a day before the calendar tab did.
      final date = arrCalendarDate(raw);
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

/// The library, read so that a failure is still a failure when it arrives.
///
/// **[moviesProvider] itself**, which reads `getMoviesOrThrow` now: this was
/// a second copy of the same request, and with the KPI rail's a third, so the
/// heaviest answer the app asks for was downloaded up to three times a
/// session. One read, `noProviderRetry` like the wall and the rail: a blip is
/// the user's Retry. Pull-to-refresh and the sections' Retry invalidate it.
final radarrOverviewMoviesProvider = moviesProvider;

/// Everything Radarr will release in the next [radarrComingUpDays] days.
///
/// Derived client-side rather than from `/api/v3/calendar`: for Radarr the
/// calendar endpoint answers with library movies whose dates fall in range, and
/// the library is already loaded. (Sonarr and Lidarr genuinely need the
/// endpoint: an episode is not a row of the series list.)
final radarrComingUpProvider =
    FutureProvider.autoDispose<List<RadarrUpcomingRelease>>((ref) async {
      final movies = await ref.watch(radarrOverviewMoviesProvider.future);
      return radarrUpcomingReleases(movies, now: DateTime.now());
      // Its source carries the flag, so this does: see `provider_retry.dart`.
    }, retry: noProviderRetry);

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
    final added = parseLocalInstant(movie.added);
    if (added != null) dated.add((added, movie));
  }
  dated.sort((a, b) => b.$1.compareTo(a.$1));
  return List.unmodifiable(dated.take(limit).map((entry) => entry.$2));
}

final radarrRecentlyAddedProvider =
    FutureProvider.autoDispose<List<RadarrMovie>>((ref) async {
      final movies = await ref.watch(radarrOverviewMoviesProvider.future);
      return radarrRecentlyAdded(movies);
    }, retry: noProviderRetry);

// ─── Needs attention ────────────────────────────────────────────────────────

/// The three conditions this screen can derive today.
///
/// Each carries its own tone, and that is the whole point of the enum: two of
/// these are faults and the third is backlog, which the five-arm tone rule
/// paints neutral. Collapsing them into one "attention" colour is how a pile of
/// upgrades ends up wearing the same amber as a broken import.
enum RadarrAttentionKind implements ArrAttentionKind {
  /// Radarr grabbed the release and could not move it into the library.
  importFailed(StatusTone.warning, Icons.file_download_off_rounded),

  /// The transfer is not moving. A fault: the user did not ask for this.
  stalled(StatusTone.warning, Icons.sync_problem_rounded),

  /// Files on disk below the configured quality cutoff. Backlog, so neutral:
  /// nothing is broken, there is simply work outstanding.
  belowCutoff(StatusTone.neutral, Icons.upgrade_rounded);

  const RadarrAttentionKind(this.tone, this.icon);

  @override
  final StatusTone tone;

  @override
  final IconData icon;
}

/// One row of Needs attention (`ArrAttentionItem`).
typedef RadarrAttentionItem = ArrAttentionItem<RadarrAttentionKind>;

/// Reads the faults out of a page of **raw** `/queue` records.
///
/// Raw, because `ArrQueueSnapshot` folds a queue down to one entry per movie id
/// and keeps neither the release title nor `added`, and this section is
/// entirely made of those two.
///
/// Stalled is tested before import: a transfer that is not moving has not
/// reached the import stage at all, and Radarr marks both with the same
/// `trackedDownloadStatus: warning`.
///
/// Several downloads in one of the two states are one row (`3 downloads
/// stuck`, the titles in the detail) whose door is the Queue tab, which lists
/// them all; one of a kind keeps its own row and opens its own page. The
/// records of one download count once. [instanceId] is the connection the
/// records were read from, which a download's page is addressed by, and
/// [cutShort] says the walk stopped on a full page, so a count taken in it is
/// a floor.
List<RadarrAttentionItem> radarrQueueFaults(
  List<Map<String, dynamic>> records, {
  required DateTime now,
  String instanceId = '',
  bool cutShort = false,
}) {
  final items = <RadarrAttentionItem>[];
  for (final record in records) {
    final title =
        arrPrimaryMediaTitle(record) ??
        arrReleaseTitle(record) ??
        'Unknown release';
    final when = parseLocalInstant(stringOrNull(record['added']));
    final age = when == null ? null : formatRelativeDateTime(when, now: now);
    final message =
        stringOrNull(record['errorMessage']) ?? arrQueueWarningMessage(record);
    final door = arrQueueRecordDoor(record, instanceId: instanceId);

    if (isStalledRecord(record)) {
      items.add(
        RadarrAttentionItem(
          kind: RadarrAttentionKind.stalled,
          headline: '${StateWord.stuck.label}\u00A0· $title',
          detail: joinDisplayParts([
            stringOrNull(record['downloadClient']),
            message,
            age,
          ]),
          door: door,
          subject: title,
        ),
      );
      continue;
    }

    if (isImportFaultRecord(record)) {
      items.add(
        RadarrAttentionItem(
          kind: RadarrAttentionKind.importFailed,
          headline: 'Import failed\u00A0· $title',
          detail: joinDisplayParts([message, age]),
          door: door,
          subject: title,
        ),
      );
    }
  }
  return foldAttention<RadarrAttentionItem, RadarrAttentionKind>(
    items,
    kindOf: (item) => item.kind,
    // The download a row is: a record counted twice is not two faults.
    identityOf: (item) => item.door ?? item,
    merge: (kind, members) {
      final words = kind == RadarrAttentionKind.stalled
          ? stuckDownloadsWords(members.length, floor: cutShort)
          : failedImportsWords(members.length, floor: cutShort);
      return RadarrAttentionItem(
        kind: kind,
        headline: words.headline,
        spokenHeadline: words.spoken,
        detail: attentionNames(members.map((member) => member.subject ?? '')),
        door: const AttentionDoor.tab(ServiceTab.queue),
        count: members.length,
      );
    },
  );
}

/// The backlog row, or null when there is no backlog to report, and null too
/// when the server never reported one.
///
/// A null [count] is "we could not ask", which draws no row rather than a
/// confident zero. Same rule as `sonarrBelowCutoffItem`.
RadarrAttentionItem? radarrBelowCutoffItem(int? count) {
  if (count == null || count <= 0) return null;
  return RadarrAttentionItem(
    kind: RadarrAttentionKind.belowCutoff,
    headline: count == 1
        ? '1 movie below your quality cutoff'
        : '$count movies below your quality cutoff',
    // Names the mechanism rather than an instruction: nothing is wrong, Radarr
    // is simply still looking.
    detail: 'Radarr keeps searching for an upgrade',
    // Wanted lists what is below its cutoff beside what is missing.
    door: const AttentionDoor.tab(ServiceTab.wanted),
  );
}

/// The raw `/queue` walk, with its envelope.
///
/// The equivalent of the private `_loadServiceQueueItems` in
/// `services_provider.dart`, stopping one step earlier: that one maps straight
/// to `ServiceQueueItem`, which carries title/subtitle/progress/warning and no
/// timestamp at all.
///
/// The page and not its bare rows, so [ArrRecordPage.cutShort] reaches the
/// section that counts faults in them: a walk that stopped on a full page with
/// no total read its faults out of the first 200 records, and the header
/// stated their count as if it were all of them.
final radarrQueueRecordsProvider = FutureProvider.autoDispose<ArrRecordPage>((
  ref,
) {
  return ref.watch(radarrServiceProvider).getQueuePage();
});

/// How many library files sit below the configured quality cutoff, or null
/// when the server did not say.
///
/// One request, and the figure read off the envelope's `totalRecords` rather
/// than counted from the records themselves. `getAllCutoff()` answers the same
/// question by walking up to fifty pages of 250 records, thousands of maps
/// parsed to take a `.length` the envelope hands over in a field, and a count
/// that silently caps at 12,500, and it swallows its own failure into `[]`,
/// which made "this fork does not serve wanted/cutoff" and "there is no
/// backlog" the same answer.
///
/// `getCutoffPage` degrades to a **null** total instead, and null draws no row:
/// the shape `sonarrBacklogProvider` already uses.
final radarrCutoffUnmetCountProvider = FutureProvider.autoDispose<int?>((
  ref,
) async {
  // The page itself is thrown away, only the total is read, so ask for the
  // smallest one the server will send.
  final page = await ref
      .watch(radarrServiceProvider)
      .getCutoffPage(page: 1, pageSize: 1);
  return page.total;
});

/// Faults first, backlog last.
///
/// The order is the design's: what needs a decision before what is merely
/// outstanding. When the queue walk stopped short the faults are only those in
/// the rows it read, and the section's count is a floor: read
/// `radarrQueueRecordsProvider`'s `cutShort` beside this.
final radarrNeedsAttentionProvider =
    FutureProvider.autoDispose<List<RadarrAttentionItem>>((ref) async {
      // Both reads start together: the cutoff count does not wait for the
      // queue. `.wait` surfaces a failure through `unwrapFailure`.
      final (page, cutoff) = await readTogether(
        ref.watch(radarrQueueRecordsProvider.future),
        ref.watch(radarrCutoffUnmetCountProvider.future),
      );
      final backlog = radarrBelowCutoffItem(cutoff);
      return [
        ...radarrQueueFaults(
          page.recordMaps,
          now: DateTime.now(),
          // The connection the queue was read from: a download's page is
          // addressed by it.
          instanceId:
              ref.watch(activeInstanceProvider(ServiceKey.radarr))?.id ?? '',
          cutShort: page.cutShort,
        ),
        ?backlog,
      ];
    });

// ─── History today ──────────────────────────────────────────────────────────

/// One history record, resolved into the two lines the row draws.
typedef RadarrHistoryEntry = OverviewHistoryEntry;

/// The records from today, newest first, capped at [limit].
///
/// "Today" is the local calendar day of [now]. A record from 23:50 yesterday is
/// out even though it is twenty minutes old: the section is headed `today`,
/// and a heading is a promise.
List<RadarrHistoryEntry> radarrHistoryToday(
  List<dynamic> records, {
  required DateTime now,
  int limit = radarrHistoryTodayLimit,
}) => overviewHistoryToday(
  records,
  now: now,
  limit: limit,
  subjectOf: (record) =>
      arrPrimaryMediaTitle(record) ??
      arrReleaseTitle(record) ??
      'Unknown release',
);

/// Today's history, from one page of twenty.
final radarrHistoryTodayProvider =
    FutureProvider.autoDispose<List<RadarrHistoryEntry>>((ref) async {
      final records = await ref
          .watch(radarrServiceProvider)
          .getHistory(page: 1, pageSize: radarrHistoryPageSize);
      return radarrHistoryToday(records, now: DateTime.now());
    });

// ─── Shared parsing ─────────────────────────────────────────────────────────
