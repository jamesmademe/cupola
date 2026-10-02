import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/data/seerr_service.dart';

import '../../../test_helpers/profiles/fakes/arr_fakes.dart';
import '../../../test_helpers/profiles/profiles.dart';

/// Which copy a request is about, read through the app's own Seerr client
/// against P1's Seerr, where Tears of Steel (request 6) was asked for in 4K
/// and both Radarrs hold it.
void main() {
  test(
    'P1: a 4K request names Radarr 4K\'s copy, not the standard one',
    () async {
      final harness = await ProfileHarness.start(Profiles.p1);
      final seerr = harness
          .container(retry: (_, _) => null)
          .read(seerrServiceProvider);

      final request = await seerr.getRequest(6);

      expect(request.is4k, isTrue);
      expect(request.copy?.is4k, isTrue);
      expect(
        request.copy?.externalId,
        RadarrFake.idOf(WorldTitles.tearsOfSteel, is4k: true),
      );
      // Seerr's id of Radarr 4K, the server the request names too.
      expect(request.copy?.serverId, 1);
      expect(request.serverId, 1);
      expect(
        request.media?.externalServiceId,
        RadarrFake.idOf(WorldTitles.tearsOfSteel, is4k: false),
      );
      expect(request.copy?.externalId, isNot(request.media?.externalServiceId));
    },
  );
}
