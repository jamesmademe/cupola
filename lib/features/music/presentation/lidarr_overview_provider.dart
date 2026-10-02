/// What the Lidarr Overview reads, and the pure functions that shape it.
///
/// Built the same way Radarr's Overview provider is — every windowing
/// rule is a top-level pure function taking an explicit `now`, so the
/// boundaries are unit-testable without a clock or a container — but the shape
/// of the page differs from Radarr's in three places, and each difference is a
/// fact about what this client can actually ask Lidarr for:
///
///  * **There is no Coming up section.** Radarr derives its week from the
///    library, because a film carries its own three release dates on the row
///    the library list already returned. A Lidarr *artist* carries no dates at
///    all — the date belongs to the album — and [LidarrService.getAlbums] is
///    artist-scoped, so "what releases this week" would be one request per
///    artist, or the `/api/v1/calendar` endpoint this client does not call.
///    A window the client cannot fetch is a window that would have to be
///    invented, so the section is absent rather than empty.
///  * **The record is a track inside an album inside an artist.** One album
///    import writes one history record *per track*, so an ungrouped feed shows
///    the same album three times and calls it three events. [lidarrHistoryToday]
///    folds a page down to albums and only states a track count when it can
///    prove it has every record — see [lidarrHistoryPageIsComplete].
///  * **The backlog figure comes off the envelope, not off the page.**
///    `wanted/missing` answers twenty rows by default, so `records.length` is
///    the size of the page and not the size of the backlog. [ArrRecordPage.total]
///    is the only figure that answers the question the row asks.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/core/api/base_arr_service.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/core/utils/byte_format.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/core/utils/release_utils.dart';
import 'package:cupola/features/activity/domain/global_activity_status.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_formatters.dart'
    show formatRelativeDateTime;
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';
import 'package:cupola/features/music/presentation/music_provider.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';

/// Artists on the Recently added rail.
const int lidarrRecentlyAddedLimit = 6;

/// One page of history, and deliberately only one.
///
/// `getAllHistory()` walks up to fifty pages of two hundred and fifty records
/// to answer a question about the last few hours.
const int lidarrHistoryPageSize = 20;

/// Rows the History today section draws, after grouping.
const int lidarrHistoryTodayLimit = 3;

/// One page of `wanted/missing`, read for its envelope rather than its rows.
///
/// Twenty and not one, although the headline only needs `totalRecords`: the
/// rows are what the "across n artists" clause is counted from, and a page of
/// one could never support it. Twenty is the endpoint's own default, so this
/// costs nothing extra on the wire.
const int lidarrMissingPageSize = 20;

// ─── Shared shaping ─────────────────────────────────────────────────────────

/// A figure for a section subtitle, or an em dash when nobody answered.
///
/// The rule the whole function exists for: **a count whose source did not
/// answer is not zero**. A section that printed "0 releases" over a failed
/// fetch would be making a claim no server made, and it is the reassuring
/// direction of wrong — nothing to do here — which is exactly why it has to be
/// impossible to write by accident.
String lidarrCountLabel(int? count, {required String noun, String? plural}) {
  if (count == null) return '—';
  return '$count ${count == 1 ? noun : (plural ?? '${noun}s')}';
}

/// `Cindy Lee — Diamond Jubilee`, for the eye.
///
/// An \*arr record embeds `artist` and `album` as separate objects and this is
/// the only place the app joins them, so the em dash lives here rather than in
/// four row builders. Falls back through album, artist, then the release title
/// the record was grabbed under — the last of which is ugly and true, which
/// beats "Unknown" for a row whose whole job is to name a thing.
String lidarrRecordTitle(Map<String, dynamic> record) {
  final artist = arrArtistName(record);
  final album = arrAlbumTitle(record);
  if (artist != null && album != null) return '$artist, $album';
  return album ?? artist ?? arrReleaseTitle(record) ?? 'Unknown release';
}

/// The same fact, for the ear.
///
/// An em dash is punctuation, and a screen reader either names it ("em dash")
/// or swallows it depending on the user's verbosity setting; neither is what
/// the layout meant by it. Spoken, the two names are simply two clauses.
String lidarrRecordSpokenTitle(Map<String, dynamic> record) {
  final artist = arrArtistName(record);
  final album = arrAlbumTitle(record);
  if (artist != null && album != null) return joinSpokenParts([artist, album]);
  return album ?? artist ?? arrReleaseTitle(record) ?? 'Unknown release';
}

/// Parses an \*arr ISO timestamp into local time, or null when it is absent or
/// unreadable.
///
/// Local, always: every window on this screen is a run of local calendar days,
/// and Lidarr answers in UTC.
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

int? _sizeBytes(Map<String, dynamic> record) {
  final bytes =
      intOrNull(record['size']) ??
      intOrNull(mapOrNull(record['data'])?['size']);
  if (bytes == null || bytes <= 0) return null;
  return bytes;
}

// ─── Recently added ─────────────────────────────────────────────────────────

/// The newest [limit] artists added, newest first.
///
/// **Artists, where the board draws albums**, and the substitution is the
/// honest half of a blocked section rather than a shortcut: the board's rail is
/// six album covers captioned `Artist · Year`, which needs a library-wide
/// `GET /api/v1/album?includeArtist=true` this client has no method for —
/// `getAlbums` takes an `artistId`. The artist list is already loaded for the
/// KPI rail, carries `added`, and captions with a fact the model really holds
/// (`albumCount`). The rail therefore says less than the board asks for, and
/// nothing the server did not say.
///
/// An artist with no parseable `added` is dropped rather than sorted to one
/// end: the rail claims to be ordered by when things arrived, and an entry with
/// no arrival time cannot honour that claim in either direction.
List<LidarrArtist> lidarrRecentlyAdded(
  List<LidarrArtist> artists, {
  int limit = lidarrRecentlyAddedLimit,
}) {
  final dated = <(DateTime, LidarrArtist)>[];
  for (final artist in artists) {
    final added = _parseLocal(artist.added);
    if (added != null) dated.add((added, artist));
  }
  dated.sort((a, b) => b.$1.compareTo(a.$1));
  return List.unmodifiable(dated.take(limit).map((entry) => entry.$2));
}

/// The artist list, read so that a failure is still a failure when it arrives.
///
/// **[musicProvider] itself**, which reads `getArtistsOrThrow`: one read of
/// the library a session, shared with the wall and the KPI rail, as
/// `sonarrOverviewSeriesProvider` is. `noProviderRetry`, so a blip is the
/// user's Retry. Pull-to-refresh and the section's Retry invalidate it.
final lidarrOverviewArtistsProvider = musicProvider;

/// The newest arrivals, off [lidarrOverviewArtistsProvider].
final lidarrRecentlyAddedProvider =
    FutureProvider.autoDispose<List<LidarrArtist>>((ref) async {
      final artists = await ref.watch(lidarrOverviewArtistsProvider.future);
      return lidarrRecentlyAdded(artists);
      // Its source carries the flag, so this does.
    }, retry: noProviderRetry);

// ─── Needs attention ────────────────────────────────────────────────────────

/// The three conditions this screen can derive today.
///
/// Each carries its own tone, and that is the whole point of the enum: two of
/// these are faults and the third is backlog, which the five-arm tone rule
/// paints **neutral**. Collapsing them into one "attention" colour is how a
/// library with a normal wishlist ends up wearing the same amber as a broken
/// import.
enum LidarrAttentionKind {
  /// Lidarr grabbed the release and could not move it into the library.
  importFailed(StatusTone.warning, Icons.file_download_off_rounded),

  /// The transfer is not moving. A fault — the user did not ask for this.
  stalled(StatusTone.warning, Icons.sync_problem_rounded),

  /// Monitored albums with no files. Backlog, so neutral: nothing is broken,
  /// there is simply work outstanding — this is the resting state of every
  /// \*arr that is still following an artist.
  missingAlbums(StatusTone.neutral, Icons.album_outlined);

  const LidarrAttentionKind(this.tone, this.icon);

  final StatusTone tone;
  final IconData icon;
}

/// One row of Needs attention: what happened, to what, and when.
///
/// The per-row cross-service action the board draws ("Fix", "Search all") is
/// deliberately absent — those need a write this client does not make, and a
/// button that cannot do the thing it names is worse than no button.
@immutable
class LidarrAttentionItem {
  const LidarrAttentionItem({
    required this.kind,
    required this.headline,
    required this.detail,
    String? spokenHeadline,
  }) : _spokenHeadline = spokenHeadline;

  final LidarrAttentionKind kind;

  /// The fault and its subject: `Import failed · Alvvays — Blue Rev`.
  final String headline;

  /// The evidence: the service's own message, the client, the timestamp.
  /// Empty when the record carried none.
  final String detail;

  /// [headline] with its em dash resolved into a clause, when the two differ.
  final String? _spokenHeadline;

  StatusTone get tone => kind.tone;
  IconData get icon => kind.icon;

  /// The row as a sentence, with the dots the layout uses turned back into
  /// commas — `·` is decoration, and a screen reader either names it or drops
  /// it depending on the user's punctuation setting.
  String get spoken => joinSpokenParts([
    spokenFromDotted(_spokenHeadline ?? headline),
    spokenFromDotted(detail),
  ]);
}

/// Reads the faults out of a page of **raw** `/queue` records.
///
/// Raw, because `ArrQueueSnapshot` folds a queue down to one entry per album id
/// and keeps neither the release title nor `added` — and this section is
/// entirely made of those two.
///
/// Stalled is tested before import: a transfer that is not moving has not
/// reached the import stage at all, and Lidarr marks both with the same
/// `trackedDownloadStatus: warning`.
///
/// An in-flight import is **not** a row here, although the board draws one.
/// A healthy import is informational — blue, by the tone rule — and a blue row
/// under a heading that says "Needs attention" is the heading lying about its
/// own contents. It belongs to the Queue tab, which is where the header's link
/// would send you and where the same record is already drawn with its progress.
List<LidarrAttentionItem> lidarrQueueFaults(
  List<Map<String, dynamic>> records, {
  required DateTime now,
}) {
  final items = <LidarrAttentionItem>[];
  for (final record in records) {
    final title = lidarrRecordTitle(record);
    final spokenTitle = lidarrRecordSpokenTitle(record);
    final when = _parseLocal(stringOrNull(record['added']));
    final age = when == null ? null : formatRelativeDateTime(when, now: now);
    final message =
        stringOrNull(record['errorMessage']) ?? arrQueueWarningMessage(record);

    if (_isStalled(record)) {
      items.add(
        LidarrAttentionItem(
          kind: LidarrAttentionKind.stalled,
          headline: '${StateWord.stuck.label} · $title',
          spokenHeadline: '${StateWord.stuck.label} · $spokenTitle',
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
        LidarrAttentionItem(
          kind: LidarrAttentionKind.importFailed,
          headline: 'Import failed · $title',
          spokenHeadline: 'Import failed · $spokenTitle',
          detail: joinDisplayParts([message, age]),
        ),
      );
    }
  }
  return List.unmodifiable(items);
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
  // The canonical "One or more tracks expected in this release were not
  // imported" arrives as a pending import carrying a status message, which is
  // how the service says a human has to look at it — see `arrQueueSeverity`.
  return state == 'importpending' &&
      arrQueueSeverity(record) != ArrQueueSeverity.ok;
}

/// The backlog row, built from one page of `wanted/missing`.
///
/// Two figures, and they are read from two different places on purpose:
///
///  * **how many** comes from [ArrRecordPage.total], the envelope's
///    `totalRecords`. `records.length` is the size of the page — twenty — and a
///    library with three hundred gaps in it would read "20 missing", which is
///    wrong in the one direction that matters because it makes a large backlog
///    look finished.
///  * **across how many artists** is counted from the rows, and can therefore
///    only be stated when the page holds the whole set. When it does not, the
///    clause is dropped rather than qualified: "across 6 artists" computed from
///    a fifth of the backlog is a smaller, more precise-looking lie than no
///    clause at all.
///
/// A server whose envelope carried no readable total has told us nothing about
/// the size of the set, so the headline says `at least n` over the rows it
/// really has. Null when there is nothing to report.
LidarrAttentionItem? lidarrMissingAlbumsItem(ArrRecordPage page) {
  final total = page.total;
  final rows = page.records.map(mapOrNull).whereType<Map<String, dynamic>>();
  final complete = total != null && page.records.length >= total;

  final count = total ?? (rows.isEmpty ? 0 : rows.length);
  if (count <= 0) return null;

  final artists = <String>{for (final row in rows) ?arrArtistName(row)};
  final spread = complete && artists.isNotEmpty
      ? 'across ${artists.length} ${artists.length == 1 ? 'artist' : 'artists'}'
      : null;

  final headline = total == null
      ? 'At least $count missing monitored ${count == 1 ? 'album' : 'albums'}'
      : '$count missing monitored ${count == 1 ? 'album' : 'albums'}';

  return LidarrAttentionItem(
    kind: LidarrAttentionKind.missingAlbums,
    headline: headline,
    // Names the mechanism rather than an instruction: nothing is wrong, Lidarr
    // is simply still looking.
    detail: joinDisplayParts([spread, 'Lidarr keeps searching for them']),
  );
}

/// The raw `/queue` walk, with its envelope.
///
/// The equivalent of the private `_loadServiceQueueItems` in
/// `services_provider.dart`, stopping one step earlier: that one maps straight
/// to `ServiceQueueItem`, which carries title/subtitle/progress/warning and no
/// timestamp at all. The page and not its bare rows, for the reason
/// `radarrQueueRecordsProvider` gives: faults counted in a walk that stopped
/// short are a floor.
final lidarrQueueRecordsProvider = FutureProvider.autoDispose<ArrRecordPage>((
  ref,
) {
  return ref.watch(lidarrServiceProvider).getQueuePage();
});

/// One page of the wishlist, kept as a page so its envelope survives.
///
/// `getMissingPage` and not `getMissing`: the record-only getter throws the
/// `totalRecords` away, and the total is the entire reason this is fetched.
final lidarrMissingPageProvider = FutureProvider.autoDispose<ArrRecordPage>((
  ref,
) async {
  return ref
      .watch(lidarrServiceProvider)
      .getMissingPage(page: 1, pageSize: lidarrMissingPageSize);
});

/// Faults first, backlog last.
///
/// The order is the design's: what needs a decision before what is merely
/// outstanding.
final lidarrNeedsAttentionProvider =
    FutureProvider.autoDispose<List<LidarrAttentionItem>>((ref) async {
      final page = await ref.watch(lidarrQueueRecordsProvider.future);
      final missing = await ref.watch(lidarrMissingPageProvider.future);
      final backlog = lidarrMissingAlbumsItem(missing);
      return [
        ...lidarrQueueFaults(page.recordMaps, now: DateTime.now()),
        ?backlog,
      ];
    });

// ─── History today ──────────────────────────────────────────────────────────

/// One album's worth of today's history, resolved into the two lines the row
/// draws.
@immutable
class LidarrHistoryEntry {
  const LidarrHistoryEntry({
    required this.title,
    required this.spokenTitle,
    required this.event,
    required this.tone,
    required this.detail,
    required this.date,
    required this.trackCount,
  });

  /// `Cindy Lee — Diamond Jubilee`.
  final String title;

  /// The same, with the em dash spoken as a pause.
  final String spokenTitle;

  /// What happened to it, in the shared history vocabulary — `Imported`,
  /// `Grabbed`, `Failed`.
  final String event;

  final StatusTone tone;

  /// Quality, size or track count, and how long ago, as far as the records
  /// carried them.
  final String detail;

  /// The newest record in the group; what the row sorts and dates by.
  final DateTime date;

  /// How many records were folded into this row, or null when the page could
  /// not prove it held them all. **Never printed when null** — see
  /// [lidarrHistoryToday].
  final int? trackCount;

  String get spoken =>
      joinSpokenParts([spokenTitle, event, spokenFromDotted(detail)]);
}

/// Whether [page] holds every history record the server has.
///
/// The question the track count depends on. Two ways to know, and both are
/// about the envelope rather than about the rows:
///
///  * a readable `totalRecords` no larger than what came back means we have
///    the lot;
///  * no total at all leaves only the page size — a short page cannot have
///    been truncated, a full one very well may have been.
///
/// A full page is treated as incomplete even when it happens not to be, which
/// is the safe direction: the cost is a row that omits its track count, and the
/// alternative is a row that states "14 tracks" when the fifteenth was on page
/// two.
bool lidarrHistoryPageIsComplete(
  ArrRecordPage page, {
  int pageSize = lidarrHistoryPageSize,
}) {
  final total = page.total;
  if (total != null) return page.records.length >= total;
  return page.records.length < pageSize;
}

/// Today's records, folded to one row per album and event, newest first.
///
/// "Today" is the local calendar day of [now]. A record from 23:50 yesterday is
/// out even though it is twenty minutes old — the section is headed `today`,
/// and a heading is a promise.
///
/// **The fold is what makes this readable at all.** Lidarr's history is written
/// per *track*: importing a fourteen-track album writes fourteen
/// `trackFileImported` records, so the three-row cap would show one album three
/// times and imply three events. Grouping by album and event type turns that
/// back into the one thing that happened.
///
/// [complete] is passed rather than inferred because it is a fact about the
/// fetch, not about the records, and it decides what the row may claim:
///
///  * complete, several records → `FLAC · 14 tracks · 3 h ago`. The count is
///    exact, so it is stated.
///  * not complete, several records → no count and no size. A count taken from
///    a truncated page is a floor wearing the clothes of a total, and one
///    track's size read as the album's is the same error in bytes.
///  * exactly one record → quality, its own size, and its age, whatever the
///    page. One record cannot be a partial count of itself.
List<LidarrHistoryEntry> lidarrHistoryToday(
  List<dynamic> records, {
  required DateTime now,
  required bool complete,
  int limit = lidarrHistoryTodayLimit,
}) {
  final local = now.toLocal();
  final groups = <String, _HistoryGroup>{};

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
    // The album id keys the fold where the record carries one; the visible
    // title is the fallback, because two different albums with one title is a
    // far rarer accident than a record that embedded no album object.
    final albumId = intOrNull(mapOrNull(record['album'])?['id']);
    final key = '$eventType#${albumId ?? lidarrRecordTitle(record)}';

    final existing = groups[key];
    if (existing == null) {
      groups[key] = _HistoryGroup(
        record: record,
        eventType: eventType,
        date: date,
        count: 1,
        bytes: _sizeBytes(record),
      );
      continue;
    }

    // The newest record in the group becomes its face: it is the one whose
    // quality and timestamp the row prints, and the one the section sorts on.
    final newest = date.isAfter(existing.date);
    groups[key] = _HistoryGroup(
      record: newest ? record : existing.record,
      eventType: eventType,
      date: newest ? date : existing.date,
      count: existing.count + 1,
      bytes: _addBytes(existing.bytes, _sizeBytes(record)),
    );
  }

  final entries = groups.values.map((group) {
    // The shared \*arr table, not a local override of it. Lidarr's three own
    // spellings (`trackFileImported`, `trackFileRetagged`,
    // `albumImportIncomplete`) now live in `global_activity_status.dart`
    // beside Radarr's, Sonarr's and Readarr's. While they lived in a private
    // switch here, this Overview and the global Activity feed — reading the
    // same record — disagreed about the colour of a completed import.
    final (event, tone) = historyEventDisplay(group.eventType);
    final countable = complete && group.count > 1;
    final sizeBytes = group.count == 1 || countable ? group.bytes : null;

    return LidarrHistoryEntry(
      title: lidarrRecordTitle(group.record),
      spokenTitle: lidarrRecordSpokenTitle(group.record),
      event: event,
      tone: tone,
      detail: joinDisplayParts([
        _qualityName(group.record['quality']),
        countable ? '${group.count} tracks' : null,
        sizeBytes == null ? null : formatReleaseSize(sizeBytes),
        formatRelativeDateTime(group.date, now: now),
      ]),
      date: group.date,
      trackCount: countable ? group.count : null,
    );
  }).toList();

  entries.sort((a, b) => b.date.compareTo(a.date));
  return List.unmodifiable(entries.take(limit));
}

/// A fold in progress: the face record, how many rows landed on it, and their
/// total size so far.
@immutable
class _HistoryGroup {
  const _HistoryGroup({
    required this.record,
    required this.eventType,
    required this.date,
    required this.count,
    required this.bytes,
  });

  final Map<String, dynamic> record;
  final String eventType;
  final DateTime date;
  final int count;

  /// Null as soon as any record in the group carried no size: a sum missing a
  /// term looks exactly like a sum.
  final int? bytes;
}

int? _addBytes(int? a, int? b) => a == null || b == null ? null : a + b;

/// Today's history, from one page of twenty.
///
/// Sorted explicitly rather than on the server's default: the "today" filter
/// keeps whatever is *in* the page, so which twenty records arrive is the whole
/// question, and `date descending` is the only ordering under which page one is
/// the recent past.
final lidarrHistoryTodayProvider =
    FutureProvider.autoDispose<List<LidarrHistoryEntry>>((ref) async {
      final page = await ref
          .watch(lidarrServiceProvider)
          .getHistoryPage(
            page: 1,
            pageSize: lidarrHistoryPageSize,
            queryParameters: const {
              'sortKey': 'date',
              'sortDirection': 'descending',
            },
          );
      return lidarrHistoryToday(
        page.records,
        now: DateTime.now(),
        complete: lidarrHistoryPageIsComplete(page),
      );
    });

// ─── Root folders ───────────────────────────────────────────────────────────

/// One root folder, as far as `/api/v1/rootfolder` describes it.
@immutable
class LidarrRootFolder {
  const LidarrRootFolder({required this.path, required this.freeSpace});

  final String path;

  /// Bytes free, or null when the record did not say.
  final int? freeSpace;

  /// `1.8 TB free`, or an em dash when the server did not report it.
  ///
  /// **What the board draws and this cannot**: `2.2 TB used · 55% of 4 TB`.
  /// A root folder record carries `freeSpace` and no capacity, so the used
  /// figure, the percentage and the bar all need `GET /api/v1/diskspace`, which
  /// this client does not call. A bar drawn from free space alone would have to
  /// invent its own denominator, so there is no bar.
  String get freeLabel =>
      freeSpace == null ? '—' : '${formatBytes(freeSpace!)} free';
}

/// The configured root folders, tolerating the shapes the record arrives in.
List<LidarrRootFolder> lidarrRootFolders(List<Map<String, dynamic>> records) {
  final folders = <LidarrRootFolder>[];
  for (final record in records) {
    final path = stringOrNull(record['path']);
    if (path == null) continue;
    folders.add(
      LidarrRootFolder(path: path, freeSpace: intOrNull(record['freeSpace'])),
    );
  }
  return List.unmodifiable(folders);
}

/// Where this Lidarr files music, and how much room is left there.
///
/// `fetchRootFolders` is the one \*arr helper that lets a failure travel, by
/// design, so an unreachable server takes this section into its error state
/// rather than claiming the library has nowhere to go.
final lidarrRootFoldersProvider =
    FutureProvider.autoDispose<List<LidarrRootFolder>>((ref) async {
      final records = await ref.watch(lidarrServiceProvider).getRootFolders();
      return lidarrRootFolders(records);
    });
