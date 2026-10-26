/// Every row about a copy knows what the copy is and which copy it is.
///
/// In flight, Activity's queue, history and blocklist, on the profiles: the
/// arr's title and the release or file string as the service returned it. A
/// matched In flight row keeps its release name; a torrent no arr claims is its
/// raw name until something recognises it.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/media_names.dart';
import 'package:cupola/features/activity/presentation/activity_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/profiles/profiles.dart';
import 'package:cupola/demo/world/service_fakes.dart';

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

  test('P1, Activity: the queue names the release, an import in the history '
      'the file it became, the blocklist the release it refused', () async {
    final harness = await ProfileHarness.start(Profiles.p1);
    harness.network.on(
      WorldIds.radarr,
      'GET',
      '/api/v3/blocklist',
      (r) => NetworkReply.json(
        pagedEnvelope(r, [
          {
            'id': 3,
            'movieId': 2,
            'movie': {'id': 2, 'title': 'Big Buck Bunny', 'year': 2008},
            'sourceTitle': 'Big.Buck.Bunny.2008.CAM',
            'date': harness.network.now.toUtc().toIso8601String(),
            'message': 'Manually blocklisted',
          },
        ]),
      ),
    );
    final container = harness.container(retry: (_, _) => null);

    final queue = await container.read(globalNowItemsProvider.future);
    final sprite = queue.items.singleWhere(
      (item) =>
          '${item.raw?['downloadId']}'.toLowerCase() ==
          WorldDownloads.spriteFright.id,
    );
    expect(sprite.names?.title, 'Sprite Fright');
    expect(sprite.names?.machineName, 'Sprite.Fright.2021.1080p.WEB');
    expect(sprite.names?.machineKind, MachineNameKind.release);

    final history = container.read(globalHistoryFeedProvider.notifier);
    await history.loading;
    final feed = container.read(globalHistoryFeedProvider).feed!;
    final coffeeRun = feed.items.singleWhere(
      (item) =>
          item.kind == GlobalActivityKind.history &&
          item.instanceId == WorldIds.radarr &&
          item.names?.title == 'Coffee Run',
    );
    expect(coffeeRun.names?.machineKind, MachineNameKind.file);
    expect(coffeeRun.names?.machineName, endsWith('Coffee Run (2020).mkv'));

    final blocked = await container.read(globalBlocklistItemsProvider.future);
    final bunny = blocked.items.single;
    expect(bunny.names?.title, 'Big Buck Bunny');
    expect(bunny.names?.machineName, 'Big.Buck.Bunny.2008.CAM');
    expect(bunny.names?.machineKind, MachineNameKind.release);
  });
}
