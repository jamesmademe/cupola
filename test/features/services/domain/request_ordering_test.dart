import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/services/domain/request_ordering.dart';

SeerrRequest _request({
  required int id,
  RequestStatus status = RequestStatus.completed,
  SeerrMediaAvailability mediaStatus = SeerrMediaAvailability.unknown,
  String createdAt = '2024-01-01T00:00:00Z',
}) => SeerrRequest(
  id: id,
  status: status,
  media: RequestMedia(title: 'Title $id', tmdbId: id, status: mediaStatus),
  createdAt: createdAt,
  type: 'movie',
);

void main() {
  group('isAwaitingApproval', () {
    test('reads request status, not displayStatus', () {
      // The trap: `displayStatus` lets media availability override request state,
      // so this request reads "Available" while still needing a human. Keying the
      // actionable set off displayStatus would silently drop exactly the
      // approvals that matter most: the ones for media already on disk.
      final pendingButAvailable = _request(
        id: 1,
        status: RequestStatus.pendingApproval,
        mediaStatus: SeerrMediaAvailability.available,
      );

      expect(pendingButAvailable.displayStatus.label, 'Available');
      expect(isAwaitingApproval(pendingButAvailable), isTrue);
    });

    test('is false for every settled status', () {
      for (final status in [
        RequestStatus.approved,
        RequestStatus.declined,
        RequestStatus.failed,
        RequestStatus.completed,
      ]) {
        expect(
          isAwaitingApproval(_request(id: 1, status: status)),
          isFalse,
          reason: status.name,
        );
      }
    });
  });

  group('sortRequestsPendingFirst', () {
    test('pending comes first even when it is the oldest request', () {
      // A single sort on recency would bury a three-day-old approval under
      // today's auto-approved traffic.
      final sorted = sortRequestsPendingFirst([
        _request(id: 1, createdAt: '2024-06-01T00:00:00Z'),
        _request(
          id: 2,
          status: RequestStatus.pendingApproval,
          createdAt: '2024-01-01T00:00:00Z',
        ),
        _request(id: 3, createdAt: '2024-05-01T00:00:00Z'),
      ], limit: 10);

      expect(sorted.map((request) => request.id), [2, 1, 3]);
    });

    test('within each group, newest first', () {
      final sorted = sortRequestsPendingFirst([
        _request(
          id: 1,
          status: RequestStatus.pendingApproval,
          createdAt: '2024-01-01T00:00:00Z',
        ),
        _request(
          id: 2,
          status: RequestStatus.pendingApproval,
          createdAt: '2024-03-01T00:00:00Z',
        ),
      ], limit: 10);

      expect(sorted.map((request) => request.id), [2, 1]);
    });

    test('never filters: resolved requests survive alongside pending', () {
      // The whole reason this is one region and not two.
      final sorted = sortRequestsPendingFirst([
        _request(id: 1, status: RequestStatus.pendingApproval),
        _request(id: 2),
        _request(id: 3),
      ], limit: 10);

      expect(sorted, hasLength(3));
    });

    test('an unparseable date sorts last within its group', () {
      final sorted = sortRequestsPendingFirst([
        _request(id: 1, createdAt: ''),
        _request(id: 2, createdAt: '2020-01-01T00:00:00Z'),
      ], limit: 10);

      expect(sorted.map((request) => request.id), [2, 1]);
    });

    test('caps at the limit', () {
      final sorted = sortRequestsPendingFirst([
        for (var index = 0; index < 20; index++) _request(id: index),
      ], limit: 2);

      expect(sorted, hasLength(2));
    });

    test('leaves the caller\'s list untouched', () {
      final input = [
        _request(id: 1),
        _request(id: 2, status: RequestStatus.pendingApproval),
      ];

      sortRequestsPendingFirst(input, limit: 10);

      expect(input.first.id, 1);
    });
  });
}
