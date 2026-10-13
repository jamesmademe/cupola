import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/features/discover/domain/seerr_permission.dart';
import 'package:cupola/features/onboarding/data/known_candidates_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_candidate.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/profiles/profiles.dart';

/// What a Seerr or a Prowlarr connection knows of the rest of the stack, read
/// through the app's own providers against the profiles' fake network.
void main() {
  Future<(ProfileHarness, ProviderContainer)> start(
    ConfigProfile profile,
  ) async {
    final harness = await ProfileHarness.start(profile);
    return (harness, harness.container(retry: (_, _) => null));
  }

  Future<List<ConnectionCandidate>> known(
    ProviderContainer container,
    String connectionId,
  ) => container.read(knownCandidatesProvider(connectionId).future);

  List<String> settingsPaths(ProfileHarness harness, String connectionId) => [
    for (final request in harness.network.requestsTo(connectionId))
      if (request.path.contains('/settings/')) request.path,
  ];

  group('Seerr with its key', () {
    test('P5: each arr it knows, with its key, from that connection', () async {
      final (harness, container) = await start(Profiles.p5);

      final candidates = await known(container, WorldIds.seerr);

      expect(
        [for (final c in candidates) (c.service, c.displayName)],
        [(ServiceKey.radarr, 'Radarr'), (ServiceKey.sonarr, 'Sonarr')],
      );
      expect(
        [for (final c in candidates) c.apiKey],
        [worldKey(WorldIds.radarr), worldKey(WorldIds.sonarr)],
      );
      expect(
        {for (final c in candidates) c.source.connectionId},
        {WorldIds.seerr},
      );
      expect(settingsPaths(harness, WorldIds.seerr), [
        '/api/v1/settings/radarr',
        '/api/v1/settings/sonarr',
      ]);
    });

    test('P5 on Docker: the names Seerr uses are kept, and proposed on '
        "Seerr's host", () async {
      final (_, container) = await start(Profiles.p5.withDockerHostnames());

      final candidates = await known(container, WorldIds.seerr);

      expect(
        [for (final c in candidates) c.reportedUrl],
        [WorldContainers.radarr, WorldContainers.sonarr],
      );
      expect(
        [for (final c in candidates) c.proposal!.hostAndPort],
        ['nas.home.arpa:7878', 'nas.home.arpa:8989'],
      );
    });

    test('the key is never in what the candidates print', () async {
      final (_, container) = await start(Profiles.p5.withDockerHostnames());

      final candidates = await known(container, WorldIds.seerr);

      final printed = [for (final c in candidates) c.toString()].join('\n');
      expect(printed, isNot(contains(worldKey(WorldIds.radarr))));
      expect(printed, isNot(contains(worldKey(WorldIds.sonarr))));
      expect(printed, contains('key: given'));
    });

    test('a Seerr that did not answer throws, as did not answer', () async {
      final (_, container) = await start(
        Profiles.p5.withBehaviour(
          WorldIds.seerr,
          ConnectionBehaviour.didNotAnswer,
        ),
      );

      await expectLater(
        known(container, WorldIds.seerr),
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

  group('Seerr with an account', () {
    test('a household member is not asked: nothing offered, nothing '
        'requested', () async {
      final (harness, container) = await start(Profiles.p2);

      final candidates = await known(container, WorldIds.seerr);

      expect(candidates, isEmpty);
      expect(settingsPaths(harness, WorldIds.seerr), isEmpty);
    });

    test('an administrator account is asked', () async {
      final (harness, container) = await start(
        Profiles.p2.withSeerrPermissions(SeerrPermission.admin.value),
      );

      final candidates = await known(container, WorldIds.seerr);

      // P2's Seerr knows nothing: an answer, from a server that was asked.
      expect(candidates, isEmpty);
      expect(settingsPaths(harness, WorldIds.seerr), [
        '/api/v1/settings/radarr',
        '/api/v1/settings/sonarr',
      ]);
    });
  });

  group('Prowlarr', () {
    ConfigProfile prowlarrOnly() => Profiles.p4
        .without(ServiceKey.radarr)
        .without(ServiceKey.sonarr)
        .without(ServiceKey.lidarr);

    test('each application it knows, none with a key', () async {
      final (harness, container) = await start(prowlarrOnly());

      final candidates = await known(container, WorldIds.prowlarr);

      expect(
        [for (final c in candidates) (c.service, c.displayName)],
        [
          (ServiceKey.radarr, 'Radarr'),
          (ServiceKey.radarr, 'Radarr 4K'),
          (ServiceKey.sonarr, 'Sonarr'),
          (ServiceKey.lidarr, 'Lidarr'),
        ],
      );
      expect(candidates.every((c) => !c.hasKey), isTrue);
      expect(
        {for (final c in candidates) c.source.connectionId},
        {WorldIds.prowlarr},
      );
      expect([
        for (final request in harness.network.requestsTo(WorldIds.prowlarr))
          request.path,
      ], contains('/api/v1/applications'));
    });
  });

  group('a service that knows nothing of the others', () {
    test('is not asked', () async {
      final (harness, container) = await start(Profiles.p1);

      final candidates = await known(container, WorldIds.radarr);

      expect(candidates, isEmpty);
      expect(harness.network.requestsTo(WorldIds.radarr), isEmpty);
    });
  });

  group('what is connected already is left out', () {
    test('P1: every server Seerr knows is connected, by address', () async {
      final (_, container) = await start(Profiles.p1);

      expect(await known(container, WorldIds.seerr), isEmpty);
    });

    test('P1 on Docker: by key, whatever name Seerr reaches them by', () async {
      final (_, container) = await start(Profiles.p1.withDockerHostnames());

      expect(await known(container, WorldIds.seerr), isEmpty);
    });

    test('P1 on Docker without its 4K Radarr: the key tells it from the '
        "Radarr connected at the address it is proposed at", () async {
      final (_, container) = await start(
        Profiles.p1.withDockerHostnames().withoutConnection(WorldIds.radarr4k),
      );

      final candidates = await known(container, WorldIds.seerr);

      expect([for (final c in candidates) c.displayName], ['Radarr 4K']);
      expect(candidates.single.proposal!.url, WorldHosts.radarr);
    });

    test('P1 without Sonarr: the one Seerr knows that is not set up', () async {
      final (_, container) = await start(
        Profiles.p1.without(ServiceKey.sonarr),
      );

      final candidates = await known(container, WorldIds.seerr);

      expect([for (final c in candidates) c.displayName], ['Sonarr']);
    });

    test('Prowlarr gives no key: the address it reports, or proposes, is '
        'enough', () async {
      final (_, container) = await start(Profiles.p1.withDockerHostnames());

      // Radarr, Radarr 4K, Sonarr and Lidarr are all connected in P1: each is
      // either at its reported address or at the one proposed for it.
      expect(await known(container, WorldIds.prowlarr), isEmpty);
    });

    test('a connection that is a form half filled matches nothing', () async {
      final (_, container) = await start(Profiles.p5);
      final settings = container.read(currentSettingsProvider);
      await container
          .read(settingsProvider.notifier)
          .updateSettings(
            settings.copyWithInstance(
              ServiceInstance(
                id: ServiceInstance.primaryIdFor(ServiceKey.radarr),
                service: ServiceKey.radarr,
              ),
            ),
          );

      final candidates = await known(container, WorldIds.seerr);

      expect([for (final c in candidates) c.displayName], ['Radarr', 'Sonarr']);
    });

    test('adding a connection re-filters the list and does not ask the source '
        'again', () async {
      final (harness, container) = await start(Profiles.p5);
      final subscription = container.listen(
        knownCandidatesProvider(WorldIds.seerr),
        (_, _) {},
      );
      addTearDown(subscription.close);
      expect(await known(container, WorldIds.seerr), hasLength(2));
      final asked = settingsPaths(harness, WorldIds.seerr).length;

      final settings = container.read(currentSettingsProvider);
      await container
          .read(settingsProvider.notifier)
          .updateSettings(
            settings.copyWithService(
              ServiceKey.radarr,
              url: WorldHosts.radarr,
              apiKey: worldKey(WorldIds.radarr),
            ),
          );

      expect(
        [for (final c in await known(container, WorldIds.seerr)) c.displayName],
        ['Sonarr'],
      );
      expect(settingsPaths(harness, WorldIds.seerr), hasLength(asked));
    });
  });
}
