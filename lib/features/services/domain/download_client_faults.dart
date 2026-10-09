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

import 'package:cupola/features/nzbget/domain/models/nzbget_models.dart';
import 'package:cupola/features/qbittorrent/domain/models/torrent.dart';
import 'package:cupola/features/sabnzbd/domain/models/sabnzbd_models.dart';
import 'package:cupola/features/services/domain/in_flight.dart';
import 'package:cupola/features/transmission/domain/models/transmission_models.dart';

/// One client row, read: a transfer, a download held on purpose, or a fault,
/// with the client's own words for the fault when it gave any.
class InFlightReading {
  /// Bytes are moving, or waiting their turn to.
  const InFlightReading.moving() : fault = null, reason = null, held = false;

  /// A download somebody stopped on purpose, with bytes still to come: the
  /// backlog, which the tone rule files under neutral. Not in flight and not
  /// a fault, the same on every client.
  const InFlightReading.held() : fault = null, reason = null, held = true;

  /// The row stopped being a transfer, for [reason] when the client said why.
  const InFlightReading.fault(InFlightFault this.fault, {this.reason})
    : held = false;

  final InFlightFault? fault;

  /// The client's reason, as it put it, or null when it gave none and the
  /// fault's own word stands.
  final String? reason;

  /// Stopped on purpose: see [InFlightReading.held].
  final bool held;

  @override
  bool operator ==(Object other) =>
      other is InFlightReading &&
      other.fault == fault &&
      other.reason == reason &&
      other.held == held;

  @override
  int get hashCode => Object.hash(fault, reason, held);

  @override
  String toString() =>
      'InFlightReading(${fault?.name ?? (held ? 'held' : 'moving')}'
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
///   `downloadWait`, `check`, `checkWait`. A stopped torrent with bytes still
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
  if (torrent.status == TransmissionStatus.stopped &&
      torrent.leftUntilDone > 0) {
    return const InFlightReading.held();
  }
  if (!torrent.status.isIncoming) return null;
  if (torrent.errorKind == TransmissionErrorKind.trackerError) {
    return InFlightReading.fault(InFlightFault.failed, reason: torrent.warning);
  }
  if (torrent.isStalled && torrent.status == TransmissionStatus.download) {
    return _stuckOnceIdle(
      idleSince(lastActivity: torrent.activityDate, added: torrent.addedDate),
      now,
      unknownIsStuck: true,
    );
  }
  return const InFlightReading.moving();
}

/// A qBittorrent torrent (`/api/v2/torrents/info`), or null when it is not in
/// flight. Decided on `state`, the raw wire value, and on how long nothing
/// has arrived.
///
/// `stalledDL` is a stall once nothing has arrived for [stuckAfter], by
/// `last_activity` (or `added_on` for a torrent that never received a byte):
/// qBittorrent sets it at any instant the payload rate is zero, so on its own
/// it is a slow moment, not a fault. `metaDL`, fetching the torrent's
/// metadata, is the same: it waits on peers, and a magnet nobody answers sits
/// in it at 0% for good, so past [stuckAfter] it is a stall too. `error` and
/// `missingFiles` are failures on any
/// row, a finished one included: qBittorrent stops a torrent it cannot read
/// or write, and dropping it with the seeding library made a broken download
/// vanish from Home with nothing saying so. `missingFiles` says why; a bare
/// `error` does not, and the API carries no message for it. A download paused
/// or stopped on purpose (`pausedDL`, `stoppedDL`) is held. Seeding, checking
/// and a finished torrent stopped (`pausedUP`, `stoppedUP`) are not in
/// flight.
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
  );
  return switch (TorrentState.fromString(state)) {
    TorrentState.downloading ||
    TorrentState.queuedDl => const InFlightReading.moving(),
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

/// When a torrent last received anything, from the client's epoch seconds:
/// [lastActivity] when the client recorded one, else [added], since a torrent
/// that never received a byte has waited since it was added. Null when the
/// client gave neither.
DateTime? idleSince({required int lastActivity, required int added}) {
  final seconds = lastActivity > 0 ? lastActivity : added;
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
            reason: reasons.toSet().join(' · '),
          );
  }
  if (stoppedByDisk) {
    return const InFlightReading.fault(
      InFlightFault.stalled,
      reason: diskFullReason,
    );
  }
  if (pausedOnPurpose) return const InFlightReading.held();
  return const InFlightReading.moving();
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
  return const InFlightReading.moving();
}
