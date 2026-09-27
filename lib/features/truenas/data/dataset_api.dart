import 'package:cupola/features/truenas/data/truenas_api_base.dart';
import 'package:cupola/features/truenas/domain/models/dataset.dart';

/// Dataset / zvol / snapshot operations (`pool.dataset.*`, `zfs.snapshot.*`).
///
/// **The snapshot half is 25.04's API, and 25.10 moved it.** At tag
/// TS-25.10.0 the `zfs.snapshot` service is declared `private = True`
/// (`plugins/zfs_/snapshot.py`), so it cannot be called over `/api/current`;
/// the public namespace there is `pool.snapshot.*`
/// (`api/v25_10_0/pool_snapshot.py`). The calls below are left on
/// `zfs.snapshot.*` because the replacement has not been exercised against a
/// live 25.10 server. On one, [getSnapshots] fails and the dataset page's
/// Snapshots section shows its own retry while the rest of the page reads; a
/// create or delete reports the server's refusal like any failed write.
class TrueNasDatasetApi extends TrueNasApiBase {
  const TrueNasDatasetApi(super.client);

  /// Top-level datasets with nested `children` (a tree per pool).
  Future<List<TrueNasDataset>> getDatasetTree() =>
      queryList('pool.dataset.query', TrueNasDataset.fromJson, [
        const <dynamic>[],
        {
          'extra': {'flat': false},
        },
      ]);

  Future<TrueNasDataset?> getDataset(String id) =>
      queryFirst('pool.dataset.query', TrueNasDataset.fromJson, [
        [
          ['id', '=', id],
        ],
      ]);

  Future<void> createDataset(Map<String, dynamic> payload) =>
      client.call('pool.dataset.create', [payload]);

  Future<void> updateDataset(String id, Map<String, dynamic> patch) =>
      client.call('pool.dataset.update', [id, patch]);

  /// Deletes a dataset. [recursive] also removes child datasets/snapshots.
  Future<dynamic> deleteDataset(String id, {bool recursive = false}) =>
      client.call('pool.dataset.delete', [
        id,
        {'recursive': recursive},
      ]);

  Future<List<TrueNasSnapshot>> getSnapshots(String dataset) =>
      queryList('zfs.snapshot.query', TrueNasSnapshot.fromJson, [
        [
          ['dataset', '=', dataset],
        ],
      ]);

  Future<void> createSnapshot(
    String dataset,
    String name, {
    bool recursive = false,
  }) => client.call('zfs.snapshot.create', [
    {'dataset': dataset, 'name': name, 'recursive': recursive},
  ]);

  Future<void> deleteSnapshot(String id) =>
      client.call('zfs.snapshot.delete', [id]);
}
