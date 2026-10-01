/// Resolves every Activity row onto the shared [MediaStatusInfo] vocabulary.
///
/// This layer exists because the presentation layer used to colour rows by
/// *category* rather than by state: a `switch` on the row's kind gave every
/// history record the success green and every queue record the service accent.
/// A `downloadFailed` event therefore rendered the word "Failed" inside a green
/// pill, and a failed download was chromatically identical to a healthy one —
/// while the per-service tiles, which had their own separate derivation, got the
/// same events right. Two screens in one feature disagreed about the colour of
/// one event.
///
/// So the rule is the one DESIGN.md states: a widget renders a resolved status,
/// it never derives one. Everything that needs a tone, a label, a progress value
/// or a warning for an Activity row comes from here.
library;

import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';

/// The kinds of record the global Activity feed can show.
///
/// Declared here rather than beside the provider because the resolvers below
/// switch on it, and a domain layer must not import presentation.
/// `activity_provider.dart` re-exports it, so existing call sites are unchanged.
enum GlobalActivityKind { request, queue, history, blocklist, missing, cutoff }

/// Resolves an \*arr record of the given [kind] into a renderable status.
MediaStatusInfo resolveActivityStatus(
  GlobalActivityKind kind,
  Map<String, dynamic> item,
) {
  return switch (kind) {
    GlobalActivityKind.queue => resolveQueueDisplayStatus(item),
    GlobalActivityKind.history => resolveHistoryStatus(item),
    GlobalActivityKind.blocklist => resolveBlocklistStatus(item),
    GlobalActivityKind.missing => resolveWantedStatus(item, isCutoff: false),
    GlobalActivityKind.cutoff => resolveWantedStatus(item, isCutoff: true),
    // Requests never arrive as a raw map; see [resolveRequestStatus].
    GlobalActivityKind.request => const MediaStatusInfo.unknown(),
  };
}

/// Resolves a queue record for display.
///
/// A thin wrapper over the canonical [ArrQueueEntry] parser so Activity, the
/// media detail pages and the poster grids can never disagree about what a queue
/// record means. Unlike the media resolvers this always returns a status: an
/// already-imported record still has a row to render.
MediaStatusInfo resolveQueueDisplayStatus(Map<String, dynamic> item) {
  final entry = ArrQueueEntry.fromQueueItem(item);
  if (entry != null) {
    return MediaStatusInfo(
      pipeline: entry.pipeline,
      progress: entry.progress,
      hasWarning: entry.hasWarning,
      detail: entry.detail,
      labelOverride: entry.label,
      toneOverride: entry.toneOverride,
    );
  }

  // `imported` / `ignored`: the pipeline is done with this record.
  final trackedState = stringOrNull(
    item['trackedDownloadState'],
  )?.toLowerCase();
  return MediaStatusInfo(
    availability: MediaAvailability.available,
    labelOverride: trackedState == 'ignored' ? 'Ignored' : 'Imported',
    hasWarning: arrQueueHasWarning(item),
    detail: arrQueueWarningMessage(item),
  );
}

/// Whether a queue record is waiting on a human to import it.
///
/// Two shapes of the same request for help. `importBlocked` is the current
/// \*arrs' own word for it. An `importPending` record that also carries a
/// warning is how the older forks — Sonarr v3, Lidarr, Readarr — say the same
/// thing ("Unable to Import Automatically", "No files found are eligible for
/// import"): the file is on disk and the service will not place it on its own.
///
/// Neither clears by waiting, which is why neither is *importing*. The Activity
/// readout used to count both as progress, so eighteen rows each reading
/// "Import blocked" sat under a header that said "18 importing" — a fault
/// summarised as good news. The Dashboard reads the same rule, so one record
/// cannot be a decision on one tab and progress on the other.
bool queueNeedsManualImport({
  required MediaPipeline? pipeline,
  required bool hasWarning,
}) =>
    pipeline == MediaPipeline.importBlocked ||
    (pipeline == MediaPipeline.importPending && hasWarning);

/// `1 needs a manual import`, `18 need a manual import`.
///
/// The one phrase for [queueNeedsManualImport], shared by the Activity readout
/// and the Dashboard so the two surfaces name the fault in the same words — and
/// name it by its remedy, which is the verb on the row.
///
/// [floor] when the rows it counts are only the ones a queue walk read before
/// it stopped short: `18+ need a manual import`, never `18`, and for the ear
/// ([spoken]) `at least 18 need a manual import`.
String needsManualImportClause(
  int count, {
  bool floor = false,
  bool spoken = false,
}) {
  final figure = !floor
      ? '$count'
      : spoken
      ? 'at least $count'
      : Lexicon.floor(count);
  return count == 1
      ? '$figure needs a manual import'
      : '$figure need a manual import';
}

/// Resolves a history record from its `eventType`.
///
/// History describes something that already happened, so there is no live
/// availability or pipeline to derive a tone from — hence [
/// MediaStatusInfo.toneOverride]. The severity mapping is the point of this
/// function: an import is a success, a failed download is a *fault*, and a
/// grab, a deletion or a rename is a record of something that worked.
MediaStatusInfo resolveHistoryStatus(Map<String, dynamic> item) {
  final eventType = stringOrNull(item['eventType']) ?? 'unknown';
  final (label, tone) = historyEventDisplay(eventType);
  return MediaStatusInfo(
    labelOverride: label,
    toneOverride: tone,
    glyph: historyEventGlyph(eventType),
    // Only the faults carry one. A failed grab or a failed import is the one
    // history row a user has to act on, and until now it said "Failed" and
    // nothing else — the service's own sentence was sitting in the record,
    // unread, while the queue rows one tab away printed theirs. A `grabbed`
    // row is gated out rather than filtered: a reason under a neutral label
    // reads as a problem that is not there.
    detail: tone == StatusTone.warning ? historyFailureReason(item) : null,
  );
}

/// The service's own explanation for a failed history record.
///
/// \*arr files it under `data`, not at the top level where the queue keeps it,
/// so the queue's [arrQueueWarningMessage] cannot be reused — this is the read
/// the `act` annotation names, and nothing in the app performed it. The
/// top-level key is still checked second because Lidarr answers with a flat
/// `message` on some events.
String? historyFailureReason(Map<String, dynamic> item) {
  final data = mapOrNull(item['data']);
  final messages = extractArrStatusMessages(data?['statusMessages']);
  if (messages.isNotEmpty) return messages.first;
  return stringOrNull(data?['message']) ?? stringOrNull(item['message']);
}

/// Where a history record says its file landed, or was dropped.
///
/// `importedPath` is the destination an `downloadFolderImported` event wrote
/// to; `droppedPath` is where the client left the file when the import failed,
/// and is therefore the folder a manual import has to be seeded from. Both live
/// under `data`, both were unread, and the failed row needs the second one to
/// offer its way out at all.
String? historyFilePath(Map<String, dynamic> item) {
  final data = mapOrNull(item['data']);
  return stringOrNull(data?['importedPath']) ??
      stringOrNull(data?['droppedPath']);
}

/// The label and severity for an \*arr history `eventType`.
///
/// Shared by the global feed and the per-service history tile so both spell and
/// colour the same event identically.
///
/// **The table is the union of the forks' vocabularies, not Radarr's.** Each
/// \*arr names the event after the entity it writes a record for, so an import
/// is `downloadFolderImported` on Radarr and Sonarr and `bookFileImported` on
/// Readarr — and an event this table does not name falls through to
/// [humanizeCamelCase] and [StatusTone.neutral], which is the right answer for
/// an event nobody has classified and the wrong one for a fork's most common
/// row. A per-screen override table is how that gap used to be patched, and it
/// puts two spellings of one event on two tabs of one service.
///
/// **This table is the only derivation of this vocabulary.** It had been
/// re-derived independently three times — here, in a private switch in
/// `lidarr_overview_provider.dart`, and in `readarrEventStyle` in
/// `readarr_tiles.dart`, whose default arm shouted the raw camel-case event
/// name — and the three disagreed about `trackFileImported`,
/// `albumImportIncomplete`, `bookFileRenamed` and `grabbed`. Both overrides are
/// gone: anything needing a label, a tone or a glyph for an `eventType` reads
/// [historyEventLabel], [historyEventTone] or [historyEventGlyph]. A screen
/// that genuinely means something different must say in a comment what and
/// why, because the next reader will take a silent disagreement for a bug.
(String, StatusTone) historyEventDisplay(String eventType) {
  return (historyEventLabel(eventType), historyEventTone(eventType));
}

/// The glyph an \*arr history `eventType` depicts.
///
/// Separate from the tone because the two answer different questions: five of
/// these events are correctly neutral and none of them is the same picture.
StatusGlyph? historyEventGlyph(String eventType) {
  return switch (eventType) {
    'grabbed' => StatusGlyph.grabbed,
    'downloadFolderImported' ||
    'downloadImported' ||
    'bookFileImported' ||
    'authorFolderImported' ||
    'trackFileImported' => StatusGlyph.imported,
    'downloadFailed' || 'importFailed' => StatusGlyph.failed,
    // The forks' own import failures. Both depict the same thing as an
    // `importFailed`: a release that arrived and did not make it into the
    // library whole.
    'bookImportIncomplete' || 'albumImportIncomplete' => StatusGlyph.failed,
    'downloadIgnored' => StatusGlyph.ignored,
    'episodeFileDeleted' ||
    'movieFileDeleted' ||
    'trackFileDeleted' ||
    'bookFileDeleted' => StatusGlyph.deleted,
    'episodeFileRenamed' ||
    'movieFileRenamed' ||
    'trackFileRenamed' ||
    'bookFileRenamed' => StatusGlyph.renamed,
    // `bookFileRetagged` and `trackFileRetagged` deliberately have none: a
    // metadata rewrite is not a picture, and the five glyphs above are all
    // events with a shape.
    _ => null,
  };
}

String historyEventLabel(String eventType) => _historyEvent(eventType).$1;

StatusTone historyEventTone(String eventType) => _historyEvent(eventType).$2;

(String, StatusTone) _historyEvent(String eventType) {
  return switch (eventType) {
    // A grab is the system doing its job, not news: the release was found
    // and handed to a client. Blue used to say "in flight", which the queue
    // already says, and said it on every row of a page that is mostly grabs.
    'grabbed' => ('Grabbed', StatusTone.neutral),
    'downloadFolderImported' ||
    'downloadImported' ||
    // Readarr spells its own import. It writes one record per *book file*,
    // under names no other fork uses, so before these arms existed the most
    // common row on a book history — a completed import, the one event on the
    // page that is unambiguously good news — fell through to
    // `humanizeCamelCase` and came out as a neutral "Book File Imported".
    // `authorFolderImported` is the same event on an older Readarr.
    'bookFileImported' ||
    'authorFolderImported' ||
    // Lidarr spells its own import, and writes one record per *track file*.
    // The same gap, one fork over: before this arm the most common row on a
    // music history — a completed import, the one event on the page that is
    // unambiguously good news — came out a neutral "Track File Imported".
    'trackFileImported' => ('Imported', StatusTone.success),
    // Faults, and therefore amber. Red is reserved for a connection that did
    // not answer — a failed grab means the service answered and told us so.
    'downloadFailed' => ('Failed', StatusTone.warning),
    'importFailed' => ('Import failed', StatusTone.warning),
    // The forks' own import faults, and the failure each library actually
    // suffers: the book went in with files missing, the album with tracks
    // missing. Amber for the same reason as the two above — the service
    // answered and told us so.
    'bookImportIncomplete' ||
    'albumImportIncomplete' => ('Import incomplete', StatusTone.warning),
    // Deliberately not an error, and no longer sharing `importFailed`'s wording.
    // `downloadIgnored` is a choice somebody made — the \*arr was told to leave
    // this release alone. Rendering it as a red "Import failed" sent the user
    // looking for a fault that never happened.
    'downloadIgnored' => ('Ignored', StatusTone.neutral),
    // A file the user or an upgrade removed. Amber would claim a fault that
    // nobody experienced; this is backlog, and backlog is neutral.
    'episodeFileDeleted' ||
    'movieFileDeleted' ||
    'trackFileDeleted' ||
    'bookFileDeleted' => ('Deleted', StatusTone.neutral),
    'episodeFileRenamed' ||
    'movieFileRenamed' ||
    'trackFileRenamed' ||
    'bookFileRenamed' => ('Renamed', StatusTone.neutral),
    // A metadata rewrite: Readarr or Lidarr doing maintenance nobody asked to
    // be told about. Neutral, and not a fault.
    'bookFileRetagged' ||
    'trackFileRetagged' => ('Retagged', StatusTone.neutral),
    _ => (humanizeCamelCase(eventType), StatusTone.neutral),
  };
}

/// A blocked release — and deliberately not toned.
///
/// The user actively rejected this release, so the blocklist working is the
/// system obeying an instruction. Red said "a thing went wrong" about the one
/// list on which every row went exactly right.
MediaStatusInfo resolveBlocklistStatus(Map<String, dynamic> item) {
  return MediaStatusInfo(
    labelOverride: 'Blocked',
    toneOverride: StatusTone.neutral,
    glyph: StatusGlyph.blocked,
    detail: _blocklistReason(item),
  );
}

/// Resolves a Wanted row — a missing item or one below the quality cutoff.
///
/// Every row here is backlog, so every row here is neutral. In the Wanted
/// bucket being missing is the *definition* of membership, not news about it:
/// toning the rows at all — red once, then amber and blue — meant the page
/// shouted its own title back at the reader in colour, and left nothing for the
/// one row that is genuinely stuck.
///
/// The distinctions the tones used to carry are still on the row, in the words:
/// Missing, Cutoff unmet, Unmonitored.
MediaStatusInfo resolveWantedStatus(
  Map<String, dynamic> item, {
  required bool isCutoff,
}) {
  if (item['monitored'] == false) {
    return const MediaStatusInfo(
      availability: MediaAvailability.missing,
      unmonitored: true,
      labelOverride: 'Unmonitored',
      toneOverride: StatusTone.neutral,
    );
  }

  if (isCutoff) {
    return const MediaStatusInfo(
      availability: MediaAvailability.upgradable,
      // Matches the "Cutoff unmet" sub-segment label. The old string was
      // 'Cutoff', which is not even the term the \*arr services use. Sentence
      // case, not Title Case: this is a state, and the app capitalises a state
      // like a sentence everywhere else it names one.
      labelOverride: 'Cutoff unmet',
      toneOverride: StatusTone.neutral,
    );
  }

  return const MediaStatusInfo(
    availability: MediaAvailability.missing,
    labelOverride: 'Missing',
    toneOverride: StatusTone.neutral,
  );
}

/// Resolves a Seerr request onto the same vocabulary as everything else.
///
/// Seerr's own wording is preserved via [MediaStatusInfo.labelOverride] — it is
/// the language the user sees in Seerr itself — while the tone comes from the
/// request's display kind.
///
/// `pending` is blue — queued, waiting its turn — like every other thing in
/// the app that is in line and not broken. It used to be amber on the argument
/// that it waits on a *human*, but amber is the fault arm and a request awaiting
/// approval is not a fault: painting it amber put the alarm colour on the
/// normal resting state of a request list, which is exactly the mistake the
/// tone rule exists to stop. (Decided 2026-09-28.) The Dashboard still draws
/// the same request neutral inside its decisions list, where the presence of
/// the row is already the signal.
MediaStatusInfo resolveRequestStatus(SeerrRequest request) {
  final display = request.displayStatus;
  final tone = switch (display.kind) {
    SeerrRequestDisplayKind.available ||
    SeerrRequestDisplayKind.completed => StatusTone.success,
    SeerrRequestDisplayKind.processing ||
    SeerrRequestDisplayKind.partiallyAvailable ||
    SeerrRequestDisplayKind.approved ||
    SeerrRequestDisplayKind.pending => StatusTone.info,
    // Seerr answered; it just answered no. A declined, blocklisted or
    // deleted request is a closed decision, and a failed one is a fault the
    // service reported — neither is a connection that did not answer.
    SeerrRequestDisplayKind.failed => StatusTone.warning,
    SeerrRequestDisplayKind.declined ||
    SeerrRequestDisplayKind.blocklisted ||
    SeerrRequestDisplayKind.deleted => StatusTone.neutral,
    SeerrRequestDisplayKind.unknown => StatusTone.neutral,
  };

  return MediaStatusInfo(labelOverride: display.label, toneOverride: tone);
}

String? _blocklistReason(Map<String, dynamic> item) {
  final directMessage = stringOrNull(item['message']);
  if (directMessage != null) return directMessage;

  final messages = extractArrStatusMessages(item['statusMessages']);
  return messages.isEmpty ? null : messages.first;
}
