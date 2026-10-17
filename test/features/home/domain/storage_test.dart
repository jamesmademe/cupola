import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/home/domain/storage.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/truenas/domain/models/pool.dart';
import 'package:cupola/features/unraid/domain/models/unraid_models.dart';

const _tb = 1024 * 1024 * 1024 * 1024;

// A Tuesday evening.
final _now = DateTime(2026, 9, 29, 20, 41);

TrueNasPool _pool(Map<String, Object?> extra) => TrueNasPool.fromJson({
  'id': 1,
  'name': 'tank',
  'status': 'ONLINE',
  'healthy': true,
  'size': (43.6 * _tb).round(),
  'allocated': (31.2 * _tb).round(),
  ...extra,
});

/// Storage on the Home: a TrueNAS pool and an Unraid array, read alike.
void main() {
  group('a TrueNAS pool', () {
    test('healthy: the share, the figures, and when it was scrubbed', () {
      final pool = storagePoolOfTrueNas(
        _pool({
          'scan': {
            'function': 'SCRUB',
            'state': 'FINISHED',
            // Sunday the 27th, early.
            'end_time': {
              '\$date': DateTime(2026, 9, 27, 3).millisecondsSinceEpoch,
            },
          },
        }),
        instanceId: 'nas',
        now: _now,
      );
      expect(pool.service, ServiceKey.truenas);
      expect(pool.healthy, isTrue);
      expect(pool.percent, '72%');
      expect(pool.capacity, '31.2 of 43.6\u00A0TB');
      expect(pool.stateLine, 'Healthy\u00A0· scrubbed Sunday');
      expect(pool.disks, isEmpty);
    });

    test('a scrub that runs says how far it is', () {
      final pool = storagePoolOfTrueNas(
        _pool({
          'scan': {'function': 'SCRUB', 'state': 'SCANNING', 'percentage': 41},
        }),
        instanceId: 'nas',
        now: _now,
      );
      expect(pool.stateLine, 'Healthy\u00A0· scrubbing 41%');
    });

    test('degraded: its state, and each disk in trouble by name', () {
      final pool = storagePoolOfTrueNas(
        _pool({
          'status': 'DEGRADED',
          'healthy': false,
          'topology': {
            'data': [
              {
                'type': 'RAIDZ1',
                'status': 'DEGRADED',
                'children': [
                  {'disk': 'sda', 'status': 'ONLINE'},
                  {
                    'disk': 'sdd',
                    'status': 'ONLINE',
                    'stats': {
                      'read_errors': 6,
                      'write_errors': 0,
                      'checksum_errors': 2,
                    },
                  },
                  {'disk': 'sde', 'status': 'FAULTED'},
                ],
              },
            ],
          },
        }),
        instanceId: 'nas',
        now: _now,
      );
      expect(pool.healthy, isFalse);
      expect(pool.state, 'Degraded');
      expect(pool.disks, ['Disk sdd reports 8 errors', 'Disk sde has failed']);
    });

    test('a pool that reported no capacity says no share', () {
      final pool = storagePoolOfTrueNas(
        TrueNasPool.fromJson({
          'name': 'fast',
          'status': 'ONLINE',
          'healthy': true,
        }),
        instanceId: 'nas',
        now: _now,
      );
      expect(pool.percent, isNull);
      expect(pool.capacity, isNull);
    });
  });

  group('an Unraid array', () {
    UnraidArray array({
      String state = 'STARTED',
      List<UnraidDisk> disks = const [],
    }) => UnraidArray(
      state: state,
      usedFraction: 0.5,
      usedBytes: 4 * _tb,
      totalBytes: 8 * _tb,
      disks: disks,
    );

    test('started with every drive fine: healthy', () {
      final pool = storagePoolOfUnraid(
        array(
          disks: const [UnraidDisk(name: 'disk1', status: 'DISK_OK', temp: 34)],
        ),
        instanceId: 'tower',
      );
      expect(pool.name, 'Array');
      expect(pool.healthy, isTrue);
      expect(pool.stateLine, 'Healthy');
      expect(pool.capacity, '4.0 of 8.0\u00A0TB');
    });

    test('a flagged drive and a hot one, each in a sentence', () {
      final pool = storagePoolOfUnraid(
        array(
          disks: const [
            UnraidDisk(name: 'disk3', status: 'DISK_DSBL', temp: null),
            UnraidDisk(name: 'parity', status: 'DISK_OK', temp: 47),
            UnraidDisk(name: 'disk4', status: 'DISK_NP', temp: null),
          ],
        ),
        instanceId: 'tower',
      );
      expect(pool.healthy, isFalse);
      expect(pool.state, 'Started');
      expect(pool.disks, ['Disk 3 is disabled', 'Parity is at 47\u00A0°C']);
    });

    test('stopped is said, and not healthy', () {
      final pool = storagePoolOfUnraid(
        array(state: 'STOPPED'),
        instanceId: 'tower',
      );
      expect(pool.healthy, isFalse);
      expect(pool.state, 'Stopped');
    });
  });
}
