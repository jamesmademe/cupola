/// Activity matches a queue record to its download the way Home does.
///
/// It had no join at all: the client was a name on the record, and a torrent
/// qBittorrent called broken read "Downloading" because its arr still said
/// so, while Home had already made it a decision.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/activity/presentation/activity_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/profiles/profiles.dart';

const _gb = 1024 * 1024 * 1024;

/// An upgrade Radarr grabbed whose torrent qBittorrent can no longer write:
/// Radarr still calls it downloading.
const _qbError = WorldDownload(
  id: 'a1f0c3d4e5f60718293a4b5c6d7e8f9012345611',
  release: 'Coffee.Run.2020.2160p.WEB',
  client: 'qbittorrent',
  state: DownloadState.failed,
  progress: 0.55,
  size: 3 * _gb,
  arr: WorldIds.radarr,
  title: WorldTitles.coffeeRun,
);

GlobalActivityItem _record(ActivityFeed feed, String downloadId) =>
    feed.items.singleWhere(
      (item) =>
          item.kind == GlobalActivityKind.queue &&
          '${item.raw?['downloadId']}'.toLowerCase() ==
              downloadId.toLowerCase(),
    );

void main() {
  test('P1: a record meets its client\'s row, and the client\'s fault is '
      'the record\'s', () async {
    final harness = await ProfileHarness.start(
      Profiles.p1.withDownloads([_qbError]),
    );
    final container = harness.container(retry: (_, _) => null);
    final feed = await container.read(globalNowItemsProvider.future);

    final coffeeRun = _record(feed, _qbError.id);
    expect(coffeeRun.download?.clientService, ServiceKey.qbittorrent);
    expect(coffeeRun.status.pipeline, MediaPipeline.failed);
    expect(coffeeRun.status.tone, StatusTone.warning);

    // A healthy torrent lends its progress and leaves the state alone.
    final spriteFright = _record(feed, WorldDownloads.spriteFright.id);
    expect(spriteFright.download?.clientService, ServiceKey.qbittorrent);
    expect(spriteFright.status.pipeline, MediaPipeline.downloading);
    expect(spriteFright.status.progress, 0.62);

    // The 4K's records meet SABnzbd's jobs, on the 4K's own connection.
    final elephants = _record(feed, WorldDownloads.elephantsDream4k.id);
    expect(elephants.instanceId, WorldIds.radarr4k);
    expect(elephants.download?.clientService, ServiceKey.sabnzbd);

    expect(feed.clients.answered.map((source) => source.service).toSet(), {
      ServiceKey.qbittorrent,
      ServiceKey.sabnzbd,
    });
  });

  test('P1, SABnzbd dark: the 4K\'s records keep the arr\'s word, and the '
      'client is kept as one that did not answer', () async {
    final harness = await ProfileHarness.start(
      Profiles.p1.withBehaviour(
        WorldIds.sabnzbd,
        ConnectionBehaviour.didNotAnswer,
      ),
    );
    final container = harness.container(retry: (_, _) => null);
    final feed = await container.read(globalNowItemsProvider.future);

    final elephants = _record(feed, WorldDownloads.elephantsDream4k.id);
    expect(elephants.download, isNull);
    expect(elephants.status.pipeline, MediaPipeline.downloading);
    expect(feed.clients.failed.keys.map((source) => source.service), [
      ServiceKey.sabnzbd,
    ]);
    // Not a row out of the list: the 4K answered, and is not named as
    // missing.
    expect(feed.failures, isEmpty);
  });
}
