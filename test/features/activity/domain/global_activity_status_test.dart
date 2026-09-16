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

    test('an unknown event type is humanised and stays neutral', () {
      final status = resolveHistoryStatus(const {
        'eventType': 'someFutureEvent',
      });

      expect(status.label, 'Some Future Event');
      expect(status.tone, StatusTone.neutral);
    });

    test('a missing event type does not throw', () {
      expect(resolveHistoryStatus(const {}).tone, StatusTone.neutral);
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

      // Matches the "Cutoff Unmet" sub-segment label; the old string was
      // 'Cutoff', which is not the term the *arr services use.
      final cutoff = resolveWantedStatus(const {}, isCutoff: true);
      expect(cutoff.label, 'Cutoff Unmet');
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

    // `pending` is the one row the tone rule does not settle, and it is amber
    // on purpose: not backlog (no server is working on it) and not a fault
    // (nothing is broken) — it is waiting on a *human*, which is the only thing
    // this screen can act on.
    test('a pending request warns and an approved one is in-flight', () {
      expect(
        resolveRequestStatus(requestWith(RequestStatus.pendingApproval)).tone,
        StatusTone.warning,
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
        'Cutoff Unmet',
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
