import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/features/home/domain/downloads.dart';
import 'package:cupola/features/services/domain/in_flight.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The words of the Home's Downloads module.
void main() {
  group('the rows', () {
    test('the stuck ones are kept first, and drawn after what moves', () {
      expect(downloadRowsOf([1, 2, 3, 4, 5], ['a']), [1, 2, 3, 'a']);
      expect(downloadRowsOf([1, 2], ['a', 'b']), [1, 2, 'a', 'b']);
      expect(downloadRowsOf([1], ['a', 'b', 'c', 'd', 'e']), [
        'a',
        'b',
        'c',
        'd',
      ]);
      expect(downloadRowsOf(<Object>[], <Object>[]), isEmpty);
    });

    test('a download fault is a stall or a failure, never a blocked '
        'import', () {
      expect(isDownloadFault(InFlightFault.stalled), isTrue);
      expect(isDownloadFault(InFlightFault.failed), isTrue);
      expect(isDownloadFault(InFlightFault.needsImport), isFalse);
      expect(isDownloadFault(null), isFalse);
    });
  });

  group('the line under the name', () {
    test('what moves, what is stuck, and the clients\' speed', () {
      expect(
        downloadsSubtitle(
          moving: 3,
          stuck: 1,
          queued: 0,
          clientSetUp: true,
          rateBytesPerSecond: 40400000,
        ),
        matches(RegExp('^3 moving · 1 stuck · \\d+(\\.\\d)?\\u00A0MB/s\$')),
      );
      expect(
        downloadsSubtitle(moving: 0, stuck: 2, queued: 0, clientSetUp: true),
        '2 stuck',
      );
    });

    test('a client that did not answer makes the speed a dash; no client, '
        'no speed', () {
      expect(
        downloadsSubtitle(
          moving: 4,
          stuck: 0,
          queued: 0,
          clientSetUp: true,
          clientSilent: true,
          rateBytesPerSecond: 1000,
        ),
        '4 moving · —',
      );
      expect(
        downloadsSubtitle(
          moving: 3,
          stuck: 1,
          queued: 0,
          clientSetUp: false,
          rateBytesPerSecond: 1000,
        ),
        '3 moving · 1 stuck',
      );
    });

    test('nothing moving says so', () {
      expect(
        downloadsSubtitle(moving: 0, stuck: 0, queued: 0, clientSetUp: true),
        'Nothing moving',
      );
    });

    test('what waits its turn is said after what is stuck', () {
      expect(
        downloadsSubtitle(
          moving: 3,
          stuck: 1,
          queued: 1,
          clientSetUp: true,
          rateBytesPerSecond: 40400000,
        ),
        matches(
          RegExp('^3 moving · 1 stuck · 1 queued · \\d+(\\.\\d)?\\u00A0MB/s\$'),
        ),
      );
      expect(
        downloadsSubtitle(moving: 3, stuck: 0, queued: 2, clientSetUp: false),
        '3 moving · 2 queued',
      );
    });

    test('with nothing moving or stuck, queued stands alone, and the speed '
        'follows it', () {
      expect(
        downloadsSubtitle(moving: 0, stuck: 0, queued: 1, clientSetUp: true),
        '1 queued',
      );
      expect(
        downloadsSubtitle(
          moving: 0,
          stuck: 0,
          queued: 1,
          clientSetUp: true,
          rateBytesPerSecond: 2000000,
        ),
        matches(RegExp('^1 queued · \\d+(\\.\\d)?\\u00A0MB/s\$')),
      );
      expect(
        downloadsSubtitle(moving: 0, stuck: 2, queued: 1, clientSetUp: true),
        '2 stuck · 1 queued',
      );
    });

    test('a queued count over a walk cut short is a floor, and is said '
        'so', () {
      final coverage = SourceCoverage.answeredBy(
        ServiceKey.sonarr,
        cutShort: true,
      );
      final line = downloadsSubtitle(
        moving: 2,
        stuck: 0,
        queued: 5,
        clientSetUp: false,
        coverage: coverage,
      );
      expect(line, '2+ moving · 5+ queued');
      expect(
        spokenDownloadsSubtitle(line),
        'at least 2 moving, at least 5 queued',
      );
    });

    test('over a walk cut short the counts are floors', () {
      final coverage = SourceCoverage.answeredBy(
        ServiceKey.sonarr,
        cutShort: true,
      );
      expect(
        downloadsSubtitle(
          moving: 200,
          stuck: 3,
          queued: 0,
          clientSetUp: false,
          coverage: coverage,
        ),
        '200+ moving · 3+ stuck',
      );
    });

    test('a screen reader hears the dash as an unknown speed, and a floor '
        'as at least', () {
      expect(
        spokenDownloadsSubtitle('4 moving · —'),
        '4 moving, speed unknown',
      );
      expect(
        spokenDownloadsSubtitle('200+ moving · 3+ stuck'),
        'at least 200 moving, at least 3 stuck',
      );
      expect(
        spokenDownloadsSubtitle(
          '3 moving · 1 stuck · 1 queued · 40.4\u00A0MB/s',
        ),
        '3 moving, 1 stuck, 1 queued, 40.4\u00A0MB/s',
      );
      expect(spokenDownloadsSubtitle('1 queued'), '1 queued');
    });
  });

  group('a row', () {
    test('a moving one says how far and how long, either alone', () {
      expect(movingValue(percent: 88, etaSeconds: 60), '88% · 1\u00A0min');
      expect(movingValue(percent: 88), '88%');
      expect(movingValue(etaSeconds: 660), '11\u00A0min');
      // SABnzbd, live: `0:00:00` of a job nothing reaches is no estimate.
      expect(movingValue(percent: 0, etaSeconds: 0), '0%');
      expect(movingValue(), '');
      expect(
        spokenMovingValue(percent: 88, etaSeconds: 60),
        '88 percent done, 1\u00A0min left',
      );
    });

    test('a stuck one says where it stopped; a failed one says so', () {
      expect(stuckValue(InFlightFault.stalled, percent: 47), 'Stuck at 47%');
      expect(stuckValue(InFlightFault.stalled), 'Stuck');
      expect(stuckValue(InFlightFault.failed, percent: 47), 'Failed');
    });
  });

  group('the calm line', () {
    final now = DateTime(2026, 10, 8, 21, 30);

    test('the last download finished today, yesterday, this week', () {
      expect(
        lastFinishedLine(DateTime(2026, 10, 8, 18, 52), now: now),
        'The last download finished at 18:52.',
      );
      expect(
        lastFinishedLine(DateTime(2026, 10, 7, 23, 5), now: now),
        'The last download finished yesterday at 23:05.',
      );
      expect(
        lastFinishedLine(DateTime(2026, 10, 4, 9), now: now),
        'The last download finished on Sunday.',
      );
    });

    test('past a week, or with nothing known, nothing is said', () {
      expect(lastFinishedLine(DateTime(2026, 9, 30), now: now), isNull);
      expect(lastFinishedLine(null, now: now), isNull);
    });
  });

  test('a silent queue reads a dash, not zero', () {
    final coverage = SourceCoverage.failure(
      ServiceKey.radarr,
      const ClassifiedFailure(ServiceFailureReason.unreachable),
    );
    expect(coveredFigure(3, coverage), '—');
  });
}
