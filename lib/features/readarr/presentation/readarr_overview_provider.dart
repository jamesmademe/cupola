/// What the Readarr Overview reads, and the pure functions that shape it.
///
/// **This is the intersection of the board and the client, not the board.**
/// `HomeReadarr` draws five regions; two of them are asked of endpoints
/// `ReadarrService` does not call and no model in `lib/features/readarr`
/// represents, so they are absent rather than faked:
///
///  * **Coming up** needs `GET /api/v1/calendar`. Unlike Radarr, where the
///    three release dates already ride on every library row, so its window is a
///    filter over data in hand. Readarr's library entity is the *author*, and
///    an author carries no release date at all. There is nothing client-side to
///    filter.
///  * **Recently added** needs `GET /api/v1/book`. `ReadarrAuthor` is the only
///    library model there is; it has no `added` and no `images`, so the rail
///    would have neither an order nor a poster.
///
/// What is left is derived from calls the client demonstrably makes:
/// `getAuthors()` (already loading for the KPI rail), `getQueue()` and
/// `getHistory()`, plus `fetchRootFolders()` and `getCutoffPage()` inherited
/// from `ArrActivityMixin`.
///
/// Every windowing rule lives in a top-level pure function taking an explicit
/// `now`, so the boundaries are unit-testable without a clock or a container,
/// the same shape `radarr_overview_provider.dart` established.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/utils/parallel_reads.dart';
import 'package:cupola/core/api/base_arr_service.dart';
import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/core/utils/byte_format.dart';
import 'package:cupola/core/utils/date_format.dart' show formatRelativeDateTime;
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/core/utils/release_utils.dart';
import 'package:cupola/features/activity/domain/global_activity_status.dart';
import 'package:cupola/features/readarr/domain/models/readarr_models.dart';
import 'package:cupola/features/readarr/presentation/readarr_provider.dart';
import 'package:cupola/features/services/domain/attention_door.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// One page of history, and deliberately only one.
///
/// `getAllHistory()` walks up to fifty pages of two hundred and fifty records
/// to answer a question about the last few hours.
const int readarrHistoryPageSize = 20;

/// Rows the History today section draws.
const int readarrHistoryTodayLimit = 3;

/// One page of a backlog endpoint.
///
/// Nothing here reads a backlog *record*: the row prints the envelope's
/// `totalRecords` and the rows are discarded. The default page rather than a
/// page of one, because the size is what every other \*arr caller in the app
/// asks for and a one-row page is the kind of request a fork answers oddly.
const int readarrBacklogPageSize = 20;

// ─── Titles ─────────────────────────────────────────────────────────────────

/// The name of the thing a Readarr queue or history record is about.
///
/// Not `arrPrimaryMediaTitle`: that helper knows movie, series, album and
/// artist and has **no book arm**, so on a Readarr record every one of its four
/// lookups misses and it answers null. Local rather than a fifth arm added to
/// `lib/core/utils/arr_activity_display.dart`, which is outside this change's
/// paths: see `found`.
///
/// Book before author because the book is the subject: `Import failed ·
/// Orbital` is the sentence the board writes, and "Import failed · Samantha
/// Harvey" would name the wrong noun. `sourceTitle`/`title` last, because the
/// raw release name (`Orbital.2023.RETAIL.EPUB-XYZ`) is what the record carries
/// when the server could not match it to anything: true, and the least
/// readable of the three.
String readarrRecordTitle(Map<String, dynamic> record) {
  return stringOrNull(mapOrNull(record['book'])?['title']) ??
      stringOrNull(mapOrNull(record['author'])?['authorName']) ??
      arrReleaseTitle(record) ??
      'Unknown release';
}

// ─── Needs attention ────────────────────────────────────────────────────────

/// The four conditions this screen can derive today, and their tones.
///
/// The tones are the point of the enum. Two of these are faults and two are
/// backlog, and the five-arm rule paints the pairs differently: collapsing them
/// into a single "attention" colour is how a pile of missing books ends up
/// wearing the same amber as a broken import.
enum ReadarrAttentionKind {
  /// Readarr grabbed the release and could not move it into the library.
  importFailed(StatusTone.warning, Icons.file_download_off_rounded),

  /// The transfer is not moving. A fault: the user did not ask for this.
  stalled(StatusTone.warning, Icons.sync_problem_rounded),

  /// Monitored books with no file on disk. Backlog, so neutral: nothing is
  /// broken, there is simply work outstanding.
  missingBooks(StatusTone.neutral, Icons.menu_book_outlined),

  /// Books on disk in a format below the quality cutoff. Backlog again: the
  /// book is readable today and Readarr is merely still looking for a better
  /// copy.
  belowCutoff(StatusTone.neutral, Icons.upgrade_rounded);

  const ReadarrAttentionKind(this.tone, this.icon);

  final StatusTone tone;
  final IconData icon;
}

/// One row of Needs attention: what happened, to what, and when.
///
/// Every row leads somewhere: a download's own page for one stuck or failed
/// download, the Queue tab for the several a folded row stands for, the
/// Wanted tab for the backlog. What Readarr can do about a download it cannot
/// import ("Manual import", "Search all") is a `POST /api/v1/command` write
/// the client does not make, so no row carries a verb: the page it opens does.
@immutable
class ReadarrAttentionItem {
  const ReadarrAttentionItem({
    required this.kind,
    required this.headline,
    required this.detail,
    this.door,
    this.subject,
    this.count = 1,
    String? spokenHeadline,
  }) : _spokenHeadline = spokenHeadline;

  final ReadarrAttentionKind kind;

  /// The fault and its subject: `Import failed · Orbital`.
  final String headline;

  /// The evidence: the service's own message, the client, the timestamp.
  /// Empty when the record carried none.
  final String detail;

  /// Where the row leads, or null where the app has no place that shows it.
  final AttentionDoor? door;

  /// What the fault is about, bare (`Orbital`), for a folded row to name.
  final String? subject;

  /// How many faults the row stands for: one, or the downloads a folded row
  /// folds. The section's own count adds these, so folding never changes how
  /// many things need attention.
  final int count;

  /// [headline] as the ear should hear it, where it differs (`at least 3`
  /// for a floor).
  final String? _spokenHeadline;

  StatusTone get tone => kind.tone;
  IconData get icon => kind.icon;

  /// The row as a sentence, with the dots the layout uses turned back into
  /// commas: `·` is decoration, and a screen reader either names it or drops
  /// it depending on the user's punctuation setting.
  String get spoken => joinSpokenParts([
    spokenFromDotted(_spokenHeadline ?? headline),
    spokenFromDotted(detail),
  ]);
}

// There is no standing "upstream is archived" row here, and its absence is
// deliberate. It was a constant: derived from nothing, confirmed by no request
// and clearable by none, pushed onto the head of this list on every load, so
// the section's count could never read below 1 and the resting state
// ("Nothing needs you") was unreachable by construction. A permanent,
// undismissable row inside a section named for things that need you teaches the
// user to stop reading the count, which is the one part of the section visible
// without scrolling. The board (`HomeReadarr.dc.html`) draws no such row. The
// fact itself is true and is stated where a fact about the service belongs:
// `readarr_service.dart` and `service_tab.dart`, not in the fault list.

/// Reads the faults out of a page of **raw** `/queue` records.
///
/// Raw, because `ArrQueueSnapshot` folds a queue down to one entry per media id
/// and keeps neither the release title nor `added`, and these rows are
/// entirely made of those two.
///
/// Stalled is tested before import: a transfer that is not moving has not
/// reached the import stage at all, and Readarr marks both with the same
/// `trackedDownloadStatus: warning`.
///
/// Several downloads in one of the two states are one row (`3 downloads
/// stuck`, the titles in the detail) whose door is the Queue tab, which lists
/// them all; one of a kind keeps its own row and opens its own page. The
/// records of one download count once. [instanceId] is the connection the
/// records were read from, which a download's page is addressed by, and
/// [cutShort] says the walk stopped on a full page, so a count taken in it is
/// a floor.
List<ReadarrAttentionItem> readarrQueueFaults(
  List<Map<String, dynamic>> records, {
  required DateTime now,
  String instanceId = '',
  bool cutShort = false,
}) {
  final items = <ReadarrAttentionItem>[];
  for (final record in records) {
    final title = readarrRecordTitle(record);
    final when = _parseLocal(stringOrNull(record['added']));
    final age = when == null ? null : formatRelativeDateTime(when, now: now);
    final message =
        stringOrNull(record['errorMessage']) ?? arrQueueWarningMessage(record);
    final door = arrQueueRecordDoor(record, instanceId: instanceId);

    if (_isStalled(record)) {
      items.add(
        ReadarrAttentionItem(
          kind: ReadarrAttentionKind.stalled,
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

    if (_isImportFault(record)) {
      items.add(
        ReadarrAttentionItem(
          kind: ReadarrAttentionKind.importFailed,
          headline: 'Import failed\u00A0· $title',
          detail: joinDisplayParts([message, age]),
          door: door,
          subject: title,
        ),
      );
    }
  }
  return foldAttention<ReadarrAttentionItem, ReadarrAttentionKind>(
    items,
    kindOf: (item) => item.kind,
    // The download a row is: the books of one torrent are one fault.
    identityOf: (item) => item.door ?? item,
    merge: (kind, members) {
      final words = kind == ReadarrAttentionKind.stalled
          ? stuckDownloadsWords(members.length, floor: cutShort)
          : failedImportsWords(members.length, floor: cutShort);
      return ReadarrAttentionItem(
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

/// The backlog row (books with no file), or null when there is none.
///
/// **Derived from the author list, not from `wanted/missing`, and that is a
/// deliberate choice about agreement rather than about accuracy.** The KPI rail
/// two inches above this row prints `Missing` from exactly this arithmetic
/// (`service_kpi_provider.dart`, `_readarrKpis`); asking `wanted/missing` for
/// its envelope total would put a second, differently-derived figure under the
/// same word on the same screen: monitored-filtered on one side and not on the
/// other, and two numbers that disagree teach the user to trust neither.
///
/// The sums are taken before the clamp, not after, for the same reason: it is
/// the rail's arithmetic character for character, so the two figures cannot
/// drift apart on a server whose statistics are odd.
///
/// "across N authors" counts the authors carrying a gap, which is the one part
/// of the board's phrasing only the author list can answer at all.
ReadarrAttentionItem? readarrMissingBooksItem(List<ReadarrAuthor> authors) {
  var books = 0;
  var files = 0;
  var authorsWithGaps = 0;
  for (final author in authors) {
    books += author.bookCount;
    files += author.bookFileCount;
    if (author.bookCount > author.bookFileCount) authorsWithGaps++;
  }
  final missing = (books - files).clamp(0, books);
  if (missing <= 0) return null;

  return ReadarrAttentionItem(
    kind: ReadarrAttentionKind.missingBooks,
    headline: missing == 1
        ? '1 book missing a file'
        : '$missing books missing a file',
    // "across N authors", not "monitored": the figure above is not filtered by
    // `monitored`, and a word in the headline that the arithmetic does not
    // honour is the same lie as a wrong number.
    detail: authorsWithGaps == 1
        ? 'across 1 author'
        : 'across $authorsWithGaps authors',
    door: const AttentionDoor.tab(ServiceTab.wanted),
  );
}

/// The upgrade backlog row (books on disk below the quality cutoff), or null
/// when there is none.
///
/// Takes the **envelope total**, never `records.length`: `wanted/cutoff`
/// answers twenty rows by default, so a count taken from the page said "20
/// books below cutoff" for every library with more than twenty. A null total is
/// a server that did not say, and says nothing: `getCutoffPage` already
/// degrades a fork that does not serve the endpoint to a null total for exactly
/// this reason, so "no answer" and "none" cannot come out as the same row.
///
/// Neutral, like the missing row. Nothing is broken: the book is on disk and
/// readable today, Readarr is merely still looking for a better copy. The
/// board's detail names the formats (`epub wanted, have azw3`), which needs a
/// per-book read the envelope cannot give without claiming one row's formats
/// speak for the rest, so the row states the standing fact instead.
ReadarrAttentionItem? readarrBelowCutoffItem(int? total) {
  if (total == null || total <= 0) return null;
  return ReadarrAttentionItem(
    kind: ReadarrAttentionKind.belowCutoff,
    headline: total == 1
        ? '1 book below your quality cutoff'
        : '$total books below your quality cutoff',
    detail: 'Readarr keeps searching for an upgrade',
    // Wanted lists what is below its cutoff beside what is missing.
    door: const AttentionDoor.tab(ServiceTab.wanted),
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
  // The canonical "Unable to Import Automatically" arrives as a pending import
  // carrying a status message, which is how an \*arr says a human has to look
  // at it: see `arrQueueSeverity`.
  return state == 'importpending' &&
      arrQueueSeverity(record) != ArrQueueSeverity.ok;
}

/// The raw `/queue` walk, with its envelope.
///
/// Its own rather than `readarrQueueProvider`, which the KPI rail awaits
/// inside a `catch` and keeps for the life of the app under `noProviderRetry`;
/// this one goes with the section, and a section that cannot read the queue
/// has to *say so* rather than claim nothing is wrong. The page and not its
/// bare rows, for the reason `radarrQueueRecordsProvider` gives: faults
/// counted in a walk that stopped short are a floor.
final readarrQueueRecordsProvider = FutureProvider.autoDispose<ArrRecordPage>((
  ref,
) {
  return ref.watch(readarrServiceProvider).getQueuePage();
});

/// The upgrade backlog, on its own so it cannot take the faults down with it.
///
/// `getCutoffPage` swallows a fork that does not serve `wanted/cutoff` into a
/// null total, but a server that answers with a 500 still throws, and the
/// faults above are the subject of this section, so a cutoff endpoint that
/// failed reports no row rather than replacing a broken import with an error
/// slot.
final readarrBelowCutoffProvider =
    FutureProvider.autoDispose<ReadarrAttentionItem?>((ref) async {
      try {
        final page = await ref
            .watch(readarrServiceProvider)
            .getCutoffPage(page: 1, pageSize: readarrBacklogPageSize);
        return readarrBelowCutoffItem(page.total);
      } catch (_) {
        return null;
      }
    });

/// Faults, then backlog.
///
/// The order is the board's, and it is an order of decision: what needs a
/// decision before what is merely outstanding. Within the backlog, missing
/// before below-cutoff: a book with no file at all outranks one that is merely
/// the wrong format, which is the order the board draws too.
///
/// `retry: noProviderRetry` because [readarrAuthorsProvider] carries it: a
/// derivation that dropped it would re-run a dark library ten times behind a
/// backoff that its source had declined.
final readarrNeedsAttentionProvider =
    FutureProvider.autoDispose<List<ReadarrAttentionItem>>((ref) async {
      // The three reads start together (see radarrNeedsAttentionProvider).
      final (page, authors, cutoff) = await readTogether3(
        ref.watch(readarrQueueRecordsProvider.future),
        ref.watch(readarrAuthorsProvider.future),
        ref.watch(readarrBelowCutoffProvider.future),
      );
      final backlog = readarrMissingBooksItem(authors);
      return [
        ...readarrQueueFaults(
          page.recordMaps,
          now: DateTime.now(),
          // The connection the queue was read from: a download's page is
          // addressed by it.
          instanceId:
              ref.watch(activeInstanceProvider(ServiceKey.readarr))?.id ?? '',
          cutShort: page.cutShort,
        ),
        ?backlog,
        ?cutoff,
      ];
    }, retry: noProviderRetry);

// ─── Root folder ────────────────────────────────────────────────────────────

/// A library root and how much room is left on it.
///
/// [freeBytes] is nullable and never defaulted to zero: a root folder resource
/// that did not carry `freeSpace` (an older build, a path the server cannot
/// stat) has told us nothing about the disk, and `0 B free` is an alarm about
/// a disk nobody measured.
@immutable
class ReadarrRootFolder {
  const ReadarrRootFolder({required this.path, required this.freeBytes});

  final String path;
  final int? freeBytes;

  /// `840 GB free`, or the em dash when the server did not say.
  String get freeLabel =>
      freeBytes == null ? '—' : '${formatBytes(freeBytes!)} free';

  /// The em dash is a typographic shrug; read aloud it is either "em dash" or
  /// silence, and neither says why the number is absent.
  String get spoken => joinSpokenParts([
    path,
    freeBytes == null ? 'free space unknown' : freeLabel,
  ]);
}

/// Maps `/rootfolder` records, dropping any that carry no path.
///
/// A row with no path is a row that cannot name what it is reporting on, and a
/// free-space figure attached to nothing is worse than one row fewer.
List<ReadarrRootFolder> readarrRootFolders(List<Map<String, dynamic>> records) {
  final folders = <ReadarrRootFolder>[];
  for (final record in records) {
    final path = stringOrNull(record['path']);
    if (path == null || path.isEmpty) continue;
    folders.add(
      ReadarrRootFolder(path: path, freeBytes: intOrNull(record['freeSpace'])),
    );
  }
  return List.unmodifiable(folders);
}

/// Where Readarr files books, and the room left there.
///
/// `fetchRootFolders()` lets its failure travel rather than degrading to `[]`,
/// which is exactly what this section wants: an empty list means "this server
/// has nowhere to put a book", a real and rare sentence, and it must not be the
/// same pixels as "we could not ask".
final readarrRootFoldersProvider =
    FutureProvider.autoDispose<List<ReadarrRootFolder>>((ref) async {
      final records = await ref
          .watch(readarrServiceProvider)
          .fetchRootFolders();
      return readarrRootFolders(records);
    });

// ─── History today ──────────────────────────────────────────────────────────

/// One history record, resolved into the two lines the row draws.
@immutable
class ReadarrHistoryEntry {
  const ReadarrHistoryEntry({
    required this.title,
    required this.event,
    required this.tone,
    required this.detail,
    required this.date,
  });

  /// The book.
  final String title;

  /// What happened to it, in the shared history vocabulary: `Imported`,
  /// `Grabbed`, `Failed`.
  final String event;

  final StatusTone tone;

  /// Format, size and how long ago, as far as the record carried them.
  final String detail;

  final DateTime date;

  String get spoken =>
      joinSpokenParts([title, event, spokenFromDotted(detail)]);
}

/// The records from today, newest first, capped at [limit].
///
/// "Today" is the local calendar day of [now]. A record from 23:50 yesterday is
/// out even though it is twenty minutes old. The section is headed `today`,
/// and a heading is a promise.
///
/// Takes raw records rather than `ReadarrHistoryItem`, which
/// `ReadarrService.getRecentHistory` maps: that model keeps id, eventType,
/// sourceTitle, date and author and drops the book title, the quality and the
/// size, which is three of the four things a row on this board prints.
List<ReadarrHistoryEntry> readarrHistoryToday(
  List<dynamic> records, {
  required DateTime now,
  int limit = readarrHistoryTodayLimit,
}) {
  final local = now.toLocal();
  final entries = <ReadarrHistoryEntry>[];

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
    // The shared \*arr table, not a local override of it. Readarr writes one
    // record per **book file**, under names no other fork uses
    // (`bookFileImported`, `bookImportIncomplete`, `bookFileRetagged`), and
    // those spellings now live in `global_activity_status.dart` beside
    // Radarr's and Sonarr's. A private switch here would have kept the rows
    // honest on this one screen while the Activity feed, reading the same
    // records through the same table: still drew a completed import grey.
    final (event, tone) = historyEventDisplay(eventType);
    entries.add(
      ReadarrHistoryEntry(
        title: readarrRecordTitle(record),
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
final readarrHistoryTodayProvider =
    FutureProvider.autoDispose<List<ReadarrHistoryEntry>>((ref) async {
      final records = await ref
          .watch(readarrServiceProvider)
          .getHistory(page: 1, pageSize: readarrHistoryPageSize);
      return readarrHistoryToday(records, now: DateTime.now());
    });

// ─── Shared parsing ─────────────────────────────────────────────────────────

/// Parses an \*arr ISO timestamp into local time, or null when it is absent or
/// unreadable.
///
/// Local, always: every window on this screen is a run of local calendar days,
/// and Readarr answers in UTC.
DateTime? _parseLocal(String? raw) {
  final value = raw?.trim();
  if (value == null || value.isEmpty) return null;
  final parsed = DateTime.tryParse(value);
  return parsed?.toLocal();
}

/// `epub`, `mobi`: Readarr's quality names are formats, which is why the row
/// reads `epub · 2.1 MB` where Radarr's reads `Bluray-1080p · 8.4 GB`.
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
