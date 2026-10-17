/// The in-flight grammar, and the rule that a missing figure is not zero.
library;

import 'package:flutter_test/flutter_test.dart';

import 'dart:io';

import 'package:cupola/features/services/domain/in_flight.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

const _silent = SocketException('Connection refused');

void main() {
  test('a count takes its noun in the singular for one, and only one', () {
    expect(countedNoun(0, 'peer', 'peers'), '0 peers');
    expect(countedNoun(1, 'peer', 'peers'), '1 peer');
    expect(countedNoun(12, 'seed', 'seeds'), '12 seeds');
  });

  group('done of total', () {
    test('renders both sides on the total\'s unit', () {
      expect(
        formatDoneOfTotal(
          doneBytes: 14 * 1024 * 1024 * 1024,
          totalBytes: 15 * 1024 * 1024 * 1024,
        ),
        '14.0 of 15.0\u00A0GB',
      );
    });

    test('a figure the source did not report is —, never 0', () {
      // The whole rule, twice: a count nobody was able to take is not zero, and
      // `0 B of …` would say the transfer has not started.
      expect(formatDoneOfTotal(doneBytes: null, totalBytes: 100), '—');
      expect(formatDoneOfTotal(doneBytes: 100, totalBytes: null), '—');
      expect(formatDoneOfTotal(doneBytes: null, totalBytes: null), '—');
      expect(
        formatDoneOfTotal(doneBytes: null, totalBytes: 100),
        isNot('0\u00A0B'),
      );
    });

    test(
      'under 100 both sides carry one decimal, so the pair reads as one',
      () {
        const gib = 1024 * 1024 * 1024;
        expect(
          formatDoneOfTotal(doneBytes: gib, totalBytes: 4 * gib),
          '1.0 of 4.0\u00A0GB',
        );
        expect(
          formatDoneOfTotal(
            doneBytes: 2 * gib,
            totalBytes: (9.4 * gib).round(),
          ),
          '2.0 of 9.4\u00A0GB',
        );
      },
    );

    test('from 100 up in the total\'s unit both sides read whole', () {
      const gib = 1024 * 1024 * 1024;
      expect(
        formatDoneOfTotal(doneBytes: 120 * gib, totalBytes: 152 * gib),
        '120 of 152\u00A0GB',
      );
      // Each half follows the shared rule on its own: the done figure still
      // has its tenth while it is under 100, and loses it at 100.
      expect(
        formatDoneOfTotal(
          doneBytes: (5.2 * gib).round(),
          totalBytes: 152 * gib,
        ),
        '5.2 of 152\u00A0GB',
      );
      expect(
        formatDoneOfTotal(
          doneBytes: (99.96 * gib).round(),
          totalBytes: 152 * gib,
        ),
        '100 of 152\u00A0GB',
      );
    });

    test('a done figure under one unit reads a tenth, not 0', () {
      const gib = 1024 * 1024 * 1024;
      expect(
        formatDoneOfTotal(doneBytes: (0.4 * gib).round(), totalBytes: 4 * gib),
        '0.4 of 4.0\u00A0GB',
      );
    });

    test('bytes stay whole', () {
      expect(
        formatDoneOfTotal(doneBytes: 300, totalBytes: 512),
        '300 of 512\u00A0B',
      );
    });

    test('nothing downloaded yet is 0, which is a reading', () {
      // The counterweight: zero *reported* is a fact, and must not be hidden.
      expect(
        formatDoneOfTotal(doneBytes: 0, totalBytes: 2 * 1024 * 1024 * 1024),
        '0.0 of 2.0\u00A0GB',
      );
    });
  });

  group('time left', () {
    test('never prints seconds above a minute, and never a bare number', () {
      expect(formatTimeLeft(48), '48\u00A0s left');
      expect(formatTimeLeft(180), '3\u00A0min left');
      expect(formatTimeLeft(7800), '2\u00A0h 10\u00A0min left');
      expect(formatTimeLeft(7200), '2\u00A0h left');
      // A day or more keeps its hours: `3 d left` was a day short of the truth.
      expect(formatTimeLeft(3 * 86400 + 4 * 3600), '3\u00A0d 4\u00A0h left');
      expect(formatTimeLeft(2 * 86400), '2\u00A0d left');
    });

    test('no estimate is —', () {
      expect(formatTimeLeft(null), '—');
      expect(formatTimeLeft(-1), '—');
    });
  });

  group('the row line', () {
    test('is quality, done of total, time left, client', () {
      expect(
        formatInFlightLine(
          quality: '2160p',
          doneBytes: 14 * 1024 * 1024 * 1024,
          totalBytes: 15 * 1024 * 1024 * 1024,
          etaSeconds: 180,
          client: 'qBittorrent',
        ),
        '2160p\u00A0· 14.0 of 15.0\u00A0GB\u00A0· 3\u00A0min left\u00A0· qBittorrent',
      );
    });

    test('drops the quality when the source has none, and keeps the rest', () {
      final line = formatInFlightLine(
        doneBytes: null,
        totalBytes: null,
        etaSeconds: null,
        client: 'SABnzbd',
      );

      // Three fields, two of them explicitly absent. A client that knows only
      // its own name still produces a readable row.
      expect(line, '—\u00A0· —\u00A0· SABnzbd');
    });
  });

  group('the eyebrow', () {
    test('sums the rate across clients and counts them', () {
      expect(
        inFlightEyebrow(
          active: 2,
          rateBytesPerSecond: 16 * 1024 * 1024,
          clients: 2,
        ),
        '2 downloading\u00A0· 16.0\u00A0MB/\u2060s across 2 clients',
      );
    });

    test('says only the count when nobody reported a rate', () {
      expect(
        inFlightEyebrow(active: 3, rateBytesPerSecond: null, clients: 0),
        '3 downloading',
      );
    });

    test('a queue nobody could read is —, never 0, and has no rate', () {
      expect(
        inFlightEyebrow(
          active: 0,
          rateBytesPerSecond: 1024,
          clients: 1,
          coverage: SourceCoverage.merge([
            SourceCoverage.failure(ServiceKey.radarr, _silent),
            SourceCoverage.failure(ServiceKey.sabnzbd, _silent),
          ]),
        ),
        '— downloading',
      );
    });

    test('a partial count stands, and is qualified underneath', () {
      // The line under it (`coverageNote`) is what says SABnzbd is missing;
      // the count itself is still a count of what answered.
      expect(
        inFlightEyebrow(
          active: 3,
          rateBytesPerSecond: null,
          clients: 0,
          coverage: SourceCoverage.merge([
            SourceCoverage.answeredBy(ServiceKey.radarr),
            SourceCoverage.failure(ServiceKey.sabnzbd, _silent),
          ]),
        ),
        '3 downloading',
      );
    });
  });

  group('a fault leaves Downloads and says what it is', () {
    test('the footnote names each fault, blocked imports first', () {
      expect(inFlightFaultFootnote(), isNull);
      expect(inFlightFaultFootnote(stalled: 1), '1 stuck\u00A0· in Needs you');
      expect(
        inFlightFaultFootnote(stalled: 2, needsImport: 18),
        '18 need a manual import\u00A0· 2 stuck\u00A0· in Needs you',
      );
      expect(
        inFlightFaultFootnote(needsImport: 1, failed: 1),
        '1 needs a manual import\u00A0· 1 failed\u00A0· in Needs you',
      );
      // APP-04: eighteen blocked imports were footnoted "18 stalls", which
      // named the wrong fault and so the wrong remedy.
      expect(inFlightFaultFootnote(needsImport: 18), isNot(contains('stall')));
    });

    test('a walk cut short makes every count a floor', () {
      // Sonarr's queue walk stopped on a full page with no total: the part it
      // did not read may hold more of any fault, and the figures counted
      // rows, not the queue.
      final cutShort = SourceCoverage.merge([
        SourceCoverage.answeredBy(ServiceKey.sonarr, cutShort: true),
        SourceCoverage.answeredBy(ServiceKey.qbittorrent),
      ]);
      final footnote = inFlightFaultFootnote(
        stalled: 2,
        needsImport: 18,
        failed: 1,
        coverage: cutShort,
      )!;
      expect(
        footnote,
        '18+ need a manual import\u00A0· 2+ stuck\u00A0· 1+ failed\u00A0· in Needs you',
      );
      expect(
        spokenFaultFootnote(footnote),
        'at least 18 need a manual import, at least 2 stuck, at least 1 '
        'failed, in Needs you',
      );

      // Read whole, the counts are the counts.
      final whole = inFlightFaultFootnote(
        stalled: 2,
        needsImport: 18,
        coverage: SourceCoverage.answeredBy(ServiceKey.sonarr),
      )!;
      expect(
        whole,
        '18 need a manual import\u00A0· 2 stuck\u00A0· in Needs you',
      );
      expect(
        spokenFaultFootnote(whole),
        '18 need a manual import, 2 stuck, in Needs you',
      );
    });

    test('the queue is empty only when it holds nothing', () {
      expect(inFlightEmptyLabel(faults: 0), 'The queue is empty');
      // Eighteen records in the queue, none of them moving: not empty.
      expect(inFlightEmptyLabel(faults: 18), 'Nothing moving');
      // SABnzbd's queue is not empty because SABnzbd did not answer.
      expect(inFlightEmptyLabel(faults: 0, whole: false), 'Nothing moving');
      // A paused queue is not an empty one.
      expect(inFlightEmptyLabel(faults: 0, held: 3), 'Nothing moving');
    });
  });

  group('arrQueueIsQueued', () {
    test('`queued` and `delay` are waiting their turn, however they are '
        'cased', () {
      for (final status in ['queued', 'delay', 'Queued', ' DELAY ']) {
        expect(arrQueueIsQueued({'status': status}), isTrue, reason: status);
      }
    });

    test('every other status, and none, is not', () {
      for (final status in [
        'downloading',
        'paused',
        'completed',
        'warning',
        'failed',
        'downloadClientUnavailable',
        '',
      ]) {
        expect(arrQueueIsQueued({'status': status}), isFalse, reason: status);
      }
      expect(arrQueueIsQueued(const {}), isFalse);
      expect(arrQueueIsQueued({'status': 3}), isFalse);
    });
  });

  group('arrQueueFault', () {
    test('a blocked import is an import fault, not a stall', () {
      expect(
        arrQueueFault(const {
          'status': 'completed',
          'trackedDownloadState': 'importBlocked',
          'trackedDownloadStatus': 'warning',
          'statusMessages': ['No files found are eligible for import'],
        }),
        InFlightFault.needsImport,
      );
    });

    test("an older fork's pending import with a warning is the same fault", () {
      // Sonarr v3, Lidarr and Readarr say "blocked" this way.
      expect(
        arrQueueFault(const {
          'status': 'completed',
          'trackedDownloadState': 'importPending',
          'trackedDownloadStatus': 'warning',
          'statusMessages': ['Unable to Import Automatically'],
        }),
        InFlightFault.needsImport,
      );
    });

    test('a pending import without a warning is still in flight', () {
      // It clears itself within seconds; it is not a decision.
      expect(
        arrQueueFault(const {
          'status': 'completed',
          'trackedDownloadState': 'importPending',
        }),
        isNull,
      );
    });

    test('a stall the arr reports in prose is a stall', () {
      expect(
        arrQueueFault(const {
          'status': 'warning',
          'trackedDownloadState': 'downloading',
          'errorMessage': 'The download is stalled with no connections',
        }),
        InFlightFault.stalled,
      );
    });

    test('a warning on a download that is still moving keeps it in flight', () {
      // APP-04: "any warning is a stall" is the rule this replaces.
      expect(
        arrQueueFault(const {
          'status': 'downloading',
          'trackedDownloadState': 'downloading',
          'trackedDownloadStatus': 'warning',
          'statusMessages': ['Found matching series via grab history'],
        }),
        isNull,
      );
    });

    test('a failed download, an error or a lost client is a failure', () {
      expect(arrQueueFault(const {'status': 'failed'}), InFlightFault.failed);
      expect(
        arrQueueFault(const {'status': 'downloadClientUnavailable'}),
        InFlightFault.failed,
      );
      expect(
        arrQueueFault(const {
          'status': 'downloading',
          'trackedDownloadState': 'downloading',
          'trackedDownloadStatus': 'error',
        }),
        InFlightFault.failed,
      );
    });

    test('a record the arr already imported is nothing', () {
      expect(arrQueueFault(const {'trackedDownloadState': 'imported'}), isNull);
    });
  });

  test('the spoken row re-separates the dots and leads with progress', () {
    expect(
      inFlightRowValue(
        line: '2160p\u00A0· 3\u00A0min left\u00A0· qBittorrent',
        percent: 92,
      ),
      '92 percent done, 2160p, 3\u00A0min left, qBittorrent',
    );
  });
}
