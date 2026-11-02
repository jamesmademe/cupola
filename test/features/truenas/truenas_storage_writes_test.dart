import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/truenas/data/dataset_api.dart';
import 'package:cupola/features/truenas/data/sharing_api.dart';
import 'package:cupola/features/truenas/data/truenas_ws_client.dart';

/// A [TrueNasWsClient] that records every RPC instead of opening a socket.
class _RecordingClient extends TrueNasWsClient {
  _RecordingClient() : super(baseUrl: 'https://nas.local', apiKey: 'key');

  final List<(String, List<dynamic>)> calls = [];

  @override
  Future<dynamic> call(String method, [List<dynamic> params = const []]) async {
    calls.add((method, params));
    return null;
  }
}

/// The writes of the Shares and Datasets pages, by the middleware method and
/// the params each one sends. A wrong name is refused by the server at the
/// moment someone taps, so it is held here, offline; the live check against
/// a real TrueNAS is `testlab_truenas_e2e_test`.
void main() {
  late _RecordingClient client;
  setUp(() => client = _RecordingClient());

  group('TrueNasSharingApi', () {
    test('an SMB share is created, patched, switched and deleted', () async {
      final api = TrueNasSharingApi(client);

      await api.createSmbShare({'name': 'media', 'path': '/mnt/tank/media'});
      await api.updateSmbShare(3, {'comment': 'films'});
      await api.setSmbEnabled(3, false);
      await api.deleteSmbShare(3);

      expect(
        client.calls.map(_described),
        [
          (
            'sharing.smb.create',
            [
              {'name': 'media', 'path': '/mnt/tank/media'},
            ],
          ),
          (
            'sharing.smb.update',
            [
              3,
              {'comment': 'films'},
            ],
          ),
          (
            'sharing.smb.update',
            [
              3,
              {'enabled': false},
            ],
          ),
          ('sharing.smb.delete', [3]),
        ].map(_described),
      );
    });

    test('an NFS share is created, switched and deleted', () async {
      final api = TrueNasSharingApi(client);

      await api.createNfsShare({'path': '/mnt/tank/backup'});
      await api.setNfsEnabled(4, true);
      await api.deleteNfsShare(4);

      expect(client.calls.map(_described), [
        _described((
          'sharing.nfs.create',
          [
            {'path': '/mnt/tank/backup'},
          ],
        )),
        _described((
          'sharing.nfs.update',
          [
            4,
            {'enabled': true},
          ],
        )),
        _described(('sharing.nfs.delete', [4])),
      ]);
    });

    test('an iSCSI target is deleted by its id', () async {
      await TrueNasSharingApi(client).deleteIscsiTarget(9);

      expect(client.calls.map(_described), [
        _described(('iscsi.target.delete', [9])),
      ]);
    });
  });

  group('TrueNasDatasetApi', () {
    test('a dataset is created and patched by its path', () async {
      final api = TrueNasDatasetApi(client);

      await api.createDataset({'name': 'tank/media'});
      await api.updateDataset('tank/media', {'comments': 'films'});

      expect(client.calls.map(_described), [
        _described((
          'pool.dataset.create',
          [
            {'name': 'tank/media'},
          ],
        )),
        _described((
          'pool.dataset.update',
          [
            'tank/media',
            {'comments': 'films'},
          ],
        )),
      ]);
    });

    test(
      'a delete keeps the children unless it is asked to take them',
      () async {
        final api = TrueNasDatasetApi(client);

        await api.deleteDataset('tank/media');
        await api.deleteDataset('tank/old', recursive: true);

        expect(client.calls.map(_described), [
          _described((
            'pool.dataset.delete',
            [
              'tank/media',
              {'recursive': false},
            ],
          )),
          _described((
            'pool.dataset.delete',
            [
              'tank/old',
              {'recursive': true},
            ],
          )),
        ]);
      },
    );

    test('a snapshot is taken of one dataset and deleted by its id', () async {
      final api = TrueNasDatasetApi(client);

      await api.createSnapshot('tank/media', 'before-upgrade');
      await api.deleteSnapshot('tank/media@before-upgrade');

      expect(client.calls.map(_described), [
        _described((
          'zfs.snapshot.create',
          [
            {
              'dataset': 'tank/media',
              'name': 'before-upgrade',
              'recursive': false,
            },
          ],
        )),
        _described(('zfs.snapshot.delete', ['tank/media@before-upgrade'])),
      ]);
    });
  });
}

/// A record holding lists compares them by identity: one call as text
/// compares by content.
String _described((String, List<dynamic>) call) => '${call.$1} ${call.$2}';
