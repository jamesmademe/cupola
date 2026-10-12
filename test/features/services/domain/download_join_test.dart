import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/services/domain/download_join.dart';
import 'package:cupola/features/services/domain/in_flight.dart';

typedef _Arr = ({String name, String? downloadId});
typedef _Client = ({String name, String? id});

DownloadJoin<_Arr, _Client> _join(List<_Arr> arr, List<_Client> clients) =>
    joinDownloads<_Arr, _Client>(
      arr: arr,
      clients: clients,
      arrDownloadId: (row) => row.downloadId,
      clientDownloadId: (row) => row.id,
    );

void main() {
  group('joinDownloads', () {
    test('an arr row meets its torrent across the two spellings of the '
        'hash', () {
      final join = _join(
        [(name: 'Sprite Fright', downloadId: 'A1F0C3D4')],
        [(name: 'Sprite.Fright.2021.1080p.WEB', id: 'a1f0c3d4')],
      );
      expect(join.joined.single.client?.name, 'Sprite.Fright.2021.1080p.WEB');
      expect(join.unclaimed, isEmpty);
    });

    test('the episodes of one season pack all meet its one torrent', () {
      final join = _join(
        [
          (name: 'S2 E1', downloadId: 'PACK'),
          (name: 'S2 E2', downloadId: 'pack'),
        ],
        [(name: 'The.Boys.S02.1080p', id: 'pack')],
      );
      expect(join.joined.map((row) => row.client?.name), [
        'The.Boys.S02.1080p',
        'The.Boys.S02.1080p',
      ]);
      expect(join.unclaimed, isEmpty);
    });

    test('a row with no id joins nothing, and a torrent added by hand stays '
        'its own', () {
      final join = _join(
        [
          (name: 'Unknown', downloadId: null),
          (name: 'Blank', downloadId: '  '),
        ],
        [(name: 'ubuntu.iso', id: 'u1'), (name: 'nameless', id: null)],
      );
      expect(join.joined.map((row) => row.client), [null, null]);
      expect(join.unclaimed.map((row) => row.name), ['ubuntu.iso', 'nameless']);
    });

    test('the arr keeps its order, the clients theirs, and the first client '
        'with an id wins it', () {
      final join = _join(
        [(name: 'B', downloadId: 'b'), (name: 'A', downloadId: 'a')],
        [
          (name: 'a in qBittorrent', id: 'a'),
          (name: 'a in Transmission', id: 'A'),
          (name: 'b', id: 'b'),
        ],
      );
      expect(join.joined.map((row) => (row.arr.name, row.client?.name)), [
        ('B', 'b'),
        ('A', 'a in qBittorrent'),
      ]);
      expect(join.unclaimed.map((row) => row.name), ['a in Transmission']);
    });
  });

  group('queueStatusWithClient', () {
    const downloading = MediaStatusInfo(
      pipeline: MediaPipeline.downloading,
      progress: 0.4,
    );

    test('a client stall the arr has not noticed makes the record a stall, '
        'in amber', () {
      final status = queueStatusWithClient(
        downloading,
        arrFault: null,
        clientFault: InFlightFault.stalled,
        clientProgress: 0.47,
      );
      expect(status.pipeline, MediaPipeline.stalled);
      expect(status.tone, StatusTone.warning);
      expect(status.progress, 0.47);
    });

    test('a client failure is a failure, in the client\'s words', () {
      final status = queueStatusWithClient(
        downloading,
        arrFault: null,
        clientFault: InFlightFault.failed,
        clientReason: 'Disk full',
      );
      expect(status.pipeline, MediaPipeline.failed);
      expect(status.tone, StatusTone.warning);
      expect(status.detail, 'Disk full');
    });

    test('the arr\'s own fault stands over the client\'s', () {
      const blocked = MediaStatusInfo(
        pipeline: MediaPipeline.importBlocked,
        hasWarning: true,
        detail: 'Found matching series via grab history',
      );
      expect(
        queueStatusWithClient(
          blocked,
          arrFault: InFlightFault.needsImport,
          clientFault: InFlightFault.failed,
          clientReason: 'Files missing',
        ),
        same(blocked),
      );
    });

    test('the arr\'s stall waits on a client that dates its last byte: '
        'moving for 30 minutes, then stuck by the client\'s clock', () {
      const stalled = MediaStatusInfo(
        pipeline: MediaPipeline.stalled,
        progress: 0.4,
        hasWarning: true,
      );
      final moving = queueStatusWithClient(
        stalled,
        arrFault: InFlightFault.stalled,
        clientFault: null,
        clientProgress: 0.41,
        clientMeasuresIdle: true,
      );
      expect(moving.pipeline, MediaPipeline.downloading);
      expect(moving.tone, isNot(StatusTone.warning));
      expect(moving.progress, 0.41);

      final stuck = queueStatusWithClient(
        stalled,
        arrFault: InFlightFault.stalled,
        clientFault: InFlightFault.stalled,
        clientMeasuresIdle: true,
      );
      expect(stuck.pipeline, MediaPipeline.stalled);
      expect(stuck.tone, StatusTone.warning);
    });

    test('a client that cannot date its last byte leaves the arr\'s stall '
        'standing', () {
      const stalled = MediaStatusInfo(
        pipeline: MediaPipeline.stalled,
        hasWarning: true,
      );
      expect(
        queueStatusWithClient(
          stalled,
          arrFault: InFlightFault.stalled,
          clientFault: null,
        ),
        same(stalled),
      );
    });

    test('a healthy client lends its progress and nothing else', () {
      final status = queueStatusWithClient(
        downloading,
        arrFault: null,
        clientFault: null,
        clientProgress: 0.62,
      );
      expect(status.pipeline, MediaPipeline.downloading);
      expect(status.progress, 0.62);
      expect(
        queueStatusWithClient(downloading, arrFault: null, clientFault: null),
        same(downloading),
      );
    });
  });
}
