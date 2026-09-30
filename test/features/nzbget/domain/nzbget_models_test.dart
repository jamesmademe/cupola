import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/nzbget/domain/models/nzbget_models.dart';

void main() {
  group('NzbgetGroup', () {
    test('derives progress from the two sizes the server reported', () {
      final group = NzbgetGroup.fromJson({
        'NZBID': 7,
        'NZBName': 'Some.Job',
        'Status': 'DOWNLOADING',
        'FileSizeMB': 1000,
        'RemainingSizeMB': 440,
      });

      expect(group.remainingSizeMb, 440);
      expect(group.progress, closeTo(0.56, 1e-9));
      expect(group.percentage, 56);
    });

    test('recomposes the Hi/Lo halves when no MB field is present', () {
      final group = NzbgetGroup.fromJson({
        'NZBID': 7,
        'NZBName': 'Some.Job',
        'FileSizeHi': 0,
        'FileSizeLo': 1000 * 1024 * 1024,
        'RemainingSizeHi': 0,
        'RemainingSizeLo': 500 * 1024 * 1024,
      });

      expect(group.fileSizeMb, 1000);
      expect(group.remainingSizeMb, 500);
      expect(group.percentage, 50);
    });

    test('a job whose remaining size nobody reported has no progress', () {
      // The defect: with no `RemainingSizeMB` and no Hi/Lo pair, a 0 default
      // made `(file - 0) / file` == 1, so a job the server said nothing about
      // drew a full bar and read `100%` — a percentage nobody computed,
      // presented as finished.
      final group = NzbgetGroup.fromJson({
        'NZBID': 7,
        'NZBName': 'Some.Job',
        'Status': 'DOWNLOADING',
        'FileSizeMB': 4800,
      });

      expect(group.percentage, isNull);
      expect(group.progress, isNull);
      expect(group.remainingSizeMb, isNull);
      expect(group.remainingLabel, '—');
    });

    test('a zero remaining size the server did report is a finished job', () {
      final group = NzbgetGroup.fromJson({
        'NZBID': 7,
        'NZBName': 'Some.Job',
        'FileSizeMB': 4800,
        'RemainingSizeMB': 0,
      });

      expect(group.remainingSizeMb, 0);
      expect(group.percentage, 100);
    });

    test('a job whose size nobody reported has no progress either', () {
      final group = NzbgetGroup.fromJson({
        'NZBID': 7,
        'NZBName': 'Some.Job',
        'RemainingSizeMB': 400,
      });

      expect(group.fileSizeMb, isNull);
      expect(group.progress, isNull);
      expect(group.percentage, isNull);
    });
  });

  // An \*arr records the job's `drone` parameter as its `downloadId`, never the
  // NZBID, so a join on the NZBID never met the job an \*arr sent.
  group('NzbgetGroup.downloadId', () {
    test('is the drone parameter an arr tagged the job with', () {
      final group = NzbgetGroup.fromJson({
        'NZBID': 12,
        'NZBName': 'Sintel.2010.2160p',
        'Parameters': [
          {'Name': '*Unpack:', 'Value': 'yes'},
          {'Name': 'drone', 'Value': '0b1f0c7d4e5a4c1f9a3e2d6b8c7a9f01'},
        ],
      });

      expect(group.droneId, '0b1f0c7d4e5a4c1f9a3e2d6b8c7a9f01');
      expect(group.downloadId, '0b1f0c7d4e5a4c1f9a3e2d6b8c7a9f01');
      // Actions still address the job by its NZBID.
      expect(group.nzbId, 12);
    });

    test('falls back to the NZBID for a job no arr tagged', () {
      for (final parameters in [
        null,
        const <Object>[],
        [
          {'Name': 'drone', 'Value': ''},
        ],
      ]) {
        final group = NzbgetGroup.fromJson({
          'NZBID': 12,
          'NZBName': 'debian-12.iso',
          'Parameters': ?parameters,
        });

        expect(group.droneId, isNull);
        expect(group.downloadId, '12');
      }
    });
  });

  group('NzbgetStatus download rate', () {
    test('reads the 64-bit Lo/Hi pair NZBGet 24.2 replaced it with', () {
      final status = NzbgetStatus.fromJson({
        // Deprecated since 24.2, and a 32-bit field cannot hold 5 GiB/s.
        'DownloadRate': 2147483647,
        'DownloadRateLo': 1073741824,
        'DownloadRateHi': 1,
        'RemainingSizeMB': 0,
      });

      expect(status.downloadRateBytes, 5 * 1024 * 1024 * 1024);
    });

    test('still reads DownloadRate from a daemon older than 24.2', () {
      final status = NzbgetStatus.fromJson({
        'DownloadRate': 2097152,
        'RemainingSizeMB': 0,
      });

      expect(status.downloadRateBytes, 2097152);
    });
  });

  group('NZBGet RSS and messages', () {
    test('groups numbered feed settings, sorts them, and skips blank URLs', () {
      final feeds = nzbgetFeedsFromConfig(const [
        {'Name': 'Feed2.URL', 'Value': 'https://two.test/rss'},
        {'Name': 'Feed2.Name', 'Value': 'Two'},
        {'Name': 'Feed1.URL', 'Value': ''},
        {'Name': 'Feed2.PauseNzb', 'Value': 'yes'},
        {'Name': 'Feed2.Priority', 'Value': '50'},
        {'Name': 'ControlIP', 'Value': '0.0.0.0'},
      ]);

      expect(feeds, hasLength(1));
      expect(feeds.single.index, 2);
      expect(feeds.single.pauseNzb, isTrue);
      expect(feeds.single.priority, 50);
    });

    test('a message without time keeps the timestamp unavailable', () {
      final message = NzbgetMessage.fromJson(const {
        'ID': '7',
        'Kind': 'INFO',
        'Text': 'Queue loaded',
      });

      expect(message.id, 7);
      expect(message.time, isNull);
      expect(message.isFault, isFalse);
    });
  });
}
