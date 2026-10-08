import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/domain/seerr_arr_server.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Seerr's settings for a Radarr, as `GET /api/v1/settings/radarr` sends it.
Map<String, dynamic> _settings({
  int id = 0,
  String name = 'Radarr',
  String hostname = 'nas.home.arpa',
  int port = 7878,
  bool useSsl = false,
  String baseUrl = '',
  bool is4k = false,
  bool isDefault = true,
}) => {
  'id': id,
  'name': name,
  'hostname': hostname,
  'port': port,
  'apiKey': 'not-for-cupola',
  'useSsl': useSsl,
  'baseUrl': baseUrl,
  'activeProfileId': is4k ? 7 : 4,
  'activeProfileName': is4k ? 'Ultra-HD' : 'HD-1080p',
  'activeDirectory': is4k ? '/films-4k' : '/films',
  'is4k': is4k,
  'isDefault': isDefault,
};

SeerrArrServer _server(Map<String, dynamic> json) =>
    SeerrArrServer.fromSettingsJson(json, service: ServiceKey.radarr);

ServiceInstance _radarr(
  String url, {
  String id = 'radarr',
  String label = '',
}) => ServiceInstance(
  id: id,
  service: ServiceKey.radarr,
  label: label,
  url: url,
  credential: 'key',
);

SeerrRequest _request({
  String type = 'movie',
  bool is4k = false,
  int? serverId,
  int? profileId,
  String? rootFolder,
}) => SeerrRequest(
  id: 1,
  status: RequestStatus.pendingApproval,
  createdAt: '2026-09-30T10:00:00Z',
  type: type,
  is4k: is4k,
  serverId: serverId,
  profileId: profileId,
  rootFolder: rootFolder,
);

void main() {
  final hd = _server(_settings());
  final uhd = _server(
    _settings(id: 1, name: 'Radarr 4K', port: 7879, useSsl: true, is4k: true),
  );
  final spare = _server(
    _settings(id: 2, name: 'Radarr spare', port: 7880, isDefault: false),
  );

  group('SeerrArrServer.fromSettingsJson', () {
    test('reads the server, its address and its defaults', () {
      expect(uhd.id, 1);
      expect(uhd.name, 'Radarr 4K');
      expect(uhd.is4k, isTrue);
      expect(uhd.isDefault, isTrue);
      expect(uhd.hostname, 'nas.home.arpa');
      expect(uhd.port, 7879);
      expect(uhd.activeProfileId, 7);
      expect(uhd.activeDirectory, '/films-4k');
      expect(uhd.service, ServiceKey.radarr);
    });
  });

  group('reaches', () {
    test('the same host, port and base path is the same server', () {
      expect(hd.reaches(_radarr('http://nas.home.arpa:7878')), isTrue);
      expect(hd.reaches(_radarr('http://NAS.home.arpa:7878/')), isTrue);
    });

    test('another port is another server', () {
      expect(hd.reaches(_radarr('http://nas.home.arpa:7879')), isFalse);
    });

    test('the base path has to agree, whatever its slashes', () {
      final proxied = _server(_settings(port: 443, baseUrl: '/radarr/'));
      expect(proxied.reaches(_radarr('https://nas.home.arpa/radarr')), isTrue);
      expect(proxied.reaches(_radarr('https://nas.home.arpa')), isFalse);
      expect(hd.reaches(_radarr('http://nas.home.arpa:7878/radarr')), isFalse);
    });

    test('a container name, with no Seerr address to read it against, '
        'does not match', () {
      final byContainer = _server(_settings(hostname: 'radarr'));
      expect(
        byContainer.reaches(_radarr('http://nas.home.arpa:7878')),
        isFalse,
      );
    });

    test('a connection to another kind of service never matches', () {
      const sonarr = ServiceInstance(
        id: 'sonarr',
        service: ServiceKey.sonarr,
        url: 'http://nas.home.arpa:7878',
        credential: 'key',
      );
      expect(hd.reaches(sonarr), isFalse);
    });

    test('connectionIn finds the configured connection to the server', () {
      final connections = [
        _radarr('http://nas.home.arpa:7878'),
        _radarr('https://nas.home.arpa:7879', id: 'radarr-4k', label: '4K'),
      ];
      expect(uhd.connectionIn(connections)?.id, 'radarr-4k');
      expect(spare.connectionIn(connections), isNull);
    });
  });

  group('reaches, read against the Seerr it came from', () {
    const seerr = 'http://nas.home.arpa:5055';

    /// A server as Seerr in Docker knows it: by container, with [key].
    SeerrArrServer inDocker({
      String hostname = 'radarr',
      int port = 7878,
      String key = 'key-hd',
      bool is4k = false,
    }) => SeerrArrServer.fromSettingsJson(
      {..._settings(hostname: hostname, port: port, is4k: is4k), 'apiKey': key},
      service: ServiceKey.radarr,
      seenFrom: seerr,
    );

    ServiceInstance radarr(
      String url, {
      String id = 'radarr',
      String key = '',
    }) => ServiceInstance(
      id: id,
      service: ServiceKey.radarr,
      url: url,
      credential: key,
    );

    test("a container name is looked for at Seerr's own host", () {
      expect(
        inDocker().reaches(radarr('http://nas.home.arpa:7878', key: 'key-hd')),
        isTrue,
      );
      expect(
        inDocker(
          hostname: 'localhost',
        ).reaches(radarr('http://nas.home.arpa:7878')),
        isTrue,
        reason: 'no key on the connection: the proposal is all there is',
      );
      expect(
        inDocker().reaches(radarr('http://nas.home.arpa:7879', key: 'key-hd')),
        isTrue,
        reason: 'the same key is the same server, at any address',
      );
    });

    test('a different key at the proposed address is another server', () {
      // Radarr 4K listens on 7878 in its container and is published on 7879:
      // Seerr's host with 7878 is where the other Radarr answers.
      final uhd = inDocker(hostname: 'radarr-4k', key: 'key-4k', is4k: true);
      expect(
        uhd.reaches(radarr('http://nas.home.arpa:7878', key: 'key-hd')),
        isFalse,
      );
      expect(
        uhd.connectionIn([radarr('http://nas.home.arpa:7878', key: 'key-hd')]),
        isNull,
      );
    });

    test('the key decides between two Radarrs near Seerr', () {
      final connections = [
        radarr('http://nas.home.arpa:7878', key: 'key-hd'),
        radarr('https://nas.home.arpa:7879', id: 'radarr-4k', key: 'key-4k'),
      ];
      expect(inDocker().connectionIn(connections)?.id, 'radarr');
      expect(
        inDocker(
          hostname: 'radarr-4k',
          key: 'key-4k',
          is4k: true,
        ).connectionIn(connections)?.id,
        'radarr-4k',
      );
    });

    test('a key match comes before an address match', () {
      final connections = [
        radarr('http://nas.home.arpa:7878', key: 'stale'),
        radarr('https://radarr.example.com', id: 'radarr-proxy', key: 'key-hd'),
      ];
      final server = SeerrArrServer.fromSettingsJson(
        {..._settings(), 'apiKey': 'key-hd'},
        service: ServiceKey.radarr,
        seenFrom: seerr,
      );
      expect(server.connectionIn(connections)?.id, 'radarr-proxy');
      // Without the key's match, the shared address still is the server.
      expect(server.connectionIn([connections.first])?.id, 'radarr');
    });

    test("a real address is never moved to Seerr's host", () {
      final elsewhere = inDocker(hostname: 'radarr.example.com', port: 443);
      expect(elsewhere.reaches(radarr('http://nas.home.arpa:443')), isFalse);
    });

    test('the key it holds is never printed', () {
      final server = inDocker(key: 'sentinel-key-5c09d2');
      expect(server.toString(), isNot(contains('sentinel-key-5c09d2')));
    });
  });

  group('seerrTargetServer', () {
    final servers = [hd, uhd, spare];

    test('a request naming no server goes to the default of its copy', () {
      expect(seerrTargetServer(servers, serverId: null, is4k: false), same(hd));
      expect(seerrTargetServer(servers, serverId: null, is4k: true), same(uhd));
    });

    test('a request naming a server goes there', () {
      expect(seerrTargetServer(servers, serverId: 2, is4k: false), same(spare));
    });

    test('no server for the copy, or a server Seerr no longer has: none', () {
      expect(seerrTargetServer([hd], serverId: null, is4k: true), isNull);
      expect(seerrTargetServer(servers, serverId: 9, is4k: false), isNull);
    });
  });

  group('SeerrApproveTarget', () {
    final connections = [
      _radarr('http://nas.home.arpa:7878'),
      _radarr('https://nas.home.arpa:7879', id: 'radarr-4k', label: '4K'),
    ];
    String title(ServiceInstance connection) =>
        connection.label.isEmpty ? 'Radarr' : 'Radarr · ${connection.label}';

    test('a 4K request goes to the 4K server and its connection', () {
      final target = SeerrApproveTarget.of(
        _request(is4k: true),
        servers: [hd, uhd],
        connections: connections,
      );

      expect(target.server, same(uhd));
      expect(target.connection?.id, 'radarr-4k');
      expect(target.profileId, 7);
      expect(target.rootFolder, '/films-4k');
      expect(
        target.confirmation('Sintel', connectionTitle: title),
        'Sintel goes to Radarr · 4K and starts downloading.',
      );
    });

    test("the request's own profile and folder win over the server's", () {
      final target = SeerrApproveTarget.of(
        _request(profileId: 9, rootFolder: '/archive'),
        servers: [hd],
        connections: connections,
      );

      expect(target.profileId, 9);
      expect(target.rootFolder, '/archive');
    });

    test('a server Cupola has no connection to says so, plainly', () {
      final target = SeerrApproveTarget.of(
        _request(serverId: 2),
        servers: [hd, uhd, spare],
        connections: connections,
      );

      expect(target.server, same(spare));
      expect(target.connection, isNull);
      expect(
        target.confirmation('Charge', connectionTitle: title),
        'Charge goes to Radarr spare and starts downloading. Cupola has no '
        'connection to that server.',
      );
    });

    test('Seerr with no server for the copy: nothing will download', () {
      final target = SeerrApproveTarget.of(
        _request(is4k: true),
        servers: [hd],
        connections: connections,
      );

      expect(target.hasNoServer, isTrue);
      expect(
        target.confirmation('Sintel', connectionTitle: title),
        'Seerr has no 4K Radarr to send Sintel to, so nothing will download.',
      );
    });

    test('a list that could not be read leaves the server unknown', () {
      final target = SeerrApproveTarget.of(_request(type: 'tv'), servers: null);

      expect(target.arr, ServiceKey.sonarr);
      expect(target.hasNoServer, isFalse);
      expect(
        target.confirmation('Cosmos Laundromat', connectionTitle: title),
        "Cosmos Laundromat goes to Seerr's Sonarr and starts downloading.",
      );
    });

    test('an approved row says where the request went, as the confirmation '
        'named it', () {
      expect(
        SeerrApproveTarget.of(
          _request(is4k: true),
          servers: [hd, uhd],
          connections: connections,
        ).approvedLine(connectionTitle: title),
        'Approved · sent to Radarr · 4K',
      );
      expect(
        SeerrApproveTarget.of(
          _request(serverId: 2),
          servers: [hd, uhd, spare],
          connections: connections,
        ).approvedLine(connectionTitle: title),
        'Approved · sent to Radarr spare',
      );
      expect(
        SeerrApproveTarget.of(
          _request(is4k: true),
          servers: [hd],
          connections: connections,
        ).approvedLine(connectionTitle: title),
        'Approved · Seerr has no 4K Radarr for it',
      );
      expect(
        SeerrApproveTarget.of(
          _request(type: 'tv'),
          servers: null,
        ).approvedLine(connectionTitle: title),
        "Approved · sent to Seerr's Sonarr",
      );
    });

    test('no confirmation leans on an em dash', () {
      final targets = [
        SeerrApproveTarget.of(
          _request(),
          servers: [hd],
          connections: connections,
        ),
        SeerrApproveTarget.of(_request(serverId: 2), servers: [spare]),
        SeerrApproveTarget.of(_request(is4k: true), servers: [hd]),
        SeerrApproveTarget.of(_request(), servers: null),
      ];
      for (final target in targets) {
        expect(
          target.confirmation('Sintel', connectionTitle: title),
          isNot(contains('—')),
        );
      }
    });
  });
}
