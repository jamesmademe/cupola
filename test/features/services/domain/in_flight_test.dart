/// The in-flight grammar, and the rule that a missing figure is not zero.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/services/domain/in_flight.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

void main() {
  test('a count takes its noun in the singular for one, and only one', () {
    expect(countedNoun(0, 'peer', 'peers'), '0 peers');
    expect(countedNoun(1, 'peer', 'peers'), '1 peer');
    expect(countedNoun(12, 'seed', 'seeds'), '12 seeds');
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
}
