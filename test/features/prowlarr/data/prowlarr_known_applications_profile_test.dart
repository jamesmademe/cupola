import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/features/prowlarr/data/prowlarr_service.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/profiles/profiles.dart';

/// The arrs Prowlarr knows, read through the app's own Prowlarr client
/// against the profiles' Prowlarr.
void main() {
  Future<(ProfileHarness, ProwlarrService)> start(ConfigProfile profile) async {
    final harness = await ProfileHarness.start(profile);
    return (
      harness,
      harness.container(retry: (_, _) => null).read(prowlarrServiceProvider),
    );
  }

  test('P1: each arr at the address Prowlarr reaches it, no key', () async {
    final (_, prowlarr) = await start(Profiles.p1);

    final apps = await prowlarr.knownApplications();

    expect(
      [for (final a in apps) (a.service, a.name, a.baseUrl)],
      [
        (ServiceKey.radarr, 'Radarr', WorldHosts.radarr),
        (ServiceKey.radarr, 'Radarr 4K', WorldHosts.radarr4k),
        (ServiceKey.sonarr, 'Sonarr', WorldHosts.sonarr),
        (ServiceKey.lidarr, 'Lidarr', WorldHosts.lidarr),
      ],
    );
    expect(apps.every((a) => a.prowlarrUrl == WorldHosts.prowlarr), isTrue);
  });

  test(
    'P1 on Docker: the containers, Prowlarr named as they reach it',
    () async {
      final (_, prowlarr) = await start(Profiles.p1.withDockerHostnames());

      final apps = await prowlarr.knownApplications();

      expect(
        [for (final a in apps) a.baseUrl],
        [
          WorldContainers.radarr,
          WorldContainers.radarr4k,
          WorldContainers.sonarr,
          WorldContainers.lidarr,
        ],
      );
      expect(
        apps.every((a) => a.prowlarrUrl == WorldContainers.prowlarr),
        isTrue,
      );
    },
  );

  test(
    'P4: a stack without Seerr learns the same arrs from Prowlarr',
    () async {
      final (harness, prowlarr) = await start(Profiles.p4);

      final apps = await prowlarr.knownApplications();

      expect(apps.map((a) => a.name), [
        'Radarr',
        'Radarr 4K',
        'Sonarr',
        'Lidarr',
      ]);
      expect(
        harness.network.requestsTo(WorldIds.prowlarr).map((r) => r.uri.path),
        contains('/api/v1/applications'),
      );
    },
  );

  test('an application Cupola does not connect to has no service', () async {
    final (harness, prowlarr) = await start(Profiles.p4);
    harness.network.on(
      WorldIds.prowlarr,
      'GET',
      '/api/v1/applications',
      (_) => NetworkReply.json([
        {
          'id': 9,
          'name': 'Whisparr',
          'implementation': 'Whisparr',
          'fields': [
            {'name': 'baseUrl', 'value': 'http://whisparr:6969'},
            {'name': 'apiKey', 'value': '********'},
          ],
        },
      ]),
    );

    final apps = await prowlarr.knownApplications();

    expect(apps.single.service, isNull);
    expect(apps.single.baseUrl, 'http://whisparr:6969');
  });

  test('an answer that is not a list throws, never reads as none', () async {
    final (harness, prowlarr) = await start(Profiles.p4);
    harness.network.on(
      WorldIds.prowlarr,
      'GET',
      '/api/v1/applications',
      (_) => NetworkReply.json({'message': 'nope'}),
    );

    await expectLater(
      prowlarr.knownApplications(),
      throwsA(isA<FormatException>()),
    );
  });

  test('a Prowlarr that did not answer throws, as did not answer', () async {
    final (_, prowlarr) = await start(
      Profiles.p1.withBehaviour(
        WorldIds.prowlarr,
        ConnectionBehaviour.didNotAnswer,
      ),
    );

    await expectLater(
      prowlarr.knownApplications(),
      throwsA(
        predicate(
          (Object e) =>
              classifyConnectionFailure(e) == ServiceFailureReason.unreachable,
        ),
      ),
    );
  });
}
