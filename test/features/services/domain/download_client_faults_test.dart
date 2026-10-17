import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/nzbget/domain/models/nzbget_models.dart';
import 'package:cupola/features/qbittorrent/domain/models/torrent.dart';
import 'package:cupola/features/sabnzbd/domain/models/sabnzbd_models.dart';
import 'package:cupola/features/services/domain/download_client_faults.dart';
import 'package:cupola/features/services/domain/in_flight.dart';
import 'package:cupola/features/transmission/domain/models/transmission_models.dart';

/// The moment every reading below is taken at.
final _now = DateTime(2026, 10, 9, 21);

/// [_now] less [ago], in the epoch seconds the clients send.
int _secondsAgo(Duration ago) =>
    _now.subtract(ago).millisecondsSinceEpoch ~/ 1000;

TransmissionTorrent _torrent({
  int status = 4,
  int error = 0,
  String errorString = '',
  bool isStalled = false,
  int activityDate = 0,
  int addedDate = 0,
  int startDate = 0,
  double? percentDone,
}) => TransmissionTorrent.fromJson({
  'hashString': 'abc',
  'name': 'Night.Shift.S02E04.1080p.WEB',
  'status': status,
  'percentDone': ?percentDone,
  'error': error,
  'errorString': errorString,
  'isStalled': isStalled,
  'activityDate': activityDate,
  'addedDate': addedDate,
  'startDate': startDate,
});

Torrent _qb(
  String state, {
  int lastActivity = 0,
  int addedOn = 0,
  double progress = 0,
}) => Torrent.fromJson({
  'hash': 'abc',
  'name': 'Big.Buck.Bunny.2008.1080p.BluRay',
  'state': state,
  'progress': progress,
  'last_activity': lastActivity,
  'added_on': addedOn,
});

void main() {
  group('transmissionInFlight', () {
    test('a downloading or verifying torrent is a transfer', () {
      // Download wait (3) is not here: it is in line, and not moving.
      for (final status in [4, 2, 1]) {
        expect(
          transmissionInFlight(_torrent(status: status), now: _now),
          const InFlightReading.moving(),
          reason: 'status $status',
        );
      }
    });

    test('a download waiting its turn (status 3) is queued, not moving', () {
      expect(
        transmissionInFlight(_torrent(status: 3), now: _now),
        const InFlightReading.queued(),
      );
      // A queue wait does not hide a fault: the daemon's own error stands.
      expect(
        transmissionInFlight(
          _torrent(status: 3, error: 3, errorString: 'No space left'),
          now: _now,
        ),
        const InFlightReading.fault(
          InFlightFault.failed,
          reason: 'No space left',
        ),
      );
    });

    test('a seeding or a finished stopped torrent is not in flight', () {
      for (final status in [6, 5, 0]) {
        expect(
          transmissionInFlight(
            _torrent(status: status, percentDone: 1),
            now: _now,
          ),
          isNull,
          reason: 'status $status',
        );
      }
    });

    test('a stopped torrent with bytes still to come is held', () {
      expect(
        transmissionInFlight(
          TransmissionTorrent.fromJson({
            'hashString': 'abc',
            'name': 'Night.Shift.S02E04.1080p.WEB',
            'status': 0,
            'leftUntilDone': 1024,
          }),
          now: _now,
        ),
        const InFlightReading.held(),
      );
    });

    test('a magnet stopped before its metadata is held, though it knows no '
        'size; a finished one stopped is not in flight', () {
      // Transmission 4, live: a stopped magnet says 0 left and 0 done.
      expect(
        transmissionInFlight(
          TransmissionTorrent.fromJson({
            'hashString': '89abcdef0123456789abcdef0123456789abcdef',
            'name': 'Cupola Test Transmission',
            'status': 0,
            'leftUntilDone': 0,
            'percentDone': 0.0,
          }),
          now: _now,
        ),
        const InFlightReading.held(),
      );
      expect(
        transmissionInFlight(
          TransmissionTorrent.fromJson({
            'hashString': 'abc',
            'name': 'Night.Shift.S02E04.1080p.WEB',
            'status': 0,
            'leftUntilDone': 0,
            'percentDone': 1.0,
          }),
          now: _now,
        ),
        isNull,
      );
    });

    test('a stalled download is a stall', () {
      expect(
        transmissionInFlight(_torrent(isStalled: true), now: _now),
        const InFlightReading.fault(InFlightFault.stalled),
      );
    });

    test('a local error is a failure on any torrent, in the daemon\'s '
        'words', () {
      for (final status in [0, 4, 6]) {
        expect(
          transmissionInFlight(
            _torrent(status: status, error: 3, errorString: 'No data found!'),
            now: _now,
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
          now: _now,
        ),
        const InFlightReading.fault(
          InFlightFault.failed,
          reason: 'Torrent not registered',
        ),
      );
      expect(
        transmissionInFlight(
          _torrent(error: 1, errorString: 'Timed out'),
          now: _now,
        ),
        const InFlightReading.moving(),
      );
    });
  });

  group('qbittorrentInFlight', () {
    test('downloading, fetching metadata and moving are transfers', () {
      for (final state in [
        'downloading',
        'forcedDL',
        'metaDL',
        'moving',
        'allocating',
      ]) {
        expect(
          qbittorrentInFlight(_qb(state), now: _now),
          const InFlightReading.moving(),
          reason: state,
        );
      }
    });

    test('a finished download whose files move to their folder is done', () {
      expect(
        qbittorrentInFlight(_qb('moving', progress: 1), now: _now),
        isNull,
      );
    });

    test('a download waiting its turn (queuedDL) is queued, not moving', () {
      expect(
        qbittorrentInFlight(_qb('queuedDL'), now: _now),
        const InFlightReading.queued(),
      );
      // A queued upload is a seeding torrent's wait, and not in flight.
      expect(qbittorrentInFlight(_qb('queuedUP'), now: _now), isNull);
    });

    test('a stalled download is a stall', () {
      expect(
        qbittorrentInFlight(_qb('stalledDL'), now: _now),
        const InFlightReading.fault(InFlightFault.stalled),
      );
    });

    test('error and missingFiles are failures, never dropped', () {
      expect(
        qbittorrentInFlight(_qb('error'), now: _now),
        const InFlightReading.fault(InFlightFault.failed),
      );
      expect(
        qbittorrentInFlight(_qb('missingFiles'), now: _now),
        const InFlightReading.fault(
          InFlightFault.failed,
          reason: qbittorrentMissingFiles,
        ),
      );
    });

    test('seeding, checking and finished stopped torrents are not in '
        'flight', () {
      for (final state in [
        'uploading',
        'stalledUP',
        'forcedUP',
        'queuedUP',
        'pausedUP',
        'stoppedUP',
        'checkingDL',
        'checkingUP',
        'something-new',
      ]) {
        expect(
          qbittorrentInFlight(_qb(state), now: _now),
          isNull,
          reason: state,
        );
      }
    });

    test('a download paused or stopped on purpose is held', () {
      for (final state in ['pausedDL', 'stoppedDL']) {
        expect(
          qbittorrentInFlight(_qb(state), now: _now),
          const InFlightReading.held(),
          reason: state,
        );
      }
    });
  });

  group('stuck only after 30 minutes with nothing arriving', () {
    test('qBittorrent: stalledDL is a slow moment until 30 minutes pass', () {
      expect(
        qbittorrentInFlight(
          _qb(
            'stalledDL',
            lastActivity: _secondsAgo(const Duration(minutes: 29)),
          ),
          now: _now,
        ),
        const InFlightReading.moving(),
      );
      expect(
        qbittorrentInFlight(
          _qb('stalledDL', lastActivity: _secondsAgo(stuckAfter)),
          now: _now,
        ),
        const InFlightReading.fault(InFlightFault.stalled),
      );
    });

    test('qBittorrent: a metadata wait nobody answers is stuck at 30 '
        'minutes, dated from when it was added', () {
      expect(
        qbittorrentInFlight(
          _qb('metaDL', addedOn: _secondsAgo(const Duration(minutes: 10))),
          now: _now,
        ),
        const InFlightReading.moving(),
      );
      expect(
        qbittorrentInFlight(
          _qb('metaDL', addedOn: _secondsAgo(const Duration(days: 2))),
          now: _now,
        ),
        const InFlightReading.fault(InFlightFault.stalled),
      );
    });

    test('qBittorrent: a torrent that received data lately is not stuck, '
        'however long ago it was added', () {
      expect(
        qbittorrentInFlight(
          _qb(
            'stalledDL',
            addedOn: _secondsAgo(const Duration(days: 3)),
            lastActivity: _secondsAgo(const Duration(minutes: 5)),
          ),
          now: _now,
        ),
        const InFlightReading.moving(),
      );
    });

    test('Transmission: a torrent stopped for weeks and started again waits '
        'from when it started, not from when it was added', () {
      final resumed = _torrent(
        isStalled: true,
        addedDate: _secondsAgo(const Duration(days: 26)),
        startDate: _secondsAgo(const Duration(minutes: 10)),
      );
      expect(
        transmissionInFlight(resumed, now: _now),
        const InFlightReading.moving(),
      );
      expect(
        idleSince(
          lastActivity: resumed.activityDate,
          added: resumed.addedDate,
          started: resumed.startDate,
        ),
        DateTime.fromMillisecondsSinceEpoch(resumed.startDate * 1000),
      );
    });

    test('Transmission: isStalled is a stall at 30 minutes by '
        'activityDate', () {
      expect(
        transmissionInFlight(
          _torrent(
            isStalled: true,
            activityDate: _secondsAgo(const Duration(minutes: 12)),
          ),
          now: _now,
        ),
        const InFlightReading.moving(),
      );
      expect(
        transmissionInFlight(
          _torrent(
            isStalled: true,
            activityDate: _secondsAgo(const Duration(hours: 3)),
          ),
          now: _now,
        ),
        const InFlightReading.fault(InFlightFault.stalled),
      );
    });

    test('idleSince reads the last activity, else the time added, else '
        'nothing', () {
      expect(
        idleSince(lastActivity: 1000, added: 10),
        DateTime.fromMillisecondsSinceEpoch(1000 * 1000),
      );
      expect(
        idleSince(lastActivity: 0, added: 10),
        DateTime.fromMillisecondsSinceEpoch(10 * 1000),
      );
      expect(idleSince(lastActivity: 0, added: 0), isNull);
    });
  });

  group('InFlightReading', () {
    test('queued is its own reading, equal to itself and to nothing else', () {
      expect(const InFlightReading.queued(), const InFlightReading.queued());
      expect(
        const InFlightReading.queued(),
        isNot(const InFlightReading.moving()),
      );
      expect(const InFlightReading.queued().fault, isNull);
      expect(const InFlightReading.queued().held, isFalse);
      expect(const InFlightReading.queued().queued, isTrue);
      expect(const InFlightReading.moving().queued, isFalse);
      expect(const InFlightReading.held().queued, isFalse);
      expect(
        const InFlightReading.fault(InFlightFault.stalled).queued,
        isFalse,
      );
      expect(const InFlightReading.queued().toString(), contains('queued'));
    });
  });

  group('stuckRemedyFor', () {
    test('somebody has the whole file: look for peers again', () {
      expect(stuckRemedyFor(swarmSeeds: 3), StuckRemedy.lookForPeers);
    });

    test('nobody has it, or the client cannot say: try another '
        'download', () {
      expect(stuckRemedyFor(swarmSeeds: 0), StuckRemedy.tryAnotherDownload);
      expect(stuckRemedyFor(swarmSeeds: null), StuckRemedy.tryAnotherDownload);
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
          reason: 'Duplicate\u00A0· Too large',
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

    test('a job waiting out propagation is a transfer waiting its turn; a '
        'wait label on a paused job is no fault', () {
      expect(
        sabnzbdSlotInFlight(
          slot(status: 'Propagating', labels: ['PROPAGATING 5 min']),
          stoppedByDisk: false,
        ),
        const InFlightReading.moving(),
      );
      expect(
        sabnzbdSlotInFlight(
          slot(status: 'Paused', labels: ['PROPAGATING 5 min']),
          stoppedByDisk: false,
        ),
        const InFlightReading.held(),
      );
    });

    test('a job somebody paused is held, even on a full disk', () {
      expect(
        sabnzbdSlotInFlight(slot(status: 'Paused'), stoppedByDisk: true),
        const InFlightReading.held(),
      );
    });

    test('a job waiting for its turn (Queued) is queued, not moving', () {
      expect(
        sabnzbdSlotInFlight(slot(status: 'Queued'), stoppedByDisk: false),
        const InFlightReading.queued(),
      );
      expect(
        sabnzbdSlotInFlight(slot(status: 'queued'), stoppedByDisk: false),
        const InFlightReading.queued(),
      );
      // Only what SABnzbd calls Queued: Downloading, Fetching and a
      // propagation wait stay what they were.
      for (final status in ['Downloading', 'Fetching', 'Propagating']) {
        expect(
          sabnzbdSlotInFlight(slot(status: status), stoppedByDisk: false),
          const InFlightReading.moving(),
          reason: status,
        );
      }
    });

    test('a start is the finish of the job ahead: a queue of three, one '
        'moving and two queued', () {
      // `timeleft` is cumulative: this one ends in 5 min, the next in 5 + 6,
      // the last in 5 + 6 + 9.
      expect(sabnzbdStartsInSeconds([300, 660, 1200]), [null, 300, 660]);
    });

    test('a start is dated by the nearest job ahead that has a figure', () {
      // SABnzbd prints 0:00:00 for a job it skips (paused, propagating): it
      // adds nothing to the running total, and is no figure.
      expect(sabnzbdStartsInSeconds([300, 0, 660]), [null, 300, 300]);
      expect(sabnzbdStartsInSeconds([0, 0, 660]), [null, null, null]);
      expect(sabnzbdStartsInSeconds([null, 300, 660]), [null, null, 300]);
      // No speed: every figure is 0:00:00, and nobody can say.
      expect(sabnzbdStartsInSeconds([0, 0, 0]), [null, null, null]);
      expect(sabnzbdStartsInSeconds(const []), isEmpty);
    });

    test('a queue somebody paused holds its jobs, and still stalls the ones '
        'SABnzbd held', () {
      expect(
        sabnzbdSlotInFlight(
          slot(status: 'Queued'),
          stoppedByDisk: false,
          pausedOnPurpose: true,
        ),
        const InFlightReading.held(),
      );
      expect(
        sabnzbdSlotInFlight(
          slot(status: 'Paused', labels: ['ENCRYPTED']),
          stoppedByDisk: false,
          pausedOnPurpose: true,
        ).fault,
        InFlightFault.stalled,
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
        const InFlightReading.held(),
      );
      expect(
        nzbgetGroupInFlight(group(status: 'UNPACKING'), stoppedByDisk: true),
        const InFlightReading.moving(),
      );
    });

    test('a QUEUED group is queued, not moving; anything else that fetches or '
        'unpacks still is', () {
      expect(
        nzbgetGroupInFlight(group(status: 'QUEUED'), stoppedByDisk: false),
        const InFlightReading.queued(),
      );
      for (final status in [
        'DOWNLOADING',
        'FETCHING',
        'UNPACKING',
        'PP_QUEUED',
      ]) {
        expect(
          nzbgetGroupInFlight(group(status: status), stoppedByDisk: false),
          const InFlightReading.moving(),
          reason: status,
        );
      }
    });

    test('a group somebody paused, or a queue paused on purpose, is held; '
        'post-processing goes on', () {
      expect(
        nzbgetGroupInFlight(group(status: 'PAUSED'), stoppedByDisk: false),
        const InFlightReading.held(),
      );
      expect(
        nzbgetGroupInFlight(
          group(status: 'QUEUED'),
          stoppedByDisk: false,
          pausedOnPurpose: true,
        ),
        const InFlightReading.held(),
      );
      expect(
        nzbgetGroupInFlight(
          group(status: 'UNPACKING'),
          stoppedByDisk: false,
          pausedOnPurpose: true,
        ),
        const InFlightReading.moving(),
      );
    });
  });
}
