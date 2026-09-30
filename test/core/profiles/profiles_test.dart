/// The profiles as values: what each one configures, where its lens rests, and
/// that the table in the config inventory is what the code holds.
///
/// Nothing here touches the network — `profile_network_test.dart` does that.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../test_helpers/profiles/profiles.dart';

void main() {
  group('every profile', () {
    for (final profile in Profiles.all) {
      test('${profile.id} builds a settings model the app accepts', () {
        final settings = profile.settings;
        final ids = [for (final c in profile.connections) c.id];

        expect(ids.toSet(), hasLength(ids.length), reason: 'ids are unique');
        expect(settings.instances, hasLength(profile.connections.length));
        for (final connection in profile.connections) {
          expect(
            settings.instanceById(connection.id)?.isConfigured,
            isTrue,
            reason: '${connection.id} has what isServiceConfigured needs',
          );
        }
        // The first of each service is its primary, on the id whose storage
        // keys predate multi-instance — the shape a real install has.
        for (final service in ServiceKey.values) {
          final first = settings.primaryOf(service);
          if (first != null) expect(first.id, service.routeParam);
        }
      });
    }
  });

  group('the inventory table', () {
    test('P1 is the full household: twelve connections, six not set up', () {
      final p1 = Profiles.p1;
      expect(p1.connections, hasLength(12));
      for (final service in const [
        ServiceKey.plex,
        ServiceKey.readarr,
        ServiceKey.transmission,
        ServiceKey.nzbget,
        ServiceKey.unraid,
        ServiceKey.nginxProxyManager,
      ]) {
        expect(p1.settings.isServiceConfigured(service), isFalse);
      }
      expect(p1.connectionsOf(ServiceKey.radarr).map((c) => c.id), [
        WorldIds.radarr,
        WorldIds.radarr4k,
      ]);
      expect(
        p1.cases,
        containsAll([
          ConfigCase.severalInstances,
          ConfigCase.notSetUp,
          ConfigCase.matchNotVerified,
        ]),
      );
      expect(p1.unverifiedMatches, isNotEmpty);
    });

    test('P2 is Anna, with the requester half left as a hook', () {
      expect(Profiles.p2.connections.map((c) => c.service), [ServiceKey.seerr]);
      expect(Profiles.p2.seerrRequester?.displayName, WorldPeople.anna);
      final jellyfin = Profiles.p2WithJellyfin.connection(WorldIds.jellyfin);
      expect(jellyfin.behaviour, ConnectionBehaviour.readOnly);
    });

    test('P3 is the first day: Radarr, Sonarr and Seerr only', () {
      expect(Profiles.p3.connections.map((c) => c.service).toSet(), {
        ServiceKey.radarr,
        ServiceKey.sonarr,
        ServiceKey.seerr,
      });
    });

    test('P4 has two download clients and no Seerr', () {
      final p4 = Profiles.p4;
      expect(p4.has(ServiceKey.seerr), isFalse);
      expect(p4.has(ServiceKey.qbittorrent), isTrue);
      expect(p4.has(ServiceKey.transmission), isTrue);
    });

    test('P5 knows Radarr and Sonarr only through Seerr', () {
      final p5 = Profiles.p5;
      expect(p5.has(ServiceKey.radarr), isFalse);
      expect(p5.has(ServiceKey.sonarr), isFalse);
      expect(p5.seerrKnows.map((s) => s.service).toSet(), {
        ServiceKey.radarr,
        ServiceKey.sonarr,
      });
      expect(p5.cases, contains(ConfigCase.knownThroughAnother));
    });

    test('P6 has two Radarr and two Sonarr, told apart by id and label', () {
      final p6 = Profiles.p6;
      final radarr = p6.connectionsOf(ServiceKey.radarr);
      final sonarr = p6.connectionsOf(ServiceKey.sonarr);

      expect(radarr.map((c) => c.id), [WorldIds.radarr, WorldIds.radarr4k]);
      expect(sonarr.map((c) => c.id), [WorldIds.sonarr, WorldIds.sonarrAnime]);
      expect(radarr.map((c) => c.instance.label), ['', '4K']);
      expect(sonarr.map((c) => c.instance.label), ['', 'Anime']);
      expect(p6.settings.hasMultipleInstances(ServiceKey.radarr), isTrue);
      expect(p6.settings.hasMultipleInstances(ServiceKey.sonarr), isTrue);
      expect(
        p6.settings.connectionTitle(WorldIds.radarr4k, ServiceKey.radarr),
        'Radarr · 4K',
      );
      expect(p6.has(ServiceKey.plex), isTrue);
      expect(p6.has(ServiceKey.jellyfin), isFalse);
      expect(p6.bazarrFollows, {ServiceKey.radarr});
      final seerrRadarr = p6.seerrKnows.where(
        (s) => s.service == ServiceKey.radarr,
      );
      expect(seerrRadarr.map((s) => (s.is4k, s.isDefault)), [
        (false, true),
        (true, true),
      ]);
    });

    test('P7 is P1 degraded and away', () {
      final p7 = Profiles.p7;
      expect(p7.place, NetworkPlace.away);
      expect(
        p7.connections.map((c) => c.id),
        Profiles.p1.connections.map((c) => c.id),
      );

      ConnectionBehaviour away(String id) => p7.behaviourOf(id);
      expect(away(WorldIds.jellyfin), ConnectionBehaviour.didNotAnswer);
      expect(away(WorldIds.bazarr), ConnectionBehaviour.didNotAnswer);
      expect(away(WorldIds.qbittorrent), ConnectionBehaviour.refusesKey);
      for (final homeOnly in const [
        WorldIds.lidarr,
        WorldIds.prowlarr,
        WorldIds.sabnzbd,
        WorldIds.truenas,
        WorldIds.dockge,
      ]) {
        expect(
          away(homeOnly),
          ConnectionBehaviour.didNotAnswer,
          reason: homeOnly,
        );
      }
      expect(away(WorldIds.radarr4k), ConnectionBehaviour.answers);

      // Home-only composes with the behaviour underneath it: at home the
      // TrueNAS key is still read-only, and Lidarr answers.
      final home = p7.at(NetworkPlace.home);
      expect(home.behaviourOf(WorldIds.truenas), ConnectionBehaviour.readOnly);
      expect(home.behaviourOf(WorldIds.lidarr), ConnectionBehaviour.answers);
    });
  });

  group('the lens', () {
    test(
      'rests on the first connection unless the profile says otherwise',
      () async {
        final harness = await ProfileHarness.start(Profiles.p6);
        final container = harness.container();

        expect(
          container.read(activeInstanceProvider(ServiceKey.radarr))?.id,
          WorldIds.radarr,
        );
        expect(
          container.read(activeInstanceProvider(ServiceKey.sonarr))?.id,
          WorldIds.sonarr,
        );
      },
    );

    test('rests where withLens puts it', () async {
      final profile = Profiles.p6
          .withLens(ServiceKey.radarr, WorldIds.radarr4k)
          .withLens(ServiceKey.sonarr, WorldIds.sonarrAnime);
      final harness = await ProfileHarness.start(profile);
      final container = harness.container();

      expect(profile.lensOn(ServiceKey.radarr)?.id, WorldIds.radarr4k);
      expect(
        container.read(activeInstanceProvider(ServiceKey.radarr))?.id,
        WorldIds.radarr4k,
      );
      expect(
        container.read(activeInstanceProvider(ServiceKey.sonarr))?.id,
        WorldIds.sonarrAnime,
      );
    });

    test('withLens refuses a connection of another service', () {
      expect(
        () => Profiles.p6.withLens(ServiceKey.radarr, WorldIds.sonarr),
        throwsArgumentError,
      );
    });
  });

  group('variants', () {
    test('withBehaviour changes one connection and leaves the rest', () {
      final dark = Profiles.p1.withBehaviour(
        WorldIds.radarr4k,
        ConnectionBehaviour.didNotAnswer,
      );
      expect(
        dark.behaviourOf(WorldIds.radarr4k),
        ConnectionBehaviour.didNotAnswer,
      );
      expect(dark.behaviourOf(WorldIds.radarr), ConnectionBehaviour.answers);
      expect(
        Profiles.p1.behaviourOf(WorldIds.radarr4k),
        ConnectionBehaviour.answers,
      );
    });

    test('without removes a service and its lens', () {
      final noSeerr = Profiles.p1.without(ServiceKey.seerr);
      expect(noSeerr.has(ServiceKey.seerr), isFalse);
      expect(noSeerr.settings.isServiceConfigured(ServiceKey.seerr), isFalse);
    });

    test('withConnection adds a World-B service', () {
      final withNpm = Profiles.p1.withConnection(
        WorldConnections.npm.withBehaviour(ConnectionBehaviour.readOnly),
      );
      expect(
        withNpm.settings.isServiceConfigured(ServiceKey.nginxProxyManager),
        isTrue,
      );
      expect(withNpm.behaviourOf('npm'), ConnectionBehaviour.readOnly);
    });
  });
}
