/// The in-flight grammar, and the rule that a missing figure is not zero.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/services/domain/in_flight.dart';

void main() {
  group('done of total', () {
    test('renders both sides on the total\'s unit', () {
      expect(
        formatDoneOfTotal(
          doneBytes: 14 * 1024 * 1024 * 1024,
          totalBytes: 15 * 1024 * 1024 * 1024,
        ),
        '14.0 of 15.0 GB',
      );
    });

    test('a figure the source did not report is —, never 0', () {
      // The whole rule, twice: a count nobody was able to take is not zero, and
      // `0 B of …` would say the transfer has not started.
      expect(formatDoneOfTotal(doneBytes: null, totalBytes: 100), '—');
      expect(formatDoneOfTotal(doneBytes: 100, totalBytes: null), '—');
      expect(formatDoneOfTotal(doneBytes: null, totalBytes: null), '—');
      expect(formatDoneOfTotal(doneBytes: null, totalBytes: 100), isNot('0 B'));
    });

    test('nothing downloaded yet is 0, which is a reading', () {
      // The counterweight: zero *reported* is a fact, and must not be hidden.
      expect(
        formatDoneOfTotal(doneBytes: 0, totalBytes: 2 * 1024 * 1024 * 1024),
        '0.0 of 2.00 GB',
      );
    });
  });

  group('time left', () {
    test('never prints seconds above a minute, and never a bare number', () {
      expect(formatTimeLeft(48), '48 s left');
      expect(formatTimeLeft(180), '3 min left');
      expect(formatTimeLeft(7800), '2 h 10 min left');
      expect(formatTimeLeft(7200), '2 h left');
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
        '2160p · 14.0 of 15.0 GB · 3 min left · qBittorrent',
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
      expect(line, '— · — · SABnzbd');
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
        '2 downloading · 16 MB/s across 2 clients',
      );
    });

    test('says only the count when nobody reported a rate', () {
      expect(
        inFlightEyebrow(active: 3, rateBytesPerSecond: null, clients: 0),
        '3 downloading',
      );
    });
  });

  group('a fault leaves this region and says what it is', () {
    test('the footnote names each fault, blocked imports first', () {
      expect(inFlightFaultFootnote(), isNull);
      expect(
        inFlightFaultFootnote(stalled: 1),
        '1 stalled · under Needs a decision',
      );
      expect(
        inFlightFaultFootnote(stalled: 2, needsImport: 18),
        '18 need a manual import · 2 stalled · under Needs a decision',
      );
      expect(
        inFlightFaultFootnote(needsImport: 1, failed: 1),
        '1 needs a manual import · 1 failed · under Needs a decision',
      );
      // APP-04: eighteen blocked imports were footnoted "18 stalls", which
      // named the wrong fault and so the wrong remedy.
      expect(inFlightFaultFootnote(needsImport: 18), isNot(contains('stall')));
    });

    test('the queue is empty only when it holds nothing', () {
      expect(inFlightEmptyLabel(faults: 0), 'The queue is empty');
      // Eighteen records in the queue, none of them moving: not empty.
      expect(inFlightEmptyLabel(faults: 18), 'Nothing moving');
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
      inFlightRowValue(line: '2160p · 3 min left · qBittorrent', percent: 92),
      '92% done, 2160p, 3 min left, qBittorrent',
    );
  });
}
