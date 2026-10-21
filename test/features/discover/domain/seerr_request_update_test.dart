import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/domain/seerr_arr_server.dart';
import 'package:cupola/features/discover/domain/seerr_request_update.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

const _uhd = SeerrArrServer(
  service: ServiceKey.radarr,
  id: 1,
  name: 'Radarr 4K',
  is4k: true,
  isDefault: true,
);

const _movie = SeerrRequest(
  id: 7,
  status: RequestStatus.pendingApproval,
  createdAt: '2026-09-30T10:00:00Z',
  type: 'movie',
  serverId: 0,
  profileId: 4,
  rootFolder: '/films',
  tags: [3],
);

void main() {
  group('seerrRequestUpdateBody', () {
    test('a series request with no seasons is refused: Seerr would throw', () {
      const bare = SeerrRequest(
        id: 9,
        status: RequestStatus.pendingApproval,
        createdAt: '2026-09-30T10:00:00Z',
        type: 'tv',
      );

      expect(
        () => seerrRequestUpdateBody(bare, profileId: 2),
        throwsArgumentError,
      );
    });

    test('a movie request never goes to a Sonarr', () {
      expect(
        () => seerrRequestUpdateBody(
          _movie,
          server: const SeerrArrServer(
            service: ServiceKey.sonarr,
            id: 0,
            name: 'Sonarr',
          ),
        ),
        throwsArgumentError,
      );
    });

    test('a server of the other copy is refused', () {
      expect(
        () => seerrRequestUpdateBody(_movie, server: _uhd),
        throwsArgumentError,
      );
    });

    test('a 4K request may move between 4K servers', () {
      const uhdRequest = SeerrRequest(
        id: 10,
        status: RequestStatus.pendingApproval,
        createdAt: '2026-09-30T10:00:00Z',
        type: 'movie',
        is4k: true,
      );

      expect(seerrRequestUpdateBody(uhdRequest, server: _uhd), {
        'mediaType': 'movie',
        'is4k': true,
        'serverId': 1,
      });
    });
  });
}
