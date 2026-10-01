import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/features/discover/domain/models/discover_detail_model.dart';
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
MediaStatusInfo seerrMediaStatus(
  Map<String, dynamic>? mediaInfo, {
  bool is4k = false,
  SeerrNumbering? numbering,
}) {
  final code = intOrNull(mediaInfo?[is4k ? 'status4k' : 'status']);
  final entry = seerrDownloadEntry(
    mediaInfo?[is4k ? 'downloadStatus4k' : 'downloadStatus'],
  );

  // Seerr has no record of this title at all.
  if (code == null) {
    return const MediaStatusInfo(
      availability: MediaAvailability.notTracked,
      labelOverride: 'Available to request',
    );
  }

  final media = SeerrMediaAvailability.fromCode(code, numbering: numbering);

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
MediaStatusInfo? seerr4kMediaStatus(
  Map<String, dynamic>? mediaInfo, {
  SeerrNumbering? numbering,
}) {
  final code = intOrNull(mediaInfo?['status4k']);
  final moving = seerrDownloadEntry(mediaInfo?['downloadStatus4k']) != null;
  if ((code == null || code == _seerrUnknownCode) && !moving) return null;

  final info = seerrMediaStatus(mediaInfo, is4k: true, numbering: numbering);
  return info.copyWith(labelOverride: '4K: ${info.label}');
}

/// Seerr's `MediaStatus.UNKNOWN`, the code of a resolution nobody asked for.
const int _seerrUnknownCode = 1;

/// Resolves a status for every season of a title, keyed by season number.
///
/// Seerr reports per-season availability inside `mediaInfo.seasons`, a list of
/// `{seasonNumber, status}` records. That mapping used to happen inside
/// `DiscoverSeasonsList.build`, which both put a raw `Map<String, dynamic>` in
/// the presentation layer's hands and produced a bare
/// [SeerrMediaAvailability] the shared status vocabulary could not render.
/// Routing it through [seerrMediaStatus] means a season badge speaks exactly the
/// same language as the page's own — including Seerr's wording for
/// "Partially available".
///
/// Seasons absent from the payload are [seerrUntrackedSeasonStatus].
///
/// The returned map covers **every** season in [seasons], so a caller never has
/// to invent a fallback for a missing key — which is what the seasons list was
/// doing, restating this exact `notTracked` decision inside a widget.
Map<int, MediaStatusInfo> seerrSeasonStatuses(
  Map<String, dynamic>? mediaInfo,
  List<TvSeason> seasons, {
  SeerrNumbering? numbering,
}) {
  final byNumber = <int, MediaStatusInfo>{};

  final rawSeasons = mediaInfo?['seasons'];
  if (rawSeasons is List) {
    for (final raw in rawSeasons) {
      final entry = mapOrNull(raw);
      if (entry == null) continue;

      final seasonNumber = intOrNull(entry['seasonNumber']);
      if (seasonNumber == null) continue;

      byNumber[seasonNumber] = seerrMediaStatus(<String, dynamic>{
        'status': entry['status'],
      }, numbering: numbering);
    }
  }

  for (final season in seasons) {
    byNumber.putIfAbsent(season.seasonNumber, () => seerrUntrackedSeasonStatus);
  }

  return byNumber;
}

/// The status of a season Seerr has no record of.
///
/// Named and exported so the one decision lives in one place: Seerr has never
/// heard of this season, which is a different fact from "unknown" and the one the
/// Request button acts on. [seerrSeasonStatuses] fills absent seasons with it, and
/// `DiscoverSeasonsList` reads it for the total-function lookup Dart's
/// `Map<int, …>[]` forces — rather than writing a second `notTracked` literal
/// that could silently disagree with this one.
const MediaStatusInfo seerrUntrackedSeasonStatus = MediaStatusInfo(
  availability: MediaAvailability.notTracked,
);

/// Parses Seerr's `downloadStatus` array into a single queue entry.
///
/// The records use the same field names as an \*arr `/queue` record, except
/// that the remaining bytes arrive as `sizeLeft` rather than `sizeleft` —
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
