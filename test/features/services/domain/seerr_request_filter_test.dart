import 'package:flutter_test/flutter_test.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/services/domain/request_ordering.dart';
import 'package:cupola/features/services/domain/seerr_request_filter.dart';

/// [mediaStatus] defaults to `unknown`, which is what makes `displayStatus` fall
/// through to the request's own [status] instead of overriding it.
SeerrRequest _request({
  required int id,
  RequestStatus status = RequestStatus.approved,
  SeerrMediaAvailability mediaStatus = SeerrMediaAvailability.unknown,
}) {
  return SeerrRequest(
    id: id,
    status: status,
    media: RequestMedia(title: 'Title $id', status: mediaStatus),
    createdAt: '2026-05-01T10:00:00Z',
    type: 'movie',
  );
}

void main() {
  group('chip labels', () {
    test('reads All, Waiting for approval, Approved, Declined in order', () {
      expect(SeerrRequestFilter.values.map((f) => f.label), [
        'All',
        'Waiting for approval',
        'Approved',
        'Declined',
      ]);
    });
  });

  group('approved means "got past approval"', () {
    // This is the whole reason the enum exists. `displayStatus` lets media
    // availability override the request's own status, so an approved request
    // that is downloading reports `processing` and a finished one reports
    // `available` — neither reports `approved`. Matching the label literally
    // would leave this bucket almost always empty.
    test('includes requests whose media has moved past approval', () {
      final downloading = _request(
        id: 1,
        mediaStatus: SeerrMediaAvailability.processing,
      );
      final finished = _request(
        id: 2,
        mediaStatus: SeerrMediaAvailability.available,
      );
      final partly = _request(
        id: 3,
        mediaStatus: SeerrMediaAvailability.partiallyAvailable,
      );

      expect(
        downloading.displayStatus.kind,
        SeerrRequestDisplayKind.processing,
      );
      expect(finished.displayStatus.kind, SeerrRequestDisplayKind.available);

      final visible = SeerrRequestFilter.approved.apply([
        downloading,
        finished,
        partly,
      ]);
      expect(visible.map((r) => r.id), [1, 2, 3]);
    });

    test('excludes a request still awaiting approval', () {
      final pending = _request(id: 1, status: RequestStatus.pendingApproval);

      expect(SeerrRequestFilter.approved.apply([pending]), isEmpty);
      expect(SeerrRequestFilter.pending.apply([pending]).map((r) => r.id), [1]);
    });
  });

  group('pending reads the request, never its media', () {
    // The trap: `displayStatus` lets the media's availability stand in for
    // the request's own status. A request still waiting for approval, for a
    // series some of which is already on disk, reads "Partially available".
    test('a waiting request whose media is partially available is pending', () {
      final waiting = _request(
        id: 1,
        status: RequestStatus.pendingApproval,
        mediaStatus: SeerrMediaAvailability.partiallyAvailable,
      );

      expect(
        waiting.displayStatus.kind,
        SeerrRequestDisplayKind.partiallyAvailable,
      );
      // It fell out of Pending, into Approved.
      expect(SeerrRequestFilter.pending.apply([waiting]).map((r) => r.id), [1]);
      expect(SeerrRequestFilter.approved.apply([waiting]), isEmpty);
    });

    test('a waiting request whose media is available is pending', () {
      final waiting = _request(
        id: 1,
        status: RequestStatus.pendingApproval,
        mediaStatus: SeerrMediaAvailability.available,
      );

      expect(SeerrRequestFilter.pending.apply([waiting]).length, 1);
      expect(SeerrRequestFilter.approved.apply([waiting]), isEmpty);
    });

    test('a decided request whose media is still pending is not', () {
      // Its pill says "Waiting for approval": the media's word, for a
      // request nobody has to decide any more.
      final approved = _request(
        id: 1,
        status: RequestStatus.approved,
        mediaStatus: SeerrMediaAvailability.pending,
      );
      final declined = _request(
        id: 2,
        status: RequestStatus.declined,
        mediaStatus: SeerrMediaAvailability.pending,
      );

      expect(approved.displayStatus.kind, SeerrRequestDisplayKind.pending);
      expect(SeerrRequestFilter.pending.apply([approved, declined]), isEmpty);
      expect(SeerrRequestFilter.approved.apply([approved]).length, 1);
      expect(SeerrRequestFilter.declined.apply([declined]).length, 1);
    });

    test('lists exactly the requests the waiting count counts', () {
      final requests = [
        _request(id: 1, status: RequestStatus.pendingApproval),
        _request(
          id: 2,
          status: RequestStatus.pendingApproval,
          mediaStatus: SeerrMediaAvailability.partiallyAvailable,
        ),
        _request(
          id: 3,
          status: RequestStatus.approved,
          mediaStatus: SeerrMediaAvailability.pending,
        ),
        _request(
          id: 4,
          status: RequestStatus.approved,
          mediaStatus: SeerrMediaAvailability.processing,
        ),
      ];

      expect(
        SeerrRequestFilter.pending.apply(requests).map((r) => r.id),
        requests.where(isAwaitingApproval).map((r) => r.id),
      );
    });

    test('no request sits in two buckets', () {
      final requests = [
        for (final status in RequestStatus.values)
          for (final media in SeerrMediaAvailability.values)
            _request(id: 1, status: status, mediaStatus: media),
      ];
      for (final request in requests) {
        final buckets = [
          SeerrRequestFilter.pending,
          SeerrRequestFilter.approved,
          SeerrRequestFilter.declined,
        ].where((filter) => filter.matches(request));
        expect(
          buckets.length,
          lessThanOrEqualTo(1),
          reason: '${request.status} over ${request.media?.status}',
        );
      }
    });
  });

  group('declined', () {
    test('groups declined, failed and deleted as "will not deliver"', () {
      final declined = _request(id: 1, status: RequestStatus.declined);
      final failed = _request(id: 2, status: RequestStatus.failed);
      final deleted = _request(
        id: 3,
        mediaStatus: SeerrMediaAvailability.deleted,
      );

      expect(
        SeerrRequestFilter.declined.apply([declined, failed, deleted]).length,
        3,
      );
    });

    test('does not swallow an unparsed status', () {
      // `unknown` belongs to no bucket but `all`, so a status the app failed to
      // parse can never hide behind a wrong label.
      final unknown = _request(id: 1, status: RequestStatus.unknown);

      expect(unknown.displayStatus.kind, SeerrRequestDisplayKind.unknown);
      expect(SeerrRequestFilter.declined.apply([unknown]), isEmpty);
      expect(SeerrRequestFilter.pending.apply([unknown]), isEmpty);
      expect(SeerrRequestFilter.approved.apply([unknown]), isEmpty);
      expect(SeerrRequestFilter.all.apply([unknown]).length, 1);
    });
  });

  group('all', () {
    test('passes the list through untouched, order preserved', () {
      final requests = [
        _request(id: 1, status: RequestStatus.pendingApproval),
        _request(id: 2, status: RequestStatus.declined),
      ];

      expect(SeerrRequestFilter.all.apply(requests), same(requests));
    });
  });

  group('emptyLabel', () {
    test('names the bucket so an empty screen explains itself', () {
      expect(SeerrRequestFilter.all.emptyLabel, 'No requests found');
      expect(
        SeerrRequestFilter.pending.emptyLabel,
        'No requests waiting for approval',
      );
      expect(SeerrRequestFilter.declined.emptyLabel, 'No declined requests');
    });
  });
}
