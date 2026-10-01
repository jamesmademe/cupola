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

import 'package:cupola/features/qbittorrent/domain/models/torrent.dart';
import 'package:cupola/features/services/domain/in_flight.dart';
import 'package:cupola/features/transmission/domain/models/transmission_models.dart';

/// One client row, read: a transfer ([fault] null) or a fault, with the
/// client's own words for it when it gave any.
class InFlightReading {
  /// Bytes are moving, or waiting their turn to.
  const InFlightReading.moving() : fault = null, reason = null;

  /// The row stopped being a transfer, for [reason] when the client said why.
  const InFlightReading.fault(InFlightFault this.fault, {this.reason});

  final InFlightFault? fault;

  /// The client's reason, as it put it, or null when it gave none and the
  /// fault's own word stands.
  final String? reason;

  @override
  bool operator ==(Object other) =>
      other is InFlightReading &&
      other.fault == fault &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(fault, reason);

  @override
  String toString() =>
      'InFlightReading(${fault?.name ?? 'moving'}'
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
///   `downloadWait`, `check`, `checkWait`. A stopped torrent was stopped on
///   purpose, and a seeding one has nothing left to fetch.
/// * `error` 2, a tracker error, on an incoming torrent is a failure: the
///   model's [TransmissionErrorKind.isBlocking] rule. A tracker *warning* is
///   announce noise and stays a transfer.
/// * `isStalled` on a downloading torrent is a stall.
InFlightReading? transmissionInFlight(TransmissionTorrent torrent) {
  if (torrent.errorKind == TransmissionErrorKind.localError) {
    return InFlightReading.fault(InFlightFault.failed, reason: torrent.warning);
  }
  if (!torrent.status.isIncoming) return null;
  if (torrent.errorKind == TransmissionErrorKind.trackerError) {
    return InFlightReading.fault(InFlightFault.failed, reason: torrent.warning);
  }
  if (torrent.isStalled && torrent.status == TransmissionStatus.download) {
    return const InFlightReading.fault(InFlightFault.stalled);
  }
  return const InFlightReading.moving();
}

/// A qBittorrent torrent (`/api/v2/torrents/info`), or null when it is not in
/// flight. Decided on `state`, the raw wire value.
///
/// `stalledDL` is a stall. `error` and `missingFiles` are failures on any
/// row, a finished one included: qBittorrent stops a torrent it cannot read
/// or write, and dropping it with the seeding library made a broken download
/// vanish from Home with nothing saying so. `missingFiles` says why; a bare
/// `error` does not, and the API carries no message for it. Paused, stopped,
/// seeding and checking rows are not in flight.
InFlightReading? qbittorrentInFlight(String? state) {
  if (state == 'missingFiles') {
    return const InFlightReading.fault(
      InFlightFault.failed,
      reason: qbittorrentMissingFiles,
    );
  }
  return switch (TorrentState.fromString(state)) {
    TorrentState.downloading ||
    TorrentState.metaDownloading ||
    TorrentState.queuedDl => const InFlightReading.moving(),
    // `stalled` is only ever `stalledDL`: a stalled upload parses as seeding.
    TorrentState.stalled => const InFlightReading.fault(InFlightFault.stalled),
    TorrentState.error => const InFlightReading.fault(InFlightFault.failed),
    TorrentState.seeding ||
    TorrentState.checking ||
    TorrentState.paused ||
    TorrentState.queuedUp ||
    TorrentState.unknown => null,
  };
}

/// What a `missingFiles` torrent's decision says: its data is not where
/// qBittorrent left it.
const String qbittorrentMissingFiles = 'Files missing';
