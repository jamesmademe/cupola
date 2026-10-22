@Tags(['e2e'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/unraid/data/unraid_client.dart';
import 'package:cupola/features/unraid/domain/models/unraid_models.dart';
import 'package:cupola/features/unraid/domain/unraid_alerts.dart';
import 'package:cupola/features/unraid/presentation/unraid_overview_provider.dart';

/// Unraid in the macOS lab, through Cupola's own client: the flow catalogue's
/// I-16 to I-18, and I-19 held as what it is, an absence.
///
/// The state comes from the `unraid-state` scenario, which owns the
/// simulator's world in `test/e2e/testlab/mock_unraid/`:
///
/// ~~~bash
/// python3 test/e2e/testlab/testlab.py scenario apply unraid-state
/// flutter test --tags e2e --run-skipped test/e2e/testlab_unraid_e2e_test.dart
/// python3 test/e2e/testlab/testlab.py scenario teardown unraid-state
/// ~~~
///
/// This file resets the world before every test and again at the end, so a run
/// is repeatable without the scenario and leaves the lab where it found it:
/// the two flows it proves are *transitions*, and an archived notification
/// does not come back through the API. The full answer-by-answer check, field
/// against fixture, is `unraid_contract.py`; here the client is the reader.
///
/// The keys are the ones the Compose service fixes, not secrets. Pass
/// `CUPOLA_TESTLAB_UNRAID_URL`, `CUPOLA_TESTLAB_UNRAID_KEY` and
/// `CUPOLA_TESTLAB_UNRAID_READONLY_KEY` to point the test elsewhere.
void main() {
  late UnraidClient admin;
  late UnraidClient readonly;

  setUpAll(() async {
    admin = UnraidClient(url: _url, apiKey: _adminKey);
    readonly = UnraidClient(url: _url, apiKey: _readonlyKey);
    await _waitForSimulator();
  });

  // Every test starts from the documented world: these flows are transitions,
  // and a test that inherits the previous one's VM state or archive would pass
  // or fail on the order it happened to run in.
  setUp(() async {
    await _reset();
  });

  tearDownAll(() async {
    await _reset();
    admin.close();
    readonly.close();
  });

  group('I-16 Unraid: start, stop, resume and pause a VM', () {
    test('the domain list carries the four libvirt states', () async {
      final vms = await admin.getVms();
      final byId = {for (final vm in vms) vm.id: vm};

      expect(
        byId.keys,
        containsAll(const [
          'vm:homeassistant',
          'vm:windows',
          'vm:nasbackup',
          'vm:retro',
        ]),
      );
      expect(byId['vm:homeassistant']!.isRunning, isTrue);
      expect(byId['vm:windows']!.state, 'SHUTOFF');
      expect(byId['vm:nasbackup']!.isPaused, isTrue);
      expect(byId['vm:retro']!.isFaulted, isTrue);
      expect(byId['vm:retro']!.tone, StatusTone.warning);
      expect(byId['vm:windows']!.tone, StatusTone.neutral);
    });

    test('start and stop move a guest, and the next read says so', () async {
      expect(
        await admin.runVmAction('vm:windows', UnraidVmAction.start),
        isTrue,
        reason: 'start on a stopped guest is accepted',
      );
      expect(await _stateOf(admin, 'vm:windows'), 'RUNNING');

      expect(
        await admin.runVmAction('vm:windows', UnraidVmAction.stop),
        isTrue,
        reason: 'stop on a running guest is accepted',
      );
      expect(await _stateOf(admin, 'vm:windows'), 'SHUTOFF');
    });

    test('pause and resume move a running guest and the next read '
        'says so', () async {
      expect(
        await admin.runVmAction('vm:homeassistant', UnraidVmAction.pause),
        isTrue,
      );
      expect(await _stateOf(admin, 'vm:homeassistant'), 'PAUSED');

      expect(
        await admin.runVmAction('vm:homeassistant', UnraidVmAction.resume),
        isTrue,
      );
      expect(await _stateOf(admin, 'vm:homeassistant'), 'RUNNING');
    });

    test('a transition the daemon refuses is false, not a throw', () async {
      // The arm the screen answers with "<vm> did not accept <verb>": the
      // mutation ran, the daemon refused it, and the answer says so.
      expect(
        await admin.runVmAction('vm:homeassistant', UnraidVmAction.start),
        isFalse,
        reason: 'the guest is already running',
      );
      expect(
        await admin.runVmAction('vm:windows', UnraidVmAction.stop),
        isFalse,
        reason: 'the guest is already stopped',
      );
      expect(
        await admin.runVmAction('vm:windows', UnraidVmAction.resume),
        isFalse,
        reason: 'the guest is not paused',
      );
      expect(await _stateOf(admin, 'vm:windows'), 'SHUTOFF');
    });

    test('an id no domain answers throws, and nothing moves', () async {
      await expectLater(
        admin.runVmAction('vm:nowhere', UnraidVmAction.start),
        throwsA(isA<UnraidException>()),
      );
      expect(await _stateOf(admin, 'vm:homeassistant'), 'RUNNING');
      expect(await _stateOf(admin, 'vm:windows'), 'SHUTOFF');
    });

    test('a read-only key changes nothing, and its refusal is a '
        'permission', () async {
      final capabilities = await readonly.getCapabilities();
      expect(capabilities.answered, isTrue);
      expect(capabilities.isAdmin, isFalse);
      expect(capabilities.writable, isEmpty);
      expect(capabilities.canWrite(UnraidResource.vms), isFalse);

      await expectLater(
        readonly.runVmAction('vm:windows', UnraidVmAction.start),
        throwsA(
          isA<UnraidException>()
              .having((error) => error.forbidden, 'forbidden', isTrue)
              .having(
                (error) => error.isPermissionRefusal,
                'isPermissionRefusal',
                isTrue,
              )
              .having(
                (error) => error.message,
                'message',
                contains('Forbidden resource'),
              ),
        ),
      );

      expect(
        await _stateOf(admin, 'vm:windows'),
        'SHUTOFF',
        reason: 'the refused mutation left the guest alone',
      );
    });
  });

  group('I-17 Unraid: the unread list and the archive', () {
    test('the unread list carries three rows and the overview counts '
        'them', () async {
      final notifications = await admin.getNotifications();

      expect(notifications.items, hasLength(3));
      expect(notifications.unread.total, 3);
      expect(notifications.unread.info, 1);
      expect(notifications.unread.warning, 1);
      expect(notifications.unread.alert, 1);
      expect(notifications.archived.total, 1);

      final disabled = notifications.items.singleWhere(
        (item) => item.id == 'notification:disk2-disabled',
      );
      expect(disabled.importance, 'ALERT');
      expect(disabled.tone, StatusTone.warning);
      expect(disabled.title, contains('Disk 2'));
      expect(disabled.timestamp, isNotNull);
    });

    test('archiving takes the row out of the unread list', () async {
      final archived = await admin.archiveNotification(
        'notification:disk2-disabled',
      );
      expect(archived.id, 'notification:disk2-disabled');
      expect(archived.type, 'ARCHIVE');
      expect(archived.title, contains('Disk 2'));

      final unread = await admin.getNotifications();
      expect(
        unread.items.map((item) => item.id),
        isNot(contains('notification:disk2-disabled')),
      );
      expect(unread.items, hasLength(2));
      expect(unread.unread.total, 2);
      expect(unread.archived.total, 2);

      final archive = await admin.getNotifications(
        type: UnraidNotificationType.archive,
      );
      expect(
        archive.items.map((item) => item.id),
        contains('notification:disk2-disabled'),
      );
      expect(archive.items.first.id, 'notification:disk2-disabled');
      expect(archive.items.first.type, 'ARCHIVE');
    });

    test('a read-only key cannot archive, and nothing is archived', () async {
      final before = await admin.getNotifications(
        type: UnraidNotificationType.archive,
      );

      await expectLater(
        readonly.archiveNotification('notification:cache-hot'),
        throwsA(
          isA<UnraidException>()
              .having(
                (error) => error.isPermissionRefusal,
                'isPermissionRefusal',
                isTrue,
              )
              .having(
                (error) => error.message,
                'message',
                contains('Forbidden resource'),
              ),
        ),
      );

      final after = await admin.getNotifications(
        type: UnraidNotificationType.archive,
      );
      expect(
        after.items.map((item) => item.id).toList(),
        before.items.map((item) => item.id).toList(),
      );
    });
  });

  group('I-18 Unraid: the array, the containers and the shares', () {
    test('the array is started, sixty per cent used, with one disabled '
        'disk', () async {
      final array = await admin.getArray();

      expect(array.state, 'STARTED');
      expect(unraidArrayStateWords(array.state), 'Started');
      expect(array.usedPercent, 60);
      expect(array.usedBytes, 6000000000 * 1024);
      expect(array.totalBytes, 10000000000 * 1024);

      expect(array.parities, hasLength(2));
      expect(array.caches, hasLength(1));
      expect(
        array.drives,
        hasLength(4),
        reason: 'the empty second parity is a slot, not a drive',
      );
      expect(
        array.parities.singleWhere((disk) => disk.name == 'parity2').empty,
        isTrue,
      );
      expect(array.caches.single.warm, isTrue, reason: 'cache at 47 C');

      final disk2 = array.disks.singleWhere((disk) => disk.name == 'disk2');
      expect(disk2.status, 'DISK_DSBL');
      expect(disk2.flagged, isTrue);
      expect(disk2.spunDown, isTrue);
      expect(disk2.tone, StatusTone.warning);
      expect(unraidFlaggedSlotHeadline(disk2), 'Disk 2 is disabled');
    });

    test('the disabled disk is what Needs you says, once', () async {
      final array = await admin.getArray();
      final notifications = await admin.getNotifications();
      final alerts = unraidAlerts(array: array, notifications: notifications);

      expect(alerts.map((alert) => alert.id), contains('slot-disk2'));
      expect(
        alerts.where((alert) => alert.id == 'slot-disk2').single.title,
        'Disk 2 is disabled',
      );
      // The alert about the same slot is the slot said twice: the slot is the
      // lasting fact, the notification is not repeated beside it.
      expect(
        alerts.where((alert) => !alert.isDisk).map((alert) => alert.id),
        isNot(contains('notification-notification:disk2-disabled')),
      );
    });

    test(
      'docker reports the lab stack, and the stops are told apart',
      () async {
        final containers = await admin.getDockerContainers();
        expect(containers, hasLength(14));

        final plex = containers.singleWhere((row) => row.name == 'plex');
        expect(plex.running, isTrue);
        expect(plex.condition, UnraidContainerCondition.running);
        expect(plex.age, '3 days');
        expect(plex.autoStart, isTrue);
        expect(plex.tone, StatusTone.success);

        // Exited 0: somebody stopped it, and that is not damage.
        final readarr = containers.singleWhere((row) => row.name == 'readarr');
        expect(readarr.condition, UnraidContainerCondition.stopped);
        expect(readarr.exitCode, 0);
        expect(readarr.age, '4 hours ago');
        expect(readarr.tone, StatusTone.neutral);

        // Exited 137: the OOM kill, which is a fault.
        final nzbget = containers.singleWhere((row) => row.name == 'nzbget');
        expect(nzbget.condition, UnraidContainerCondition.exitedUnexpectedly);
        expect(nzbget.exitCode, 137);
        expect(nzbget.tone, StatusTone.warning);

        // Up and unhealthy: the healthcheck is failing while it is still up.
        final bazarr = containers.singleWhere((row) => row.name == 'bazarr');
        expect(bazarr.condition, UnraidContainerCondition.unhealthy);
        expect(bazarr.age, '2 days');
        expect(bazarr.tone, StatusTone.warning);

        // A restart loop is not two states, it is one container dying again.
        final npm = containers.singleWhere(
          (row) => row.name == 'nginx-proxy-manager',
        );
        expect(npm.condition, UnraidContainerCondition.restarting);
        expect(npm.exitCode, 1);
        expect(npm.tone, StatusTone.warning);
      },
    );

    test('the shares report their used fraction and their pool', () async {
      final shares = await admin.getShares();
      expect(shares, hasLength(3));

      final media = shares.singleWhere((share) => share.name == 'media');
      expect(media.usedFraction, closeTo(0.6, 0.0001));
      expect(media.cached, isFalse);
      expect(media.comment, 'Movies, series and music');

      final appdata = shares.singleWhere((share) => share.name == 'appdata');
      expect(appdata.cached, isTrue);
      expect(appdata.usedFraction, closeTo(0.2, 0.0001));

      final backups = shares.singleWhere((share) => share.name == 'backups');
      expect(backups.luksStatus, 'ENCRYPTED');
    });

    test('the info names the release the app prints', () async {
      final info = await admin.getInfo();
      expect(info.distro, 'Unraid');
      expect(info.version, '7.0.0');
      expect(info.uptime, isNotNull);
      expect(unraidUptimeLabel(info.uptime, now: DateTime.now()), isNotNull);
    });

    test('a read-only key reads every tab', () async {
      expect((await readonly.getInfo()).version, '7.0.0');
      expect((await readonly.getArray()).usedPercent, 60);
      expect(await readonly.getDockerContainers(), hasLength(14));
      expect(await readonly.getShares(), hasLength(3));
      expect(await readonly.getVms(), hasLength(4));
      // The world `setUp` restores: three unread, one archived.
      final notifications = await readonly.getNotifications();
      expect(notifications.items, hasLength(3));
      expect(notifications.archived.total, 1);
    });
  });

  group('I-19 Unraid: container and array writes are declared X', () {
    test('the client has no container or array mutation', () {
      // The catalogue declares this flow impossible because the app offers no
      // such action, and the contract declares no mutation behind one. A
      // dynamic call is the one runtime way to hold an absence in Dart: if a
      // method of this name ever lands, this test starts failing instead of
      // the catalog quietly going stale.
      final dynamic writable = admin;
      expect(() => writable.startContainer('abc123'), throwsNoSuchMethodError);
      expect(() => writable.stopContainer('abc123'), throwsNoSuchMethodError);
      expect(
        () => writable.restartContainer('abc123'),
        throwsNoSuchMethodError,
      );
      expect(() => writable.startArray(), throwsNoSuchMethodError);
      expect(() => writable.stopArray(), throwsNoSuchMethodError);
      expect(() => writable.mountDisk('disk1'), throwsNoSuchMethodError);

      // What it can write: these six verbs on a VM, and one archive.
      expect(
        UnraidVmAction.values.map((action) => action.graphQl).toSet(),
        const {'start', 'stop', 'pause', 'resume', 'forceStop', 'reboot'},
      );
    });
  });
}

/// The simulator's address and the two keys its Compose service fixes.
String get _url =>
    Platform.environment['CUPOLA_TESTLAB_UNRAID_URL'] ??
    'http://127.0.0.1:8480';

String get _adminKey =>
    Platform.environment['CUPOLA_TESTLAB_UNRAID_KEY'] ?? 'test-key';

String get _readonlyKey =>
    Platform.environment['CUPOLA_TESTLAB_UNRAID_READONLY_KEY'] ??
    'cupola-readonly';

Future<String> _stateOf(UnraidClient client, String id) async {
  final vms = await client.getVms();
  return vms.singleWhere((vm) => vm.id == id).state;
}

/// Puts the simulator's world back, through the control route it exposes for
/// the scenario and for this file.
Future<void> _reset() async {
  final http = HttpClient();
  try {
    final request = await http.postUrl(Uri.parse('$_url/control/reset'));
    request.headers.set('x-api-key', _adminKey);
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    expect(
      response.statusCode,
      200,
      reason: 'the simulator answers a reset: $body',
    );
  } finally {
    http.close(force: true);
  }
}

/// The Compose healthcheck's own question, asked until it is yes. A test that
/// fails here is a lab that is not up, not a failure of the client.
Future<void> _waitForSimulator({
  Duration timeout = const Duration(seconds: 60),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    try {
      final http = HttpClient();
      try {
        final request = await http.getUrl(Uri.parse('$_url/graphql'));
        final response = await request.close();
        await response.drain<void>();
        if (response.statusCode == 200) return;
      } finally {
        http.close(force: true);
      }
    } on IOException {
      // Not up yet.
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  fail(
    'No Unraid simulator at $_url. Bring it up with '
    '`docker compose -p cupola-testlab -f docker-compose.testlab.yml '
    'up -d --no-deps unraid-mock`, or run the unraid-state scenario.',
  );
}
