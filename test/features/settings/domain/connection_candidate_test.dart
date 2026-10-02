import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/found_address.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/domain/seerr_known_arr.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_provider.dart';
import 'package:cupola/features/settings/domain/connection_candidate.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/profiles/profiles.dart';

/// Stands for a key wherever one would leak: nothing printed may contain it.
const _sentinel = 'sentinel-key-7b21e4';

const _seerr = CandidateSource(
  service: ServiceKey.seerr,
  connectionId: WorldIds.seerr,
  url: WorldHosts.seerr,
);

ConnectionCandidate _radarr4k({String? apiKey = _sentinel}) =>
    ConnectionCandidate(
      service: ServiceKey.radarr,
      name: 'Radarr 4K',
      reportedUrl: WorldContainers.radarr4k,
      source: _seerr,
      apiKey: apiKey,
      is4k: true,
      isDefault: true,
    );

void main() {
  group('a candidate', () {
    test('is a value', () {
      expect(_radarr4k(), _radarr4k());
      expect(_radarr4k().hashCode, _radarr4k().hashCode);
      expect(_radarr4k(), isNot(_radarr4k(apiKey: 'another')));
      expect(_radarr4k(), isNot(_radarr4k(apiKey: null)));
    });

    test('never prints its key', () {
      expect(_radarr4k().toString(), isNot(contains(_sentinel)));
      expect(_radarr4k().toString(), contains('key: given'));
      expect(_radarr4k(apiKey: null).toString(), contains('key: none'));
    });

    test("is named by its source, or by the service's own title", () {
      expect(_radarr4k().displayName, 'Radarr 4K');
      expect(
        const ConnectionCandidate(
          service: ServiceKey.sonarr,
          name: '',
          reportedUrl: WorldContainers.sonarr,
          source: _seerr,
        ).displayName,
        ServiceKey.sonarr.title,
      );
    });

    test(
      "is proposed on its source's host when only the source resolves it",
      () {
        expect(
          _radarr4k().proposal,
          const ProposedAddress(
            url: 'http://nas.home.arpa:7878',
            basis: FoundAddressBasis.sourceHost,
          ),
        );
      },
    );
  });

  group('from Seerr', () {
    Future<List<ConnectionCandidate>> fromSeerr(ConfigProfile profile) async {
      final harness = await ProfileHarness.start(profile);
      final answer = await harness
          .container(retry: (_, _) => null)
          .read(seerrServiceProvider)
          .knownServers();
      final seerr = profile.connection(WorldIds.seerr).instance;
      return switch (answer) {
        SeerrKnownArrsRead(:final servers) => [
          for (final server in servers) ?server.toCandidate(seerr),
        ],
        SeerrKnownArrsNotAllowed() => fail('expected the servers'),
      };
    }

    test(
      'P1 on Docker: every arr with its key, from that connection',
      () async {
        final candidates = await fromSeerr(Profiles.p1.withDockerHostnames());

        expect(candidates, [
          ConnectionCandidate(
            service: ServiceKey.radarr,
            name: 'Radarr',
            reportedUrl: WorldContainers.radarr,
            source: _seerr,
            apiKey: worldKey(WorldIds.radarr),
            externalUrl: WorldHosts.radarr,
            isDefault: true,
          ),
          ConnectionCandidate(
            service: ServiceKey.radarr,
            name: 'Radarr 4K',
            reportedUrl: WorldContainers.radarr4k,
            source: _seerr,
            apiKey: worldKey(WorldIds.radarr4k),
            externalUrl: WorldHosts.radarr4k,
            is4k: true,
            isDefault: true,
          ),
          ConnectionCandidate(
            service: ServiceKey.sonarr,
            name: 'Sonarr',
            reportedUrl: WorldContainers.sonarr,
            source: _seerr,
            apiKey: worldKey(WorldIds.sonarr),
            externalUrl: WorldHosts.sonarr,
            isDefault: true,
          ),
        ]);
      },
    );

    test(
      'P1 on Docker: Radarr 4K is proposed where the other Radarr answers',
      () async {
        final candidates = await fromSeerr(Profiles.p1.withDockerHostnames());

        expect(
          [for (final c in candidates) c.proposal!.hostAndPort],
          ['nas.home.arpa:7878', 'nas.home.arpa:7878', 'nas.home.arpa:8989'],
        );
        // Docker publishes Radarr 4K on 7879: only its own key tried at the
        // proposal can tell the two apart, and the address a browser opens
        // it at is the one that reaches it.
        expect(candidates[1].proposal!.url, isNot(WorldHosts.radarr4k));
        expect(candidates[1].externalUrl, WorldHosts.radarr4k);
      },
    );

    test('P6 on Docker: two Sonarrs end on one proposed address', () async {
      final candidates = await fromSeerr(Profiles.p6.withDockerHostnames());

      final sonarrs = candidates.where((c) => c.service == ServiceKey.sonarr);
      expect(sonarrs.map((c) => c.displayName), ['Sonarr', 'Sonarr Anime']);
      expect(sonarrs.map((c) => c.proposal), [
        const ProposedAddress(
          url: 'http://nas.home.arpa:8989',
          basis: FoundAddressBasis.sourceHost,
        ),
        const ProposedAddress(
          url: 'http://nas.home.arpa:8989',
          basis: FoundAddressBasis.sourceHost,
        ),
      ]);
      expect(sonarrs.map((c) => c.apiKey).toSet(), hasLength(2));
    });

    test('P1: an address this device reaches already stays as it is', () async {
      final candidates = await fromSeerr(Profiles.p1);

      expect(
        [for (final c in candidates) c.proposal],
        [
          for (final url in [
            WorldHosts.radarr,
            WorldHosts.radarr4k,
            WorldHosts.sonarr,
          ])
            ProposedAddress(url: url, basis: FoundAddressBasis.asReported),
        ],
      );
    });

    test('a server whose settings say no address is no candidate', () {
      final known = SeerrKnownArr.fromSettingsJson(const {
        'id': 3,
        'name': 'Radarr',
        'hostname': '',
        'port': 7878,
      }, service: ServiceKey.radarr);

      expect(
        known.toCandidate(Profiles.p1.connection(WorldIds.seerr).instance),
        isNull,
      );
    });
  });

  group('from Prowlarr', () {
    test('P1 on Docker: every arr Cupola connects to, without a key', () async {
      final profile = Profiles.p1.withDockerHostnames();
      final harness = await ProfileHarness.start(profile);
      final apps = await harness
          .container(retry: (_, _) => null)
          .read(prowlarrServiceProvider)
          .knownApplications();
      final prowlarr = profile.connection(WorldIds.prowlarr).instance;

      final candidates = [for (final a in apps) ?a.toCandidate(prowlarr)];

      expect(
        [
          for (final c in candidates)
            (c.service, c.displayName, c.proposal!.hostAndPort),
        ],
        [
          (ServiceKey.radarr, 'Radarr', 'nas.home.arpa:7878'),
          (ServiceKey.radarr, 'Radarr 4K', 'nas.home.arpa:7878'),
          (ServiceKey.sonarr, 'Sonarr', 'nas.home.arpa:8989'),
          (ServiceKey.lidarr, 'Lidarr', 'nas.home.arpa:8686'),
        ],
      );
      expect(candidates.every((c) => !c.hasKey), isTrue);
      expect(candidates.map((c) => c.source).toSet(), {
        const CandidateSource(
          service: ServiceKey.prowlarr,
          connectionId: WorldIds.prowlarr,
          url: WorldHosts.prowlarr,
        ),
      });
    });
  });
}
