import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

ServiceInstance _radarr(String id, {String label = '', String url = ''}) =>
    ServiceInstance(
      id: id,
      service: ServiceKey.radarr,
      label: label,
      url: url,
      credential: 'key-$id',
    );

void main() {
  group('lookups', () {
    final settings = SettingsModel(
      instances: [
        _radarr('radarr', label: '4K', url: 'https://nas:7878'),
        _radarr('radarr-aaa1111', label: 'HD', url: 'https://nas:7879'),
        const ServiceInstance(
          id: 'sonarr',
          service: ServiceKey.sonarr,
          url: 'https://nas:8989',
          credential: 'k',
        ),
      ],
    );

    test('instancesOf keeps the user order and excludes other services', () {
      expect(settings.instancesOf(ServiceKey.radarr).map((i) => i.label), [
        '4K',
        'HD',
      ]);
      expect(settings.instancesOf(ServiceKey.sonarr), hasLength(1));
      expect(settings.instancesOf(ServiceKey.plex), isEmpty);
    });

    test('primaryOf is the first one, not the lowest id', () {
      expect(settings.primaryOf(ServiceKey.radarr)?.label, '4K');
      expect(settings.primaryOf(ServiceKey.plex), isNull);
    });

    test('hasMultipleInstances is the question the UI actually asks', () {
      expect(settings.hasMultipleInstances(ServiceKey.radarr), isTrue);
      expect(settings.hasMultipleInstances(ServiceKey.sonarr), isFalse);
      expect(settings.hasMultipleInstances(ServiceKey.plex), isFalse);
    });

    test('instanceById finds across services', () {
      expect(settings.instanceById('radarr-aaa1111')?.label, 'HD');
      expect(settings.instanceById('nope'), isNull);
    });

    test('a half-filled slot is not a connection the UI may offer', () {
      // The state between "Add another Radarr" and typing an address. It is a
      // real entry in the list — the settings form is looking at it — and it is
      // not something any other surface may count, name or point a lens at.
      final adding = SettingsModel(
        instances: [
          _radarr('radarr', label: '4K', url: 'https://nas:7878'),
          const ServiceInstance(
            id: 'radarr-bbb2222',
            service: ServiceKey.radarr,
          ),
        ],
      );

      expect(adding.instancesOf(ServiceKey.radarr), hasLength(2));
      expect(adding.configuredInstancesOf(ServiceKey.radarr), hasLength(1));
      // The whole point: the badge, the app-bar label and every provenance
      // chip stay off until the second connection can actually answer.
      expect(adding.hasMultipleInstances(ServiceKey.radarr), isFalse);
    });
  });

  group('the flat names resolve to the first instance', () {
    final settings = SettingsModel(
      instances: [
        _radarr('radarr', label: '4K', url: 'https://first:7878'),
        _radarr('radarr-bbb2222', label: 'HD', url: 'https://second:7879'),
      ],
    );

    test('urlFor and radarrUrl agree, and both mean the first', () {
      expect(settings.radarrUrl, 'https://first:7878');
      expect(settings.urlFor(ServiceKey.radarr), 'https://first:7878');
      expect(settings.radarrApiKey, 'key-radarr');
    });

    test('a service with no instance reads empty, never throws', () {
      const empty = SettingsModel();
      for (final service in ServiceKey.values) {
        expect(empty.urlFor(service), '');
        expect(empty.apiKeyFor(service), '');
        expect(empty.usernameFor(service), '');
        expect(empty.isServiceConfigured(service), isFalse);
      }
    });

    test('the viewer is per instance, and reads off the first', () {
      final withViewer = settings.copyWithViewer(ServiceKey.jellyfin, 'u-1');
      expect(withViewer.jellyfinUserId, 'u-1');
      // Radarr's instances are untouched by a Jellyfin write.
      expect(withViewer.instancesOf(ServiceKey.radarr), hasLength(2));
    });
  });

  group('copyWithInstance', () {
    test('replaces by id and keeps the position', () {
      final settings = SettingsModel(
        instances: [
          _radarr('radarr', label: '4K'),
          _radarr('radarr-c33', label: 'HD'),
        ],
      );
      final edited = settings.copyWithInstance(
        settings.instanceById('radarr')!.copyWith(label: 'UHD'),
      );

      expect(edited.instances.map((i) => i.label), ['UHD', 'HD']);
      expect(edited.instances, hasLength(2));
    });

    test('appends an unknown id rather than replacing anything', () {
      final settings = SettingsModel(
        instances: [_radarr('radarr', label: '4K')],
      );
      final edited = settings.copyWithInstance(
        _radarr('radarr-d44', label: 'HD'),
      );

      expect(edited.instances.map((i) => i.label), ['4K', 'HD']);
    });
  });

  group('copyWithoutInstance', () {
    test('drops the one named and leaves the rest in order', () {
      final settings = SettingsModel(
        instances: [
          _radarr('radarr', label: '4K'),
          _radarr('radarr-e55', label: 'HD'),
          _radarr('radarr-f66', label: 'Anime'),
        ],
      );
      final edited = settings.copyWithoutInstance('radarr-e55');
      expect(edited.instances.map((i) => i.label), ['4K', 'Anime']);
    });

    test('removing the first promotes the next to primary', () {
      final settings = SettingsModel(
        instances: [
          _radarr('radarr', label: '4K'),
          _radarr('radarr-g77', label: 'HD'),
        ],
      );
      final edited = settings.copyWithoutInstance('radarr');

      expect(edited.primaryOf(ServiceKey.radarr)?.label, 'HD');
      // The survivor keeps its own id, so its stored values stay where they are.
      expect(edited.primaryOf(ServiceKey.radarr)?.id, 'radarr-g77');
    });

    test('an unknown id changes nothing', () {
      final settings = SettingsModel(instances: [_radarr('radarr')]);
      expect(
        settings.copyWithoutInstance('nope').instances,
        settings.instances,
      );
    });
  });

  group('an empty write mints nothing', () {
    test('walking every service with blanks leaves the list empty', () {
      // Exactly what the load path does on a fresh install: it iterates the
      // whole enum writing whatever it read, and reads '' seventeen times.
      var settings = const SettingsModel();
      for (final service in ServiceKey.values) {
        settings = settings.copyWithService(service, url: '', apiKey: '');
      }
      expect(settings.instances, isEmpty);
    });

    test('but a credential with no address is still recorded', () {
      // Half-configured is a state the user can see and fix; silently dropping
      // the key they pasted is not.
      final settings = const SettingsModel().copyWithService(
        ServiceKey.radarr,
        apiKey: 'k',
      );
      expect(settings.apiKeyFor(ServiceKey.radarr), 'k');
      expect(settings.isServiceConfigured(ServiceKey.radarr), isFalse);
    });

    test('the first write takes the id whose keys predate this model', () {
      final settings = const SettingsModel().copyWithService(
        ServiceKey.nginxProxyManager,
        url: 'http://nas:81',
      );
      expect(settings.primaryOf(ServiceKey.nginxProxyManager)?.id, 'npm');
    });
  });

  group('isServiceConfigured asks all the instances', () {
    test('true when any one of them is set up', () {
      final settings = SettingsModel(
        instances: [
          const ServiceInstance(id: 'radarr', service: ServiceKey.radarr),
          _radarr('radarr-h88', url: 'https://nas:7879'),
        ],
      );
      expect(settings.isServiceConfigured(ServiceKey.radarr), isTrue);
    });

    test('false when none of them is', () {
      final settings = SettingsModel(
        instances: [
          const ServiceInstance(
            id: 'radarr',
            service: ServiceKey.radarr,
            credential: 'k',
          ),
        ],
      );
      expect(settings.isServiceConfigured(ServiceKey.radarr), isFalse);
    });
  });

  group('copyWithoutServiceExtras clears every instance of the service', () {
    test('two Jellyfin both lose their viewer', () {
      final settings = SettingsModel(
        instances: [
          const ServiceInstance(
            id: 'jellyfin',
            service: ServiceKey.jellyfin,
            url: 'https://a',
            credential: 'k',
            viewerId: 'u-1',
          ),
          const ServiceInstance(
            id: 'jellyfin-i99',
            service: ServiceKey.jellyfin,
            url: 'https://b',
            credential: 'k',
            viewerId: 'u-2',
          ),
        ],
      );
      final cleared = settings.copyWithoutServiceExtras(ServiceKey.jellyfin);
      expect(cleared.instancesOf(ServiceKey.jellyfin).map((i) => i.viewerId), [
        '',
        '',
      ]);
    });

    test('a service with no viewer to clear is left alone', () {
      final settings = SettingsModel(instances: [_radarr('radarr')]);
      expect(
        settings.copyWithoutServiceExtras(ServiceKey.radarr).instances,
        settings.instances,
      );
    });
  });

  group('certificates see instances, not services (ADR-6)', () {
    // The bug this fixes: the origin check used to iterate ServiceKey.values
    // and ask each service for *its* URL, so a second instance of the same
    // service behind the same reverse proxy was invisible. Removing either one
    // then forgot a pin the other still needed, and the next connection to
    // that origin silently reused a trust the user was never asked for again.
    SettingsModel behindOneProxy() => SettingsModel(
      instances: const [
        ServiceInstance(
          id: 'radarr',
          service: ServiceKey.radarr,
          url: 'https://proxy.lan:443/radarr-4k',
          credential: 'k',
        ),
        ServiceInstance(
          id: 'radarr-j00',
          service: ServiceKey.radarr,
          url: 'https://proxy.lan:443/radarr-hd',
          credential: 'k',
        ),
      ],
      trustedCertificates: {'https://proxy.lan:443': 'abc123'},
    );

    test('both instances are counted as users of the origin', () {
      final settings = behindOneProxy();
      expect(
        settings.instancesSharingOriginOf('https://proxy.lan:443/x'),
        hasLength(2),
      );
    });

    test('removing one keeps the pin the other still needs', () {
      final settings = behindOneProxy();
      final removed = settings
          .copyWithoutInstance('radarr')
          .copyWithoutUnusedCertificate('https://proxy.lan:443/radarr-4k');

      expect(removed.pinForUrl('https://proxy.lan:443/radarr-hd'), 'abc123');
    });

    test('removing the last one does forget it', () {
      final settings = behindOneProxy();
      final removed = settings
          .copyWithoutInstance('radarr')
          .copyWithoutInstance('radarr-j00')
          .copyWithoutUnusedCertificate('https://proxy.lan:443/radarr-4k');

      expect(removed.pinForUrl('https://proxy.lan:443/anything'), isNull);
    });

    test('a NON-primary instance alone keeps the pin alive', () {
      // The case that separates this from the old per-service check, and the
      // only one that actually proves the fix: Radarr's *first* instance is
      // somewhere else entirely, so asking "what URL does Radarr have" answers
      // with an origin that has nothing to do with this pin. The second
      // instance is the last thing behind the proxy, and it is invisible to
      // that question. The old code forgot the certificate here — and the next
      // service pointed at the proxy would have silently inherited the trust,
      // because pins are keyed by origin and nothing would prompt again.
      final settings = SettingsModel(
        instances: const [
          ServiceInstance(
            id: 'radarr',
            service: ServiceKey.radarr,
            url: 'https://direct.lan:7878',
            credential: 'k',
          ),
          ServiceInstance(
            id: 'radarr-k11',
            service: ServiceKey.radarr,
            url: 'https://proxy.lan:443/radarr-hd',
            credential: 'k',
          ),
          ServiceInstance(
            id: 'sonarr',
            service: ServiceKey.sonarr,
            url: 'https://proxy.lan:443/sonarr',
            credential: 'k',
          ),
        ],
        trustedCertificates: {'https://proxy.lan:443': 'abc123'},
      );

      final sonarrGone = settings
          .copyWithoutInstance('sonarr')
          .copyWithoutUnusedCertificate('https://proxy.lan:443/sonarr');

      expect(
        sonarrGone.pinForUrl('https://proxy.lan:443/radarr-hd'),
        'abc123',
        reason: 'the second Radarr is still reached through that certificate',
      );
    });

    test('connectionTitle drops a label the sibling took with it', () {
      // A label outlives what made it necessary: adding a second Radarr derives
      // a name for the first, and removing the second leaves that name behind.
      // Every badge and chip goes quiet again because they all ask
      // `hasMultipleInstances` first — `displayTitle` does not, so a sentence
      // built straight off it announced "Radarr \u00b7 7878" for the only Radarr
      // there is.
      final lone = SettingsModel(
        instances: [_radarr('radarr', label: '7878', url: 'https://nas:7878')],
      );

      expect(lone.instanceById('radarr')!.displayTitle, 'Radarr \u00b7 7878');
      expect(lone.connectionTitle('radarr', ServiceKey.radarr), 'Radarr');
    });

    test('connectionTitle names the connection once there are two', () {
      final pair = SettingsModel(
        instances: [
          _radarr('radarr', label: 'Home', url: 'https://home:7878'),
          _radarr('radarr-away11', label: 'Away', url: 'https://away:7878'),
        ],
      );

      expect(
        pair.connectionTitle('radarr-away11', ServiceKey.radarr),
        'Radarr \u00b7 Away',
      );
      // An id naming nothing \u2014 a queued job from a connection since removed \u2014
      // falls back to the service rather than to an empty sentence.
      expect(
        pair.connectionTitle('radarr-gone11', ServiceKey.radarr),
        'Radarr',
      );
    });

    test('servicesSharingOriginOf names the service once, not twice', () {
      // The sentence version: "forgetting this also affects Radarr, Radarr"
      // is how a per-instance list reads to someone who thinks in servers.
      expect(
        behindOneProxy().servicesSharingOriginOf('https://proxy.lan:443/x'),
        [ServiceKey.radarr],
      );
    });
  });
}
