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
