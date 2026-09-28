import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/activity/domain/global_activity_status.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';

void main() {
  group('resolveHistoryStatus', () {
    test('a failed download is a fault, not a success', () {
      // The regression this whole layer exists for: the tile switched on the
      // row's *kind*, so `history` was unconditionally the success green and a
      // `downloadFailed` event rendered the word "Failed" inside a green pill.
      //
      // Amber rather than red: the service answered and told us the grab
      // failed. Red is kept for a service that did not answer at all.
      final status = resolveHistoryStatus(const {
        'eventType': 'downloadFailed',
      });

      expect(status.label, 'Failed');
      expect(status.tone, StatusTone.warning);
    });

    test('an import is a success and a grab is unremarkable', () {
      expect(
        resolveHistoryStatus(const {'eventType': 'downloadImported'}).tone,
        StatusTone.success,
      );
      expect(
        resolveHistoryStatus(const {
          'eventType': 'downloadFolderImported',
        }).tone,
        StatusTone.success,
      );
      // A grab is the system doing its job, on a page that is mostly grabs:
      // toning it blue spent a colour on the baseline.
      expect(
        resolveHistoryStatus(const {'eventType': 'grabbed'}).tone,
        StatusTone.neutral,
      );
    });

    test('a deletion and a rename are both unremarkable', () {
      // A file somebody removed, or an upgrade replaced. Backlog, not damage.
      expect(
        resolveHistoryStatus(const {'eventType': 'movieFileDeleted'}).tone,
        StatusTone.neutral,
      );
      expect(
        resolveHistoryStatus(const {'eventType': 'episodeFileRenamed'}).tone,
        StatusTone.neutral,
      );
    });

    test("Readarr's own spellings are in the table, not in one screen", () {
      // Each \*arr names the event after the entity it writes a record for, and
      // Readarr writes one record per **book file**. Before these arms existed
      // every one of them fell through to `humanizeCamelCase` and neutral, so
      // the most common row on a book history — a completed import, the one
      // event on the page that is unambiguously good news — read as a grey
      // "Book File Imported", and `bookImportIncomplete`, the failure a book
      // library actually suffers, read as backlog rather than as a fault.
      final imported = resolveHistoryStatus(const {
        'eventType': 'bookFileImported',
      });
      expect(imported.label, 'Imported');
      expect(imported.tone, StatusTone.success);
      expect(imported.glyph, StatusGlyph.imported);

      // The same event on an older Readarr.
      expect(
        resolveHistoryStatus(const {'eventType': 'authorFolderImported'}).tone,
        StatusTone.success,
      );

      final incomplete = resolveHistoryStatus(const {
        'eventType': 'bookImportIncomplete',
      });
      expect(incomplete.label, 'Import incomplete');
      expect(incomplete.tone, StatusTone.warning);
      expect(incomplete.glyph, StatusGlyph.failed);
    });

    test("Readarr's bookkeeping events stay neutral", () {
      // A deletion, a rename and a metadata rewrite. Amber would claim a fault
      // nobody experienced.
      expect(
        resolveHistoryStatus(const {'eventType': 'bookFileDeleted'}).label,
        'Deleted',
      );
      expect(
        resolveHistoryStatus(const {'eventType': 'bookFileDeleted'}).tone,
        StatusTone.neutral,
      );
      expect(
        resolveHistoryStatus(const {'eventType': 'bookFileRenamed'}).label,
        'Renamed',
      );
      expect(
        resolveHistoryStatus(const {'eventType': 'bookFileRenamed'}).tone,
        StatusTone.neutral,
      );
      final retagged = resolveHistoryStatus(const {
        'eventType': 'bookFileRetagged',
      });
      expect(retagged.label, 'Retagged');
      expect(retagged.tone, StatusTone.neutral);
      // Maintenance has no picture; the glyphs are for events with a shape.
      expect(retagged.glyph, isNull);
    });

    test("Lidarr's own spellings are in the table, not in one screen", () {
      // The same gap Readarr's arms closed, one fork over. Lidarr writes one
      // record per **track file**, under names no other fork uses, so
      // `trackFileImported` — the most common row on a music history, and the
      // one event on the page that is unambiguously good news — fell through to
      // `humanizeCamelCase` and came out a neutral "Track File Imported", while
      // `albumImportIncomplete`, a genuine fault, drew as backlog grey.
      //
      // `lidarr_overview_provider.dart` had the three correct arms as a
      // per-screen override, so the Overview and the global feed disagreed
      // about the same record.
      final imported = resolveHistoryStatus(const {
        'eventType': 'trackFileImported',
      });
      expect(imported.label, 'Imported');
      expect(imported.tone, StatusTone.success);
      expect(imported.glyph, StatusGlyph.imported);

      final incomplete = resolveHistoryStatus(const {
        'eventType': 'albumImportIncomplete',
      });
      expect(incomplete.label, 'Import incomplete');
      expect(incomplete.tone, StatusTone.warning);
      expect(incomplete.glyph, StatusGlyph.failed);

      final retagged = resolveHistoryStatus(const {
        'eventType': 'trackFileRetagged',
      });
      expect(retagged.label, 'Retagged');
      expect(retagged.tone, StatusTone.neutral);
      // Maintenance has no picture, exactly as `bookFileRetagged` has none.
      expect(retagged.glyph, isNull);
    });

    test('an unknown event type is humanised and stays neutral', () {
      final status = resolveHistoryStatus(const {
        'eventType': 'someFutureEvent',
      });

      expect(status.label, 'Some future event');
      expect(status.tone, StatusTone.neutral);
    });

    test('a missing event type does not throw', () {
      expect(resolveHistoryStatus(const {}).tone, StatusTone.neutral);
    });

    test('a fault carries the service\'s own reason, and nothing else does', () {
      // The read the design names and that nothing in the app performed: \*arr
      // files a history record's messages under `data`, not at the top level
      // where the queue keeps them, so the queue's extractor could not be
      // reused and the failed row said "Failed" and stopped.
      final failed = resolveHistoryStatus(const {
        'eventType': 'importFailed',
        'data': {
          'statusMessages': [
            {
              'title': 'Import failed',
              'messages': ['No files found are eligible for import'],
            },
          ],
        },
      });
      expect(failed.detail, contains('No files found'));

      // A successful event with messages attached prints none of them: a
      // reason under a neutral label reads as a problem that is not there.
      final grabbed = resolveHistoryStatus(const {
        'eventType': 'grabbed',
        'data': {
          'statusMessages': [
            {'message': 'Release accepted'},
          ],
        },
      });
      expect(grabbed.detail, isNull);
    });
  });

  group('historyFilePath', () {
    test('prefers where the file landed over where it was dropped', () {
      // `importedPath` is the destination of a successful import;
      // `droppedPath` is where the client left the files when it failed, and is
      // therefore what a manual import has to be seeded from. A record can
      // carry both, and the destination is the one worth printing.
      expect(
        historyFilePath(const {
          'data': {
            'importedPath': '/mnt/tank/media/movies/Dune (2024).mkv',
            'droppedPath': '/downloads/complete/Dune.2024',
          },
        }),
        '/mnt/tank/media/movies/Dune (2024).mkv',
      );

      expect(
        historyFilePath(const {
          'data': {'droppedPath': '/downloads/complete/Dune.2024'},
        }),
        '/downloads/complete/Dune.2024',
      );

      expect(historyFilePath(const {}), isNull);
    });
  });

  group('resolveQueueDisplayStatus', () {
    test('a failed queue record resolves to the fault tone', () {
      // The other half of the same bug: the queue row was painted in the service
      // accent, so a stalled download was chromatically identical to a healthy
      // one and nothing on the row was red.
      final status = resolveQueueDisplayStatus(const {
        'status': 'failed',
        'title': 'Some.Release',
      });

      expect(status.tone, StatusTone.warning);
    });

    test('a downloading record carries progress and the info tone', () {
      final status = resolveQueueDisplayStatus(const {
        'status': 'downloading',
        'size': 100,
        'sizeleft': 25,
      });

      expect(status.pipeline, MediaPipeline.downloading);
      expect(status.progress, 0.75);
      expect(status.progressPercent, 75);
      expect(status.tone, StatusTone.info);
    });

    test('an already-imported record still gets a row', () {
      final status = resolveQueueDisplayStatus(const {
        'trackedDownloadState': 'imported',
      });

      expect(status.label, 'Imported');
    });

    test('an ignored record is labelled as such', () {
      final status = resolveQueueDisplayStatus(const {
        'trackedDownloadState': 'ignored',
      });

      expect(status.label, 'Ignored');
    });

    test('a warning escalates an otherwise calm tone', () {
      final status = resolveQueueDisplayStatus(const {
        'trackedDownloadState': 'imported',
        'trackedDownloadStatus': 'warning',
      });

      expect(status.hasWarning, isTrue);
      expect(status.tone, StatusTone.warning);
    });
  });

  group('resolveWantedStatus', () {
    test('every row in the bucket is untoned backlog', () {
      // Being missing is the *definition* of membership in this bucket, not
      // news about it. Colouring the rows at all — red once, then amber and
      // blue — made the page shout its own title back in colour and left
      // nothing for the one row that is genuinely stuck.
      final missing = resolveWantedStatus(const {}, isCutoff: false);
      expect(missing.label, 'Missing');
      expect(missing.tone, StatusTone.neutral);

      // Matches the "Cutoff unmet" sub-segment label; the old string was
      // 'Cutoff', which is not the term the *arr services use. Sentence case
      // since the lexicon pass: the pill, the badge and this label are one
      // string, and Title Case here was the odd one out.
      final cutoff = resolveWantedStatus(const {}, isCutoff: true);
      expect(cutoff.label, 'Cutoff unmet');
      expect(cutoff.tone, StatusTone.neutral);

      // The distinctions the tones used to carry are still on the row, in the
      // words.
      expect(missing.label, isNot(cutoff.label));
    });

    test('an unmonitored item is neutral in both buckets', () {
      for (final isCutoff in [true, false]) {
        final status = resolveWantedStatus(const {
          'monitored': false,
        }, isCutoff: isCutoff);

        expect(status.label, 'Unmonitored');
        expect(status.tone, StatusTone.neutral, reason: 'isCutoff: $isCutoff');
      }
    });
  });

  group('resolveBlocklistStatus', () {
    test('is untoned and carries the reason', () {
      // The one list on which every row went exactly right: the user rejected
      // this release and the blocklist obeyed.
      final status = resolveBlocklistStatus(const {
        'message': 'Release rejected by the indexer',
      });

      expect(status.label, 'Blocked');
      expect(status.tone, StatusTone.neutral);
      expect(status.detail, 'Release rejected by the indexer');
    });

    test('falls back to the first status message when there is no message', () {
      final status = resolveBlocklistStatus(const {
        'statusMessages': [
          {'title': 'Not an upgrade'},
        ],
      });

      expect(status.detail, isNotNull);
    });
  });

  group('resolveRequestStatus', () {
    SeerrRequest requestWith(RequestStatus status) => SeerrRequest(
      id: 1,
      status: status,
      createdAt: '2026-04-03T09:05:00Z',
      type: 'movie',
    );

    test('a declined request is a closed decision, not a fault', () {
      // Seerr answered; it just answered no. Nothing is broken and nothing is
      // waiting — the word carries the whole fact.
      final status = resolveRequestStatus(requestWith(RequestStatus.declined));

      expect(status.tone, StatusTone.neutral);
      expect(status.label, 'Declined');
    });

    // A request awaiting approval is in line, not broken: blue, like an
    // approved one. Amber is the fault arm, and a pending request is the normal
    // resting state of a request list.
    test('a pending request is queued, like an approved one', () {
      expect(
        resolveRequestStatus(requestWith(RequestStatus.pendingApproval)).tone,
        StatusTone.info,
      );
      expect(
        resolveRequestStatus(requestWith(RequestStatus.approved)).tone,
        StatusTone.info,
      );
    });

    test("preserves Seerr's own wording as the label", () {
      final status = resolveRequestStatus(
        requestWith(RequestStatus.pendingApproval),
      );

      expect(status.label, 'Pending');
    });
  });

  group('resolveActivityStatus', () {
    test('dispatches each kind to its resolver', () {
      expect(
        resolveActivityStatus(GlobalActivityKind.history, const {
          'eventType': 'downloadFailed',
        }).tone,
        StatusTone.warning,
      );
      expect(
        resolveActivityStatus(GlobalActivityKind.blocklist, const {}).tone,
        StatusTone.neutral,
      );
      expect(
        resolveActivityStatus(GlobalActivityKind.missing, const {}).label,
        'Missing',
      );
      expect(
        resolveActivityStatus(GlobalActivityKind.cutoff, const {}).label,
        'Cutoff unmet',
      );
    });
  });

  group('MediaStatusInfo.toneOverride', () {
    test('overrides the derived tone', () {
      const status = MediaStatusInfo(
        availability: MediaAvailability.available,
        toneOverride: StatusTone.error,
      );

      // Availability alone would resolve to success.
      expect(status.tone, StatusTone.error);
    });

    test('a warning escalates over an override, but never over an error', () {
      const warned = MediaStatusInfo(
        toneOverride: StatusTone.neutral,
        hasWarning: true,
      );
      expect(warned.tone, StatusTone.warning);

      const errored = MediaStatusInfo(
        toneOverride: StatusTone.error,
        hasWarning: true,
      );
      expect(errored.tone, StatusTone.error);
    });

    test('participates in equality and copyWith', () {
      const base = MediaStatusInfo(toneOverride: StatusTone.info);

      expect(base, const MediaStatusInfo(toneOverride: StatusTone.info));
      expect(base == const MediaStatusInfo(), isFalse);
      expect(
        base.copyWith(toneOverride: StatusTone.error).tone,
        StatusTone.error,
      );
    });
  });
}
