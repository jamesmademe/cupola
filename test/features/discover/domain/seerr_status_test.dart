import 'package:flutter_test/flutter_test.dart';
import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/domain/seerr_status.dart';

void main() {
  group('seerrMediaStatus', () {
    test('no media record at all is an invitation to request', () {
      final status = seerrMediaStatus(null);

      expect(status.label, 'Available to request');
      expect(status.availability, MediaAvailability.notTracked);
      // The resting state: one of the five arms, never the ink.
      expect(status.tone, StatusTone.neutral);
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

  group('seerrTitleStatuses', () {
    List<String> labels(Map<String, dynamic>? media) =>
        seerrTitleStatuses(media).map((status) => status.label).toList();

    test('a title only in 4K draws no standard badge', () {
      // Seerr's 1 is no record of that copy: it drew "Unknown" beside the
      // 4K state.
      expect(labels({'status': 1, 'status4k': 2}), [
        '4K: Waiting for approval',
      ]);
      expect(labels({'status4k': 5}), ['4K: Available']);
    });

    test('a standard download moving keeps its badge', () {
      expect(
        labels({
          'status': 1,
          'status4k': 5,
          'downloadStatus': [
            {'status': 'downloading', 'size': 100, 'sizeLeft': 50},
          ],
        }),
        ['Downloading', '4K: Available'],
      );
    });

    test('both copies with a record: both badges', () {
      expect(labels({'status': 5, 'status4k': 3}), [
        'Available',
        '4K: Processing',
      ]);
    });

    test('no record of either copy reads as it always did', () {
      expect(labels({'status': 1, 'status4k': 1}), ['Unknown']);
      expect(labels(null), ['Available to request']);
      expect(labels({'status': 5}), ['Available']);
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

  // The requester's words (brand book, *The requester*): what will happen to
  // a request, never how, never a fault, never Seerr's own words.
  group('the requester reads', () {
    MediaStatusInfo read(Map<String, dynamic>? media, {bool is4k = false}) =>
        seerrMediaStatus(
          media,
          is4k: is4k,
          numbering: SeerrNumbering.seerr,
          audience: Audience.requester,
        );

    List<Object?> download(Map<String, dynamic> record) => [record];

    test('the states with no download', () {
      expect(read(null).label, 'Available to request');
      expect(read({'status': 2}).label, 'Waiting for approval');
      expect(read({'status': 3}).label, 'On its way');
      expect(read({'status': 4}).label, 'Partly on the server');
      expect(read({'status': 5}).label, 'On the server');
      expect(read({'status': 5}).tone, StatusTone.success);
    });

    test('a title the operator barred reads Blocked, neutral', () {
      final status = read({'status': 6});
      expect(status.label, 'Blocked');
      expect(status.tone, StatusTone.neutral);
      expect(status.glyph, StatusGlyph.blocked);
    });

    test('removed or with no state, it can be asked for again', () {
      for (final code in [1, 7, 999]) {
        final status = read({'status': code});
        expect(status.label, 'Available to request', reason: '$code');
        expect(status.availability, MediaAvailability.notTracked);
      }
    });

    test('a download moving reads Downloading, with its ring', () {
      final status = read({
        'status': 3,
        'downloadStatus': download({
          'status': 'downloading',
          'size': 100,
          'sizeLeft': 38,
        }),
      });
      expect(status.label, 'Downloading');
      expect(status.progressPercent, 62);
      expect(status.tone, StatusTone.info);
    });

    test('downloaded and being put in place: Finishing on the server', () {
      for (final state in ['importPending', 'importing']) {
        final status = read({
          'status': 3,
          'downloadStatus': download({
            'status': 'completed',
            'trackedDownloadState': state,
          }),
        });
        expect(status.label, 'Finishing on the server', reason: state);
        expect(status.tone, StatusTone.info);
      }
    });

    test('a fault is never theirs: On its way, blue, no figure', () {
      final faults = <String, Map<String, dynamic>>{
        'stalled': {
          'status': 'downloading',
          'trackedDownloadState': 'downloading',
          'size': 100,
          'sizeLeft': 57,
          'errorMessage': 'The download is stalled with no connections',
        },
        'failed': {'status': 'failed', 'trackedDownloadState': 'failed'},
        'import blocked': {
          'status': 'completed',
          'trackedDownloadState': 'importBlocked',
        },
        'client unavailable': {'status': 'downloadClientUnavailable'},
        'paused': {'status': 'paused'},
        'warning': {
          'status': 'warning',
          'trackedDownloadStatus': 'warning',
          'size': 100,
          'sizeLeft': 50,
        },
      };
      faults.forEach((name, record) {
        final media = {'status': 3, 'downloadStatus': download(record)};
        // The operator reads the download's own state: the record parsed.
        expect(
          seerrMediaStatus(media, numbering: SeerrNumbering.seerr).label,
          isNot(anyOf('Processing', 'On its way')),
          reason: name,
        );
        final status = read(media);
        expect(status.label, 'On its way', reason: name);
        expect(status.tone, StatusTone.info, reason: name);
        expect(status.hasWarning, isFalse, reason: name);
        expect(status.detail, isNull, reason: name);
        expect(status.progressPercent, isNull, reason: name);
      });
    });

    test('the title page: no copy Seerr removed, 4K in their words', () {
      List<String> labels(Map<String, dynamic>? media) => seerrTitleStatuses(
        media,
        numbering: SeerrNumbering.seerr,
        audience: Audience.requester,
      ).map((status) => status.label).toList();

      expect(labels({'status': 5, 'status4k': 3}), [
        'On the server',
        '4K: On its way',
      ]);
      expect(labels({'status': 7, 'status4k': 5}), ['4K: On the server']);
      expect(labels({'status': 5, 'status4k': 7}), ['On the server']);
      expect(labels({'status': 1, 'status4k': 1}), ['Available to request']);
    });
  });

  // A poster in the catalogue says what Seerr holds, and nothing when Seerr
  // holds nothing: most of a catalogue is titles nobody has asked for.
  group('seerrCatalogStatus', () {
    test('a title Seerr holds no record of says nothing', () {
      expect(seerrCatalogStatus(null), isNull);
      expect(seerrCatalogStatus(const {}), isNull);
    });

    test("Seerr's own Unknown states no fact, and says nothing", () {
      expect(seerrCatalogStatus(const {'status': 1}), isNull);
    });

    test('a title on the server says so, in each reader\'s words', () {
      final operator = seerrCatalogStatus(const {'status': 5})!;
      expect(operator.availability, MediaAvailability.available);
      expect(operator.label, 'Available');

      final requester = seerrCatalogStatus(const {
        'status': 5,
      }, audience: Audience.requester)!;
      expect(requester.label, 'On the server');
    });

    test('a title waiting for approval says so', () {
      expect(
        seerrCatalogStatus(const {'status': 2})!.label,
        'Waiting for approval',
      );
    });

    test('a removed title is one the requester can ask for again, and says '
        'nothing to her', () {
      expect(
        seerrCatalogStatus(const {'status': 7}, audience: Audience.requester),
        isNull,
      );
    });

    test('a title held only in 4K reads the 4K copy', () {
      expect(
        seerrCatalogStatus(const {'status': 1, 'status4k': 5})!.label,
        '4K: Available',
      );
    });
  });
}
