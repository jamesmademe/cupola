/// A download no arr's queue claims is named by asking the arrs.
///
/// The arr the client's category points at, or every one set up; their own
/// reading, a library title first; the raw name when none can read it. Each
/// name is asked once and kept, and a read sends a few at a time.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/media_names.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/profiles/profiles.dart';

const _gb = 1024 * 1024 * 1024;

WorldDownload _byHand(
  String release, {
  required String id,
  String client = 'qbittorrent',
}) => WorldDownload(
  id: id,
  release: release,
  client: client,
  state: DownloadState.downloading,
  progress: 0.2,
  size: _gb,
  speed: 1024,
);

final _tears = _byHand(
  'Tears.of.Steel.2012.2160p.WEB',
  id: 'd4a1d4c5f6a70819304b5c6d7e8f901234567901',
);
final _iso = _byHand(
  'ubuntu-24.10-desktop-amd64.iso',
  id: 'd4a1d4c5f6a70819304b5c6d7e8f901234567902',
);

int _parses(ProfileHarness harness, String instanceId) => harness.network
    .requestsTo(instanceId)
    .where((r) => r.path.endsWith('/parse'))
    .length;

void main() {
  test('P1, In flight: a torrent added by hand is named by the Radarr that '
      'holds it, asked once', () async {
    final harness = await ProfileHarness.start(
      Profiles.p1.withDownloads([_tears]),
    );
    final container = harness.container(retry: (_, _) => null);

    final queue = await container.read(servicesQueueProvider.future);
    final row = queue.items.singleWhere((item) => item.id == _tears.id);
    expect(row.service, ServiceKey.qbittorrent);
    expect(
      row.names,
      const MediaNames(
        title: 'Tears of Steel',
        machineName: 'Tears.of.Steel.2012.2160p.WEB',
        machineKind: MachineNameKind.release,
      ),
    );
    // The first Radarr held it: nobody else was asked.
    expect(_parses(harness, WorldIds.radarr), 1);
    expect(_parses(harness, WorldIds.sonarr), 0);

    // The answer is kept: the next read asks nobody.
    container.invalidate(servicesQueueProvider);
    await container.read(servicesQueueProvider.future);
    expect(_parses(harness, WorldIds.radarr), 1);
  });

  test('P1: a name no arr can read stays its raw self, with no second '
      'name', () async {
    final harness = await ProfileHarness.start(
      Profiles.p1.withDownloads([_iso]),
    );
    final container = harness.container(retry: (_, _) => null);

    final queue = await container.read(servicesQueueProvider.future);
    final row = queue.items.singleWhere((item) => item.id == _iso.id);
    expect(row.names, const MediaNames.raw('ubuntu-24.10-desktop-amd64.iso'));
    // Every arr was asked: two Radarr, Sonarr and Lidarr.
    for (final id in [
      WorldIds.radarr,
      WorldIds.radarr4k,
      WorldIds.sonarr,
      WorldIds.lidarr,
    ]) {
      expect(_parses(harness, id), 1, reason: id);
    }
  });

  test('P1: a read sends at most six names to the arrs, and the rest are '
      'asked on the next', () async {
    final harness = await ProfileHarness.start(
      Profiles.p1.withDownloads([
        for (var i = 0; i < 4; i++)
          _byHand(
            'linux-$i.iso',
            id: 'e5a1d4c5f6a70819304b5c6d7e8f9012345679${i.toString().padLeft(2, '0')}',
          ),
      ]),
    );
    final container = harness.container(retry: (_, _) => null);

    int parses() => [
      WorldIds.radarr,
      WorldIds.radarr4k,
      WorldIds.sonarr,
      WorldIds.lidarr,
    ].fold(0, (sum, id) => sum + _parses(harness, id));

    await container.read(servicesQueueProvider.future);
    expect(parses(), downloadNameParseCap);

    container.invalidate(servicesQueueProvider);
    await container.read(servicesQueueProvider.future);
    expect(parses(), 2 * downloadNameParseCap);
  });

  test('P1, qBittorrent\'s own list: a download an arr claims is its item, '
      'one it does not is asked about, one nobody reads is raw', () async {
    final harness = await ProfileHarness.start(Profiles.p1);
    final container = harness.container(retry: (_, _) => null);

    final names = await container.read(
      downloadClientNamesProvider((
        service: ServiceKey.qbittorrent,
        instanceId: WorldIds.qbittorrent,
      )).future,
    );

    // In Radarr's queue: its title, beside qBittorrent's own name for it.
    final sprite = names[WorldDownloads.spriteFright.id]!;
    expect(sprite.title, 'Sprite Fright');
    expect(sprite.machineName, WorldDownloads.spriteFright.release);

    // Seeding, long imported: Radarr reads the name and holds the film.
    final sintel = names[WorldDownloads.sintelSeeding.id]!;
    expect(sintel.title, 'Sintel');
    expect(sintel.source, MediaTitleSource.library);
    expect(sintel.machineName, WorldDownloads.sintelSeeding.release);

    expect(
      names[WorldDownloads.ubuntu.id],
      MediaNames.raw(WorldDownloads.ubuntu.release),
    );
  });
}
