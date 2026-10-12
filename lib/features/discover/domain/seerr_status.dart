import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';

/// Resolves the badge status for a Seerr media entry.
///
/// Seerr's `status` code alone cannot say whether a "Processing" item is
/// actually moving: that lives in `mediaInfo.downloadStatus`, an array of live
/// records forwarded from the connected \*arr instances. Reading it turns a
/// static "Processing" into a real "Downloading 42%".
///
/// [numbering] is the numbering of the Seerr that sent [mediaInfo]: the code
/// is decoded by [SeerrMediaAvailability.fromCode], the one decoder every
/// Seerr surface shares. A Seerr 7 reads "Deleted", which is what "Remove
/// from Radarr" leaves behind, and a Seerr 6 reads "Blocklisted" in the
/// neutral tone, an operator's choice rather than a fault.
///
/// [audience] is who reads it: the requester reads their own words
/// ([_requesterStatus]), never Seerr's or the download's.
MediaStatusInfo seerrMediaStatus(
  Map<String, dynamic>? mediaInfo, {
  bool is4k = false,
  SeerrNumbering? numbering,
  Audience audience = Audience.operator,
}) {
  final code = intOrNull(mediaInfo?[is4k ? 'status4k' : 'status']);
  final entry = seerrDownloadEntry(
    mediaInfo?[is4k ? 'downloadStatus4k' : 'downloadStatus'],
  );

  // Seerr has no record of this title at all.
  if (code == null) return _noRecord;

  final media = SeerrMediaAvailability.fromCode(code, numbering: numbering);
  if (audience == Audience.requester) return _requesterStatus(media, entry);

  // Nothing is downloading for a title the operator barred, and nothing is
  // wrong with it either: the word and its glyph, in the backlog's tone.
  if (media == SeerrMediaAvailability.blocklisted) {
    return MediaStatusInfo(
      labelOverride: StateWord.blocklisted.label,
      toneOverride: StatusTone.neutral,
      glyph: StatusGlyph.blocked,
    );
  }

  final availability = switch (media) {
    SeerrMediaAvailability.partiallyAvailable => MediaAvailability.partial,
    SeerrMediaAvailability.available => MediaAvailability.available,
    SeerrMediaAvailability.deleted => MediaAvailability.deleted,
    SeerrMediaAvailability.pending ||
    SeerrMediaAvailability.processing => MediaAvailability.missing,
    SeerrMediaAvailability.blocklisted ||
    SeerrMediaAvailability.unknown => MediaAvailability.unknown,
  };

  // Seerr's own coarse pipeline states, superseded by the live download record
  // whenever one is present.
  final fallbackPipeline = switch (media) {
    SeerrMediaAvailability.pending => MediaPipeline.queued,
    SeerrMediaAvailability.processing => MediaPipeline.downloading,
    _ => null,
  };

  return MediaStatusInfo(
    availability: availability,
    pipeline: entry?.pipeline ?? fallbackPipeline,
    progress: entry?.progress,
    hasWarning: entry?.hasWarning ?? false,
    detail: entry?.detail,
    // Preserve Seerr's wording only while there is no better live state to
    // report.
    labelOverride: entry != null
        ? entry.label
        : switch (media) {
            SeerrMediaAvailability.pending ||
            SeerrMediaAvailability.processing ||
            SeerrMediaAvailability.partiallyAvailable ||
            SeerrMediaAvailability.deleted => media.label,
            _ => null,
          },
  );
}

/// A title Seerr holds no record of: the Request beside it is the way in.
const MediaStatusInfo _noRecord = MediaStatusInfo(
  availability: MediaAvailability.notTracked,
  labelOverride: 'Available to request',
);

/// [media] as the requester reads it, with [entry] the download Seerr
/// forwards (brand book, *The requester*): what will happen to a request,
/// never how, and never a fault, which only whoever runs the server can mend.
///
/// - Waiting for approval, as the operator reads it.
/// - Approved and coming: `On its way`, whatever the download is doing, but
///   `Downloading` with its ring while bytes arrive and `Finishing on the
///   server` once they have. A stuck or failed download, a paused one, a
///   client that did not answer: still `On its way`.
/// - `On the server` and `Partly on the server`, never `Available`, which
///   beside `Available to request` reads as the same promise.
/// - `Blocked` for a title the operator barred: the button says it `Can't be
///   requested` and the sentence under it who blocked it.
/// - A title Seerr removed (`Deleted`) or holds no state for (`Unknown`) can
///   be asked for again: `Available to request`, as with no record at all.
MediaStatusInfo _requesterStatus(
  SeerrMediaAvailability media,
  ArrQueueEntry? entry,
) {
  final availability = switch (media) {
    SeerrMediaAvailability.available => MediaAvailability.available,
    SeerrMediaAvailability.partiallyAvailable => MediaAvailability.partial,
    _ => MediaAvailability.missing,
  };

  switch (media) {
    case SeerrMediaAvailability.unknown || SeerrMediaAvailability.deleted:
      return _noRecord;
    case SeerrMediaAvailability.blocklisted:
      return const MediaStatusInfo(
        labelOverride: Lexicon.blocked,
        toneOverride: StatusTone.neutral,
        glyph: StatusGlyph.blocked,
      );
    case SeerrMediaAvailability.pending:
      return MediaStatusInfo(
        availability: availability,
        pipeline: MediaPipeline.queued,
        labelOverride: StateWord.waitingForApproval.label,
      );
    case SeerrMediaAvailability.processing ||
        SeerrMediaAvailability.partiallyAvailable ||
        SeerrMediaAvailability.available:
      break;
  }

  return switch (entry?.pipeline) {
    MediaPipeline.downloading => MediaStatusInfo(
      availability: availability,
      pipeline: MediaPipeline.downloading,
      progress: entry?.progress,
    ),
    MediaPipeline.importPending || MediaPipeline.importing => MediaStatusInfo(
      availability: availability,
      pipeline: MediaPipeline.importing,
      labelOverride: Lexicon.finishingOnTheServer,
    ),
    null when media == SeerrMediaAvailability.available => MediaStatusInfo(
      availability: availability,
      labelOverride: Lexicon.onTheServer,
    ),
    null when media == SeerrMediaAvailability.partiallyAvailable =>
      MediaStatusInfo(
        availability: availability,
        labelOverride: Lexicon.partlyOnTheServer,
      ),
    _ => MediaStatusInfo(
      availability: availability,
      pipeline: MediaPipeline.queued,
      labelOverride: Lexicon.onItsWayState,
    ),
  };
}

/// The 4K copy of a title, beside its standard one, or null when Seerr holds
/// no 4K record of it.
///
/// Seerr keeps the two resolutions apart (`status4k`, `downloadStatus4k`),
/// and a title can be on disk in HD while its 4K copy waits for approval.
/// The page used to read the standard fields alone, so that title said
/// "Available" and nothing about the request still waiting.
///
/// Null for a `status4k` that is absent or UNKNOWN (1) with no 4K download
/// moving: Seerr's default for every title, which is a 4K copy nobody asked
/// for, not a state to show. Otherwise [seerrMediaStatus] on the 4K axis,
/// decoded with the same [numbering], its label led by `4K: ` so the two
/// badges cannot be read as one.
///
/// The requester is not shown a 4K copy that is not there to ask about or
/// watch: one Seerr removed reads as one nobody asked for.
MediaStatusInfo? seerr4kMediaStatus(
  Map<String, dynamic>? mediaInfo, {
  SeerrNumbering? numbering,
  Audience audience = Audience.operator,
}) {
  final code = intOrNull(mediaInfo?['status4k']);
  final moving = seerrDownloadEntry(mediaInfo?['downloadStatus4k']) != null;
  if ((code == null || code == _seerrUnknownCode) && !moving) return null;

  final info = seerrMediaStatus(
    mediaInfo,
    is4k: true,
    numbering: numbering,
    audience: audience,
  );
  if (audience == Audience.requester &&
      info.availability == MediaAvailability.notTracked) {
    return null;
  }
  return info.copyWith(labelOverride: '4K: ${info.label}');
}

/// Seerr's `MediaStatus.UNKNOWN`, the code of a resolution nobody asked for.
const int _seerrUnknownCode = 1;

/// Every state the page shows for a title: the standard copy's, then the 4K
/// copy's when Seerr holds one ([seerr4kMediaStatus]). Never empty.
///
/// A title Seerr holds only in 4K has UNKNOWN (1) for its standard copy,
/// which is Seerr's word for no record of that copy. It drew "Unknown"
/// beside the 4K state, as if something about the title were in doubt; the
/// standard badge is left out then. With no record of either copy the
/// standard one is drawn as it always was. To the requester, a standard copy
/// Seerr removed is one more copy with no record.
List<MediaStatusInfo> seerrTitleStatuses(
  Map<String, dynamic>? mediaInfo, {
  SeerrNumbering? numbering,
  Audience audience = Audience.operator,
}) {
  final standard = seerrMediaStatus(
    mediaInfo,
    numbering: numbering,
    audience: audience,
  );
  final uhd = seerr4kMediaStatus(
    mediaInfo,
    numbering: numbering,
    audience: audience,
  );
  if (uhd == null) return [standard];

  final code = intOrNull(mediaInfo?['status']);
  final moving = seerrDownloadEntry(mediaInfo?['downloadStatus']) != null;
  final noStandardRecord = audience == Audience.requester
      ? standard.availability == MediaAvailability.notTracked
      : (code == null || code == _seerrUnknownCode) && !moving;
  return noStandardRecord ? [uhd] : [standard, uhd];
}

/// Parses Seerr's `downloadStatus` array into a single queue entry.
///
/// The records use the same field names as an \*arr `/queue` record, except
/// that the remaining bytes arrive as `sizeLeft` rather than `sizeleft`:
/// `queueProgress` already accepts both spellings.
ArrQueueEntry? seerrDownloadEntry(dynamic rawDownloadStatus) {
  if (rawDownloadStatus is! List || rawDownloadStatus.isEmpty) return null;

  final entries = <ArrQueueEntry>[];
  for (final raw in rawDownloadStatus) {
    final item = mapOrNull(raw);
    if (item == null) continue;
    final entry = ArrQueueEntry.fromQueueItem(item);
    if (entry != null) entries.add(entry);
  }

  return mergeArrQueueEntries(entries);
}

/// What a poster in Seerr's catalogue says of its title, or null when it
/// should say nothing.
///
/// The title's first state as its page reads it ([seerrTitleStatuses]: the
/// standard copy, or the 4K one when only that is held). Nothing for a title
/// Seerr holds no record of, which is most of a catalogue: a badge on every
/// poster saying it can be asked for is noise, and the poster's page says it
/// with its Request. Nothing either for Seerr's own `Unknown`, which states
/// no fact.
MediaStatusInfo? seerrCatalogStatus(
  Map<String, dynamic>? mediaInfo, {
  SeerrNumbering? numbering,
  Audience audience = Audience.operator,
}) {
  if (mediaInfo == null) return null;
  final info = seerrTitleStatuses(
    mediaInfo,
    numbering: numbering,
    audience: audience,
  ).first;
  final saysNothing =
      info.availability == MediaAvailability.notTracked ||
      (info.availability == MediaAvailability.unknown &&
          info.pipeline == null &&
          info.labelOverride == null);
  return saysNothing ? null : info;
}

/// Whether Seerr says the server holds the title, whole or in part, in
/// either copy: what "Hide what I have" takes off a catalogue page, "The
/// best you're missing" leaves out and a person's or a collection's page
/// counts as on the server. Read from the same record as the badge, so a
/// title that is hidden is one whose badge would say it is there; a title
/// held in 4K alone is there too, as its badge says.
bool seerrHolds(Map<String, dynamic>? mediaInfo, {SeerrNumbering? numbering}) {
  bool holds(Object? raw) {
    final code = intOrNull(raw);
    if (code == null) return false;
    return switch (SeerrMediaAvailability.fromCode(
      code,
      numbering: numbering,
    )) {
      SeerrMediaAvailability.available ||
      SeerrMediaAvailability.partiallyAvailable => true,
      _ => false,
    };
  }

  return holds(mediaInfo?['status']) || holds(mediaInfo?['status4k']);
}
