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
    'authorFolderImported' => StatusGlyph.imported,
    'downloadFailed' || 'importFailed' => StatusGlyph.failed,
    // Readarr's own import failure. It depicts the same thing as an
    // `importFailed`: a release that arrived and did not make it into the
    // library.
    'bookImportIncomplete' => StatusGlyph.failed,
    'downloadIgnored' => StatusGlyph.ignored,
    'episodeFileDeleted' ||
    'movieFileDeleted' ||
    'trackFileDeleted' ||
    'bookFileDeleted' => StatusGlyph.deleted,
    'episodeFileRenamed' ||
    'movieFileRenamed' ||
    'trackFileRenamed' ||
    'bookFileRenamed' => StatusGlyph.renamed,
    // `bookFileRetagged` deliberately has none: a metadata rewrite is not a
    // picture, and the five glyphs above are all events with a shape.
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
    'authorFolderImported' => ('Imported', StatusTone.success),
    // Faults, and therefore amber. Red is reserved for a connection that did
    // not answer — a failed grab means the service answered and told us so.
    'downloadFailed' => ('Failed', StatusTone.warning),
    'importFailed' => ('Import Failed', StatusTone.warning),
    // Readarr's import fault, and the failure a book library actually suffers:
    // the book went in with files missing. Amber for the same reason as the two
    // above — the service answered and told us so.
    'bookImportIncomplete' => ('Import incomplete', StatusTone.warning),
    // Deliberately not an error, and no longer sharing `importFailed`'s wording.
    // `downloadIgnored` is a choice somebody made — the \*arr was told to leave
    // this release alone. Rendering it as a red "Import Failed" sent the user
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
    // A metadata rewrite: Readarr doing maintenance nobody asked to be told
    // about. Neutral, and not a fault.
    'bookFileRetagged' => ('Retagged', StatusTone.neutral),
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
/// `pending` is the one row in the app the tone rule does not settle, and it is
/// warning on purpose: it is not backlog (nothing is waiting on a server) and
/// it is not a fault (nothing is broken) — it is waiting on a *human*, which is
/// the only thing this screen can act on. The Dashboard draws the same request
/// neutral inside its decisions list, where the presence of the row is already
/// the signal and the colour would be noise.
MediaStatusInfo resolveRequestStatus(SeerrRequest request) {
  final display = request.displayStatus;
  final tone = switch (display.kind) {
    SeerrRequestDisplayKind.available ||
    SeerrRequestDisplayKind.completed => StatusTone.success,
    SeerrRequestDisplayKind.processing ||
    SeerrRequestDisplayKind.partiallyAvailable ||
    SeerrRequestDisplayKind.approved => StatusTone.info,
    SeerrRequestDisplayKind.pending => StatusTone.warning,
    // Seerr answered; it just answered no. A declined or deleted request is a
    // closed decision, and a failed one is a fault the service reported —
    // neither is a connection that did not answer.
    SeerrRequestDisplayKind.failed => StatusTone.warning,
    SeerrRequestDisplayKind.declined ||
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
