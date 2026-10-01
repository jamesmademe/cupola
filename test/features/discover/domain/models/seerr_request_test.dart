import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/domain/models/seerr_request.dart';

void main() {
  group('RequestStatus.fromCode', () {
    test('maps known Overseerr request codes', () {
      expect(RequestStatus.fromCode(1), RequestStatus.pendingApproval);
      expect(RequestStatus.fromCode(2), RequestStatus.approved);
      expect(RequestStatus.fromCode(3), RequestStatus.declined);
      expect(RequestStatus.fromCode(4), RequestStatus.failed);
      expect(RequestStatus.fromCode(5), RequestStatus.completed);
      expect(RequestStatus.fromCode(99), RequestStatus.unknown);
    });
  });

  group('SeerrRequest.displayStatus', () {
    test('prefers media availability over request workflow when available', () {
      final request = SeerrRequest(
        id: 1,
        status: RequestStatus.unknown,
        media: const RequestMedia(status: SeerrMediaAvailability.available),
        createdAt: '2026-05-01T10:00:00Z',
        type: 'movie',
      );

      expect(request.displayStatus.label, 'Available');
      expect(request.displayStatus.kind, SeerrRequestDisplayKind.available);
    });

    test('returns partially available from media status', () {
      final request = SeerrRequest(
        id: 2,
        status: RequestStatus.approved,
        media: const RequestMedia(
          status: SeerrMediaAvailability.partiallyAvailable,
        ),
        createdAt: '2026-05-01T10:00:00Z',
        type: 'tv',
      );

      expect(request.displayStatus.label, 'Partially available');
      expect(
        request.displayStatus.kind,
        SeerrRequestDisplayKind.partiallyAvailable,
      );
    });

    test(
      'falls back to approved when request is approved without media state',
      () {
        final request = SeerrRequest(
          id: 3,
          status: RequestStatus.approved,
          createdAt: '2026-05-01T10:00:00Z',
          type: 'movie',
        );

        expect(request.displayStatus.label, 'Approved');
        expect(request.displayStatus.kind, SeerrRequestDisplayKind.approved);
      },
    );
  });

  group('the 4K axis', () {
    // Seerr keeps HD and 4K apart on the media row. A title on disk in HD
    // with a 4K request still moving used to read the HD state for both.
    Map<String, dynamic> requestJson({
      required bool is4k,
      required int status,
      required int status4k,
    }) => {
      'id': 9,
      'status': 2,
      'type': 'movie',
      'is4k': is4k,
      'createdAt': '2026-05-01T10:00:00Z',
      'media': {
        'id': 40,
        'tmdbId': 45745,
        'mediaType': 'movie',
        'status': status,
        'status4k': status4k,
      },
    };

    test('status4k is decoded with the numbering of the server', () {
      final seerr = SeerrRequest.fromJson(
        requestJson(is4k: true, status: 5, status4k: 6),
        numbering: SeerrNumbering.seerr,
      );
      final overseerr = SeerrRequest.fromJson(
        requestJson(is4k: true, status: 5, status4k: 6),
        numbering: SeerrNumbering.overseerr,
      );

      expect(seerr.media!.status4k, SeerrMediaAvailability.blocklisted);
      expect(overseerr.media!.status4k, SeerrMediaAvailability.deleted);
      expect(seerr.media!.status, SeerrMediaAvailability.available);
    });

    test('a 4K request reads the 4K copy, not the HD one on disk', () {
      final request = SeerrRequest.fromJson(
        requestJson(is4k: true, status: 5, status4k: 3),
        numbering: SeerrNumbering.seerr,
      );

      expect(request.mediaAvailability, SeerrMediaAvailability.processing);
      expect(request.displayStatus.label, 'Processing');
      expect(request.displayStatus.kind, SeerrRequestDisplayKind.processing);
    });

    test('an HD request of the same title still reads the HD copy', () {
      final request = SeerrRequest.fromJson(
        requestJson(is4k: false, status: 5, status4k: 3),
        numbering: SeerrNumbering.seerr,
      );

      expect(request.mediaAvailability, SeerrMediaAvailability.available);
      expect(request.displayStatus.label, 'Available');
    });

    test('a 4K copy Seerr has no state for falls back to the request', () {
      final request = SeerrRequest.fromJson(
        requestJson(is4k: true, status: 5, status4k: 1),
        numbering: SeerrNumbering.seerr,
      );

      expect(request.displayStatus.label, 'Approved');
    });

    test('hydration keeps the 4K state', () {
      final request = SeerrRequest.fromJson(
        requestJson(is4k: true, status: 5, status4k: 2),
        numbering: SeerrNumbering.seerr,
      );
      final hydrated = request.copyWith(
        media: request.media!.copyWith(title: 'Sintel'),
      );

      expect(hydrated.media!.status4k, SeerrMediaAvailability.pending);
    });
  });

  group('where a request goes', () {
    test('reads its server, profile, folder, language profile and tags', () {
      final request = SeerrRequest.fromJson({
        'id': 4,
        'status': 1,
        'type': 'tv',
        'createdAt': '2026-09-30T10:00:00Z',
        'serverId': 1,
        'profileId': 6,
        'rootFolder': '/series/anime',
        'languageProfileId': 2,
        'tags': [3, 5],
      });

      expect(request.serverId, 1);
      expect(request.profileId, 6);
      expect(request.rootFolder, '/series/anime');
      expect(request.languageProfileId, 2);
      expect(request.tags, [3, 5]);
      expect(request.copyWith().tags, [3, 5]);
    });

    test('a request that names none of them reads none', () {
      final request = SeerrRequest.fromJson({
        'id': 4,
        'status': 1,
        'type': 'movie',
        'createdAt': '2026-09-30T10:00:00Z',
      });

      expect(request.serverId, isNull);
      expect(request.rootFolder, isNull);
      expect(request.languageProfileId, isNull);
      expect(request.tags, isNull);
    });
  });
}
