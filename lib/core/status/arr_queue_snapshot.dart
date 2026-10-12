import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/core/utils/sample_age.dart';
import 'package:cupola/core/utils/string_utils.dart';

export 'package:cupola/core/status/media_status.dart';
// Part of this layer's surface: `ArrQueueEntry.severity` is typed on it, so a
// caller holding an entry can read it without also importing the raw-JSON utils.
export 'package:cupola/core/utils/arr_activity_display.dart'
    show ArrQueueSeverity, arrQueueSeverity;

/// One media item's slice of an \*arr download queue.
///
/// The queue is fetched once per service and indexed by media id, so a detail
/// page, a poster grid and the Activity tab all read the same snapshot instead
/// of each deriving its own idea of what is happening.
class ArrQueueEntry {
  final MediaPipeline pipeline;
  final double? progress;

  /// How badly the \*arr says this record is doing.
  ///
  /// Replaces a `bool hasWarning`, which could not tell a service-reported
  /// `error` from a `warning`; see [ArrQueueSeverity].
  final ArrQueueSeverity severity;

  final String? detail;

  /// Set when the raw status carries more information than [pipeline] can, an
  /// unrecognised status keeps its own humanised wording instead of being
  /// flattened to "Queued".
  ///
  /// It no longer carries "Client unavailable": that was a real state wearing a
  /// label, and a label is exactly what the merge in [_EntryAccumulator] is
  /// entitled to discard. It is [MediaPipeline.clientUnavailable] now.
  final String? label;

  /// When the download client says the transfer will be done
  /// (`estimatedCompletionTime`), or null when it does not say. The
  /// calendar's `around 21:10`.
  final DateTime? finishesAt;

  const ArrQueueEntry({
    required this.pipeline,
    this.progress,
    this.severity = ArrQueueSeverity.ok,
    this.detail,
    this.label,
    this.finishesAt,
  });

  bool get hasWarning => severity != ArrQueueSeverity.ok;

  /// This record as a stale reading keeps it: the state stays, the progress
  /// and the time it said it would finish go. A percentage that is no longer moving must not look live, the
  /// same reason a row under `FaultBand.stale` trades its time left for the
  /// reading's age.
  ArrQueueEntry withoutProgress() => progress == null && finishesAt == null
      ? this
      : ArrQueueEntry(
          pipeline: pipeline,
          severity: severity,
          detail: detail,
          label: label,
        );

  /// The tone this record's severity earns over the one its [pipeline] implies.
  ///
  /// Only an `error` overrides, and it overrides to **amber**. A record the
  /// service flagged as failing is the canonical fault: the \*arr answered and
  /// said this download is broken. Red would claim it did not answer at all.
  /// The override still matters, because it holds the fault tone even when the
  /// pipeline alone would read calm; a warning escalates the same way through
  /// [MediaStatusInfo.hasWarning].
  StatusTone? get toneOverride =>
      severity == ArrQueueSeverity.error ? StatusTone.warning : null;

  /// Reads a single `/queue` record.
  ///
  /// `trackedDownloadState` decides the post-download phases (import, failure);
  /// for anything still with the download client the `status` field decides,
  /// because a queued item also carries `trackedDownloadState: downloading`.
  ///
  /// Returns null when the record represents work that is already finished
  /// (`imported`) or deliberately skipped (`ignored`); those must not mask the
  /// real availability of the item.
  ///
  /// Any unrecognised state still yields a non-null entry (defaulting to
  /// [MediaPipeline.queued]): the record's mere presence in the queue means
  /// something is in flight, and reporting "Queued" is always closer to the
  /// truth than falling through to "Missing".
  static ArrQueueEntry? fromQueueItem(Map<String, dynamic> item) {
    final trackedState = stringOrNull(
      item['trackedDownloadState'],
    )?.toLowerCase();
    final rawStatus = stringOrNull(item['status']);
    final status = rawStatus?.toLowerCase();

    final resolved = _resolve(
      trackedState: trackedState,
      status: status,
      rawStatus: rawStatus,
      isStalled: _looksStalled(item),
    );
    if (resolved == null) return null;

    // A `status` of `warning` is itself a severity signal, even on a record that
    // carries neither `trackedDownloadStatus` nor any status message.
    final reported = arrQueueSeverity(item);
    final severity = status == 'warning' && reported == ArrQueueSeverity.ok
        ? ArrQueueSeverity.warning
        : reported;

    return ArrQueueEntry(
      pipeline: resolved.pipeline,
      label: resolved.label,
      progress: queueProgress(item),
      severity: severity,
      detail:
          stringOrNull(item['errorMessage']) ?? arrQueueWarningMessage(item),
      finishesAt: DateTime.tryParse(
        stringOrNull(item['estimatedCompletionTime']) ?? '',
      )?.toLocal(),
    );
  }

  /// Whether the service is telling us this transfer has stopped moving.
  ///
  /// There is no `stalled` value in an \*arr's `status` field: the services
  /// report a stall in prose, via `errorMessage` or `statusMessages`, and their
  /// own web UIs read it back out the same way. Text matching is therefore the
  /// only signal available, so it is deliberately narrow: if the upstream
  /// wording changes this returns false and the record degrades to the previous
  /// behaviour (`downloading`, carrying a warning) rather than mislabelling a
  /// healthy transfer.
  static bool _looksStalled(Map<String, dynamic> item) {
    final haystack = [
      stringOrNull(item['errorMessage']),
      ...extractArrStatusMessages(item['statusMessages']),
    ].whereType<String>().join(' · ').toLowerCase();

    return haystack.contains('stalled') || haystack.contains('no connections');
  }

  static ({MediaPipeline pipeline, String? label})? _resolve({
    required String? trackedState,
    required String? status,
    required String? rawStatus,
    required bool isStalled,
  }) {
    // `trackedDownloadState` tracks which *phase* the \*arr has reached, so it
    // wins for the post-download phases: those are invisible to `status`, which
    // just reports `completed` for all of them.
    switch (trackedState) {
      case 'importpending':
        return (pipeline: MediaPipeline.importPending, label: null);
      // Split from `importpending` above, which it used to share. The two mean
      // opposite things to the user: `importPending` clears itself within
      // seconds, while `importBlocked` is the \*arr asking for a manual import
      // and will sit there until someone acts. Collapsing them hid every request
      // for help inside the most common transient state in the queue.
      case 'importblocked':
        return (pipeline: MediaPipeline.importBlocked, label: null);
      case 'importing':
        return (pipeline: MediaPipeline.importing, label: null);
      case 'failedpending':
      case 'failed':
        return (pipeline: MediaPipeline.failed, label: null);
      case 'imported':
      case 'ignored':
        return null;
    }

    // `trackedDownloadState: downloading` only means "still with the download
    // client", a queued or paused item carries it too, so it must NOT be read
    // as "bytes are moving". The client `status` is what decides that, matching
    // what the *arr's own UI shows.
    final isWithClient = trackedState == 'downloading';

    return switch (status) {
      // The client is done but the *arr has not imported yet.
      'completed' => (pipeline: MediaPipeline.importPending, label: null),
      'queued' || 'delay' => (pipeline: MediaPipeline.queued, label: null),
      'downloading' => (
        pipeline: isStalled ? MediaPipeline.stalled : MediaPipeline.downloading,
        label: null,
      ),
      'paused' => (pipeline: MediaPipeline.paused, label: null),
      'failed' => (pipeline: MediaPipeline.failed, label: null),
      'downloadclientunavailable' => (
        pipeline: MediaPipeline.clientUnavailable,
        label: null,
      ),
      // `warning` is one of the \*arr status values, not an unknown string, and
      // it used to fall through to the branch below, which turned a record the
      // service had flagged into the word "Warning" sitting in a "Queued" row.
      'warning' => (
        pipeline: isStalled
            ? MediaPipeline.stalled
            : (isWithClient ? MediaPipeline.downloading : MediaPipeline.queued),
        label: null,
      ),
      // An unrecognised status still means something is in flight; keep the
      // service's own wording (humanised from the original casing) rather than
      // flattening it away.
      final String value when value.isNotEmpty => (
        pipeline: MediaPipeline.queued,
        label: humanizeCamelCase(rawStatus ?? value),
      ),
      // No status at all: fall back to whatever the tracked phase implied.
      _ => (
        pipeline: isWithClient
            ? (isStalled ? MediaPipeline.stalled : MediaPipeline.downloading)
            : MediaPipeline.queued,
        label: null,
      ),
    };
  }
}

/// Collapses several queue entries for the same media item into one.
///
/// Returns null for an empty input. Used by Seerr, whose `downloadStatus` array
/// carries one record per connected \*arr download.
ArrQueueEntry? mergeArrQueueEntries(Iterable<ArrQueueEntry> entries) {
  _EntryAccumulator? accumulator;
  for (final entry in entries) {
    (accumulator ??= _EntryAccumulator(entry.pipeline)).add(entry);
  }
  return accumulator?.freeze();
}

/// The badge a title shows over [queue], or none while the queue is still
/// being read and the badge would hang on it.
///
/// A grid that opens on "Unknown" and turns to "Downloading" a moment later has
/// said a word it then takes back. While [queue] has neither answered nor
/// failed, a title whose state needs the queue (nothing on disk, no entry yet)
/// shows no badge at all; one the library settles alone, a film on disk, keeps
/// its own. Once the queue fails, "Unknown" is the honest word and shows.
MediaStatusInfo? badgeOverQueue(
  MediaStatusInfo status,
  ArrQueueSnapshot queue,
) => queue.isPending && status.availability == MediaAvailability.unknown
    ? null
    : status;

/// Combines the availability axis with a queue entry into a renderable status.
///
/// The single place where "what is on disk" meets "what is in flight", so every
/// \*arr resolver produces the same shape and an item in the queue can never
/// come out as `Missing`.
///
/// [queueUnknown] is the queue's half of that promise: no entry proves nothing
/// when the queue could not be read whole ([ArrQueueSnapshot.isWhole] false).
/// A title with nothing on disk may be downloading right now, so it reads
/// [MediaAvailability.unknown] rather than `Missing`; every other availability
/// is the library's own word and stands. Pass it as `!snapshot.isWhole`, and
/// as true while there is no snapshot at all.
MediaStatusInfo mediaStatusFromQueue({
  required MediaAvailability availability,
  required bool monitored,
  ArrQueueEntry? queueEntry,
  bool queueUnknown = false,
}) {
  return MediaStatusInfo(
    availability:
        queueEntry == null &&
            queueUnknown &&
            availability == MediaAvailability.missing
        ? MediaAvailability.unknown
        : availability,
    pipeline: queueEntry?.pipeline,
    progress: queueEntry?.progress,
    unmonitored: !monitored,
    hasWarning: queueEntry?.hasWarning ?? false,
    detail: queueEntry?.detail,
    labelOverride: queueEntry?.label,
    toneOverride: queueEntry?.toneOverride,
  );
}

/// An \*arr download queue indexed by media id, and when it was taken.
///
/// Three readings, and a screen has to tell them apart: the queue answered and
/// was read to the end ([isWhole]), so a title with no entry is not in it; the
/// queue answered but the walk stopped short ([cutShort]), so the entries are
/// true and an absence proves nothing; or the queue did not answer
/// ([answered] false, [ArrQueueSnapshot.failed]), so nothing is known about
/// what is in flight.
///
/// The last two used to read as the first. A failed read degraded to [empty],
/// and every title that was downloading read `Missing` on its detail page,
/// because "no entry" was taken as "not in the queue".
///
/// A fourth reading sits between them: a refresh that failed over a queue
/// that answered before ([isStale], [staleAfter]). The last answer stays, so
/// a title that was downloading a minute ago does not drop back to
/// `Unknown`, and it says it is old: it did not answer now, so it is not
/// whole and an absence proves nothing.
class ArrQueueSnapshot {
  /// A queue that answered with nothing in it.
  static const ArrQueueSnapshot empty = ArrQueueSnapshot._(
    <int, ArrQueueEntry>{},
    null,
  );

  /// A queue nobody could read, for a caller with no error to keep: a screen
  /// with no snapshot yet reads this rather than [empty].
  static const ArrQueueSnapshot unknown = ArrQueueSnapshot.failed(null);

  /// A queue read that failed with [error]: no entries, and none of them can
  /// be taken as an answer.
  const ArrQueueSnapshot.failed(this.error)
    : entriesById = const <int, ArrQueueEntry>{},
      sampledAt = null,
      answered = false,
      cutShort = false,
      isStale = false;

  const ArrQueueSnapshot._stale(this.entriesById, this.sampledAt, this.error)
    : answered = false,
      cutShort = false,
      isStale = true;

  final Map<int, ArrQueueEntry> entriesById;

  /// The queue answered. False on [ArrQueueSnapshot.failed], and on a
  /// [isStale] snapshot, whose last read did not answer either.
  final bool answered;

  /// Why the queue could not be read, when it could not and the reader kept
  /// the reason. Null on every snapshot that [answered].
  final Object? error;

  /// The last read failed and these entries are the answer before it, taken
  /// at [sampledAt] ([staleAfter]). Every entry was true then; none says how
  /// far a download has got now, and a title with none may have started
  /// since, so the snapshot is not [isWhole].
  final bool isStale;

  /// The walk across the queue's pages stopped before the end of it
  /// (`ArrRecordPage.cutShort`): every entry here is true, and a title with
  /// none may still be in the part that was not read. A figure taken from
  /// [entriesById] is then a floor, `200+`.
  final bool cutShort;

  /// The queue answered and every record of it was read, so a title with no
  /// entry is not in the queue.
  bool get isWhole => answered && !cutShort;

  /// Nothing has come back yet: the queue has neither answered nor failed.
  /// [unknown] is this state; a failed read carries its error.
  bool get isPending => !answered && !isStale && error == null;

  /// When the records in this snapshot were read from the service.
  ///
  /// The whole point of a *snapshot* is that it stops being true, and nothing
  /// in the app could previously say when it had. A queue polls on a timer, and
  /// when the poll stops coming back: the service is answering but its queue
  /// endpoint is not, or the timer was suspended with the app in the
  /// background: the rows keep their progress bars and keep looking live.
  /// A bar that is not advancing must not look like one that is, so surfaces
  /// trade the time-left for this age and the page raises
  /// `FaultBand.stale` once it is older than its own poll interval.
  ///
  /// `null` only on [empty] and on a failed read, which have nothing to be
  /// old.
  final DateTime? sampledAt;

  const ArrQueueSnapshot._(
    this.entriesById,
    this.sampledAt, {
    this.cutShort = false,
  }) : answered = true,
       error = null,
       isStale = false;

  /// This reading kept after a later read failed with [error].
  ///
  /// The entries stay without their progress
  /// ([ArrQueueEntry.withoutProgress]) and [sampledAt] stays the time they
  /// were read, so a page can say how old they are. A snapshot that never
  /// answered has nothing to keep and stays [ArrQueueSnapshot.failed].
  ArrQueueSnapshot staleAfter(Object? error) {
    if (!answered && !isStale) return ArrQueueSnapshot.failed(error);
    return ArrQueueSnapshot._stale(
      {
        for (final entry in entriesById.entries)
          entry.key: entry.value.withoutProgress(),
      },
      sampledAt,
      error,
    );
  }

  bool get isEmpty => entriesById.isEmpty;
  bool get isNotEmpty => entriesById.isNotEmpty;

  /// How old this snapshot is as of [now], or `null` when it has no sample time.
  Duration? ageAt(DateTime now) {
    final at = sampledAt;
    return at == null ? null : now.difference(at);
  }

  ArrQueueEntry? entryFor(int? mediaId) {
    if (mediaId == null) return null;
    return entriesById[mediaId];
  }

  /// Builds a snapshot from raw `/queue` records.
  ///
  /// [idsFor] returns every media id a record belongs to; a Sonarr record maps
  /// to one series, but callers that pre-resolve album → artist may return
  /// several. Records whose ids cannot be resolved are dropped.
  /// [sampledAt] defaults to now, which is true for every live fetch and is why
  /// no caller has to remember it. A test that wants to state an age passes one.
  /// [cutShort] is the walk's own word that [items] are not the whole queue.
  factory ArrQueueSnapshot.fromQueueItems(
    Iterable<dynamic> items, {
    required Iterable<int> Function(Map<String, dynamic> item) idsFor,
    DateTime? sampledAt,
    bool cutShort = false,
  }) {
    final accumulators = <int, _EntryAccumulator>{};

    for (final raw in items) {
      final item = mapOrNull(raw);
      if (item == null) continue;

      final entry = ArrQueueEntry.fromQueueItem(item);
      if (entry == null) continue;

      for (final id in idsFor(item)) {
        if (id <= 0) continue;
        (accumulators[id] ??= _EntryAccumulator(entry.pipeline)).add(entry);
      }
    }

    return ArrQueueSnapshot._(
      {for (final acc in accumulators.entries) acc.key: acc.value.freeze()},
      sampledAt ?? DateTime.now(),
      cutShort: cutShort,
    );
  }
}

/// How old [queue]'s reading is, as the end of "as it was …": what a page
/// under a stale queue ([ArrQueueSnapshot.isStale]) says of the downloads it
/// still shows. The app's one vocabulary for an age ([formatDurationAge],
/// `3 min ago`), except under a minute, which reads `a moment ago`: "as it was
/// just now" right after a failure reads as if nothing had failed.
String queueReadingAge(ArrQueueSnapshot queue, {DateTime? now}) {
  final at = now ?? DateTime.now();
  final elapsed = at.difference(queue.sampledAt ?? at);
  return elapsed.inMinutes < 1 ? 'a moment ago' : formatDurationAge(elapsed);
}

/// Collapses several queue records onto one media item.
///
/// The highest-[MediaPipeline.salience] state becomes the headline, and the
/// reported progress is the mean across the records sharing it: a series with
/// two episodes at 20% and 80% reads 50%, not 80%.
class _EntryAccumulator {
  MediaPipeline pipeline;
  String? _label;
  double _progressSum = 0;
  int _progressSamples = 0;
  ArrQueueSeverity _severity = ArrQueueSeverity.ok;
  String? _detail;
  DateTime? _finishesAt;

  _EntryAccumulator(this.pipeline);

  void add(ArrQueueEntry entry) {
    if (entry.pipeline.salience > pipeline.salience) {
      pipeline = entry.pipeline;
      _label = null;
      _detail = null;
      _finishesAt = null;
      _progressSum = 0;
      _progressSamples = 0;
    }

    if (entry.pipeline == pipeline) {
      _label ??= entry.label;
      // `_detail` follows the headline for the same reason `_label` does: both
      // describe *the state being reported*. Taking it from whichever record
      // happened to arrive first let a row headline "Downloading" and then print
      // the error message belonging to a different episode: the label was reset
      // when the headline changed and the detail was not.
      _detail ??= entry.detail;
      // The last of the headline's transfers to finish: the item is done
      // when all of them are.
      final finishes = entry.finishesAt;
      if (finishes != null &&
          (_finishesAt == null || finishes.isAfter(_finishesAt!))) {
        _finishesAt = finishes;
      }
      if (entry.progress != null) {
        _progressSum += entry.progress!;
        _progressSamples++;
      }
    }

    // Severity is deliberately the exception: it belongs to the *group*, not to
    // the headline. One episode erroring still matters when a healthy download
    // wins the headline, so this keeps the worst seen.
    if (entry.severity.index > _severity.index) _severity = entry.severity;
  }

  ArrQueueEntry freeze() {
    return ArrQueueEntry(
      pipeline: pipeline,
      label: _label,
      progress: _progressSamples == 0 ? null : _progressSum / _progressSamples,
      severity: _severity,
      detail: _detail,
      finishesAt: _finishesAt,
    );
  }
}
