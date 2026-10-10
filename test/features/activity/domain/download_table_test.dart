/// The desktop's table of downloads: how a header click orders it, and what
/// each cell says.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/media_status.dart' show StatusTone;
import 'package:cupola/features/activity/domain/download_table.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/services/domain/in_flight.dart';
import 'package:cupola/features/services/presentation/services_provider.dart'
    show ServiceQueueItem;
import 'package:cupola/features/settings/domain/service_key.dart';

final _now = DateTime(2026, 10, 9, 20, 53);

ServiceQueueItem _download(
  String title, {
  double? progress = 0.5,
  int? rate = 1048576,
  int? eta = 600,
  InFlightFault? fault,
  bool held = false,
  bool queued = false,
  int? startsIn,
}) => ServiceQueueItem(
  service: ServiceKey.radarr,
  id: title,
  title: title,
  progress: progress,
  clientLabel: 'qBittorrent',
  clientService: ServiceKey.qbittorrent,
  instanceId: 'radarr',
  clientInstanceId: 'qbittorrent',
  rateBytesPerSecond: rate,
  etaSeconds: eta,
  fault: fault,
  held: held,
  queued: queued,
  startsInSeconds: startsIn,
  stalledSince: _now.subtract(const Duration(hours: 3)),
);

List<String> _titles(List<ServiceQueueItem> items) => [
  for (final item in items) item.title,
];

void main() {
  group('a header click', () {
    test('sorts by its column, the way it sorts first', () {
      expect(nextDownloadSort(null, DownloadColumn.progress), (
        column: DownloadColumn.progress,
        descending: true,
      ));
      expect(nextDownloadSort(null, DownloadColumn.left), (
        column: DownloadColumn.left,
        descending: false,
      ));
      expect(nextDownloadSort(null, DownloadColumn.title), (
        column: DownloadColumn.title,
        descending: false,
      ));
    });

    test('again, the other way; a third time, the queue\'s own order', () {
      final first = nextDownloadSort(null, DownloadColumn.speed);
      final second = nextDownloadSort(first, DownloadColumn.speed);
      expect(second, (column: DownloadColumn.speed, descending: false));
      expect(nextDownloadSort(second, DownloadColumn.speed), isNull);
    });

    test('on another column starts that one afresh', () {
      expect(
        nextDownloadSort((
          column: DownloadColumn.speed,
          descending: false,
        ), DownloadColumn.progress),
        (column: DownloadColumn.progress, descending: true),
      );
    });
  });

  group('the order', () {
    final items = [
      _download('Cosmos', progress: 0.88, rate: 12000000, eta: 60),
      _download('Sprite', progress: 0.62, rate: 4400000, eta: 660),
      _download(
        'Bunny',
        progress: 0.47,
        fault: InFlightFault.stalled,
        rate: 0,
        eta: null,
      ),
      _download('Elephants', progress: 0.31, rate: 18000000, eta: 360),
    ];

    test('none keeps the queue\'s own', () {
      expect(_titles(sortDownloads(items, null)), [
        'Cosmos',
        'Sprite',
        'Bunny',
        'Elephants',
      ]);
    });

    test('by progress, the furthest along first', () {
      expect(
        _titles(
          sortDownloads(items, (
            column: DownloadColumn.progress,
            descending: true,
          )),
        ),
        ['Cosmos', 'Sprite', 'Bunny', 'Elephants'],
      );
    });

    test('by speed, the fastest first, and a stuck one last either way', () {
      expect(
        _titles(
          sortDownloads(items, (
            column: DownloadColumn.speed,
            descending: true,
          )),
        ),
        ['Elephants', 'Cosmos', 'Sprite', 'Bunny'],
      );
      expect(
        _titles(
          sortDownloads(items, (
            column: DownloadColumn.speed,
            descending: false,
          )),
        ),
        ['Sprite', 'Cosmos', 'Elephants', 'Bunny'],
      );
    });

    test('by time left, the soonest first; by title, A to Z', () {
      expect(
        _titles(
          sortDownloads(items, (
            column: DownloadColumn.left,
            descending: false,
          )),
        ),
        ['Cosmos', 'Elephants', 'Sprite', 'Bunny'],
      );
      expect(
        _titles(
          sortDownloads(items, (
            column: DownloadColumn.title,
            descending: false,
          )),
        ),
        ['Bunny', 'Cosmos', 'Elephants', 'Sprite'],
      );
    });
  });

  group('the cells', () {
    test('Progress says where it stands, in its tone', () {
      expect(downloadProgressCell(_download('A', progress: 0.62)), (
        text: '62%',
        tone: StatusTone.info,
      ));
      expect(
        downloadProgressCell(
          _download('A', progress: 0.47, fault: InFlightFault.stalled),
        ),
        (text: 'Stuck at 47%', tone: StatusTone.warning),
      );
      expect(downloadProgressCell(_download('A', held: true)), (
        text: 'Stopped at 50%',
        tone: StatusTone.neutral,
      ));
      expect(
        downloadProgressCell(_download('A', queued: true, startsIn: 360)),
        (text: 'Queued · starts in about 6\u00A0min', tone: StatusTone.info),
      );
      expect(downloadProgressCell(_download('A', progress: null)).text, '—');
    });

    test('Speed and Left read while it moves, the dash otherwise', () {
      final moving = _download('A', rate: 4404019, eta: 660);
      expect(downloadSpeedCell(moving), '4.2\u00A0MB/s');
      expect(downloadLeftCell(moving, now: _now), (
        left: '11\u00A0min',
        around: 'around 21:04',
      ));

      final stuck = _download('A', fault: InFlightFault.stalled);
      expect(downloadSpeedCell(stuck), '—');
      expect(downloadLeftCell(stuck, now: _now), (left: '—', around: null));
      expect(downloadSpeedCell(_download('A', held: true)), '—');
    });

    test('the line under the release: the route, and who asked or since '
        'when nothing arrived', () {
      final anna = SeerrRequest.fromJson({
        'id': 7,
        'status': 2,
        'type': 'movie',
        'requestedBy': {'id': 2, 'displayName': 'Anna'},
      });
      expect(
        downloadRouteLine(_download('A'), request: anna, now: _now),
        'Radarr → qBittorrent · Anna asked',
      );
      expect(
        downloadRouteLine(
          _download('A', fault: InFlightFault.stalled),
          request: anna,
          now: _now,
        ),
        'Radarr → qBittorrent · nothing for 3\u00A0h',
      );
    });

    test('a narrow table carries the speed and the time left in it', () {
      expect(
        downloadRouteLine(
          _download('A', rate: 4404019, eta: 660),
          now: _now,
          withFigures: true,
        ),
        'Radarr → qBittorrent · 4.2\u00A0MB/s · 11\u00A0min left',
      );
    });
  });
}
