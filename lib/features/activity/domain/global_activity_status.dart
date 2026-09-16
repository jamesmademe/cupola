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
  );
}

/// The label and severity for an \*arr history `eventType`.
///
/// Shared by the global feed and the per-service history tile so both spell and
/// colour the same event identically.
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
    'downloadFolderImported' || 'downloadImported' => StatusGlyph.imported,
    'downloadFailed' || 'importFailed' => StatusGlyph.failed,
    'downloadIgnored' => StatusGlyph.ignored,
    'episodeFileDeleted' ||
    'movieFileDeleted' ||
    'trackFileDeleted' => StatusGlyph.deleted,
    'episodeFileRenamed' ||
    'movieFileRenamed' ||
    'trackFileRenamed' => StatusGlyph.renamed,
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
    'downloadImported' => ('Imported', StatusTone.success),
    // Faults, and therefore amber. Red is reserved for a connection that did
    // not answer — a failed grab means the service answered and told us so.
    'downloadFailed' => ('Failed', StatusTone.warning),
    'importFailed' => ('Import Failed', StatusTone.warning),
    // Deliberately not an error, and no longer sharing `importFailed`'s wording.
    // `downloadIgnored` is a choice somebody made — the \*arr was told to leave
    // this release alone. Rendering it as a red "Import Failed" sent the user
    // looking for a fault that never happened.
    'downloadIgnored' => ('Ignored', StatusTone.neutral),
    // A file the user or an upgrade removed. Amber would claim a fault that
    // nobody experienced; this is backlog, and backlog is neutral.
    'episodeFileDeleted' ||
    'movieFileDeleted' ||
    'trackFileDeleted' => ('Deleted', StatusTone.neutral),
    'episodeFileRenamed' ||
    'movieFileRenamed' ||
    'trackFileRenamed' => ('Renamed', StatusTone.neutral),
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
/// Missing, Cutoff Unmet, Unmonitored.
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
      // Matches the "Cutoff Unmet" sub-segment label. The old string was
      // 'Cutoff', which is not even the term the \*arr services use.
      labelOverride: 'Cutoff Unmet',
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
