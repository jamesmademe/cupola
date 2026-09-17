import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/transmission/domain/models/transmission_models.dart';
import 'package:cupola/features/transmission/domain/transmission_tone.dart';

/// A torrent through `fromJson`, the only constructor production uses.
TransmissionTorrent _torrent({
  int status = 6,
  int error = 0,
  String errorString = '',
  bool isStalled = false,
}) {
  return TransmissionTorrent.fromJson({
    'id': 1,
    'hashString': 'hash1',
    'name': 'A Torrent',
    'status': status,
    'percentDone': 1.0,
    'totalSize': 1024,
    'error': error,
    'errorString': errorString,
    'isStalled': isStalled,
  });
}

void main() {
  group('transmissionTorrentTone', () {
    test('seeding is the one state that reads green', () {
      expect(transmissionTorrentTone(_torrent(status: 6)), StatusTone.success);
    });

    test('work in flight is blue, not green', () {
      expect(transmissionTorrentTone(_torrent(status: 4)), StatusTone.info);
      expect(transmissionTorrentTone(_torrent(status: 2)), StatusTone.info);
    });

    test('a deliberate stop is backlog, never a fault', () {
      // The single most common way the tone rule breaks: painting a torrent
      // that reached its seed ratio and stopped amber because it is the row
      // that "ended".
      expect(transmissionTorrentTone(_torrent(status: 0)), StatusTone.neutral);
    });

    test('the three queues are backlog, not completion', () {
      for (final code in [1, 3, 5]) {
        expect(
          transmissionTorrentTone(_torrent(status: code)),
          StatusTone.neutral,
          reason: 'status $code is queued, not done',
        );
      }
    });

    test('a status code this app has no name for claims nothing', () {
      // Green was the fallthrough here once, so an unknown code drew a green
      // dot beside the word "unknown". An unrecognised state is not evidence
      // that anything completed.
      expect(transmissionTorrentTone(_torrent(status: 99)), StatusTone.neutral);
    });

    test('a stall and a local error are amber, never red', () {
      // Red is reserved for a daemon that did not answer at all. This one
      // answered, and what it said is that a torrent is stuck.
      expect(
        transmissionTorrentTone(_torrent(status: 4, isStalled: true)),
        StatusTone.warning,
      );
      expect(
        transmissionTorrentTone(
          _torrent(status: 6, error: 3, errorString: 'No data found'),
        ),
        StatusTone.warning,
      );
    });

    test('a fault outranks the state it happened in', () {
      // A stopped torrent is neutral; a stopped torrent the daemon reported an
      // error on is a fault first.
      expect(
        transmissionTorrentTone(
          _torrent(status: 0, error: 3, errorString: 'No data found'),
        ),
        StatusTone.warning,
      );
    });

    test('every state the daemon can report has an arm', () {
      // The guard on the rule that broke: an exhaustive walk, so a new status
      // added to the enum cannot quietly inherit whatever the last arm was.
      for (final status in TransmissionStatus.values) {
        expect(
          transmissionTorrentTone(_torrent(status: status.code)),
          isNot(StatusTone.error),
          reason: '${status.label} must never read unreachable',
        );
      }
    });
  });
}
