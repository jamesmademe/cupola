import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/services/domain/in_flight.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Who decides a stall when an arr's record and its client's row meet: the
/// client, when it dates the last byte it received.
void main() {
  const stallMessage = 'The download is stalled with no connections';

  ServiceQueueItem arr({InFlightFault? fault, String? warning}) =>
      ServiceQueueItem(
        service: ServiceKey.radarr,
        id: '7',
        title: 'Big Buck Bunny',
        progress: 0.47,
        clientLabel: 'qBittorrent',
        downloadId: 'ABC',
        fault: fault,
        warning: warning,
      );

  ServiceQueueItem client(ServiceKey service, {InFlightFault? fault}) =>
      ServiceQueueItem(
        service: service,
        id: 'abc',
        title: 'Big.Buck.Bunny.2008.1080p.BluRay',
        progress: 0.47,
        clientLabel: service.title,
        clientService: service,
        fault: fault,
        swarmSeeds: 3,
      );

  ServiceQueueItem join(ServiceQueueItem a, ServiceQueueItem c) =>
      joinQueueSources(arr: [a], clients: [c]).single;

  test('an arr\'s stall is overruled by a torrent client that measured '
      'data arriving within 30 minutes', () {
    final row = join(
      arr(fault: InFlightFault.stalled, warning: stallMessage),
      client(ServiceKey.qbittorrent),
    );
    expect(row.fault, isNull);
    expect(row.warning, isNull);
  });

  test('a stall the client confirms keeps the arr\'s message and the '
      'swarm', () {
    final row = join(
      arr(fault: InFlightFault.stalled, warning: stallMessage),
      client(ServiceKey.transmission, fault: InFlightFault.stalled),
    );
    expect(row.fault, InFlightFault.stalled);
    expect(row.warning, stallMessage);
    expect(row.swarmSeeds, 3);
  });

  test('a usenet client dates nothing, so the arr\'s stall stands', () {
    final row = join(
      arr(fault: InFlightFault.stalled, warning: stallMessage),
      client(ServiceKey.sabnzbd),
    );
    expect(row.fault, InFlightFault.stalled);
  });

  test('an import the arr refuses is never overruled', () {
    final row = join(
      arr(fault: InFlightFault.needsImport),
      client(ServiceKey.qbittorrent),
    );
    expect(row.fault, InFlightFault.needsImport);
  });
}
