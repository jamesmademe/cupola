import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/profiles/profiles.dart';

/// Approve with changes against P6's Seerr, through the app's own client.
///
/// Charge (request 1) and Metropolis (request 2) are waiting; Sprite Fright
/// (request 3) was approved twenty days ago.
void main() {
  Iterable<String> writes(ProfileHarness harness) => harness.network
      .requestsTo(WorldIds.seerr)
      .where((r) => r.method != 'GET')
      .map((r) => '${r.method} ${r.uri.path}');

  Future<(ProfileHarness, SeerrService)> start() async {
    final harness = await ProfileHarness.start(Profiles.p6);
    final service = harness.container().read(seerrServiceProvider);
    return (harness, service);
  }

  test('P6: the edit goes to Seerr first, then the approval', () async {
    final (harness, service) = await start();
    final charge = await service.getRequest(1);
    final servers = await service.getArrServers(ServiceKey.radarr);

    await service.approveRequestWithChanges(
      charge,
      server: servers.firstWhere((s) => !s.is4k),
      rootFolder: '/mnt/tank/media/archive',
    );

    expect(writes(harness), [
      'PUT /api/v1/request/1',
      'POST /api/v1/request/1/approve',
    ]);
    final edit = harness.network
        .requestsTo(WorldIds.seerr)
        .firstWhere((r) => r.method == 'PUT');
    expect(edit.json, {
      'mediaType': 'movie',
      'is4k': false,
      'serverId': 0,
      'profileId': 1,
      'rootFolder': '/mnt/tank/media/archive',
    });
  });

  test('P6: an edit Seerr refuses approves nothing', () async {
    final (harness, service) = await start();
    harness.network.on(
      WorldIds.seerr,
      'PUT',
      '/api/v1/request/2',
      (_) => NetworkReply.json({'message': 'boom'}, status: 500),
    );
    final metropolis = await service.getRequest(2);

    await expectLater(
      service.approveRequestWithChanges(metropolis, profileId: 7),
      throwsA(anything),
    );
    expect(writes(harness), ['PUT /api/v1/request/2']);
  });

  test('P6: a request already decided is the race, and not approved', () async {
    final (harness, service) = await start();
    final spriteFright = await service.getRequest(3);

    await expectLater(
      service.approveRequestWithChanges(spriteFright, profileId: 7),
      throwsA(isA<SeerrRequestConflict>()),
    );
    expect(writes(harness), ['PUT /api/v1/request/3']);
  });
}
