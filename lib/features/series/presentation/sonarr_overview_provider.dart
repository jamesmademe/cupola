/// What the Sonarr Overview reads, and the pure functions that shape it.
///
/// Sonarr shares Radarr's bar exactly — Overview, Library, Calendar, Queue,
/// Wanted, History — so this file is deliberately the sibling of
/// `radarr_overview_provider.dart` and departs from it only where the record
/// forces it to. The record here is an **episode inside a season inside a
/// series**, and that is the one difference that runs through everything: a
/// count of episodes must say episodes, a row names the slot (`S02E05`) as well
/// as the series, and the week window can only be built out of what a *series*
/// row carries.
///
/// The one structural departure: Radarr derives its Coming up from the library
/// because a film's dates are on the film. Episodes are not on the series row
/// at all — the honest source is `GET /api/v3/calendar`, which `SonarrService`
/// has never called (the same block `lib/core/router.dart` records for the
/// Calendar tab). What is reachable is `nextAiring`, one instant per series on
/// the `series` call the KPI rail already makes, so the week window here counts
/// **series with an episode due**, never episodes. See [sonarrAiringWeek].
///
/// Every windowing rule lives in a top-level pure function taking an explicit
/// `now`, so the boundaries are unit-testable without a clock or a container.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/api/base_arr_service.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/core/utils/release_utils.dart';
import 'package:cupola/features/activity/domain/global_activity_status.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_formatters.dart'
    show formatRelativeDateTime;
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/series/domain/models/sonarr_series.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';

/// How far ahead the week window looks.
const int sonarrAiringDays = 7;

/// How many airing rows the section draws before the header's count is the only
/// place the rest are reported.
const int sonarrAiringPreviewLimit = 5;

/// Posters on the Recently downloaded rail.
const int sonarrRecentlyDownloadedLimit = 6;

/// One page of history, and deliberately only one.
///
/// Thirty rather than Radarr's twenty because the record is an episode: a
/// weekly series drops nine files where a film drops one, so twenty rows on a
/// busy Sonarr can be an hour of activity. It is still one request, and both
/// history-derived sections read this same page rather than fetching twice.
const int sonarrHistoryPageSize = 30;

/// Rows the History today section draws.
const int sonarrHistoryTodayLimit = 3;

/// One page of a backlog endpoint.
///
/// Only the envelope's `totalRecords` is printed as a figure; the rows are read
/// for one thing only — how many distinct series they span — and only when the
/// page provably holds all of them. See [sonarrSeriesSpread].
const int sonarrBacklogPageSize = 20;

// ─── Airing this week ───────────────────────────────────────────────────────

/// One series with an episode due inside the window.
@immutable
class SonarrAiringEntry {
  const SonarrAiringEntry({required this.series, required this.airsAt});

  final SonarrSeries series;

  /// Local time. The window is a run of local calendar days, so an entry
  /// compared in UTC would slip a day either side of midnight.
  final DateTime airsAt;
}

/// The week window, and whether its emptiness can be believed.
///
/// [canReport] exists because `nextAiring` is absent for two entirely different
/// reasons — nothing is scheduled, or this server never sent the field — and
/// they must not render as the same sentence. An empty list with
/// [canReport] false is "Sonarr did not say", which is a missing answer; an
/// empty list with it true is "nothing airs this week", which is an answer.
@immutable
class SonarrAiringWeek {
  const SonarrAiringWeek({required this.entries, required this.canReport});

  /// Sorted by air time, then by sort title so two episodes in the same slot
  /// have a stable order.
  final List<SonarrAiringEntry> entries;

  /// False when at least one series could still be airing and **no** series in
  /// the whole library carried a next-airing date.
  final bool canReport;
}

/// Whether Sonarr told us enough for silence to mean "nothing".
///
/// This guards the narrow case only: the server answered and the *field* was
/// absent. The wide one — the server did not answer at all — is not this
/// function's to catch and cannot be caught here, because a failed fetch and an
/// empty library arrive as the same `[]`. It is caught one layer down, by
/// [sonarrOverviewSeriesProvider] reading `getSeriesOrThrow`: by the time a
/// list reaches this function it is a list Sonarr actually sent, so `[]` means
/// an empty library.
///
/// True as soon as one series carries a date — the server answers the question,
/// so any series without one genuinely has nothing scheduled. True also for a
/// library where nothing *could* air: every series ended or was deleted, and an
/// empty week is then simply the truth. False only in the third case, a library
/// with running series and not one date in it, which is what an older Sonarr or
/// a proxy stripping fields looks like.
bool sonarrCanReportAirings(List<SonarrSeries> series) {
  var expectsDates = false;
  for (final entry in series) {
    if (_parseLocal(entry.nextAiring) != null) return true;
    if (sonarrMayStillAir(entry)) expectsDates = true;
  }
  return !expectsDates;
}

/// Whether this series could have a future episode at all.
///
/// Sonarr's series `status` is a small closed vocabulary; `continuing` and
/// `upcoming` are the two that mean "more is coming". `ended` and `deleted`
/// mean the opposite, and `unknown` is treated as ended rather than as
/// expecting a date — the alternative makes one un-catalogued series in a
/// library of finished shows suppress the whole section.
bool sonarrMayStillAir(SonarrSeries series) {
  final status = series.status.toLowerCase();
  return status == 'continuing' || status == 'upcoming';
}

/// The series with an episode due inside the next [days] local calendar days.
///
/// The window opens at local midnight **today** (inclusive) and closes at local
/// midnight [days] days later (exclusive): an episode that aired earlier today
/// is still part of today's row — the user has not seen this screen yet — and
/// one dated exactly seven days out belongs to next week's window.
///
/// The end is built with `DateTime(y, m, d + days)` rather than
/// `start.add(Duration(days: days))`: a `Duration` is absolute, so across a DST
/// change the added form lands an hour off midnight and admits or drops the
/// boundary day by accident.
///
/// **One row per series, by construction.** `nextAiring` is a single instant,
/// so a series airing Tuesday and Friday appears once, on Tuesday. That is why
/// the section counts series: an episode count derived from this would be short
/// by exactly the episodes it cannot see, which is the worst kind of wrong
/// figure — plausible.
SonarrAiringWeek sonarrAiringWeek(
  List<SonarrSeries> series, {
  required DateTime now,
  int days = sonarrAiringDays,
}) {
  final local = now.toLocal();
  final start = DateTime(local.year, local.month, local.day);
  final end = DateTime(local.year, local.month, local.day + days);

  final entries = <SonarrAiringEntry>[];
  for (final entry in series) {
    final airsAt = _parseLocal(entry.nextAiring);
    if (airsAt == null) continue;
    if (airsAt.isBefore(start) || !airsAt.isBefore(end)) continue;
    entries.add(SonarrAiringEntry(series: entry, airsAt: airsAt));
  }

  entries.sort((a, b) {
    final byDate = a.airsAt.compareTo(b.airsAt);
    return byDate != 0
        ? byDate
        : a.series.sortTitle.compareTo(b.series.sortTitle);
  });

  return SonarrAiringWeek(
    entries: List.unmodifiable(entries),
    canReport: sonarrCanReportAirings(series),
  );
}

/// The library, read so that a failure is still a failure when it arrives.
///
/// **Not [seriesProvider]**, and the duplication is deliberate. That provider
/// reads `getSeries`, which degrades to `[]`, so an unreachable, mis-keyed or
/// 500-ing Sonarr resolved it *successfully* with an empty library — and this
/// screen then printed "next 7 days · 0 series" over "Nothing airing this
/// week", directly beneath an identity band whose own probe already read
/// Unreachable. Two contradictory claims on one screenful, and the confident
/// one was the fabricated zero. [sonarrCanReportAirings] cannot catch it: a
/// failed fetch and an empty library are the same `[]` by the time it runs.
///
/// The cost is one extra `GET /series` per session on this tab. The rail above
/// no longer reads `seriesProvider` — it was printing the same fabricated zeros
/// — but it does not share *this* provider either, and deliberately: it awaits
/// its library inside a `catch`, so its own source carries
/// `retry: noProviderRetry`, while this one keeps the default retry because the
/// Overview watches it as an `AsyncValue` and a blip should heal itself. One
/// provider cannot hold both policies. `seriesProvider` keeps its degradation
/// for the browse grid, which is what it was written for.
///
/// Plain, not `autoDispose`, matching [seriesProvider]: the library is a
/// session-scoped read, and a per-visit refetch of the whole library is exactly
/// what the extra request above must not become. Pull-to-refresh invalidates it
/// explicitly.
final sonarrOverviewSeriesProvider = FutureProvider<List<SonarrSeries>>((
  ref,
) async {
  return ref.watch(sonarrServiceProvider).getSeriesOrThrow();
});

/// The week, from the library.
///
/// No `retry:` override, and that is deliberate rather than an omission: the
/// source ([sonarrOverviewSeriesProvider]) carries none either, and nothing
/// awaits this inside a `try` that exists to degrade — the failure lands on an
/// `AsyncValueWidget` that renders it with a Retry. See
/// `lib/core/providers/provider_retry.dart`; the rule that bites is the reverse
/// one, a derivation *dropping* a `noProviderRetry` its source carried.
///
/// That Retry is reachable now, which it was not while the source swallowed its
/// own failure into `[]`.
final sonarrAiringWeekProvider = FutureProvider.autoDispose<SonarrAiringWeek>((
  ref,
) async {
  final series = await ref.watch(sonarrOverviewSeriesProvider.future);
  return sonarrAiringWeek(series, now: DateTime.now());
});

// ─── Needs attention ────────────────────────────────────────────────────────

/// The four conditions this screen can derive today.
///
/// Each carries its own tone, and that is the whole point of the enum: two of
/// these are faults and two are backlog, which the five-arm tone rule paints
/// neutral. Painting the backlog amber is the single most common way that rule
/// is broken — a library with twelve episodes still to find is not a library
/// that is broken.
enum SonarrAttentionKind {
  /// Sonarr grabbed the release and could not move it into the library.
  importFailed(StatusTone.warning, Icons.file_download_off_rounded),

  /// The transfer is not moving. A fault — the user did not ask for this.
  stalled(StatusTone.warning, Icons.sync_problem_rounded),

  /// Monitored episodes that have aired and are not on disk. Backlog: nothing
  /// is broken, there is simply work outstanding.
  missing(StatusTone.neutral, Icons.radar_rounded),

  /// Episodes on disk below the configured quality cutoff. Backlog too.
  belowCutoff(StatusTone.neutral, Icons.upgrade_rounded);

  const SonarrAttentionKind(this.tone, this.icon);

  final StatusTone tone;
  final IconData icon;
}

/// One row of Needs attention: what happened, to what, and when.
///
/// The per-row cross-service action the board draws ("Manual import", "Search
/// all") is deliberately absent. Manual import needs a bridge into the download
/// client that does not exist in `lib/` yet, and "Search all missing" would
/// have to walk every page of `wanted/missing` to collect the episode ids the
/// only search command this client has takes. A button that cannot do the thing
/// it names is worse than no button.
@immutable
class SonarrAttentionItem {
  const SonarrAttentionItem({
    required this.kind,
    required this.headline,
    required this.detail,
  });

  final SonarrAttentionKind kind;

  /// The fault and its subject: `Import failed · Slow Horses S04`.
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

/// The slot a queue or history record is about: `S02E05`, or `S04` for a season
/// pack, or null when the record names neither.
///
/// [arrEpisodeCode] needs both numbers and answers null without them — which is
/// exactly the shape of a season pack, the record the board's own example row
/// is made of ("Season pack failed to import · Slow Horses S04"). Dropping to
/// the bare season is what lets that row name the thing that failed instead of
/// printing the series title twice over.
String? sonarrEpisodeSlot(Map<String, dynamic> record) {
  final code = arrEpisodeCode(record);
  if (code != null) return code;

  final season = intOrNull(
    mapOrNull(record['episode'])?['seasonNumber'] ?? record['seasonNumber'],
  );
  if (season == null) return null;
  return 'S${season.toString().padLeft(2, '0')}';
}

/// `Slow Horses S04E06` — the subject of a row, as far as the record names it.
String sonarrRecordSubject(Map<String, dynamic> record) {
  final named = joinDisplayParts([
    arrSeriesTitle(record),
    sonarrEpisodeSlot(record),
  ], separator: ' ');
  if (named.isNotEmpty) return named;
  return arrReleaseTitle(record) ?? 'Unknown release';
}

/// Reads the faults out of a page of **raw** `/queue` records.
///
/// Raw, because `ArrQueueSnapshot` folds a queue down to one entry per series
/// id and keeps neither the release title nor `added` — and this section is
/// entirely made of those two. On Sonarr the fold costs more than on Radarr: a
/// season pack and three single episodes of one series collapse to one entry,
/// so three of the four faults would vanish.
///
/// Stalled is tested before import: a transfer that is not moving has not
/// reached the import stage at all, and Sonarr marks both with the same
/// `trackedDownloadStatus: warning`.
List<SonarrAttentionItem> sonarrQueueFaults(
  List<Map<String, dynamic>> records, {
  required DateTime now,
}) {
  final items = <SonarrAttentionItem>[];
  for (final record in records) {
    final subject = sonarrRecordSubject(record);
    final when = _parseLocal(stringOrNull(record['added']));
    final age = when == null ? null : formatRelativeDateTime(when, now: now);
    final message =
        stringOrNull(record['errorMessage']) ?? arrQueueWarningMessage(record);

    if (_isStalled(record)) {
      items.add(
        SonarrAttentionItem(
          kind: SonarrAttentionKind.stalled,
          headline: 'Stalled · $subject',
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
        SonarrAttentionItem(
          kind: SonarrAttentionKind.importFailed,
          headline: 'Import failed · $subject',
          detail: joinDisplayParts([message, age]),
        ),
      );
    }
  }
  return List.unmodifiable(items);
}

/// The missing-episodes backlog row, or null when there is nothing to report —
/// **and null also when nobody could answer**.
///
/// [total] is `ArrRecordPage.total`, which is nullable precisely so a server
/// that did not answer is distinguishable from one that answered "none". A zero
/// printed over an unasked question is the failure this whole file is written
/// against, so a null total draws no row at all rather than a reassuring one.
SonarrAttentionItem? sonarrMissingEpisodesItem(int? total, {int? seriesCount}) {
  if (total == null || total <= 0) return null;
  return SonarrAttentionItem(
    kind: SonarrAttentionKind.missing,
    headline: total == 1
        ? '1 missing monitored episode'
        : '$total missing monitored episodes',
    // "across 5 series" only when the page provably held every record — see
    // [sonarrSeriesSpread]. Otherwise the mechanism, which is true at any size:
    // nothing is wrong, Sonarr is still looking.
    detail: seriesCount == null
        ? 'Sonarr keeps searching for them'
        : seriesCount == 1
        ? 'in 1 series'
        : 'across $seriesCount series',
  );
}

/// The below-cutoff backlog row, or null. Same null rule as
/// [sonarrMissingEpisodesItem].
SonarrAttentionItem? sonarrBelowCutoffItem(int? total) {
  if (total == null || total <= 0) return null;
  return SonarrAttentionItem(
    kind: SonarrAttentionKind.belowCutoff,
    headline: total == 1
        ? '1 episode below your quality cutoff'
        : '$total episodes below your quality cutoff',
    detail: 'Sonarr keeps searching for an upgrade',
  );
}

/// How many distinct series a backlog page spans, or null when the page cannot
/// answer that.
///
/// Null unless the envelope's total says this one page holds **every** record:
/// twenty rows out of two hundred span the series those twenty happened to
/// touch, and printing that as "across 5 series" turns a sampling artefact into
/// a fact about the library. The board asks for the clause; this is the only
/// condition under which the client can honour it.
int? sonarrSeriesSpread(ArrRecordPage page) {
  final total = page.total;
  if (total == null || total > page.records.length) return null;

  final ids = <int>{};
  for (final raw in page.records) {
    final record = mapOrNull(raw);
    if (record == null) continue;
    final id = intOrNull(
      record['seriesId'] ?? mapOrNull(record['series'])?['id'],
    );
    if (id != null) ids.add(id);
  }
  return ids.isEmpty ? null : ids.length;
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
  // Sonarr's canonical "One or more episodes expected in this release were not
  // imported or missing" arrives as a pending import carrying a status message,
  // which is how the service says a human has to look at it — see
  // `arrQueueSeverity`.
  return state == 'importpending' &&
      arrQueueSeverity(record) != ArrQueueSeverity.ok;
}

/// The raw `/queue` page, string-keyed.
///
/// The equivalent of the private `_loadServiceQueueItems` in
/// `services_provider.dart`, stopping one step earlier: that one maps straight
/// to `ServiceQueueItem`, which carries title/subtitle/progress/warning and no
/// timestamp at all.
final sonarrQueueRecordsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final records = await ref.watch(sonarrServiceProvider).getQueue();
      return records.whereType<Map>().map(stringKeyMap).toList(growable: false);
    });

/// The two backlog rows, or as many of them as the server would answer.
///
/// Each endpoint is wrapped on its own and degrades to "no row": the faults
/// above are the subject of this section and the backlog is an addition to it,
/// so a fork that does not serve `wanted/missing` reports no backlog rather
/// than taking a broken import down with it. `getCutoffPage` already swallows
/// its own failure for exactly this reason; `getMissingPage` does not, hence
/// the `try` here.
final sonarrBacklogProvider =
    FutureProvider.autoDispose<List<SonarrAttentionItem>>((ref) async {
      final service = ref.watch(sonarrServiceProvider);

      SonarrAttentionItem? missing;
      try {
        final page = await service.getMissingPage(
          page: 1,
          pageSize: sonarrBacklogPageSize,
        );
        missing = sonarrMissingEpisodesItem(
          page.total,
          seriesCount: sonarrSeriesSpread(page),
        );
      } catch (_) {
        missing = null;
      }

      SonarrAttentionItem? cutoff;
      try {
        final page = await service.getCutoffPage(
          page: 1,
          pageSize: sonarrBacklogPageSize,
        );
        cutoff = sonarrBelowCutoffItem(page.total);
      } catch (_) {
        cutoff = null;
      }

      return [?missing, ?cutoff];
    });

/// Faults first, backlog last.
///
/// The order is the design's: what needs a decision before what is merely
/// outstanding.
final sonarrNeedsAttentionProvider =
    FutureProvider.autoDispose<List<SonarrAttentionItem>>((ref) async {
      final records = await ref.watch(sonarrQueueRecordsProvider.future);
      final backlog = await ref.watch(sonarrBacklogProvider.future);
      return [...sonarrQueueFaults(records, now: DateTime.now()), ...backlog];
    });

// ─── History, and the two sections built from it ────────────────────────────

/// One page of history, read once and shared.
///
/// Recently downloaded and History today are two readings of the same rows, so
/// they take one request between them rather than one each. Both derive with
/// `ref.watch(...future)`, which is also why neither needs a `retry:` of its
/// own: this source declares none, so there is none to drop.
final sonarrHistoryPageProvider = FutureProvider.autoDispose<List<dynamic>>((
  ref,
) async {
  return ref
      .watch(sonarrServiceProvider)
      .getHistory(page: 1, pageSize: sonarrHistoryPageSize);
});

/// One imported episode, resolved into the tile the rail draws.
@immutable
class SonarrDownloadedEpisode {
  const SonarrDownloadedEpisode({
    required this.seriesId,
    required this.seriesTitle,
    required this.slot,
    required this.images,
    required this.date,
    required this.age,
  });

  /// Sonarr's series id — required, because the tile is a link and a poster
  /// that cannot navigate is a promise the page cannot keep.
  final int seriesId;

  final String seriesTitle;

  /// `S02E04`, or null when the record named no slot.
  final String? slot;

  /// The embedded series' `images`, for the poster.
  final List<dynamic> images;

  final DateTime date;

  /// `40 min ago`, resolved once against the `now` the window was built with.
  ///
  /// Held rather than recomputed in `build`: a string the widget derives from
  /// the wall clock is a string no test can assert and one the tile and its
  /// spoken label can disagree about across a rebuild.
  final String age;

  /// The caption under the poster: the slot, then how long ago.
  String get caption => joinDisplayParts([slot, age]);

  String get spoken => joinSpokenParts([seriesTitle, slot, age]);
}

/// The most recently imported episodes, newest first, one tile per series.
///
/// Deduplicated by series, because a season pack import writes eight records
/// and a rail of eight identical posters says less than one. The newest of them
/// wins, which is the one whose slot the caption shows.
///
/// **No time claim.** The board's header reads "9 episodes this week"; this is
/// one page of thirty records, which on a busy server may not reach back a
/// week, so the section says "latest imports" and prints no count. A figure
/// derived from however many rows happened to fit on a page is exactly the
/// plausible-but-wrong number the rest of this file refuses to print.
List<SonarrDownloadedEpisode> sonarrRecentlyDownloaded(
  List<dynamic> records, {
  required DateTime now,
  int limit = sonarrRecentlyDownloadedLimit,
}) {
  final dated = <(DateTime, SonarrDownloadedEpisode)>[];

  for (final raw in records) {
    final record = mapOrNull(raw);
    if (record == null) continue;

    final eventType = stringOrNull(record['eventType']);
    if (eventType != 'downloadFolderImported' &&
        eventType != 'downloadImported') {
      continue;
    }

    final date = _parseLocal(stringOrNull(record['date']));
    if (date == null) continue;

    final series = mapOrNull(record['series']);
    final seriesId = intOrNull(record['seriesId'] ?? series?['id']);
    if (seriesId == null || seriesId <= 0) continue;

    dated.add((
      date,
      SonarrDownloadedEpisode(
        seriesId: seriesId,
        seriesTitle: arrSeriesTitle(record) ?? 'Unknown series',
        slot: sonarrEpisodeSlot(record),
        images: (series?['images'] as List<dynamic>?) ?? const [],
        date: date,
        age: formatRelativeDateTime(date, now: now),
      ),
    ));
  }

  dated.sort((a, b) => b.$1.compareTo(a.$1));

  final seen = <int>{};
  final tiles = <SonarrDownloadedEpisode>[];
  for (final (_, tile) in dated) {
    if (!seen.add(tile.seriesId)) continue;
    tiles.add(tile);
    if (tiles.length == limit) break;
  }
  return List.unmodifiable(tiles);
}

final sonarrRecentlyDownloadedProvider =
    FutureProvider.autoDispose<List<SonarrDownloadedEpisode>>((ref) async {
      final records = await ref.watch(sonarrHistoryPageProvider.future);
      return sonarrRecentlyDownloaded(records, now: DateTime.now());
    });

/// One history record, resolved into the two lines the row draws.
@immutable
class SonarrHistoryEntry {
  const SonarrHistoryEntry({
    required this.subject,
    required this.event,
    required this.tone,
    required this.detail,
    required this.date,
  });

  /// The series and the slot: `Severance S02E04`.
  final String subject;

  /// What happened to it, in the shared history vocabulary — `Imported`,
  /// `Grabbed`, `Failed`.
  final String event;

  final StatusTone tone;

  /// Quality, size and how long ago, as far as the record carried them.
  final String detail;

  final DateTime date;

  String get spoken =>
      joinSpokenParts([subject, event, spokenFromDotted(detail)]);
}

/// The records from today, newest first, capped at [limit].
///
/// "Today" is the local calendar day of [now]. A record from 23:50 yesterday is
/// out even though it is twenty minutes old — the section is headed `today`,
/// and a heading is a promise.
List<SonarrHistoryEntry> sonarrHistoryToday(
  List<dynamic> records, {
  required DateTime now,
  int limit = sonarrHistoryTodayLimit,
}) {
  final local = now.toLocal();
  final entries = <SonarrHistoryEntry>[];

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
      SonarrHistoryEntry(
        subject: sonarrRecordSubject(record),
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

final sonarrHistoryTodayProvider =
    FutureProvider.autoDispose<List<SonarrHistoryEntry>>((ref) async {
      final records = await ref.watch(sonarrHistoryPageProvider.future);
      return sonarrHistoryToday(records, now: DateTime.now());
    });

// ─── Labels ─────────────────────────────────────────────────────────────────

const List<String> _weekdayNames = [
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];

/// `Today`, `Tomorrow`, then `Wed 3`.
///
/// Top-level and public where Radarr keeps its twin private inside the screen:
/// it is a windowing rule like the others — which day a timestamp belongs to,
/// relative to an explicit `now` — and the one boundary worth a test is that
/// 23:59 today and 00:01 tomorrow are different words.
///
/// English weekday names are hard-coded for the same reason the month names in
/// `string_utils.dart` are: English-only is a decision here, not debt, and
/// there is no `intl` dependency to reach for.
String sonarrDayLabel(DateTime date, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(date.year, date.month, date.day);
  final difference = day.difference(today).inDays;
  if (difference == 0) return 'Today';
  if (difference == 1) return 'Tomorrow';
  return '${_weekdayNames[day.weekday - 1]} ${day.day}';
}

/// `21:00`, in the reader's own timezone.
///
/// Twenty-four hour, like the board draws it, and unconditionally: the app has
/// no locale layer to ask, so a 12-hour form would be a guess wearing the
/// authority of a formatted time.
String sonarrClockLabel(DateTime date) {
  final local = date.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

// ─── Shared parsing ─────────────────────────────────────────────────────────

/// Parses an \*arr ISO timestamp into local time, or null when it is absent or
/// unreadable.
///
/// Local, always: every window on this screen is a run of local calendar days,
/// and Sonarr answers in UTC.
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
