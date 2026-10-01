import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/sabnzbd/domain/models/sabnzbd_models.dart';
import 'package:cupola/features/services/domain/download_client_faults.dart';
import 'package:cupola/features/services/domain/in_flight.dart';
import 'package:cupola/features/transmission/domain/models/transmission_models.dart';

TransmissionTorrent _torrent({
  int status = 4,
  int error = 0,
  String errorString = '',
  bool isStalled = false,
}) => TransmissionTorrent.fromJson({
  'hashString': 'abc',
  'name': 'Night.Shift.S02E04.1080p.WEB',
  'status': status,
  'error': error,
  'errorString': errorString,
  'isStalled': isStalled,
});

void main() {
  group('transmissionInFlight', () {
    test('a downloading, queued or verifying torrent is a transfer', () {
      for (final status in [4, 3, 2, 1]) {
        expect(
          transmissionInFlight(_torrent(status: status)),
          const InFlightReading.moving(),
          reason: 'status $status',
        );
      }
    });

    test('a seeding or stopped torrent is not in flight', () {
      for (final status in [6, 5, 0]) {
        expect(
          transmissionInFlight(_torrent(status: status)),
          isNull,
          reason: 'status $status',
        );
      }
    });

    test('a stalled download is a stall', () {
      expect(
        transmissionInFlight(_torrent(isStalled: true)),
        const InFlightReading.fault(InFlightFault.stalled),
      );
    });

    test('a local error is a failure on any torrent, in the daemon\'s '
        'words', () {
      for (final status in [0, 4, 6]) {
        expect(
          transmissionInFlight(
            _torrent(status: status, error: 3, errorString: 'No data found!'),
          ),
          const InFlightReading.fault(
            InFlightFault.failed,
            reason: 'No data found!',
          ),
          reason: 'status $status',
        );
      }
    });

    test('a tracker error fails a download; a tracker warning does not', () {
      expect(
        transmissionInFlight(
          _torrent(error: 2, errorString: 'Torrent not registered'),
        ),
        const InFlightReading.fault(
          InFlightFault.failed,
          reason: 'Torrent not registered',
        ),
      );
      expect(
        transmissionInFlight(_torrent(error: 1, errorString: 'Timed out')),
        const InFlightReading.moving(),
      );
    });
  });

  group('qbittorrentInFlight', () {
    test('downloading, fetching metadata, moving and queued are '
        'transfers', () {
      for (final state in [
        'downloading',
        'forcedDL',
        'metaDL',
        'queuedDL',
        'moving',
        'allocating',
      ]) {
        expect(
          qbittorrentInFlight(state),
          const InFlightReading.moving(),
          reason: state,
        );
      }
    });

    test('a stalled download is a stall', () {
      expect(
        qbittorrentInFlight('stalledDL'),
        const InFlightReading.fault(InFlightFault.stalled),
      );
    });

    test('error and missingFiles are failures, never dropped', () {
      expect(
        qbittorrentInFlight('error'),
        const InFlightReading.fault(InFlightFault.failed),
      );
      expect(
        qbittorrentInFlight('missingFiles'),
        const InFlightReading.fault(
          InFlightFault.failed,
          reason: qbittorrentMissingFiles,
        ),
      );
    });

    test('seeding, paused, stopped and checking torrents are not in '
        'flight', () {
      for (final state in [
        'uploading',
        'stalledUP',
        'forcedUP',
        'queuedUP',
        'pausedDL',
        'stoppedDL',
        'stoppedUP',
        'checkingDL',
        'checkingUP',
        'something-new',
      ]) {
        expect(qbittorrentInFlight(state), isNull, reason: state);
      }
    });
  });

  group('usenetQueueStoppedByDisk', () {
    const gb = 1024 * 1024 * 1024;

    test('a paused queue that cannot hold its smallest job was stopped by '
        'its disk', () {
      expect(
        usenetQueueStoppedByDisk(
          paused: true,
          freeBytes: gb ~/ 2,
          remainingBytes: [8 * gb, gb],
        ),
        isTrue,
      );
    });

    test('a paused queue with room for a job was paused on purpose', () {
      expect(
        usenetQueueStoppedByDisk(
          paused: true,
          freeBytes: 2 * gb,
          remainingBytes: [8 * gb, gb],
        ),
        isFalse,
      );
    });

    test('a running queue, a timed pause, an unknown free space and an '
        'empty queue prove nothing', () {
      expect(
        usenetQueueStoppedByDisk(
          paused: false,
          freeBytes: 0,
          remainingBytes: [gb],
        ),
        isFalse,
      );
      expect(
        usenetQueueStoppedByDisk(
          paused: true,
          timedPause: true,
          freeBytes: 0,
          remainingBytes: [gb],
        ),
        isFalse,
      );
      expect(
        usenetQueueStoppedByDisk(
          paused: true,
          freeBytes: null,
          remainingBytes: [gb],
        ),
        isFalse,
      );
      expect(
        usenetQueueStoppedByDisk(
          paused: true,
          freeBytes: 0,
          remainingBytes: [0, null],
        ),
        isFalse,
      );
    });
  });

  group('SABnzbd', () {
    SabnzbdQueueSlot slot({
      String status = 'Downloading',
      List<String>? labels,
    }) => SabnzbdQueueSlot.fromJson({
      'nzo_id': 'SABnzbd_nzo_x',
      'filename': 'Sintel.2010.2160p.UHD.BluRay',
      'status': status,
      'labels': ?labels,
    });

    test('the queue reads its pause timer, its free space and each slot\'s '
        'labels', () {
      final queue = SabnzbdQueue.fromJson({
        'paused': true,
        'pause_int': '12',
        'diskspace1': '0.42',
        'slots': [
          {
            'nzo_id': 'a',
            'filename': 'x',
            'status': 'Paused',
            'labels': ['ENCRYPTED', ' '],
          },
        ],
      });
      expect(queue.isTimedPause, isTrue);
      expect(queue.downloadDiskFreeGb, 0.42);
      expect(queue.slots.single.labels, ['ENCRYPTED']);

      final plain = SabnzbdQueue.fromJson({'paused': false});
      expect(plain.isTimedPause, isFalse);
      expect(plain.downloadDiskFreeGb, isNull);
    });

    test('a job SABnzbd paused itself is a stall in its own words', () {
      expect(
        sabnzbdSlotInFlight(
          slot(status: 'Paused', labels: ['ENCRYPTED']),
          stoppedByDisk: false,
        ),
        const InFlightReading.fault(InFlightFault.stalled, reason: 'ENCRYPTED'),
      );
    });

    test('a job somebody paused stays a transfer, even on a full disk', () {
      expect(
        sabnzbdSlotInFlight(slot(status: 'Paused'), stoppedByDisk: true),
        const InFlightReading.moving(),
      );
    });

    test('a full disk stalls every other job', () {
      for (final status in ['Downloading', 'Queued', 'Fetching']) {
        expect(
          sabnzbdSlotInFlight(slot(status: status), stoppedByDisk: true),
          const InFlightReading.fault(
            InFlightFault.stalled,
            reason: diskFullReason,
          ),
          reason: status,
        );
      }
      expect(
        sabnzbdSlotInFlight(slot(), stoppedByDisk: false),
        const InFlightReading.moving(),
      );
    });
  });
}
