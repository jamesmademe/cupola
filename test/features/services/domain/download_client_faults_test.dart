import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/nzbget/domain/models/nzbget_models.dart';
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

    test('a job SABnzbd paused itself is a stall, in the house words', () {
      expect(
        sabnzbdSlotInFlight(
          slot(status: 'Paused', labels: ['ENCRYPTED']),
          stoppedByDisk: false,
        ),
        const InFlightReading.fault(
          InFlightFault.stalled,
          reason: 'Password needed',
        ),
      );
      expect(
        sabnzbdSlotInFlight(
          slot(status: 'Paused', labels: ['DUPLICATE', 'TOO LARGE']),
          stoppedByDisk: false,
        ),
        const InFlightReading.fault(
          InFlightFault.stalled,
          reason: 'Duplicate · Too large',
        ),
      );
    });

    test('every documented label has its word; a wait is no fault; an '
        'unknown label stays as sent', () {
      expect(sabnzbdLabelReason('ENCRYPTED'), passwordNeededReason);
      expect(sabnzbdLabelReason('DUPLICATE'), 'Duplicate');
      expect(sabnzbdLabelReason('TOO LARGE'), 'Too large');
      expect(sabnzbdLabelReason('INCOMPLETE'), 'Incomplete');
      expect(sabnzbdLabelReason('UNWANTED'), 'Unwanted file type');
      expect(sabnzbdLabelReason('ALTERNATIVE'), isNull);
      expect(sabnzbdLabelReason('WAIT 12 sec'), isNull);
      expect(sabnzbdLabelReason('PROPAGATING 5 min'), isNull);
      // SABnzbd in German, say: not ours to translate.
      expect(sabnzbdLabelReason('VERSCHLÜSSELT'), 'VERSCHLÜSSELT');
    });

    test('a job paused only to wait out propagation stays a transfer', () {
      expect(
        sabnzbdSlotInFlight(
          slot(status: 'Paused', labels: ['PROPAGATING 5 min']),
          stoppedByDisk: false,
        ),
        const InFlightReading.moving(),
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

  group('NZBGet', () {
    NzbgetGroup group({
      String status = 'DOWNLOADING',
      int health = 1000,
      String? par,
      String? unpack,
    }) => NzbgetGroup.fromJson({
      'NZBID': 7,
      'NZBName': 'Night.Shift.S02E03.1080p.WEB',
      'Status': status,
      'Health': health,
      'CriticalHealth': 898,
      'ParStatus': ?par,
      'UnpackStatus': ?unpack,
    });

    test('the status reads its pause, its free space and what makes a stop '
        'deliberate', () {
      final status = NzbgetStatus.fromJson({
        'DownloadPaused': true,
        'FreeDiskSpaceMB': 9000,
        'FreeInterDiskSpaceMB': 180,
        'ResumeTime': 0,
        'QuotaReached': false,
      });
      expect(status.paused, isTrue);
      expect(status.writingDiskFreeMb, 180);
      expect(status.isDeliberateStop, isFalse);

      // An older daemon: no InterDir figure, so DestDir's.
      expect(
        NzbgetStatus.fromJson({'FreeDiskSpaceMB': 9000}).writingDiskFreeMb,
        9000,
      );
      expect(NzbgetStatus.fromJson(const {}).writingDiskFreeMb, isNull);
      expect(
        NzbgetStatus.fromJson({'ResumeTime': 1700000000}).isDeliberateStop,
        isTrue,
      );
      expect(
        NzbgetStatus.fromJson({'QuotaReached': true}).isDeliberateStop,
        isTrue,
      );
    });

    test('a group below its critical health cannot be repaired, paused or '
        'not', () {
      for (final status in ['DOWNLOADING', 'PAUSED']) {
        expect(
          nzbgetGroupInFlight(
            group(status: status, health: 640),
            stoppedByDisk: false,
          ),
          const InFlightReading.fault(
            InFlightFault.failed,
            reason: beyondRepairReason,
          ),
          reason: status,
        );
      }
    });

    test('a failed repair or unpack is a failure, by its cause', () {
      InFlightReading? read({String? par, String? unpack}) =>
          nzbgetGroupInFlight(
            group(status: 'UNPACKING', par: par, unpack: unpack),
            stoppedByDisk: false,
          );
      expect(
        read(par: 'FAILURE'),
        const InFlightReading.fault(
          InFlightFault.failed,
          reason: repairFailedReason,
        ),
      );
      expect(
        read(unpack: 'FAILURE'),
        const InFlightReading.fault(
          InFlightFault.failed,
          reason: unpackFailedReason,
        ),
      );
      expect(
        read(unpack: 'SPACE'),
        const InFlightReading.fault(
          InFlightFault.failed,
          reason: diskFullReason,
        ),
      );
      expect(
        read(unpack: 'PASSWORD'),
        const InFlightReading.fault(
          InFlightFault.failed,
          reason: passwordNeededReason,
        ),
      );
      expect(
        read(par: 'SUCCESS', unpack: 'NONE'),
        const InFlightReading.moving(),
      );
    });

    test('a full disk stalls the groups still fetching, not a paused one or '
        'one post-processing', () {
      expect(
        nzbgetGroupInFlight(group(status: 'QUEUED'), stoppedByDisk: true),
        const InFlightReading.fault(
          InFlightFault.stalled,
          reason: diskFullReason,
        ),
      );
      expect(
        nzbgetGroupInFlight(group(status: 'PAUSED'), stoppedByDisk: true),
        const InFlightReading.moving(),
      );
      expect(
        nzbgetGroupInFlight(group(status: 'UNPACKING'), stoppedByDisk: true),
        const InFlightReading.moving(),
      );
    });
  });
}
