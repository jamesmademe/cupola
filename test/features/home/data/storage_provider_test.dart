import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/presentation/library_calendar_provider.dart';
import 'package:cupola/features/home/data/storage.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/truenas/data/truenas_ws_client.dart';
import 'package:cupola/features/truenas/presentation/truenas_provider.dart';

import '../../../test_helpers/settings_scope.dart';

class _FakeNas extends TrueNasWsClient {
  _FakeNas(this.pools, {this.fails = false})
    : super(baseUrl: 'https://nas.local', apiKey: 'k');

  final List<Map<String, Object?>> pools;
  final bool fails;
  final List<List<dynamic>> calls = [];

  @override
  Future<dynamic> call(String method, [List<dynamic> params = const []]) async {
    calls.add(params);
    if (fails) throw const TrueNasException('connection refused');
    if (method != 'pool.query') throw const TrueNasException('no such method');
    if (params.isEmpty) return pools;
    // A filter by name, with the topology.
    final name = ((params.first as List).first as List)[2];
    return [
      for (final pool in pools)
        if (pool['name'] == name)
          {
            ...pool,
            'topology': {
              'data': [
                {
                  'type': 'MIRROR',
                  'status': 'DEGRADED',
                  'children': [
                    {'disk': 'sdc', 'status': 'ONLINE'},
                    {'disk': 'sdd', 'status': 'FAULTED'},
                  ],
                },
              ],
            },
          },
    ];
  }
}

/// What Storage reads: every TrueNAS's pools, a second look only at a pool
/// in trouble.
void main() {
  Future<HomeStorage> read(_FakeNas nas) async {
    final scope = await settingsScopeOverrides(
      configured: const [ServiceKey.truenas],
    );
    final container = ProviderContainer(
      overrides: [
        ...scope,
        calendarClockProvider.overrideWithValue(
          () => DateTime(2026, 9, 29, 20, 41),
        ),
        truenasClientForProvider.overrideWith((ref, id) => nas),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(homeStorageProvider, (_, _) {});
    addTearDown(subscription.close);
    return container.read(homeStorageProvider.future);
  }

  test(
    'a healthy pool is read once; one in trouble again, for its disks',
    () async {
      final nas = _FakeNas([
        {
          'name': 'tank',
          'status': 'ONLINE',
          'healthy': true,
          'size': 100,
          'allocated': 72,
        },
        {
          'name': 'fast',
          'status': 'DEGRADED',
          'healthy': false,
          'size': 10,
          'allocated': 3,
        },
      ]);
      final storage = await read(nas);
      expect(storage.pools.map((pool) => pool.name), ['tank', 'fast']);
      expect(storage.pools.first.disks, isEmpty);
      expect(storage.pools.last.disks, ['Disk sdd has failed']);
      // The list, then the one pool in trouble.
      expect(nas.calls, hasLength(2));
      expect(storage.coverage.isWhole, isTrue);
    },
  );

  test('a TrueNAS that did not answer gives no pool, and says so', () async {
    final storage = await read(_FakeNas(const [], fails: true));
    expect(storage.pools, isEmpty);
    expect(storage.coverage.everySourceFailed, isTrue);
  });
}
