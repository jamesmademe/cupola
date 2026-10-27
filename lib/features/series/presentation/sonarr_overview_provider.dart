/// What the Sonarr Overview reads, and the pure functions that shape it.
///
/// Sonarr shares Radarr's bar exactly: Overview, Library, Calendar, Queue,
/// Wanted, History, so this file is deliberately the sibling of
/// `radarr_overview_provider.dart` and departs from it only where the record
/// forces it to. The record here is an **episode inside a season inside a
/// series**, and that is the one difference that runs through everything: a
/// count of episodes must say episodes, a row names the slot (`S2 E5`) as well
/// as the series, and the week window can only be built out of what a *series*
/// row carries.
///
/// The one structural departure: Radarr derives its Coming up from the library
/// because a film's dates are on the film. Episodes are not on the series row
/// at all: the honest source is `GET /api/v3/calendar`, which `SonarrService`
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

import 'package:cupola/core/utils/parallel_reads.dart';
import 'package:cupola/core/api/base_arr_service.dart';
import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/core/utils/arr_overview.dart';
import 'package:cupola/core/utils/date_format.dart' show formatRelativeDateTime;
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/core/utils/episode_code.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/series/domain/models/sonarr_series.dart';
import 'package:cupola/features/series/presentation/series_provider.dart';
import 'package:cupola/features/services/domain/attention_door.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

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
/// for one thing only: how many distinct series they span, and only when the
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
/// reasons: nothing is scheduled, or this server never sent the field, and
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
/// absent. The wide one, the server did not answer at all, is not this
/// function's to catch and cannot be caught here, because a failed fetch and an
/// empty library arrive as the same `[]`. It is caught one layer down, by
/// [sonarrOverviewSeriesProvider] reading `getSeriesOrThrow`: by the time a
/// list reaches this function it is a list Sonarr actually sent, so `[]` means
/// an empty library.
///
/// True as soon as one series carries a date: the server answers the question,
/// so any series without one genuinely has nothing scheduled. True also for a
/// library where nothing *could* air: every series ended or was deleted, and an
/// empty week is then simply the truth. False only in the third case, a library
/// with running series and not one date in it, which is what an older Sonarr or
/// a proxy stripping fields looks like.
bool sonarrCanReportAirings(List<SonarrSeries> series) {
  var expectsDates = false;
  for (final entry in series) {
    if (parseLocalInstant(entry.nextAiring) != null) return true;
    if (sonarrMayStillAir(entry)) expectsDates = true;
  }
  return !expectsDates;
}

/// Whether this series could have a future episode at all.
///
/// Sonarr's series `status` is a small closed vocabulary; `continuing` and
/// `upcoming` are the two that mean "more is coming". `ended` and `deleted`
/// mean the opposite, and `unknown` is treated as ended rather than as
/// expecting a date: the alternative makes one un-catalogued series in a
/// library of finished shows suppress the whole section.
bool sonarrMayStillAir(SonarrSeries series) {
  final status = series.status.toLowerCase();
  return status == 'continuing' || status == 'upcoming';
}

/// The series with an episode due inside the next [days] local calendar days.
///
/// The window opens at local midnight **today** (inclusive) and closes at local
/// midnight [days] days later (exclusive): an episode that aired earlier today
/// is still part of today's row (the user has not seen this screen yet), and
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
/// figure: plausible.
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
    final airsAt = parseLocalInstant(entry.nextAiring);
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
/// **[seriesProvider] itself.** It was a second copy of the same request,
/// kept apart for its default retry, and with the KPI rail's a third: the
/// series list was downloaded up to three times a session. One read now,
/// `noProviderRetry` like the wall and the rail, so a blip is the user's
/// Retry. Pull-to-refresh invalidates it explicitly.
final sonarrOverviewSeriesProvider = seriesProvider;

/// The week, from the library.
///
/// `noProviderRetry`, because its source ([sonarrOverviewSeriesProvider])
/// carries it: a derivation that dropped it would retry, one step down, what
/// the source refused. See `lib/core/providers/provider_retry.dart`.
///
/// That Retry is reachable now, which it was not while the source swallowed its
/// own failure into `[]`, and it has to invalidate the source too, not only
/// this fold: the source is plain, so a Retry that re-ran the fold alone read
/// the same cached error straight back and could never recover.
final sonarrAiringWeekProvider = FutureProvider.autoDispose<SonarrAiringWeek>((
  ref,
) async {
  final series = await ref.watch(sonarrOverviewSeriesProvider.future);
  return sonarrAiringWeek(series, now: DateTime.now());
}, retry: noProviderRetry);

// ─── Needs attention ────────────────────────────────────────────────────────

/// The four conditions this screen can derive today.
///
/// Each carries its own tone, and that is the whole point of the enum: two of
/// these are faults and two are backlog, which the five-arm tone rule paints
/// neutral. Painting the backlog amber is the single most common way that rule
/// is broken: a library with twelve episodes still to find is not a library
/// that is broken.
enum SonarrAttentionKind implements ArrAttentionKind {
  /// Sonarr grabbed the release and could not move it into the library.
  importFailed(StatusTone.warning, Icons.file_download_off_rounded),

  /// The transfer is not moving. A fault: the user did not ask for this.
  stalled(StatusTone.warning, Icons.sync_problem_rounded),

  /// Monitored episodes that have aired and are not on disk. Backlog: nothing
  /// is broken, there is simply work outstanding.
  missing(StatusTone.neutral, Icons.radar_rounded),

  /// Episodes on disk below the configured quality cutoff. Backlog too.
  belowCutoff(StatusTone.neutral, Icons.upgrade_rounded);

  const SonarrAttentionKind(this.tone, this.icon);

  @override
  final StatusTone tone;

  @override
  final IconData icon;
}

/// One row of Needs attention (`ArrAttentionItem`).
typedef SonarrAttentionItem = ArrAttentionItem<SonarrAttentionKind>;

/// The slot a queue or history record is about: `S2 E5`, or `S4` for a season
/// pack, or null when the record names neither.
///
/// [arrEpisodeCode] needs both numbers and answers null without them, which is
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
  return formatSeasonCode(season);
}

/// `Slow Horses S4 E6`: the subject of a row, as far as the record names it.
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
/// id and keeps neither the release title nor `added`, and this section is
/// entirely made of those two. On Sonarr the fold costs more than on Radarr: a
/// season pack and three single episodes of one series collapse to one entry,
/// so three of the four faults would vanish.
///
/// Stalled is tested before import: a transfer that is not moving has not
/// reached the import stage at all, and Sonarr marks both with the same
/// `trackedDownloadStatus: warning`.
///
/// A season pack is one torrent and one record per episode, and one download is
/// one fault: its records are read together, and the row names the pack
/// (`Slow Horses S4 E1–E6`) rather than the first episode it happens to list.
///
/// Several downloads in one of the two states are one row (`3 downloads
/// stuck`, the series in the detail) whose door is the Queue tab, which lists
/// them all; one of a kind keeps its own row and opens its own page.
/// [instanceId] is the connection the records were read from, which a
/// download's page is addressed by, and [cutShort] says the walk stopped on a
/// full page, so a count taken in it is a floor.
List<SonarrAttentionItem> sonarrQueueFaults(
  List<Map<String, dynamic>> records, {
  required DateTime now,
  String instanceId = '',
  bool cutShort = false,
}) {
  final items = <SonarrAttentionItem>[];
  for (final download in _byDownload(records)) {
    // The download's fault is its worst record's: a stall before an import
    // (a transfer that is not moving has not reached the import stage).
    final stalled = download.where(isStalledRecord).firstOrNull;
    final record = stalled ?? download.where(isImportFaultRecord).firstOrNull;
    if (record == null) continue;

    final subject = download.length == 1
        ? sonarrRecordSubject(record)
        : _packSubject(download) ?? sonarrRecordSubject(record);
    final when = parseLocalInstant(stringOrNull(record['added']));
    final age = when == null ? null : formatRelativeDateTime(when, now: now);
    final message =
        stringOrNull(record['errorMessage']) ?? arrQueueWarningMessage(record);
    final door = arrQueueRecordDoor(record, instanceId: instanceId);

    items.add(
      stalled != null
          ? SonarrAttentionItem(
              kind: SonarrAttentionKind.stalled,
              headline: '${StateWord.stuck.label}\u00A0· $subject',
              detail: joinDisplayParts([
                stringOrNull(record['downloadClient']),
                message,
                age,
              ]),
              door: door,
              subject: subject,
            )
          : SonarrAttentionItem(
              kind: SonarrAttentionKind.importFailed,
              headline: 'Import failed\u00A0· $subject',
              detail: joinDisplayParts([message, age]),
              door: door,
              subject: subject,
            ),
    );
  }
  return foldAttention<SonarrAttentionItem, SonarrAttentionKind>(
    items,
    kindOf: (item) => item.kind,
    merge: (kind, members) {
      final words = kind == SonarrAttentionKind.stalled
          ? stuckDownloadsWords(members.length, floor: cutShort)
          : failedImportsWords(members.length, floor: cutShort);
      return SonarrAttentionItem(
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

/// The records of [records] one download at a time, in the order the queue
/// lists them: a season pack is one torrent and a record per episode, all
/// carrying the one `downloadId`. A record with no client id is its own
/// download.
List<List<Map<String, dynamic>>> _byDownload(
  List<Map<String, dynamic>> records,
) {
  final downloads = <List<Map<String, dynamic>>>[];
  final byKey = <String, List<Map<String, dynamic>>>{};
  for (final record in records) {
    final key = stringOrNull(record['downloadId'])?.trim().toLowerCase();
    if (key == null || key.isEmpty) {
      downloads.add([record]);
      continue;
    }
    final existing = byKey[key];
    if (existing != null) {
      existing.add(record);
    } else {
      final download = [record];
      byKey[key] = download;
      downloads.add(download);
    }
  }
  return downloads;
}

/// A pack in a sentence: the series and the episodes its records name,
/// `Slow Horses S4 E1–E6`. Null when the records name no series or no
/// episode.
String? _packSubject(List<Map<String, dynamic>> records) {
  final series = arrSeriesTitle(records.first);
  final bySeason = <int, List<int>>{};
  for (final record in records) {
    final episode = mapOrNull(record['episode']);
    final season = intOrNull(
      episode?['seasonNumber'] ?? record['seasonNumber'],
    );
    final number = intOrNull(
      episode?['episodeNumber'] ?? record['episodeNumber'],
    );
    if (season == null || number == null) continue;
    bySeason.putIfAbsent(season, () => []).add(number);
  }
  final runs = episodeRunsLine({
    for (final season in bySeason.keys.toList()..sort())
      season: bySeason[season]!.toSet().toList()..sort(),
  });
  if (series == null || runs == null) return null;
  return '$series $runs';
}

/// The missing-episodes backlog row, or null when there is nothing to report,
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
    // "across 5 series" only when the page provably held every record: see
    // [sonarrSeriesSpread]. Otherwise the mechanism, which is true at any size:
    // nothing is wrong, Sonarr is still looking.
    detail: seriesCount == null
        ? 'Sonarr keeps searching for them'
        : seriesCount == 1
        ? 'in 1 series'
        : 'across $seriesCount series',
    door: const AttentionDoor.tab(ServiceTab.wanted),
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
    // Wanted lists what is below its cutoff beside what is missing.
    door: const AttentionDoor.tab(ServiceTab.wanted),
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

/// The raw `/queue` walk, with its envelope.
///
/// The equivalent of the private `_loadServiceQueueItems` in
/// `services_provider.dart`, stopping one step earlier: that one maps straight
/// to `ServiceQueueItem`, which carries title/subtitle/progress/warning and no
/// timestamp at all. The page and not its bare rows, for the reason
/// `radarrQueueRecordsProvider` gives: faults counted in a walk that stopped
/// short are a floor.
final sonarrQueueRecordsProvider = FutureProvider.autoDispose<ArrRecordPage>((
  ref,
) {
  return ref.watch(sonarrServiceProvider).getQueuePage();
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

      // Both reads start together; each degrades to nothing on its own.
      final missingRead = service
          .getMissingPage(page: 1, pageSize: sonarrBacklogPageSize)
          .then<SonarrAttentionItem?>(
            (page) => sonarrMissingEpisodesItem(
              page.total,
              seriesCount: sonarrSeriesSpread(page),
            ),
          )
          .catchError((Object _) => null);
      final cutoffRead = service
          .getCutoffPage(page: 1, pageSize: sonarrBacklogPageSize)
          .then<SonarrAttentionItem?>(
            (page) => sonarrBelowCutoffItem(page.total),
          )
          .catchError((Object _) => null);

      final missing = await missingRead;
      final cutoff = await cutoffRead;
      return [?missing, ?cutoff];
    });

/// Faults first, backlog last.
///
/// The order is the design's: what needs a decision before what is merely
/// outstanding.
final sonarrNeedsAttentionProvider =
    FutureProvider.autoDispose<List<SonarrAttentionItem>>((ref) async {
      final (page, backlog) = await readTogether(
        ref.watch(sonarrQueueRecordsProvider.future),
        ref.watch(sonarrBacklogProvider.future),
      );
      return [
        ...sonarrQueueFaults(
          page.recordMaps,
          now: DateTime.now(),
          // The connection the queue was read from: a download's page is
          // addressed by it.
          instanceId:
              ref.watch(activeInstanceProvider(ServiceKey.sonarr))?.id ?? '',
          cutShort: page.cutShort,
        ),
        ...backlog,
      ];
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
    this.tmdbId,
    required this.seriesTitle,
    required this.slot,
    required this.images,
    required this.date,
    required this.age,
  });

  /// Sonarr's series id: required, because the tile is a link and a poster
  /// that cannot navigate is a promise the page cannot keep.
  final int seriesId;

  /// TMDB's id of the series, when the embedded series carries it (Sonarr
  /// v4): the series' own page opens by it.
  final int? tmdbId;

  final String seriesTitle;

  /// `S2 E4`, or null when the record named no slot.
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

    final date = parseLocalInstant(stringOrNull(record['date']));
    if (date == null) continue;

    final series = mapOrNull(record['series']);
    final seriesId = intOrNull(record['seriesId'] ?? series?['id']);
    if (seriesId == null || seriesId <= 0) continue;

    dated.add((
      date,
      SonarrDownloadedEpisode(
        seriesId: seriesId,
        tmdbId: intOrNull(series?['tmdbId']),
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
typedef SonarrHistoryEntry = OverviewHistoryEntry;

/// The records from today, newest first, capped at [limit].
///
/// "Today" is the local calendar day of [now]. A record from 23:50 yesterday is
/// out even though it is twenty minutes old. The section is headed `today`,
/// and a heading is a promise.
List<SonarrHistoryEntry> sonarrHistoryToday(
  List<dynamic> records, {
  required DateTime now,
  int limit = sonarrHistoryTodayLimit,
}) => overviewHistoryToday(
  records,
  now: now,
  limit: limit,
  subjectOf: (record) => sonarrRecordSubject(record),
);

final sonarrHistoryTodayProvider =
    FutureProvider.autoDispose<List<SonarrHistoryEntry>>((ref) async {
      final records = await ref.watch(sonarrHistoryPageProvider.future);
      return sonarrHistoryToday(records, now: DateTime.now());
    });

// ─── Shared parsing ─────────────────────────────────────────────────────────
