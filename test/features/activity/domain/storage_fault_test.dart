/// The words of a TrueNAS alert about a disk: what its errors mean for the
/// pool, the pool's evidence, and the scrub.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/activity/domain/storage_fault.dart';
import 'package:cupola/features/truenas/domain/models/pool.dart';

TrueNasPool _tank({
  bool healthy = true,
  String status = 'ONLINE',
  int errors = 8,
  String? scanState,
  String? scanFunction,
  double? scanPercentage,
  int? scanSecondsLeft,
}) => TrueNasPool(
  name: 'tank',
  status: status,
  healthy: healthy,
  sizeBytes: 100,
  allocatedBytes: 72,
  topology: {
    'data': [
      TrueNasVdev(
        type: 'RAIDZ2',
        status: status,
        members: [
          const TrueNasVdevMember(name: 'sda', status: 'ONLINE', errors: 0),
          TrueNasVdevMember(name: 'sdd', status: 'ONLINE', errors: errors),
        ],
      ),
    ],
  },
  scanState: scanState,
  scanFunction: scanFunction,
  scanPercentage: scanPercentage,
  scanSecondsLeft: scanSecondsLeft,
);

void main() {
  test('a healthy pool: the disk could not read, a scrub repairs it', () {
    expect(
      diskErrorsExplanation('sdd', _tank()),
      'sdd could not read some data by itself. The pool is still healthy: a '
      'scrub reads every block and repairs it from the other disks.',
    );
  });

  test('a pool that is not healthy says so', () {
    expect(
      diskErrorsExplanation('sdd', _tank(healthy: false, status: 'DEGRADED')),
      'sdd could not read some data by itself, and pool tank is degraded.',
    );
  });

  test('the evidence: the pool, how full, and the disk', () {
    expect(poolEvidence('sdd', _tank()), [
      'Pool tank · Healthy · 72%',
      'Disk sdd · 8 errors',
    ]);
    expect(poolEvidence('sdd', _tank(errors: 1)).last, 'Disk sdd · 1 error');
    expect(poolEvidence('sdd', _tank(errors: 0)).last, 'Disk sdd · Online');
    expect(poolEvidence('sdx', _tank()), ['Pool tank · Healthy · 72%']);
  });

  test('a running scan: what, how far, and how long it has left', () {
    final scrubbing = _tank(
      scanState: 'SCANNING',
      scanFunction: 'SCRUB',
      scanPercentage: 2.4,
      scanSecondsLeft: 9 * 3600 + 120,
    );
    expect(scrubbing.isScanning, isTrue);
    expect(
      scanningLine(scrubbing),
      'Scrubbing tank · 2% · about 9\u00A0h 2\u00A0min left',
    );
    expect(
      scanningLine(
        _tank(
          scanState: 'SCANNING',
          scanFunction: 'RESILVER',
          scanPercentage: 40,
        ),
      ),
      'Resilvering tank · 40%',
    );
    expect(_tank(scanState: 'FINISHED').isScanning, isFalse);
  });

  test('a scrub asks first, and says it reads the whole pool', () {
    final ask = scrubConfirmation(_tank());
    expect(ask.title, 'Scrub tank?');
    expect(ask.message, startsWith('A scrub reads every block of tank'));
    expect(ask.confirm, 'Scrub tank');
    expect(scrubLabel(_tank()), 'Scrub tank');
  });
}
