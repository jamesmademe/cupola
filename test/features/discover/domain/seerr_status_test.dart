import 'package:flutter_test/flutter_test.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/discover/domain/models/discover_detail_model.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/domain/seerr_status.dart';

void main() {
  group('seerrMediaStatus', () {
    test('no media record at all is an invitation to request', () {
      final status = seerrMediaStatus(null);

      expect(status.label, 'Available to request');
      expect(status.availability, MediaAvailability.notTracked);
      expect(status.tone, StatusTone.primary);
    });

    // The codes both numberings share.
    final codeLabels = <int, String>{
      1: 'Unknown',
      2: 'Waiting for approval',
      3: 'Processing',
      4: 'Partially available',
      5: 'Available',
    };

    for (final numbering in [...SeerrNumbering.values, null]) {
      codeLabels.forEach((code, label) {
        test(
          'status $code reads "$label" (${numbering?.name ?? 'unread'})',
          () {
            expect(
              seerrMediaStatus({'status': code}, numbering: numbering).label,
              label,
            );
          },
        );
      });
    }

    test('an unknown status code degrades to Unknown', () {
      expect(
        seerrMediaStatus({
          'status': 999,
        }, numbering: SeerrNumbering.seerr).label,
        'Unknown',
      );
    });

    group('the codes the numberings part on', () {
      test('Seerr: 6 is Blocklisted, neutral, under the block glyph', () {
        final status = seerrMediaStatus({
          'status': 6,
        }, numbering: SeerrNumbering.seerr);
        expect(status.label, 'Blocklisted');
        // An operator's choice, not a fault: never amber.
        expect(status.tone, StatusTone.neutral);
        expect(status.glyph, StatusGlyph.blocked);
        expect(status.pipeline, isNull);
      });

      test('Seerr: 7 is Deleted, what "Remove from Radarr" leaves', () {
        final status = seerrMediaStatus({
          'status': 7,
        }, numbering: SeerrNumbering.seerr);
        expect(status.label, 'Deleted');
        expect(status.availability, MediaAvailability.deleted);
        expect(status.tone, StatusTone.neutral);
      });

      test('Overseerr: 6 is Deleted', () {
        final status = seerrMediaStatus({
          'status': 6,
        }, numbering: SeerrNumbering.overseerr);
        expect(status.label, 'Deleted');
        expect(status.availability, MediaAvailability.deleted);
      });

      test('before the server has said: 6 is neither guess, 7 is Deleted', () {
        expect(seerrMediaStatus({'status': 6}).label, 'Unknown');
        expect(seerrMediaStatus({'status': 7}).label, 'Deleted');
      });

      test('a season reads its code in the same numbering', () {
        final statuses = seerrSeasonStatuses(
          {
            'status': 4,
            'seasons': [
              {'seasonNumber': 1, 'status': 7},
              {'seasonNumber': 2, 'status': 6},
            ],
          },
          const [],
          numbering: SeerrNumbering.seerr,
        );
        expect(statuses[1]!.label, 'Deleted');
        expect(statuses[2]!.label, 'Blocklisted');
      });
    });

    test('downloadStatus turns a static Processing into a live download', () {
      // The field Seerr has always exposed and the app never read.
      final status = seerrMediaStatus({
        'status': 3,
        'downloadStatus': [
          {
            'status': 'downloading',
            'trackedDownloadState': 'downloading',
            'size': 1000,
            'sizeLeft': 250,
          },
        ],
      });

      expect(status.label, 'Downloading');
      expect(status.progress, 0.75);
      expect(status.tone, StatusTone.info);
    });

    test('several downloads are averaged into one headline', () {
      final status = seerrMediaStatus({
        'status': 3,
        'downloadStatus': [
          {'status': 'downloading', 'size': 100, 'sizeLeft': 80},
          {'status': 'downloading', 'size': 100, 'sizeLeft': 20},
        ],
      });

      expect(status.label, 'Downloading');
      expect(status.progress, closeTo(0.5, 1e-9));
    });

    test('a warning from the connected *arr propagates', () {
      final status = seerrMediaStatus({
        'status': 3,
        'downloadStatus': [
          {'status': 'downloading', 'trackedDownloadStatus': 'warning'},
        ],
      });

      expect(status.hasWarning, isTrue);
      expect(status.tone, StatusTone.warning);
    });

    test('an empty downloadStatus array falls back to the status code', () {
      expect(
        seerrMediaStatus({'status': 3, 'downloadStatus': const []}).label,
        'Processing',
      );
    });

    test('a malformed downloadStatus payload is ignored', () {
      expect(
        seerrMediaStatus({'status': 3, 'downloadStatus': 'nonsense'}).label,
        'Processing',
      );
    });

    test('the 4k axis reads its own fields', () {
      final payload = {
        'status': 5,
        'status4k': 3,
        'downloadStatus': const [],
        'downloadStatus4k': [
          {'status': 'downloading', 'size': 100, 'sizeLeft': 10},
        ],
      };

      expect(seerrMediaStatus(payload).label, 'Available');
      expect(seerrMediaStatus(payload, is4k: true).label, 'Downloading');
      expect(
        seerrMediaStatus(payload, is4k: true).progress,
        closeTo(0.9, 1e-9),
      );
    });

    test('an available title stays available even mid-upgrade', () {
      final status = seerrMediaStatus({'status': 5});

      expect(status.availability, MediaAvailability.available);
      expect(status.tone, StatusTone.success);
    });
  });

  group('seerr4kMediaStatus', () {
    test('no 4K record reads nothing, not a second Unknown', () {
      expect(seerr4kMediaStatus(null), isNull);
      expect(seerr4kMediaStatus({'status': 5}), isNull);
      // UNKNOWN is Seerr's default for every title: a 4K copy nobody asked
      // for.
      expect(seerr4kMediaStatus({'status': 5, 'status4k': 1}), isNull);
    });

    test('a title on disk in HD and waiting in 4K reads both', () {
      final media = {'status': 5, 'status4k': 2};

      expect(seerrMediaStatus(media).label, 'Available');
      final uhd = seerr4kMediaStatus(media)!;
      expect(uhd.label, '4K: Waiting for approval');
      // The same tone the HD copy would take in that state.
      expect(uhd.tone, seerrMediaStatus({'status': 2}).tone);
    });

    test('a 4K download moving reads it, with its progress', () {
      final uhd = seerr4kMediaStatus({
        'status': 5,
        'status4k': 3,
        'downloadStatus4k': [
          {'status': 'downloading', 'size': 100, 'sizeLeft': 25},
        ],
      })!;

      expect(uhd.label, '4K: Downloading');
      expect(uhd.progress, closeTo(0.75, 1e-9));
    });

    test('the 4K code is read in the numbering of the server', () {
      expect(
        seerr4kMediaStatus({
          'status': 5,
          'status4k': 6,
        }, numbering: SeerrNumbering.seerr)!.label,
        '4K: Blocklisted',
      );
      expect(
        seerr4kMediaStatus({
          'status': 5,
          'status4k': 6,
        }, numbering: SeerrNumbering.overseerr)!.label,
        '4K: Deleted',
      );
    });
  });

  group('seerrDownloadEntry', () {
    test('returns null for anything that is not a populated list', () {
      expect(seerrDownloadEntry(null), isNull);
      expect(seerrDownloadEntry(const []), isNull);
      expect(seerrDownloadEntry('nonsense'), isNull);
      expect(seerrDownloadEntry(const ['not a map']), isNull);
    });
  });

  group('seerrSeasonStatuses', () {
    const seasons = [
      TvSeason(id: 1, seasonNumber: 1, name: 'Season 1', episodeCount: 10),
      TvSeason(id: 2, seasonNumber: 2, name: 'Season 2', episodeCount: 10),
      TvSeason(id: 0, seasonNumber: 0, name: 'Specials', episodeCount: 2),
    ];

    test('maps Seerr codes onto the shared status vocabulary', () {
      final statuses = seerrSeasonStatuses(const {
        'seasons': [
          {'seasonNumber': 1, 'status': 5},
          {'seasonNumber': 2, 'status': 4},
        ],
      }, seasons);

      expect(statuses[1]!.availability, MediaAvailability.available);
      expect(statuses[1]!.label, 'Available');
      expect(statuses[2]!.availability, MediaAvailability.partial);
      // Seerr's own wording survives, the same way the page-level status keeps
      // it.
      expect(statuses[2]!.label, 'Partially available');
    });

    test('a season Seerr has no record of is notTracked, not unknown', () {
      final statuses = seerrSeasonStatuses(const {
        'seasons': [
          {'seasonNumber': 1, 'status': 5},
        ],
      }, seasons);

      expect(statuses[0]!.availability, MediaAvailability.notTracked);
      expect(statuses[0]!.label, 'Not requested');
      expect(statuses[2]!.availability, MediaAvailability.notTracked);
    });

    test('resolves a status for every season even with no mediaInfo', () {
      final statuses = seerrSeasonStatuses(null, seasons);

      expect(statuses.keys.toSet(), {0, 1, 2});
      for (final status in statuses.values) {
        expect(status.availability, MediaAvailability.notTracked);
      }
    });

    test('survives a malformed seasons payload', () {
      final statuses = seerrSeasonStatuses(const {
        'seasons': [
          'nonsense',
          42,
          {'status': 5},
        ],
      }, seasons);

      expect(statuses.length, 3);
      expect(statuses[1]!.availability, MediaAvailability.notTracked);
    });

    test('ignores a seasons key that is not a list', () {
      expect(seerrSeasonStatuses(const {'seasons': 'nope'}, seasons).length, 3);
    });
  });
}
