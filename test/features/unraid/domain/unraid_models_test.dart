import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/unraid/domain/models/unraid_models.dart';

/// Decision 15 on one row: a container stopped on purpose is neutral, an
/// unexpected exit and an unhealthy one are amber, and red never appears —
/// Unraid answered, so nothing here is an unreachable host.
///
/// Every expectation below is on the *rule* — the condition the status line
/// resolves to and the tone that condition carries — never on a colour value.
UnraidDockerContainer _container({
  required String status,
  String state = 'exited',
  String name = 'plex',
}) {
  return UnraidDockerContainer.fromJson({
    'id': 'abc',
    'names': ['/$name'],
    'state': state,
    'status': status,
    'autoStart': true,
  });
}

void main() {
  group('UnraidDockerContainer — the status line is read, not skimmed', () {
    test('a clean exit is a deliberate stop, and neutral', () {
      final container = _container(status: 'Exited (0) 2 days ago');

      expect(container.condition, UnraidContainerCondition.stopped);
      expect(container.tone, StatusTone.neutral);
      expect(container.exitCode, 0);
      expect(container.summary, 'stopped on purpose · exit 0 · 2 days ago');
    });

    test('a non-zero exit is a fault, and amber', () {
      // 137 is the OOM kill — the case the design names by number.
      final container = _container(status: 'Exited (137) 3 hours ago');

      expect(container.condition, UnraidContainerCondition.exitedUnexpectedly);
      expect(container.tone, StatusTone.warning);
      expect(container.exitCode, 137);
      expect(container.summary, contains('exit 137'));
    });

    test('a failing healthcheck is amber while the container is still up', () {
      final container = _container(
        status: 'Up 20 minutes (unhealthy)',
        state: 'running',
      );

      expect(container.condition, UnraidContainerCondition.unhealthy);
      expect(container.tone, StatusTone.warning);
      expect(container.running, isFalse, reason: 'up, but not healthy');
    });

    test('a passing healthcheck reads exactly like no healthcheck', () {
      final healthy = _container(
        status: 'Up 2 hours (healthy)',
        state: 'running',
      );
      final plain = _container(status: 'Up 3 days', state: 'running');

      expect(healthy.condition, UnraidContainerCondition.running);
      expect(plain.condition, UnraidContainerCondition.running);
      expect(healthy.tone, StatusTone.success);
      expect(plain.summary, 'running · 3 days');
    });

    test('a paused container is deliberate, so neutral', () {
      final container = _container(
        status: 'Up 5 days (Paused)',
        state: 'running',
      );

      expect(container.condition, UnraidContainerCondition.paused);
      expect(container.tone, StatusTone.neutral);
    });

    test('a restart loop is a fault: Docker only reports it after an exit', () {
      final container = _container(status: 'Restarting (1) 5 seconds ago');

      expect(container.condition, UnraidContainerCondition.restarting);
      expect(container.tone, StatusTone.warning);
      expect(container.exitCode, 1);
    });

    test(
      'an unreadable status keeps the server\'s own words and stays neutral',
      () {
        final container = _container(status: 'Removal In Progress');

        expect(container.condition, UnraidContainerCondition.unknown);
        expect(container.tone, StatusTone.neutral);
        expect(container.summary, 'Removal In Progress');
      },
    );

    test('an unparsed exit code is null, never 0', () {
      // "Exited" with no code says the container is down and nothing about how.
      // Reporting 0 there would claim a clean stop the payload never made.
      final container = _container(status: 'Exited');

      expect(container.exitCode, isNull);
      expect(container.condition, UnraidContainerCondition.unknown);
    });

    test('an empty status falls back to the two-member state enum', () {
      expect(
        _container(status: '', state: 'RUNNING').condition,
        UnraidContainerCondition.running,
      );
      expect(
        _container(status: '', state: 'EXITED').condition,
        UnraidContainerCondition.unknown,
      );
    });
  });

  group('UnraidDisk', () {
    UnraidDisk disk(String status, {int? temp}) =>
        UnraidDisk.fromJson({'name': 'disk1', 'status': status, 'temp': temp});

    test('a slot with no temperature is spun down, not 0 °C', () {
      expect(disk('DISK_OK').spunDown, isTrue);
      expect(disk('DISK_OK').warm, isFalse);
      expect(disk('DISK_OK', temp: 34).spunDown, isFalse);
    });

    test('a healthy cool slot carries no tone at all', () {
      expect(disk('DISK_OK', temp: 34).tone, StatusTone.neutral);
    });

    test('Unraid\'s own 45 °C warning threshold is the amber line', () {
      expect(disk('DISK_OK', temp: 44).tone, StatusTone.neutral);
      expect(disk('DISK_OK', temp: 45).tone, StatusTone.warning);
    });

    test(
      'a slot the array is unhappy about is amber whatever its temperature',
      () {
        expect(disk('DISK_DSBL', temp: 30).tone, StatusTone.warning);
        expect(disk('DISK_INVALID').tone, StatusTone.warning);
      },
    );

    test('no status is not a verdict', () {
      expect(disk('', temp: 30).tone, StatusTone.neutral);
    });
  });
}
