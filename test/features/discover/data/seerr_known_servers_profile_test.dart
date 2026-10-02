import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/data/seerr_session.dart';
import 'package:cupola/features/discover/domain/seerr_known_arr.dart';
import 'package:cupola/features/discover/domain/seerr_permission.dart';
import 'package:cupola/features/discover/domain/seerr_refusal.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/profiles/profiles.dart';

/// What Seerr knows of the household's Radarr and Sonarr, read through the
/// app's own Seerr client against the profiles' Seerr.
void main() {
  Future<SeerrService> seerrOf(
    ConfigProfile profile, {
    String instanceId = '',
  }) async {
    final harness = await ProfileHarness.start(profile);
    return harness
        .container(retry: (_, _) => null)
        .read(seerrServiceForProvider(instanceId));
  }

  List<SeerrKnownArr> serversIn(SeerrKnownArrs answer) => switch (answer) {
    SeerrKnownArrsRead(:final servers) => servers,
    SeerrKnownArrsNotAllowed() => fail('expected the servers, got $answer'),
  };

  group('the admin key', () {
    test('P1 on Docker: each arr by its container, with its key', () async {
      final seerr = await seerrOf(Profiles.p1.withDockerHostnames());

      final servers = serversIn(await seerr.knownServers());

      expect(
        [for (final s in servers) (s.service, s.name, s.address)],
        [
          (ServiceKey.radarr, 'Radarr', WorldContainers.radarr),
          (ServiceKey.radarr, 'Radarr 4K', WorldContainers.radarr4k),
          (ServiceKey.sonarr, 'Sonarr', WorldContainers.sonarr),
        ],
      );
      expect(
        [for (final s in servers) s.apiKey],
        [
          worldKey(WorldIds.radarr),
          worldKey(WorldIds.radarr4k),
          worldKey(WorldIds.sonarr),
        ],
      );
      expect([for (final s in servers) s.is4k], [false, true, false]);
      expect([for (final s in servers) s.isDefault], [true, true, true]);
      // The address a browser opens each at, as the admin of such a stack
      // sets it.
      expect(servers[1].externalUrl, WorldHosts.radarr4k);
    });

    test(
      'P1: the addresses this device reaches too, when Seerr uses them',
      () async {
        final seerr = await seerrOf(Profiles.p1);

        final servers = serversIn(await seerr.knownServers());

        expect(
          [for (final s in servers) s.address],
          [WorldHosts.radarr, WorldHosts.radarr4k, WorldHosts.sonarr],
        );
        expect(servers.every((s) => s.externalUrl == null), isTrue);
      },
    );

    test(
      'P6: two Radarrs and two Sonarrs, the second Sonarr no default',
      () async {
        final seerr = await seerrOf(Profiles.p6.withDockerHostnames());

        final servers = serversIn(await seerr.knownServers());

        expect(
          [for (final s in servers) (s.name, s.address, s.isDefault)],
          [
            ('Radarr', WorldContainers.radarr, true),
            ('Radarr 4K', WorldContainers.radarr4k, true),
            ('Sonarr', WorldContainers.sonarr, true),
            ('Sonarr Anime', WorldContainers.sonarrAnime, false),
          ],
        );
        expect(servers[3].apiKey, worldKey(WorldIds.sonarrAnime));
      },
    );

    test('a refused key throws, as the key refused', () async {
      final seerr = await seerrOf(
        Profiles.p1.withBehaviour(
          WorldIds.seerr,
          ConnectionBehaviour.refusesKey,
        ),
      );

      await expectLater(
        seerr.knownServers(),
        throwsA(
          predicate(
            (Object e) =>
                classifyConnectionFailure(e) ==
                ServiceFailureReason.unauthorized,
          ),
        ),
      );
    });

    test('a Seerr that did not answer throws, as did not answer', () async {
      final seerr = await seerrOf(
        Profiles.p1.withBehaviour(
          WorldIds.seerr,
          ConnectionBehaviour.didNotAnswer,
        ),
      );

      await expectLater(
        seerr.knownServers(),
        throwsA(
          predicate(
            (Object e) =>
                classifyConnectionFailure(e) ==
                ServiceFailureReason.unreachable,
          ),
        ),
      );
    });
  });

  group('an account', () {
    test('P2: a requester reads not allowed, from the server', () async {
      final harness = await ProfileHarness.start(Profiles.p2);
      final seerr = harness
          .container(retry: (_, _) => null)
          .read(seerrServiceProvider);

      expect(await seerr.knownServers(), isA<SeerrKnownArrsNotAllowed>());
      expect(
        harness.network
            .requestsTo(WorldIds.seerr)
            .map((r) => '${r.method} ${r.uri.path}'),
        contains('GET /api/v1/settings/radarr'),
      );
    });

    test(
      'an account that manages everything but settings reads not allowed',
      () async {
        final seerr = await seerrOf(
          Profiles.p2.withSeerrPermissions(
            SeerrPermission.manageUsers.value |
                SeerrPermission.manageRequests.value |
                SeerrPermission.manageIssues.value |
                SeerrPermission.request.value,
          ),
        );

        expect(await seerr.knownServers(), isA<SeerrKnownArrsNotAllowed>());
      },
    );

    test('an admin account reads the servers and their keys', () async {
      final seerr = await seerrOf(
        Profiles.p9.withDockerHostnames().withSeerrPermissions(
          SeerrPermission.admin.value,
        ),
        instanceId: WorldIds.seerrFriend,
      );

      final servers = serversIn(await seerr.knownServers());

      expect(
        [for (final s in servers) s.address],
        [
          WorldContainers.radarr,
          WorldContainers.radarr4k,
          WorldContainers.sonarr,
        ],
      );
      expect(servers.first.apiKey, worldKey(WorldIds.radarr));
    });

    test('an admin of a Seerr that knows no arr reads an empty list', () async {
      final seerr = await seerrOf(
        Profiles.p2.withSeerrPermissions(SeerrPermission.admin.value),
      );

      expect(serversIn(await seerr.knownServers()), isEmpty);
    });

    test('an ended session throws as the ended session it is', () async {
      final seerr = await seerrOf(
        Profiles.p2.withBehaviour(
          WorldIds.seerr,
          ConnectionBehaviour.sessionExpired,
        ),
      );

      await expectLater(
        seerr.knownServers(),
        throwsA(
          predicate(
            (Object e) =>
                e is DioException &&
                e.error is SeerrSessionEnded &&
                seerrRefusalOf(e) == SeerrRefusal.sessionEnded,
          ),
        ),
      );
    });

    test(
      'P9: the operator\'s Seerr answers, the friend\'s says not allowed',
      () async {
        final harness = await ProfileHarness.start(Profiles.p9);
        final container = harness.container(retry: (_, _) => null);

        final own = await container
            .read(seerrServiceForProvider(WorldIds.seerr))
            .knownServers();
        final friend = await container
            .read(seerrServiceForProvider(WorldIds.seerrFriend))
            .knownServers();

        expect(serversIn(own), hasLength(3));
        expect(friend, isA<SeerrKnownArrsNotAllowed>());
      },
    );
  });
}
