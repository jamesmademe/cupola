import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/truenas/domain/models/alert.dart';

void main() {
  TrueNasAlert alert(Map<String, dynamic> json) =>
      TrueNasAlert.fromJson({'uuid': 'a', 'level': 'WARNING', ...json});

  test('a disk\'s uncorrectable errors read in plain words, from the '
      'figures or from TrueNAS\'s own sentence', () {
    expect(
      trueNasAlertHeadline(
        alert({
          'formatted': '8 uncorrectable errors reported for sdd (ZL2PQR7T).',
          'args': {'ue': 8, 'name': 'sdd', 'serial': 'ZL2PQR7T'},
        }),
      ),
      'Disk sdd reports 8 uncorrectable errors',
    );
    expect(
      trueNasAlertHeadline(
        alert({'formatted': '1 uncorrectable error reported for sda (X1).'}),
      ),
      'Disk sda reports 1 uncorrectable error',
    );
  });

  test('a SMART alert up to 25.04 says what smartd saw, on the disk it '
      'names', () {
    TrueNasAlert smart(String message) => alert({
      'klass': 'SMART',
      'formatted': '$message.',
      'args': {'device': "/dev/sda ('ZL2PQR7T')", 'message': message},
    });
    final cases = {
      'Device: /dev/sda [SAT], 8 Currently unreadable (pending) sectors':
          'Disk sda has 8 unreadable sectors',
      'Device: /dev/sda [SAT], 1 Offline uncorrectable sectors':
          'Disk sda has 1 uncorrectable sector',
      'Device: /dev/sda [SAT], FAILED SMART self-check. BACK UP DATA NOW!':
          'Disk sda failed its SMART health check',
      'Device: /dev/sda, Self-Test Log error count increased from 0 to 1':
          'Disk sda failed a SMART self-test',
      'Device: /dev/sda [SAT], ATA error count increased from 0 to 3':
          'Disk sda reports 3 ATA errors',
      'Device: /dev/sda [SAT], not capable of SMART self-check':
          'Disk sda reports a SMART problem',
    };
    for (final MapEntry(:key, :value) in cases.entries) {
      expect(trueNasAlertHeadline(smart(key)), value, reason: key);
    }
    expect(
      trueNasAlertHeadline(
        alert({
          'klass': 'SMART',
          'formatted':
              'Device: /dev/nvme0n1, 2 Currently unreadable (pending) sectors.',
        }),
      ),
      'Disk nvme0n1 has 2 unreadable sectors',
      reason: 'the disk from the message when the args are gone',
    );
  });

  test('a SMART alert from 25.10 reads its class and its disk', () {
    TrueNasAlert smart(String klass) => alert({
      'klass': klass,
      'formatted': 'sdb (W1) said something.',
      'args': {'name': 'sdb', 'serial': 'W1'},
    });
    expect(
      trueNasAlertHeadline(smart('SMARTFailedSelfTest')),
      'Disk sdb failed a SMART self-test',
    );
    expect(
      trueNasAlertHeadline(smart('SMARTSpareBlockCount')),
      'Disk sdb is running low on spare blocks',
    );
    expect(
      trueNasAlertHeadline(smart('SMARTEraseCycleCount')),
      'Disk sdb has a high erase count',
    );
    expect(
      trueNasAlertHeadline(
        alert({
          'klass': 'SMARTUncorrectedErrors',
          'formatted': '3 uncorrectable errors reported for sdb (W1).',
          'args': {'ue': 3, 'name': 'sdb', 'serial': 'W1'},
        }),
      ),
      'Disk sdb reports 3 uncorrectable errors',
    );
  });

  test('any other alert reads its first sentence', () {
    expect(
      trueNasAlertHeadline(
        alert({
          'formatted':
              'Pool tank state is DEGRADED. One or more devices are faulted.',
        }),
      ),
      'Pool tank state is DEGRADED',
    );
  });

  test('warning and worse need somebody; info and notice are news', () {
    for (final level in ['WARNING', 'ERROR', 'CRITICAL', 'ALERT']) {
      expect(alert({'level': level}).needsAttention, isTrue, reason: level);
    }
    for (final level in ['INFO', 'NOTICE']) {
      expect(alert({'level': level}).needsAttention, isFalse, reason: level);
    }
  });
}
