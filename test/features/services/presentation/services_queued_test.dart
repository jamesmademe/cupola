/// A download waiting its turn is queued, not moving: what each client and
/// each arr says of it, how a row joined to a client takes the client's word,
/// when a SABnzbd job starts, and what the counts make of it.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/media_names.dart';
import 'package:cupola/features/services/domain/in_flight.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/profiles/profiles.dart';

const _mb = 1024 * 1024;
const _gb = 1024 * 1024 * 1024;

/// A torrent somebody added to qBittorrent by hand, waiting behind the
/// client's active limit.
const _qbQueued = WorldDownload(
  id: 'a1f0c3d4e5f60718293a4b5c6d7e8f9012345621',
  release: 'Big.Buck.Bunny.2008.2160p.Remux',
  client: 'qbittorrent',
  state: DownloadState.queued,
  progress: 0,
  size: 4 * _gb,
);

/// The same, in Transmission's download wait.
const _transmissionQueued = WorldDownload(
  id: 'b2e1d4c5f6a70819304b5c6d7e8f901234567821',
  release: 'Agent.327.Operation.Barbershop.1080p',
  client: 'transmission',
  state: DownloadState.queued,
  progress: 0,
  size: _gb,
);

WorldDownload _nzbget(
  String id,
  String release,
  DownloadState state, {
  int speed = 0,
}) => WorldDownload(
  id: id,
  release: release,
  client: 'nzbget',
  state: state,
  progress: 0.3,
  size: 2 * _gb,
  speed: speed,
);

Future<ProviderContainer> _start(ConfigProfile profile) async {
  final harness = await ProfileHarness.start(profile);
  return harness.container(retry: (_, _) => null);
}

Future<List<ServiceQueueItem>> _items(ProviderContainer container) async =>
    (await container.read(servicesQueueProvider.future)).items;

ServiceQueueItem _of(List<ServiceQueueItem> items, String id) =>
    items.singleWhere((item) => item.id.toLowerCase() == id.toLowerCase());

/// A client's own row by the name of what it holds.
ServiceQueueItem _named(List<ServiceQueueItem> items, String release) =>
    items.singleWhere((item) => item.title == release);

ServiceQueueItem _byDownload(List<ServiceQueueItem> items, String id) => items
    .singleWhere((item) => item.downloadId?.toLowerCase() == id.toLowerCase());

/// A row as a source would build it, for the join.
ServiceQueueItem _row({
  required ServiceKey service,
  String id = 'x',
  String? downloadId,
  bool queued = false,
  bool held = false,
  InFlightFault? fault,
  int? startsInSeconds,
  int? rate,
  int? tmdbId,
  int? tvdbId,
  ServiceKey? clientService,
}) => ServiceQueueItem(
  service: service,
  id: id,
  title: 'Title',
  progress: queued ? 0 : 0.5,
  clientLabel: 'Client',
  downloadId: downloadId,
  queued: queued,
  held: held,
  fault: fault,
  startsInSeconds: startsInSeconds,
  rateBytesPerSecond: rate,
  tmdbId: tmdbId,
  tvdbId: tvdbId,
  clientService: clientService,
);

void main() {
  group('what each source says is queued', () {
    test('P1: Sintel waits its turn in SABnzbd, and an arr row joined to it '
        'takes the word', () async {
      final items = await _items(await _start(Profiles.p1));

      final sintel = _byDownload(items, WorldDownloads.sintel4k.id);
      expect(sintel.service, ServiceKey.radarr);
      expect(sintel.clientService, ServiceKey.sabnzbd);
      expect(sintel.queued, isTrue);
      expect(sintel.isActive, isTrue);
      expect(sintel.isMoving, isFalse);

      final elephants = _byDownload(items, WorldDownloads.elephantsDream4k.id);
      expect(elephants.queued, isFalse);
      expect(elephants.isMoving, isTrue);
    });

    test(
      'P7: an arr whose client says nothing reads its own `queued`',
      () async {
        // The device is away and SABnzbd answers at home only: Radarr's record
        // of Sintel (`status: queued`) is all there is to read.
        final items = await _items(await _start(Profiles.p7));

        final sintel = _byDownload(items, WorldDownloads.sintel4k.id);
        expect(sintel.clientService, isNull);
        expect(sintel.queued, isTrue);
        expect(sintel.startsInSeconds, isNull);
        expect(sintel.isMoving, isFalse);
      },
    );

    test('qBittorrent queuedDL is queued; a torrent moving is not', () async {
      final items = await _items(
        await _start(Profiles.p1.withDownloads([_qbQueued])),
      );

      final queued = _of(items, _qbQueued.id);
      expect(queued.queued, isTrue);
      expect(queued.service, ServiceKey.qbittorrent);
      expect(queued.startsInSeconds, isNull);
      expect(
        _byDownload(items, WorldDownloads.spriteFright.id).queued,
        isFalse,
      );
    });

    test('Transmission download wait is queued', () async {
      final items = await _items(
        await _start(Profiles.p4.withDownloads([_transmissionQueued])),
      );

      final queued = _of(items, _transmissionQueued.id);
      expect(queued.queued, isTrue);
      expect(queued.service, ServiceKey.transmission);
      expect(queued.isMoving, isFalse);
    });

    test('an NZBGet group QUEUED is queued', () async {
      final items = await _items(
        await _start(
          Profiles.p4.withConnection(WorldConnections.nzbget).withDownloads([
            _nzbget(
              'nzbget-q-0001',
              'Spring.2019.1080p.WEB',
              DownloadState.queued,
            ),
            _nzbget(
              'nzbget-d-0001',
              'Tears.of.Steel.2012.1080p',
              DownloadState.downloading,
              speed: 8 * _mb,
            ),
          ]),
        ),
      );

      expect(_named(items, 'Spring.2019.1080p.WEB').queued, isTrue);
      expect(_named(items, 'Tears.of.Steel.2012.1080p').queued, isFalse);
    });

    test('a queue somebody paused holds a queued job, as it did', () async {
      final items = await _items(
        await _start(Profiles.p1.withPausedQueue(WorldIds.sabnzbd)),
      );

      final sintel = _byDownload(items, WorldDownloads.sintel4k.id);
      expect(sintel.held, isTrue);
      expect(sintel.queued, isFalse);
      expect(sintel.isActive, isFalse);
    });
  });

  group('the join', () {
    List<ServiceQueueItem> join(
      ServiceQueueItem arr,
      ServiceQueueItem client,
    ) => joinQueueSources(arr: [arr], clients: [client]);

    test('the client\'s word wins: moving at the client overrules an arr that '
        'still says queued', () {
      final joined = join(
        _row(service: ServiceKey.radarr, downloadId: 'abc', queued: true),
        _row(service: ServiceKey.qbittorrent, id: 'abc'),
      ).single;

      expect(joined.queued, isFalse);
      expect(joined.isMoving, isTrue);
    });

    test('and queued at the client overrules an arr that says it is '
        'downloading', () {
      final joined = join(
        _row(service: ServiceKey.radarr, downloadId: 'abc'),
        _row(
          service: ServiceKey.sabnzbd,
          id: 'abc',
          queued: true,
          startsInSeconds: 360,
        ),
      ).single;

      expect(joined.queued, isTrue);
      expect(joined.startsInSeconds, 360);
      expect(joined.isMoving, isFalse);
    });

    test('a fault or a pause outranks a wait', () {
      final held = join(
        _row(service: ServiceKey.radarr, downloadId: 'abc', queued: true),
        _row(service: ServiceKey.qbittorrent, id: 'abc', held: true),
      ).single;
      expect(held.held, isTrue);
      expect(held.queued, isFalse);

      final faulted = join(
        _row(
          service: ServiceKey.radarr,
          downloadId: 'abc',
          fault: InFlightFault.failed,
        ),
        _row(service: ServiceKey.qbittorrent, id: 'abc', queued: true),
      ).single;
      expect(faulted.fault, InFlightFault.failed);
      expect(faulted.queued, isFalse);
    });

    test(
      'the row takes the client\'s rate, and keeps the arr\'s title ids',
      () {
        final joined = join(
          _row(
            service: ServiceKey.sonarr,
            downloadId: 'abc',
            tmdbId: 7,
            tvdbId: 9,
          ),
          _row(service: ServiceKey.qbittorrent, id: 'abc', rate: 4 * _mb),
        ).single;

        expect(joined.rateBytesPerSecond, 4 * _mb);
        expect(joined.tmdbId, 7);
        expect(joined.tvdbId, 9);
      },
    );

    test('naming a row keeps everything it carries', () {
      final named = _row(
        service: ServiceKey.sabnzbd,
        queued: true,
        startsInSeconds: 60,
        rate: 5,
        tmdbId: 1,
        tvdbId: 2,
      ).withNames(const MediaNames.raw('Other'));

      expect(named.queued, isTrue);
      expect(named.startsInSeconds, 60);
      expect(named.rateBytesPerSecond, 5);
      expect(named.tmdbId, 1);
      expect(named.tvdbId, 2);
    });
  });

  group('when a SABnzbd job starts', () {
    test('P1: Sintel starts when Elephants Dream, the job ahead of it, '
        'finishes', () async {
      final items = await _items(await _start(Profiles.p1));

      final sintel = _byDownload(items, WorldDownloads.sintel4k.id);
      // Elephants Dream has six minutes left, and is first in the queue.
      expect(sintel.startsInSeconds, 360);
      // The moving job's start is behind it, and the other clients give none.
      expect(
        _byDownload(items, WorldDownloads.elephantsDream4k.id).startsInSeconds,
        isNull,
      );
      expect(
        _byDownload(items, WorldDownloads.spriteFright.id).startsInSeconds,
        isNull,
      );
    });
  });

  group('the rate of one transfer', () {
    test('P1: a torrent has its own, and the arr row joined to it takes '
        'it', () async {
      final items = await _items(await _start(Profiles.p1));

      final sprite = _byDownload(items, WorldDownloads.spriteFright.id);
      expect(sprite.rateBytesPerSecond, (4.2 * _mb) ~/ 1);
      // Not the client's: that is the sum of its torrents.
      expect(
        sprite.clientRateBytesPerSecond,
        greaterThan(sprite.rateBytesPerSecond!),
      );
      final cosmos = _byDownload(items, WorldDownloads.cosmosS02E04.id);
      expect(cosmos.rateBytesPerSecond, (12.1 * _mb) ~/ 1);
    });

    test('Transmission reports one per torrent too', () async {
      final items = await _items(await _start(Profiles.p4));

      final nightShift = _byDownload(
        items,
        WorldDownloads.nightShiftTransmission.id,
      );
      expect(nightShift.rateBytesPerSecond, 3 * _mb);
    });

    test('P1: SABnzbd reports one for the queue, so the one job that '
        'downloads takes it, and a queued job none', () async {
      final items = await _items(await _start(Profiles.p1));

      expect(
        _byDownload(
          items,
          WorldDownloads.elephantsDream4k.id,
        ).rateBytesPerSecond,
        18 * _mb,
      );
      expect(
        _byDownload(items, WorldDownloads.sintel4k.id).rateBytesPerSecond,
        isNull,
      );
    });

    test('NZBGet gives its rate to the one group that downloads', () async {
      final items = await _items(
        await _start(
          Profiles.p4.withConnection(WorldConnections.nzbget).withDownloads([
            _nzbget(
              'nzbget-d-0001',
              'Tears.of.Steel.2012.1080p',
              DownloadState.downloading,
              speed: 8 * _mb,
            ),
            _nzbget(
              'nzbget-q-0001',
              'Spring.2019.1080p.WEB',
              DownloadState.queued,
            ),
          ]),
        ),
      );

      expect(
        _named(items, 'Tears.of.Steel.2012.1080p').rateBytesPerSecond,
        8 * _mb,
      );
      expect(_named(items, 'Spring.2019.1080p.WEB').rateBytesPerSecond, isNull);
    });

    test(
      'and to none when two do: the speed is the pair\'s, not either\'s',
      () async {
        final items = await _items(
          await _start(
            Profiles.p4.withConnection(WorldConnections.nzbget).withDownloads([
              _nzbget(
                'nzbget-d-0001',
                'Tears.of.Steel.2012.1080p',
                DownloadState.downloading,
                speed: 8 * _mb,
              ),
              _nzbget(
                'nzbget-d-0002',
                'Spring.2019.1080p.WEB',
                DownloadState.downloading,
                speed: 2 * _mb,
              ),
            ]),
          ),
        );

        expect(
          _named(items, 'Tears.of.Steel.2012.1080p').rateBytesPerSecond,
          isNull,
        );
        expect(
          _named(items, 'Spring.2019.1080p.WEB').rateBytesPerSecond,
          isNull,
        );
      },
    );

    test('an arr row no client row joined has none', () async {
      // P7: the device is away and SABnzbd and qBittorrent do not answer.
      final items = await _items(await _start(Profiles.p7));

      final sintel = _byDownload(items, WorldDownloads.sintel4k.id);
      expect(sintel.clientService, isNull);
      expect(sintel.rateBytesPerSecond, isNull);
    });
  });

  group('the title\'s ids', () {
    test('P1: a Radarr row carries the movie\'s TMDB id, from the movie the '
        'queue record embeds', () async {
      final items = await _items(await _start(Profiles.p1));

      final sprite = _byDownload(items, WorldDownloads.spriteFright.id);
      expect(sprite.service, ServiceKey.radarr);
      expect(sprite.tmdbId, WorldTitles.spriteFright.tmdbId);
      expect(sprite.tvdbId, isNull);
    });

    test('P1: a Sonarr row carries the series\' TVDB and TMDB ids', () async {
      final items = await _items(await _start(Profiles.p1));

      final cosmos = _byDownload(items, WorldDownloads.cosmosS02E04.id);
      expect(cosmos.service, ServiceKey.sonarr);
      expect(cosmos.tvdbId, WorldTitles.cosmosLaundromat.tvdbId);
      expect(cosmos.tmdbId, WorldTitles.cosmosLaundromat.tmdbId);
    });

    test('a client\'s own row has none', () async {
      final items = await _items(
        await _start(Profiles.p1.withDownloads([_qbQueued])),
      );

      final own = _of(items, _qbQueued.id);
      expect(own.tmdbId, isNull);
      expect(own.tvdbId, isNull);
    });
  });

  group('the counts', () {
    test('P1: what moves is the preview and the count; what waits is queued, '
        'and not on the Home', () async {
      final container = await _start(Profiles.p1);
      final inFlight = await container.read(servicesInFlightProvider.future);

      expect(inFlight.movingCount, 4);
      expect(inFlight.activeCount, inFlight.movingCount);
      expect(inFlight.preview.every((item) => item.isMoving), isTrue);
      expect(inFlight.preview, hasLength(4));
      expect(inFlight.queued.map((item) => item.downloadId), [
        WorldDownloads.sintel4k.id,
      ]);
      expect(inFlight.queued.single.isMoving, isFalse);
    });

    test('the queued rows come in their queue order, after everything '
        'else', () async {
      final container = await _start(Profiles.p1.withDownloads([_qbQueued]));
      final inFlight = await container.read(servicesInFlightProvider.future);
      final queue = await container.read(servicesQueueProvider.future);

      // Sintel, the arr's row, and the torrent nobody's arr asked for.
      expect(inFlight.queued.map((item) => item.title), [
        _byDownload(queue.items, WorldDownloads.sintel4k.id).title,
        _qbQueued.release,
      ]);
      // And the queue lists them last.
      final order = queue.items.map((item) => item.queued).toList();
      expect(order.indexOf(true), order.length - 2);
      expect(order.skip(order.indexOf(true)), everyElement(isTrue));
    });
  });
}
