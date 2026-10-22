@Tags(['e2e'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/capability/capability_scope.dart';
import 'package:cupola/core/network/cert_trust.dart';
import 'package:cupola/features/truenas/data/apps_api.dart';
import 'package:cupola/features/truenas/data/auth_api.dart';
import 'package:cupola/features/truenas/data/credentials_api.dart';
import 'package:cupola/features/truenas/data/data_protection_api.dart';
import 'package:cupola/features/truenas/data/dataset_api.dart';
import 'package:cupola/features/truenas/data/sharing_api.dart';
import 'package:cupola/features/truenas/data/storage_api.dart';
import 'package:cupola/features/truenas/data/system_api.dart';
import 'package:cupola/features/truenas/data/truenas_ws_client.dart';
import 'package:cupola/features/truenas/data/virt_api.dart';
import 'package:cupola/features/truenas/domain/models/alert.dart';
import 'package:cupola/features/truenas/domain/models/data_protection.dart';
import 'package:cupola/features/truenas/domain/models/dataset.dart';
import 'package:cupola/features/truenas/domain/models/service_item.dart';
import 'package:cupola/features/truenas/domain/truenas_capability.dart';
import 'package:cupola/features/truenas/domain/truenas_version.dart';
import 'package:cupola/features/truenas/presentation/truenas_capability.dart';

/// The stateful TrueNAS simulator, through the app's own client.
///
/// Covers I-09..I-15 of the flow catalogue (`A-20261021-catalogo-dei-flussi-4a87`):
/// scrub, datasets and snapshots, SMB and NFS shares, users and groups and
/// services, apps and virt instances, alerts and the update, power, and the
/// read-only key. It is not a UI journey: it proves the client and the
/// simulator agree on every answer and on every transition, which is what the
/// journeys in L12 stand on.
///
/// Bring the simulator into its starting state first (it is idempotent):
///
///     python3 test/e2e/testlab/testlab.py scenario apply truenas-state
///
/// Then:
///
///     export CUPOLA_TESTLAB_CREDENTIALS_FILE="$PWD/.ai/scratch/zz_testlab/state/credentials.env"
///     flutter test test/e2e/testlab_truenas_e2e_test.dart --tags e2e --run-skipped
///
/// The credentials file supplies the certificate fingerprint the app needs to
/// trust the lab's self-signed certificate. The address is the one a person
/// saves, `https://127.0.0.1:8460`, and the client dials `wss://` from it.
void main() {
  final credentials = _loadCredentials();

  setUp(() async {
    // Every case starts from the prepared world: a transition is only proven
    // from a known state, and a previous case's leftovers would hide one.
    await _control('POST', '/testlab/reset');
    await _control('POST', '/testlab/scenario', {'name': 'truenas-state'});
  });

  tearDownAll(() async {
    // Leave the base world behind: no jobs, no staged update, no marker.
    await _control('POST', '/testlab/reset');
  });

  TrueNasWsClient admin({Duration callTimeout = const Duration(seconds: 20)}) =>
      TrueNasWsClient(
        baseUrl: _url,
        apiKey: 'test-key',
        certFingerprint: credentials[_pinVariable]!,
        callTimeout: callTimeout,
      );

  test('I-09 TrueNAS: a scrub is a job, then the pool reports it, then it '
      'stops', () async {
    final client = admin();
    addTearDown(client.close);
    final storage = TrueNasStorageApi(client);
    final protection = TrueNasDataProtectionApi(client);

    final before = await storage.getPool('tank');
    expect(before, isNotNull, reason: 'the tank pool is in the world');
    expect(before!.isScanning, isFalse);
    expect(before.healthy, isTrue);
    expect(before.scanState?.toUpperCase(), 'FINISHED');

    // The pool page's "Start scrub": `pool.scrub.scrub` with START, fire and
    // forget, which is how the app calls it.
    await storage.runScrub('tank');

    final scanning = await _eventually(
      () => storage.getPool('tank'),
      (pool) =>
          pool != null &&
          pool.isScanning &&
          (pool.scanPercentage ?? 0) > 0,
      label: 'the scrub to start and move',
    );
    expect(scanning!.scanFunction?.toUpperCase(), 'SCRUB');
    expect(scanning.scanPercentage, greaterThan(0));

    // The job the middleware reports for it, with real progress.
    final jobs = await client.call('core.get_jobs');
    expect(jobs, isA<List>());
    final scrubJob = (jobs as List)
        .whereType<Map>()
        .where((job) => job['method'] == 'pool.scrub.scrub')
        .where((job) => job['state'] == 'RUNNING')
        .toList();
    expect(scrubJob, hasLength(1), reason: 'one running scrub job');
    final progress = scrubJob.single['progress'] as Map;
    expect(progress['percent'], isA<num>());

    // The data protection page reads the task by pool name, from
    // `pool.scrub.query`, and runs it with `pool.scrub.run`.
    final tasks = await protection.getTasks(TrueNasTaskKind.scrub);
    final tank = tasks.firstWhere((task) => task.poolName == 'tank');
    expect(tank.title, 'tank');
    expect(tank.enabled, isTrue);

    await storage.runScrub('tank', action: 'STOP');
    final stopped = await _eventually(
      () => storage.getPool('tank'),
      (pool) => pool != null && !pool.isScanning,
      label: 'the scrub to stop',
    );
    expect(stopped!.scanState?.toUpperCase(), 'FINISHED');

    // The other path the screen offers: "Run now" on the task, keyed by pool
    // name with a threshold of 0, which the simulator starts as its own job.
    await protection.run(tank);
    await _eventually(
      () => storage.getPool('tank'),
      (pool) => pool != null && pool.isScanning,
      label: 'the task to start a scrub',
    );
    await storage.runScrub('tank', action: 'STOP');
    await _eventually(
      () => storage.getPool('tank'),
      (pool) => pool != null && !pool.isScanning,
      label: 'the task scrub to stop',
    );
  });

  test('I-10 TrueNAS: datasets and snapshots are created, edited, read and '
      'deleted', () async {
    final client = admin();
    addTearDown(client.close);
    final api = TrueNasDatasetApi(client);

    await api.createDataset({
      'name': 'tank/media/podcasts',
      'type': 'FILESYSTEM',
      'comments': 'Cupola e2e',
    });
    final podcasts = await api.getDataset('tank/media/podcasts');
    expect(podcasts, isNotNull);
    expect(podcasts!.id, 'tank/media/podcasts');

    List<String> identifiers(List<TrueNasDataset> nodes) => [
      for (final node in nodes) ...[node.id, ...identifiers(node.children)],
    ];

    final tree = await api.getDatasetTree();
    expect(identifiers(tree), contains('tank/media/podcasts'));
    expect(
      identifiers(tree),
      containsAll(['tank/media/movies', 'tank/media/series']),
      reason: 'the world the shares and the arr instances live on',
    );

    await api.updateDataset('tank/media/podcasts', {'comments': 'Edited'});
    final edited = await api.getDataset('tank/media/podcasts');
    expect(edited, isNotNull);
    expect(edited!.comments, 'Edited');
    expect(edited.mountpoint, '/mnt/tank/media/podcasts');

    await api.createSnapshot('tank/media/podcasts', 'cupola-e2e');
    final snapshots = await api.getSnapshots('tank/media/podcasts');
    expect(snapshots.map((snapshot) => snapshot.name).toList(), ['cupola-e2e']);
    expect(snapshots.single.createdMs, isNotNull);

    await api.deleteSnapshot(snapshots.single.id);
    expect(await api.getSnapshots('tank/media/podcasts'), isEmpty);

    await api.deleteDataset('tank/media/podcasts');
    expect(await api.getDataset('tank/media/podcasts'), isNull);
    expect(
      identifiers(await api.getDatasetTree()),
      isNot(contains('tank/media/podcasts')),
    );
  });

  test('I-11 TrueNAS: SMB and NFS shares are created, toggled and deleted, and '
      'their services start and stop', () async {
    final client = admin();
    addTearDown(client.close);
    final sharing = TrueNasSharingApi(client);
    final system = TrueNasSystemApi(client);

    final smbBefore = await sharing.getSmbShares();
    expect(
      smbBefore.map((share) => share.name),
      containsAll(['media', 'downloads']),
    );

    await sharing.createSmbShare({
      'path': '/mnt/tank/media/books',
      'name': 'books',
      'comment': 'Cupola e2e',
      'enabled': true,
    });
    var shares = await sharing.getSmbShares();
    final books = shares.firstWhere((share) => share.name == 'books');
    expect(books.path, '/mnt/tank/media/books');
    expect(books.enabled, isTrue);

    await sharing.setSmbEnabled(books.id, false);
    shares = await sharing.getSmbShares();
    expect(
      shares.firstWhere((share) => share.name == 'books').enabled,
      isFalse,
    );
    await sharing.deleteSmbShare(books.id);
    shares = await sharing.getSmbShares();
    expect(shares.map((share) => share.name), isNot(contains('books')));

    await sharing.createNfsShare({
      'path': '/mnt/tank/media/books',
      'comment': 'Cupola e2e',
      'enabled': true,
    });
    var exports = await sharing.getNfsShares();
    final booksExport = exports.firstWhere(
      (share) => share.paths.contains('/mnt/tank/media/books'),
    );
    expect(booksExport.enabled, isTrue);
    await sharing.setNfsEnabled(booksExport.id, false);
    exports = await sharing.getNfsShares();
    expect(
      exports.firstWhere((share) => share.id == booksExport.id).enabled,
      isFalse,
    );
    await sharing.deleteNfsShare(booksExport.id);
    exports = await sharing.getNfsShares();
    expect(
      exports.any((share) => share.paths.contains('/mnt/tank/media/books')),
      isFalse,
    );

    // The banner above the two tabs starts and stops the service itself.
    await system.startService('nfs');
    var services = await system.getServices();
    expect(_service(services, 'nfs').running, isTrue);
    await system.stopService('nfs');
    services = await system.getServices();
    expect(_service(services, 'nfs').running, isFalse);
    expect(
      _service(services, 'cifs').running,
      isTrue,
      reason: 'stopping NFS leaves SMB alone',
    );
  });

  test(
    'I-12 TrueNAS: users, groups and the autostart switch are real changes',
    () async {
      final client = admin();
      addTearDown(client.close);
      final accounts = TrueNasCredentialsApi(client);
      final system = TrueNasSystemApi(client);

      final usersBefore = await accounts.getUsers();
      expect(
        usersBefore.map((user) => user.username),
        containsAll(['anna', 'luca']),
      );

      await accounts.createGroup({'name': 'cupola-e2e'});
      var groups = await accounts.getGroups();
      final group = groups.firstWhere((row) => row.name == 'cupola-e2e');
      expect(group.builtin, isFalse);

      await accounts.createUser({
        'username': 'cupola-e2e',
        'full_name': 'Cupola E2E',
        // The simulator authenticates nobody with this: it exists because the
        // screen sends the field, and the contract is about the write landing.
        'password': 'x',
        'group_create': true,
      });
      var users = await accounts.getUsers();
      final user = users.firstWhere((row) => row.username == 'cupola-e2e');
      expect(user.fullName, 'Cupola E2E');
      expect(users.map((row) => row.username), contains('cupola-e2e'));

      await accounts.deleteUser(user.id, deletePrimaryGroup: true);
      users = await accounts.getUsers();
      expect(users.map((row) => row.username), isNot(contains('cupola-e2e')));
      groups = await accounts.getGroups();
      expect(groups.map((row) => row.name), isNot(contains('cupola-e2e')));

      // The Services page: start, stop and the autostart switch, by id.
      final services = await system.getServices();
      final smartd = _service(services, 'smartd');
      expect(smartd.running, isTrue);
      await system.setServiceAutostart(smartd.id!, false);
      expect(
        _service(await system.getServices(), 'smartd').enabled,
        isFalse,
        reason: 'autostart off does not stop the service',
      );
      expect(_service(await system.getServices(), 'smartd').running, isTrue);
      await system.setServiceAutostart(smartd.id!, true);
      expect(_service(await system.getServices(), 'smartd').enabled, isTrue);
    },
  );

  test(
    'I-13 TrueNAS: apps and virt instances move through their jobs',
    () async {
      final client = admin();
      addTearDown(client.close);
      final apps = TrueNasAppsApi(client);
      final virt = TrueNasVirtApi(client);

      final listed = await apps.getApps();
      expect(
        listed.map((app) => app.name),
        containsAll(['jellyfin', 'immich']),
      );
      final jellyfin = await apps.getApp('jellyfin');
      expect(jellyfin, isNotNull);
      expect(
        jellyfin!.upgradeAvailable,
        isTrue,
        reason: 'the scenario leaves an upgrade waiting',
      );

      // Starting Immich: callJob waits on core.get_jobs, which is what the app's
      // action does before it reports success.
      await apps.start('immich');
      expect((await apps.getApp('immich'))!.state, 'RUNNING');
      await apps.stop('immich');
      expect((await apps.getApp('immich'))!.state, 'STOPPED');

      await apps.upgrade('jellyfin');
      final upgraded = await apps.getApp('jellyfin');
      expect(upgraded!.upgradeAvailable, isFalse);
      expect(upgraded.humanVersion, isNot(jellyfin.humanVersion));

      final beforeDelete = await apps.getApps();
      expect(beforeDelete.map((app) => app.name), contains('paperless'));
      await apps.delete('paperless');
      expect(
        (await apps.getApps()).map((app) => app.name),
        isNot(contains('paperless')),
      );

      final global = await virt.getGlobalConfig();
      expect(global.isReady, isTrue);
      expect(await virt.getInstances('VM'), hasLength(1));
      final devices = await virt.getDevices('cupola-vm');
      expect(devices, isNotEmpty);
      expect(devices.first.type, isNotEmpty);

      final vm = await virt.getInstance('cupola-vm');
      expect(vm, isNotNull);
      expect(vm!.isRunning, isFalse);
      await virt.start('cupola-vm');
      expect((await virt.getInstance('cupola-vm'))!.status, 'RUNNING');
      await virt.restart('cupola-vm');
      expect((await virt.getInstance('cupola-vm'))!.status, 'RUNNING');
      await virt.stop('cupola-vm');
      expect((await virt.getInstance('cupola-vm'))!.status, 'STOPPED');

      await virt.create({
        'name': 'cupola-ct',
        'instance_type': 'CONTAINER',
        'source_type': 'IMAGE',
        'image': 'alpine/3.21',
        'cpu': '2',
        'memory': 1073741824,
      });
      final containers = await virt.getInstances('CONTAINER');
      final created = containers.firstWhere(
        (instance) => instance.name == 'cupola-ct',
      );
      expect(created.isVm, isFalse);
      expect(created.status, 'STOPPED');
      await virt.delete('cupola-ct');
      expect(
        (await virt.getInstances('CONTAINER')).map((instance) => instance.name),
        isNot(contains('cupola-ct')),
      );
    },
  );

  test('I-14 TrueNAS: alerts dismiss, the update is named, and power drops the '
      'socket', () async {
    final client = admin(callTimeout: const Duration(seconds: 5));
    addTearDown(client.close);
    final system = TrueNasSystemApi(client);

    final alerts = await system.getAlerts();
    expect(alerts, isNotEmpty);
    final updateNotice = alerts.firstWhere(
      (alert) => alert.id == 'alert-update-available',
    );
    expect(updateNotice.dismissed, isFalse);
    final diskAlert = alerts.firstWhere(
      (alert) => alert.id == 'alert-smart-sdh',
    );
    expect(diskAlert.level, 'CRITICAL');
    expect(trueNasDiskErrors(diskAlert)?.disk, 'sdh');
    expect(
      trueNasAlertHeadline(diskAlert),
      'Disk sdh reports 8 uncorrectable errors',
    );

    await system.dismissAlert(updateNotice.id);
    final after = await system.getAlerts();
    expect(
      after.firstWhere((alert) => alert.id == updateNotice.id).dismissed,
      isTrue,
    );
    expect(
      after.firstWhere((alert) => alert.id == 'alert-smart-sdh').dismissed,
      isFalse,
      reason: 'dismissing one alert leaves the others',
    );

    final update = await system.checkUpdateAvailable();
    expect(update['status'], 'AVAILABLE');
    expect(update['version'], isA<String>());

    // A reboot kills the middleware under the reply: the call never returns,
    // the socket closes, and only the control surface can bring it back.
    unawaited(system.reboot().then<void>((_) {}, onError: (Object _) {}));
    final power = await _eventually(
      () => _control('GET', '/testlab/health'),
      (state) => state['power'] != 'on',
      label: 'the reboot to cut the socket',
    );
    expect(power['power'], 'rebooting');
    await expectLater(
      client.call('core.ping'),
      throwsA(isA<TrueNasException>()),
      reason: 'the socket the reboot killed does not answer',
    );

    await _control('POST', '/testlab/power', {'state': 'on'});
    final restarted = admin();
    addTearDown(restarted.close);
    expect(await restarted.call('core.ping'), 'pong');
    final info = await TrueNasSystemApi(restarted).getSystemInfo();
    expect(
      info.uptimeSeconds,
      lessThan(120),
      reason: 'the machine just came up',
    );

    // Shutdown is the same cut, and the same way back.
    final second = admin(callTimeout: const Duration(seconds: 5));
    addTearDown(second.close);
    unawaited(
      TrueNasSystemApi(
        second,
      ).shutdown().then<void>((_) {}, onError: (Object _) {}),
    );
    final down = await _eventually(
      () => _control('GET', '/testlab/health'),
      (state) => state['power'] != 'on',
      label: 'the shutdown to cut the socket',
    );
    expect(down['power'], 'shutdown');
    await _control('POST', '/testlab/power', {'state': 'on'});
  });

  test(
    'I-15 TrueNAS: a read-only key reads everything and changes nothing',
    () async {
      final readonlyClient = TrueNasWsClient(
        baseUrl: _url,
        apiKey: 'test-readonly',
        certFingerprint: credentials[_pinVariable]!,
        callTimeout: const Duration(seconds: 20),
      );
      addTearDown(readonlyClient.close);

      final roles = await TrueNasAuthApi(readonlyClient).myRoles();
      expect(roles, isNotNull);
      final readonlyRoles = roles!;
      expect(readonlyRoles, contains('READONLY_ADMIN'));
      expect(
        readonlyRoles.where(
          (role) => role.endsWith('_WRITE') || role.endsWith('_DELETE'),
        ),
        isEmpty,
        reason: 'the read-only key carries no write role',
      );
      expect(readonlyRoles, isNot(contains(trueNasFullAdmin)));

      final system = TrueNasSystemApi(readonlyClient);
      final version = TrueNasVersion.parse(await system.getVersion());
      final services = await system.getServices();
      expect(services, isNotEmpty);
      final grant = trueNasGrantFor(
        readonlyRoles,
        version: version,
        services: services.map((service) => service.name),
      );
      expect(grant.basis, CapabilityBasis.answered);
      expect(
        grant.scope,
        CapabilityScope.readOnly,
        reason: 'the surfaces draw the read-only banner from this grant',
      );

      // Reads stay possible: that is the difference between a read-only key and
      // a broken one.
      expect((await TrueNasStorageApi(readonlyClient).getPools()), isNotEmpty);
      expect(
        await TrueNasDatasetApi(readonlyClient).getDatasetTree(),
        isNotEmpty,
      );

      Future<void> expectRefused(
        String what,
        Future<void> Function() write,
      ) async {
        await expectLater(
          write(),
          throwsA(
            isA<TrueNasException>().having(
              (error) => error.forbidden,
              'forbidden',
              isTrue,
            ),
          ),
          reason: what,
        );
      }

      await expectRefused(
        'creating a dataset',
        () => TrueNasDatasetApi(
          readonlyClient,
        ).createDataset({'name': 'tank/media/refused', 'type': 'FILESYSTEM'}),
      );
      await expectRefused(
        'deleting a snapshot',
        () => TrueNasDatasetApi(
          readonlyClient,
        ).deleteSnapshot('tank/media@manual-2026-10-20'),
      );
      await expectRefused(
        'creating an SMB share',
        () => TrueNasSharingApi(
          readonlyClient,
        ).createSmbShare({'name': 'refused', 'path': '/mnt/tank/refused'}),
      );
      await expectRefused(
        'creating a user',
        () => TrueNasCredentialsApi(
          readonlyClient,
        ).createUser({'username': 'refused', 'password': 'x'}),
      );
      await expectRefused(
        'starting a service',
        () => system.startService('nfs'),
      );
      await expectRefused(
        'dismissing an alert',
        () => system.dismissAlert('alert-update-available'),
      );
      await expectRefused(
        'starting an app',
        () => TrueNasAppsApi(readonlyClient).start('immich'),
      );
      await expectRefused(
        'starting a virt instance',
        () => TrueNasVirtApi(readonlyClient).start('cupola-vm'),
      );
      await expectRefused('rebooting the host', () => system.reboot());

      // Nothing moved: a refusal is not a write that half-happened.
      final adminClient = admin();
      addTearDown(adminClient.close);
      expect(
        (await TrueNasAppsApi(adminClient).getApp('immich'))!.state,
        'STOPPED',
      );
      expect(
        _service(
          await TrueNasSystemApi(adminClient).getServices(),
          'nfs',
        ).running,
        isFalse,
      );
      expect(
        (await TrueNasVirtApi(adminClient).getInstance('cupola-vm'))!.status,
        'STOPPED',
      );
      expect(
        (await TrueNasSystemApi(adminClient).getAlerts())
            .firstWhere((alert) => alert.id == 'alert-update-available')
            .dismissed,
        isFalse,
      );
      expect(
        await TrueNasDatasetApi(adminClient).getDataset('tank/media/refused'),
        isNull,
      );
      expect(await TrueNasStorageApi(adminClient).getPool('tank'), isNotNull);
    },
  );
}

/// Which service row the page draws, by name.
TrueNasServiceItem _service(List<TrueNasServiceItem> services, String name) =>
    services.firstWhere((service) => service.name == name);

/// The scenario-driven simulator's address, as a person saves it.
const _url = 'https://127.0.0.1:8460';
const _pinVariable = 'CUPOLA_TESTLAB_TRUENAS_CERT_FINGERPRINT';

/// [read] settles on [predicate], or the case fails with what it saw last.
Future<T> _eventually<T>(
  Future<T> Function() read,
  bool Function(T value) predicate, {
  required String label,
  int attempts = 40,
}) async {
  Object? lastError;
  for (var attempt = 0; attempt < attempts; attempt++) {
    try {
      final value = await read();
      if (predicate(value)) return value;
    } catch (error) {
      lastError = error;
    }
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }
  throw StateError(
    '$label did not settle${lastError == null ? '' : ': $lastError'}',
  );
}

/// One request to the simulator's own control surface, over the lab's TLS.
///
/// The journeys and this suite need to reset the NAS and bring it back after a
/// reboot; that is the API the simulator publishes for the testlab, not a
/// write into its world.
Future<Map<String, dynamic>> _control(
  String method,
  String path, [
  Map<String, dynamic>? body,
]) async {
  final client = buildPinnedHttpClient(
    pinnedFingerprint: _lab[_pinVariable],
    pinnedHost: '127.0.0.1',
    pinnedPort: 8460,
  );
  try {
    final request = await client.openUrl(method, Uri.parse('$_url$path'));
    if (body != null) {
      final bytes = utf8.encode(jsonEncode(body));
      request.headers.contentType = ContentType.json;
      // The simulator's control surface reads Content-Length; HttpClient's
      // write() alone is chunked, and the mock answers "The body is not JSON".
      request.contentLength = bytes.length;
      request.add(bytes);
    }
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      fail('$method $path answered ${response.statusCode}: $text');
    }
    return (jsonDecode(text) as Map).cast<String, dynamic>();
  } finally {
    client.close(force: true);
  }
}

Map<String, String> _lab = const <String, String>{};

Map<String, String> _loadCredentials() {
  final path = Platform.environment['CUPOLA_TESTLAB_CREDENTIALS_FILE'];
  if (path == null || path.isEmpty) {
    fail(
      'CUPOLA_TESTLAB_CREDENTIALS_FILE must point to the bootstrap output '
      '(.ai/scratch/zz_testlab/state/credentials.env)',
    );
  }
  final file = File(path);
  if (!file.existsSync()) fail('Missing testlab credentials file: $path');
  final values = <String, String>{};
  for (final line in file.readAsLinesSync()) {
    if (line.isEmpty || line.startsWith('#')) continue;
    final separator = line.indexOf('=');
    if (separator <= 0) continue;
    values[line.substring(0, separator)] = line.substring(separator + 1);
  }
  _lab = values;
  return values;
}
