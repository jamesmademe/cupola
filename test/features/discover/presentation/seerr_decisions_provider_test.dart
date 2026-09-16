import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';

import '../../../test_helpers/fake_api_client.dart';

SeerrRequest _request({
  required int id,
  RequestStatus status = RequestStatus.pendingApproval,
  SeerrMediaAvailability mediaStatus = SeerrMediaAvailability.unknown,
  String createdAt = '2026-09-01T00:00:00Z',
}) => SeerrRequest(
  id: id,
  status: status,
  media: RequestMedia(title: 'Title $id', tmdbId: id, status: mediaStatus),
  createdAt: createdAt,
  type: 'movie',
);

Future<SeerrDecisions> _resolve(List<SeerrRequest> requests) async {
  final container = ProviderContainer(
    overrides: [requestsProvider.overrideWith((ref) async => requests)],
  );
  addTearDown(container.dispose);
  return container.read(seerrDecisionsProvider.future);
}

void main() {
  group('seerrDecisionsProvider', () {
    test('keeps a waiting request whose media is already available', () async {
      // The Seerr trap, and the only reason this provider is not a one-line
      // `where`. `displayStatus` lets the media's availability override the
      // request's own state, so this request reads "Available" while still
      // waiting on a person. A decisions list keyed off it would drop exactly
      // the approvals that matter most — the ones for titles already on disk.
      final pendingButAvailable = _request(
        id: 1,
        status: RequestStatus.pendingApproval,
        mediaStatus: SeerrMediaAvailability.available,
      );
      expect(pendingButAvailable.displayStatus.label, 'Available');

      final decisions = await _resolve([pendingButAvailable]);

      expect(decisions.total, 1);
      expect(decisions.preview.single.id, 1);
    });

    test('drops a settled request whose media still reads Pending', () async {
      // The same trap in the other direction: this one is approved and nobody
      // has to do anything, but its media has not landed yet so `displayStatus`
      // says "Pending".
      final approvedButMediaPending = _request(
        id: 2,
        status: RequestStatus.approved,
        mediaStatus: SeerrMediaAvailability.pending,
      );
      expect(approvedButMediaPending.displayStatus.label, 'Pending');

      final decisions = await _resolve([approvedButMediaPending]);

      expect(decisions.total, 0);
      expect(decisions.preview, isEmpty);
    });

    test('ignores every settled status', () async {
      final decisions = await _resolve([
        for (final status in [
          RequestStatus.approved,
          RequestStatus.declined,
          RequestStatus.failed,
          RequestStatus.completed,
          RequestStatus.unknown,
        ])
          _request(id: status.index, status: status),
      ]);

      expect(decisions.total, 0);
    });

    test('counts every waiting request, shows the first few', () async {
      final decisions = await _resolve([
        for (var i = 0; i < seerrDecisionsPreviewLimit + 3; i++)
          _request(id: i, createdAt: '2026-09-0${i + 1}T00:00:00Z'),
      ]);

      // The count is taken before the cut, so a header built from it does not
      // under-report what is waiting.
      expect(decisions.total, seerrDecisionsPreviewLimit + 3);
      expect(decisions.preview, hasLength(seerrDecisionsPreviewLimit));
    });

    test('newest first inside the waiting group', () async {
      final decisions = await _resolve([
        _request(id: 1, createdAt: '2026-09-01T00:00:00Z'),
        _request(id: 2, createdAt: '2026-09-14T00:00:00Z'),
        _request(id: 3, createdAt: '2026-09-07T00:00:00Z'),
      ]);

      expect(decisions.preview.map((r) => r.id), [2, 3, 1]);
    });

    test(
      'a Seerr that did not answer fails rather than reading zero',
      () async {
        // Overridden at the service rather than at `requestsProvider`, so the
        // real provider — and its `noProviderRetry`, which is what stops a dead
        // server from being retried forever — is the one under test.
        final client = FakeApiClient()..getException = Exception('unreachable');
        final container = ProviderContainer(
          overrides: [
            seerrServiceProvider.overrideWithValue(SeerrService(client)),
          ],
        );
        addTearDown(container.dispose);

        // "No decisions waiting" is a claim about a server that answered. An
        // unreachable one has to arrive as a failure so the section can say so.
        Object? thrown;
        try {
          await container.read(seerrDecisionsProvider.future);
        } catch (error) {
          thrown = error;
        }

        expect(thrown, isA<Exception>());
      },
    );
  });
}
