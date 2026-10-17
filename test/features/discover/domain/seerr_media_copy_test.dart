import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/domain/seerr_arr_server.dart';
import 'package:cupola/features/discover/domain/seerr_media_copy.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

void main() {
  const hd = SeerrArrServer(
    service: ServiceKey.radarr,
    id: 0,
    name: 'Radarr',
    isDefault: true,
    hostname: 'nas.home.arpa',
    port: 7878,
  );
  const uhd = SeerrArrServer(
    service: ServiceKey.radarr,
    id: 1,
    name: 'Radarr 4K',
    is4k: true,
    isDefault: true,
    hostname: 'nas.home.arpa',
    port: 7879,
  );
  const spare = SeerrArrServer(
    service: ServiceKey.radarr,
    id: 2,
    name: 'Radarr spare',
    hostname: 'nas.home.arpa',
    port: 7880,
  );
  const connections = [
    ServiceInstance(
      id: 'radarr',
      service: ServiceKey.radarr,
      url: 'http://nas.home.arpa:7878',
      credential: 'key',
    ),
    ServiceInstance(
      id: 'radarr-4k00001',
      service: ServiceKey.radarr,
      label: '4K',
      url: 'https://nas.home.arpa:7879',
      credential: 'key',
    ),
  ];
  String title(ServiceInstance connection) =>
      connection.label.isEmpty ? 'Radarr' : 'Radarr\u00A0· ${connection.label}';

  group('SeerrMediaCopy.fromMediaInfo', () {
    test('reads both copies, the standard one first', () {
      final copies = SeerrMediaCopy.fromMediaInfo({
        'serviceId': 0,
        'serviceId4k': 1,
        'externalServiceId': 6,
        'externalServiceId4k': 9,
      });

      expect(copies.map((c) => (c.is4k, c.externalId, c.serverId)), [
        (false, 6, 0),
        (true, 9, 1),
      ]);
    });

    test('a title only in 4K still has its copy', () {
      // `externalServiceId` alone read nothing here, and Manage drew no
      // Media section for it.
      final copies = SeerrMediaCopy.fromMediaInfo({
        'externalServiceId': null,
        'externalServiceId4k': 3,
        'serviceId4k': 1,
      });

      expect(copies.single.is4k, isTrue);
      expect(copies.single.externalId, 3);
    });

    test('no arr row, no copy', () {
      expect(SeerrMediaCopy.fromMediaInfo(null), isEmpty);
      expect(SeerrMediaCopy.fromMediaInfo({'status': 5}), isEmpty);
    });
  });

  group('SeerrBoundCopy', () {
    test('a 4K copy binds to the 4K server and its connection', () {
      final bound = SeerrBoundCopy.of(
        const SeerrMediaCopy(is4k: true, externalId: 9, serverId: 1),
        arr: ServiceKey.radarr,
        servers: const [hd, uhd],
        connections: connections,
      );

      expect(bound.server, same(uhd));
      expect(bound.connection?.id, 'radarr-4k00001');
      expect(bound.serverName(connectionTitle: title), 'Radarr\u00A0· 4K');
    });

    test('a row with no server id means the default server of its copy', () {
      final bound = SeerrBoundCopy.of(
        const SeerrMediaCopy(is4k: false, externalId: 6),
        arr: ServiceKey.radarr,
        servers: const [uhd, hd],
        connections: connections,
      );

      expect(bound.server, same(hd));
      expect(bound.connection?.id, 'radarr');
    });

    test('a server Cupola has no connection to is Seerr\'s alone', () {
      final bound = SeerrBoundCopy.of(
        const SeerrMediaCopy(is4k: false, externalId: 6, serverId: 2),
        arr: ServiceKey.radarr,
        servers: const [hd, uhd, spare],
        connections: connections,
      );

      expect(bound.connection, isNull);
      expect(bound.isKnownOnlyToSeerr, isTrue);
      expect(bound.serverName(connectionTitle: title), 'Radarr spare');
    });

    test('servers not read: unknown, named by its kind', () {
      final bound = SeerrBoundCopy.of(
        const SeerrMediaCopy(is4k: true, externalId: 9, serverId: 1),
        arr: ServiceKey.radarr,
        servers: null,
        connections: connections,
      );

      expect(bound.serversRead, isFalse);
      expect(bound.server, isNull);
      expect(bound.isKnownOnlyToSeerr, isFalse);
      expect(bound.serverName(connectionTitle: title), '4K Radarr');
    });
  });
}
