/// What a row of a download client's own list is to In flight, read off the
/// client's own fields.
///
/// The four clients are one family and are read by one rule: a row is either
/// not in flight at all (seeding, or stopped on purpose), a transfer, or a
/// fault, and a fault is never a row that silently drops out. Each reader
/// below names the wire fields it decides on, so the rule can be checked
/// against the client's API rather than against this file.
///
/// Pure and top-level, so each mapping is testable without a container.
library;

import 'dart:math' as math;

import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/features/nzbget/domain/models/nzbget_models.dart';
import 'package:cupola/features/qbittorrent/domain/models/torrent.dart';
import 'package:cupola/features/sabnzbd/domain/models/sabnzbd_models.dart';
import 'package:cupola/features/services/domain/in_flight.dart';
import 'package:cupola/features/transmission/domain/models/transmission_models.dart';

/// One client row, read: a transfer, a download waiting its turn, a download
/// held on purpose, or a fault, with the client's own words for the fault
/// when it gave any.
class InFlightReading {
  /// Bytes are moving, or about to: a transfer that has begun.
  const InFlightReading.moving()
    : fault = null,
      reason = null,
      held = false,
      queued = false;

  /// A download waiting its turn to start: the client has it in line behind
  /// others and has not begun. Still to come, so it is not backlog and not a
  /// fault; and not moving either, which is what it used to be counted as.
  const InFlightReading.queued()
    : fault = null,
      reason = null,
      held = false,
      queued = true;

  /// A download somebody stopped on purpose, with bytes still to come: the
  /// backlog, which the tone rule files under neutral. Not in flight and not
  /// a fault, the same on every client.
  const InFlightReading.held()
    : fault = null,
      reason = null,
      held = true,
      queued = false;

  /// The row stopped being a transfer, for [reason] when the client said why.
  const InFlightReading.fault(InFlightFault this.fault, {this.reason})
    : held = false,
      queued = false;

  final InFlightFault? fault;

  /// The client's reason, as it put it, or null when it gave none and the
  /// fault's own word stands.
  final String? reason;

  /// Stopped on purpose: see [InFlightReading.held].
  final bool held;

  /// Waiting its turn: see [InFlightReading.queued].
  final bool queued;

  @override
  bool operator ==(Object other) =>
      other is InFlightReading &&
      other.fault == fault &&
      other.reason == reason &&
      other.held == held &&
      other.queued == queued;

  @override
  int get hashCode => Object.hash(fault, reason, held, queued);

  @override
  String toString() =>
      'InFlightReading(${fault?.name ?? (held ? 'held' : (queued ? 'queued' : 'moving'))}'
      '${reason == null ? '' : ', $reason'})';
}

/// A Transmission torrent (`torrent-get`), or null when it is not in flight.
///
/// Decided on `status`, `error`, `errorString` and `isStalled`:
///
/// * `error` 3, a local error, is the daemon unable to read or write the data
///   (the disk is gone, full or read-only). It stops the torrent whatever it
///   was doing, so it is a fault on any row, a seeding one included.
/// * Otherwise only the incoming states are in flight: `download`,
///   `downloadWait`, `check`, `checkWait`. `downloadWait` (status 3) is a
///   download waiting its turn in the daemon's queue: queued, not moving.
///   A stopped torrent with bytes still
///   to come (`leftUntilDone`) was stopped on purpose and is held; a stopped
///   or seeding one with nothing left to fetch is not in flight at all.
/// * `error` 2, a tracker error, on an incoming torrent is a failure: the
///   model's [TransmissionErrorKind.isBlocking] rule. A tracker *warning* is
///   announce noise and stays a transfer.
/// * `isStalled` on a downloading torrent is a stall once nothing has arrived
///   for [stuckAfter], by `activityDate` (or `addedDate` for a torrent that
///   never received a byte). Before that it is a transfer at no speed.
InFlightReading? transmissionInFlight(
  TransmissionTorrent torrent, {
  required DateTime now,
}) {
  if (torrent.errorKind == TransmissionErrorKind.localError) {
    return InFlightReading.fault(InFlightFault.failed, reason: torrent.warning);
  }
  // Unfinished: bytes still to come, or a magnet stopped before its
  // metadata, which knows no size yet and so has none left either.
  if (torrent.status == TransmissionStatus.stopped &&
      (torrent.leftUntilDone > 0 || torrent.percentDone < 1)) {
    return const InFlightReading.held();
  }
  if (!torrent.status.isIncoming) return null;
  if (torrent.errorKind == TransmissionErrorKind.trackerError) {
    return InFlightReading.fault(InFlightFault.failed, reason: torrent.warning);
  }
  if (torrent.isStalled && torrent.status == TransmissionStatus.download) {
    return _stuckOnceIdle(
      idleSince(
        lastActivity: torrent.activityDate,
        added: torrent.addedDate,
        started: torrent.startDate,
      ),
      now,
      unknownIsStuck: true,
    );
  }
  if (torrent.status == TransmissionStatus.downloadWait) {
    return const InFlightReading.queued();
  }
  return const InFlightReading.moving();
}

/// A qBittorrent torrent (`/api/v2/torrents/info`), or null when it is not in
/// flight. Decided on `state`, the raw wire value, and on how long nothing
/// has arrived.
///
/// `stalledDL` is a stall once nothing has arrived for [stuckAfter], by
/// `last_activity` (or `added_on` for a torrent that never received a byte, or
/// the moment Cupola saw it start again, [Torrent.resumedOn], if later):
/// qBittorrent sets it at any instant the payload rate is zero, so on its own
/// it is a slow moment, not a fault. `metaDL`, fetching the torrent's
/// metadata, is the same: it waits on peers, and a magnet nobody answers sits
/// in it at 0% for good, so past [stuckAfter] it is a stall too. `error` and
/// `missingFiles` are failures on any
/// row, a finished one included: qBittorrent stops a torrent it cannot read
/// or write, and dropping it with the seeding library made a broken download
/// vanish from Home with nothing saying so. `missingFiles` says why; a bare
/// `error` does not, and the API carries no message for it. A download paused
/// or stopped on purpose (`pausedDL`, `stoppedDL`) is held, and one waiting
/// its turn behind the client's active limit (`queuedDL`) is queued. Seeding, checking,
/// a finished torrent stopped (`pausedUP`, `stoppedUP`) and one whose files
/// are moving to their folder (`moving`) are not in flight.
InFlightReading? qbittorrentInFlight(Torrent torrent, {required DateTime now}) {
  final state = torrent.state;
  if (state == 'pausedDL' || state == 'stoppedDL') {
    return const InFlightReading.held();
  }
  if (state == 'missingFiles') {
    return const InFlightReading.fault(
      InFlightFault.failed,
      reason: qbittorrentMissingFiles,
    );
  }
  final idle = idleSince(
    lastActivity: torrent.lastActivity,
    added: torrent.addedOn,
    started: torrent.resumedOn,
  );
  return switch (TorrentState.fromString(state)) {
    TorrentState.downloading => const InFlightReading.moving(),
    TorrentState.queuedDl => const InFlightReading.queued(),
    // Without a date to measure by, the metadata wait is taken as a
    // transfer: the client has not said anything is wrong.
    TorrentState.metaDownloading => _stuckOnceIdle(
      idle,
      now,
      unknownIsStuck: false,
    ),
    // `stalled` is only ever `stalledDL`: a stalled upload parses as seeding.
    TorrentState.stalled => _stuckOnceIdle(idle, now, unknownIsStuck: true),
    TorrentState.error => const InFlightReading.fault(InFlightFault.failed),
    // A pause for the move, not an end: a download with bytes still to come
    // stays in flight, a finished one leaving its incomplete folder is done.
    TorrentState.movingFiles =>
      torrent.progress < 1 ? const InFlightReading.moving() : null,
    TorrentState.seeding ||
    TorrentState.checking ||
    TorrentState.paused ||
    TorrentState.queuedUp ||
    TorrentState.unknown => null,
  };
}

/// How long a download goes with nothing arriving before it is stuck.
///
/// The word promises it (`Stuck` only after 30 minutes with nothing arriving):
/// a torrent client's own stall flag flips on at any instant the rate touches
/// zero, so a fault raised on the flag alone came and went with every slow
/// minute of a healthy download.
const Duration stuckAfter = Duration(minutes: 30);

/// Since when a torrent has waited with nothing arriving, from the client's
/// epoch seconds: the latest of [lastActivity], [added] and [started]. A
/// torrent that never received a byte has waited since it was added, and one
/// stopped for weeks and started again has waited since it started (Transmission
/// says when, `startDate`): counting from its addition called it stuck the
/// moment it was resumed, `for 26 days`. Null when the client gave none.
DateTime? idleSince({
  required int lastActivity,
  required int added,
  int started = 0,
}) {
  final seconds = [lastActivity, added, started].reduce(math.max);
  if (seconds <= 0) return null;
  return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
}

/// A stall once [since] is at least [stuckAfter] before [now], a transfer
/// before that. With no date, [unknownIsStuck] decides: the client's own
/// stall flag stands, a metadata wait does not.
InFlightReading _stuckOnceIdle(
  DateTime? since,
  DateTime now, {
  required bool unknownIsStuck,
}) {
  final stuck = since == null
      ? unknownIsStuck
      : now.difference(since) >= stuckAfter;
  return stuck
      ? const InFlightReading.fault(InFlightFault.stalled)
      : const InFlightReading.moving();
}

/// What a `missingFiles` torrent's decision says: its data is not where
/// qBittorrent left it.
const String qbittorrentMissingFiles = 'Files missing';

/// What a job stopped by a full disk says: the queue cannot write another
/// byte.
const String diskFullReason = 'Disk full';

/// Whether a usenet queue that is paused was stopped by its disk rather than
/// by a person.
///
/// SABnzbd and NZBGet stop on a full disk by flipping the switch a user's
/// pause flips (SABnzbd's `Downloader.pause()`, NZBGet's pause register), so
/// the flag cannot tell the two apart. The free space can: a paused queue
/// whose download folder cannot hold even the smallest job it still has to
/// fetch was stopped by the disk. A queue with room left is read as paused on
/// purpose, which the tone rule files under neutral: a pause the client took
/// below a free-space threshold of its own is missed rather than a person's
/// pause called a fault.
///
/// [timedPause] is always somebody's decision. A free space the client did not
/// report proves nothing, and neither does a queue with nothing left to fetch.
bool usenetQueueStoppedByDisk({
  required bool paused,
  required int? freeBytes,
  required Iterable<int?> remainingBytes,
  bool timedPause = false,
}) {
  if (!paused || timedPause || freeBytes == null) return false;
  int? smallest;
  for (final left in remainingBytes) {
    if (left == null || left <= 0) continue;
    if (smallest == null || left < smallest) smallest = left;
  }
  return smallest != null && freeBytes < smallest;
}

/// [usenetQueueStoppedByDisk] over a SABnzbd queue: its download folder's
/// free space (`diskspace1`) against the jobs it still has to fetch. One
/// reading for Home's downloads and the room's Status figure, so the two
/// cannot call one queue full and paused.
bool sabnzbdQueueStoppedByDisk(SabnzbdQueue queue) {
  const megabyte = 1024 * 1024;
  const gigabyte = 1024 * megabyte;
  final free = queue.downloadDiskFreeGb;
  return usenetQueueStoppedByDisk(
    paused: queue.paused,
    timedPause: queue.isTimedPause,
    freeBytes: free == null ? null : (free * gigabyte).round(),
    remainingBytes: [
      for (final slot in queue.slots)
        if (slot.status.toLowerCase() != 'paused')
          (slot.mbLeft * megabyte).round(),
    ],
  );
}

/// [usenetQueueStoppedByDisk] over an NZBGet queue: the free space where it
/// writes ([NzbgetStatus.writingDiskFreeMb]) against the groups it still has
/// to fetch. See [sabnzbdQueueStoppedByDisk].
bool nzbgetQueueStoppedByDisk(NzbgetStatus status, List<NzbgetGroup> groups) {
  const megabyte = 1024 * 1024;
  final free = status.writingDiskFreeMb;
  return usenetQueueStoppedByDisk(
    paused: status.paused,
    timedPause: status.isDeliberateStop,
    freeBytes: free == null ? null : free * megabyte,
    remainingBytes: [
      for (final group in groups)
        if (group.status.toUpperCase() != 'PAUSED' &&
            nzbgetIsFetching(group.status))
          switch (group.remainingSizeMb) {
            final int left => left * megabyte,
            null => null,
          },
    ],
  );
}

/// What one of SABnzbd's job `labels` says about a paused job, in the house
/// words: the reason it was held, or null for a label that marks a wait.
///
/// SABnzbd's set (`NzbObject.labels`, `sabnzbd/nzb/object.py`), and which
/// of them it pauses a job for:
///
/// * `ENCRYPTED`: an encrypted archive, paused when `pause_on_pwrar` is set
///   (`assembler.py`). [passwordNeededReason], NZBGet's word for the same.
/// * `DUPLICATE`: a job it already has, paused by the duplicate check.
/// * `TOO LARGE`: over the configured size, paused on arrival.
/// * `INCOMPLETE`: an NZB missing files, paused when incomplete NZBs are
///   allowed.
/// * `UNWANTED`: an unwanted file type, paused when that is the configured
///   action.
/// * `ALTERNATIVE`, `WAIT n sec`, `PROPAGATING n min`: a spare kept by the
///   duplicate check, a URL fetch waiting its turn, Usenet's propagation
///   delay. Waits by design, not faults.
///
/// SABnzbd translates its labels into its own language. One it does not
/// document, or a translated one, is kept exactly as sent: a machine string,
/// never rewritten by a guess.
String? sabnzbdLabelReason(String label) {
  final value = label.trim();
  final upper = value.toUpperCase();
  if (upper.startsWith('WAIT ') || upper.startsWith('PROPAGATING ')) {
    return null;
  }
  return switch (upper) {
    'ALTERNATIVE' => null,
    'ENCRYPTED' => passwordNeededReason,
    'DUPLICATE' => duplicateReason,
    'TOO LARGE' => tooLargeReason,
    'INCOMPLETE' => incompleteReason,
    'UNWANTED' => unwantedFileReason,
    _ => value.isEmpty ? null : value,
  };
}

/// A SABnzbd queue slot (`mode=queue`), read. Every slot is in flight: the
/// queue holds only jobs still to fetch.
///
/// * A slot `status` of `Paused` carrying a label SABnzbd pauses for
///   ([sabnzbdLabelReason]) is a job SABnzbd held itself, waiting on a
///   person: a stall, in the house words. A paused slot with no such label is
///   somebody's pause, and is held.
/// * [stoppedByDisk] ([usenetQueueStoppedByDisk]) stalls every other job.
/// * [pausedOnPurpose], a queue somebody paused, holds every other job.
/// * A slot `status` of `Queued` (SABnzbd's `Status.QUEUED`, a job waiting
///   for its turn to download) is queued, once the cases above have had
///   their say.
InFlightReading sabnzbdSlotInFlight(
  SabnzbdQueueSlot slot, {
  required bool stoppedByDisk,
  bool pausedOnPurpose = false,
}) {
  if (slot.status.toLowerCase() == 'paused') {
    final reasons = [
      for (final label in slot.labels) ?sabnzbdLabelReason(label),
    ];
    return reasons.isEmpty
        ? const InFlightReading.held()
        : InFlightReading.fault(
            InFlightFault.stalled,
            reason: reasons.toSet().join(dotSeparator),
          );
  }
  if (stoppedByDisk) {
    return const InFlightReading.fault(
      InFlightFault.stalled,
      reason: diskFullReason,
    );
  }
  if (pausedOnPurpose) return const InFlightReading.held();
  if (slot.status.toLowerCase() == 'queued') {
    return const InFlightReading.queued();
  }
  return const InFlightReading.moving();
}

/// When each job of a SABnzbd queue starts, in seconds, in queue order, from
/// each slot's [finishesIn]: its `timeleft` as a number of seconds, null for
/// a slot that gave none.
///
/// SABnzbd's per-slot `timeleft` is cumulative: `build_queue` (`api.py`)
/// keeps a running total of the bytes left, adds each slot's own to it, and
/// prints the time that total takes at the current speed. So each figure is
/// when **that** job finishes, counting every job ahead of it, and a job
/// starts when the one before it has finished. A slot SABnzbd skips (paused,
/// held for propagation) prints `0:00:00` and adds nothing to the total; zero
/// is no figure, so the job is dated by the nearest slot ahead that has one.
/// The first job, and one with nothing ahead of it that has a figure, starts
/// at no time anybody knows: null. Read the figure only for a job that is
/// queued; a moving job's start is behind it.
List<int?> sabnzbdStartsInSeconds(List<int?> finishesIn) {
  final starts = <int?>[];
  int? ahead;
  for (final finish in finishesIn) {
    starts.add(ahead);
    if (finish != null && finish > 0) ahead = finish;
  }
  return starts;
}

/// Whether an NZBGet `listgroups` status is one in which the group is still
/// fetching: the ones a stopped download queue holds up. The rest are
/// post-processing, which a download pause does not stop.
bool nzbgetIsFetching(String status) => switch (status.toUpperCase()) {
  'QUEUED' || 'PAUSED' || 'DOWNLOADING' || 'FETCHING' => true,
  _ => false,
};

/// A download that cannot be repaired: an NZBGet group below its critical
/// health.
const String beyondRepairReason = 'Damaged beyond repair';

/// An NZBGet group whose par repair failed.
const String repairFailedReason = 'Repair failed';

/// An NZBGet group whose unpack failed.
const String unpackFailedReason = 'Unpack failed';

/// A download whose archive wants a password: NZBGet's unpack `PASSWORD`,
/// SABnzbd's `ENCRYPTED`.
const String passwordNeededReason = 'Password needed';

/// A job its client holds as a copy of one it already has: SABnzbd's
/// `DUPLICATE`.
const String duplicateReason = 'Duplicate';

/// A job over the size its client is set to take: SABnzbd's `TOO LARGE`.
const String tooLargeReason = 'Too large';

/// A job whose NZB lacks some of its files: SABnzbd's `INCOMPLETE`.
const String incompleteReason = 'Incomplete';

/// A job carrying a file type its client is set to refuse: SABnzbd's
/// `UNWANTED`.
const String unwantedFileReason = 'Unwanted file type';

/// An NZBGet group (`listgroups`), read. Every group is in flight: the queue
/// holds only jobs NZBGet has not moved to its history.
///
/// * `Health` below `CriticalHealth` is a download that cannot be repaired,
///   whatever its `Status` (NZBGet's health check may also have paused it).
/// * `ParStatus` `FAILURE`, and `UnpackStatus` `FAILURE`, `SPACE` or
///   `PASSWORD`, are a post-processing run that failed.
/// * A `PAUSED` group otherwise is somebody's pause, and is held.
/// * [stoppedByDisk] ([usenetQueueStoppedByDisk]) stalls every other group
///   still fetching, and [pausedOnPurpose], a download queue somebody
///   paused, holds them. A pause of the download queue does not stop
///   post-processing, so a group being unpacked stays in flight.
/// * A `QUEUED` group, waiting for its turn to download, is queued, once the
///   cases above have had their say.
InFlightReading nzbgetGroupInFlight(
  NzbgetGroup group, {
  required bool stoppedByDisk,
  bool pausedOnPurpose = false,
}) {
  final health = group.health;
  final critical = group.criticalHealth;
  if (health != null && critical != null && health < critical) {
    return const InFlightReading.fault(
      InFlightFault.failed,
      reason: beyondRepairReason,
    );
  }
  if (group.parStatus == 'FAILURE') {
    return const InFlightReading.fault(
      InFlightFault.failed,
      reason: repairFailedReason,
    );
  }
  switch (group.unpackStatus) {
    case 'FAILURE':
      return const InFlightReading.fault(
        InFlightFault.failed,
        reason: unpackFailedReason,
      );
    case 'SPACE':
      return const InFlightReading.fault(
        InFlightFault.failed,
        reason: diskFullReason,
      );
    case 'PASSWORD':
      return const InFlightReading.fault(
        InFlightFault.failed,
        reason: passwordNeededReason,
      );
  }
  final status = group.status.toUpperCase();
  if (status == 'PAUSED') return const InFlightReading.held();
  if (stoppedByDisk && nzbgetIsFetching(status)) {
    return const InFlightReading.fault(
      InFlightFault.stalled,
      reason: diskFullReason,
    );
  }
  if (pausedOnPurpose && nzbgetIsFetching(status)) {
    return const InFlightReading.held();
  }
  if (status == 'QUEUED') return const InFlightReading.queued();
  return const InFlightReading.moving();
}
