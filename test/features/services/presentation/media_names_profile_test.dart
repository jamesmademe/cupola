/// Every row about a copy knows what the copy is and which copy it is.
///
/// In flight, Activity's queue, history and blocklist, on the profiles: the
/// arr's title and the release or file string as the service returned it. A
/// matched In flight row keeps its release name; a torrent no arr claims is its
/// raw name until something recognises it.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/media_names.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/profiles/profiles.dart';

void main() {
  test('P1, In flight: a matched row keeps the arr\'s title and its '
      'release', () async {
    final harness = await ProfileHarness.start(Profiles.p1);
    final container = harness.container(retry: (_, _) => null);
    final queue = await container.read(servicesQueueProvider.future);

    final sprite = queue.items.singleWhere(
      (item) =>
          item.downloadId?.toLowerCase() == WorldDownloads.spriteFright.id,
    );
    // Joined to its torrent, and still the arr's row.
    expect(sprite.clientService, ServiceKey.qbittorrent);
    expect(
      sprite.names,
      const MediaNames(
        title: 'Sprite Fright',
        machineName: 'Sprite.Fright.2021.1080p.WEB',
        machineKind: MachineNameKind.release,
      ),
    );

    final cosmos = queue.items.singleWhere(
      (item) =>
          item.downloadId?.toLowerCase() == WorldDownloads.cosmosS02E04.id,
    );
    expect(cosmos.names.title, startsWith('Cosmos Laundromat\u00A0· S'));
    expect(cosmos.names.machineName, 'Cosmos.Laundromat.S02E04.1080p.WEB');
  });
}
