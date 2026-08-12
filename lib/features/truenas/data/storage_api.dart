import 'package:cupola/features/truenas/data/truenas_api_base.dart';
import 'package:cupola/features/truenas/domain/models/pool.dart';

/// Storage pool operations (`pool.*`, `pool.scrub.*`).
class TrueNasStorageApi extends TrueNasApiBase {
  const TrueNasStorageApi(super.client);

  /// All pools, without topology (lighter — used for lists/KPIs).
  Future<List<TrueNasPool>> getPools() =>
      queryList('pool.query', TrueNasPool.fromJson);

  /// A single pool including its full topology.
  Future<TrueNasPool?> getPool(String name) =>
      queryFirst('pool.query', TrueNasPool.fromJson, [
        [
          ['name', '=', name],
        ],
        {
          'extra': {'topology': true},
        },
      ]);

  /// Starts a scrub on [poolName] (`START`), or `STOP` to cancel.
  Future<void> runScrub(String poolName, {String action = 'START'}) =>
      client.call('pool.scrub.scrub', [poolName, action]);
}
