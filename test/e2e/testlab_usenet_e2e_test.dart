@Tags(['e2e'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/nzbget/data/nzbget_client.dart';
import 'package:cupola/features/nzbget/domain/models/nzbget_models.dart';
import 'package:cupola/features/sabnzbd/data/sabnzbd_client.dart';
import 'package:cupola/features/sabnzbd/domain/models/sabnzbd_models.dart';

/// The Usenet chain of the testlab, read through the app's own clients.
///
/// `usenet_sab` and `usenet_nzbget` configure each client on the lab's local
/// NNTP server, add real yEnc NZBs, wait for the downloads, and leave one job
/// per catalog state (D-16). This suite proves what the app reads back: D-10
/// and D-11 for SABnzbd, D-12 for its servers and volume, D-13, D-14 and D-15
/// for NZBGet, and the states themselves. The scenarios are applied in
/// `setUpAll` and torn down in `tearDownAll`, so the lab is left as it was.
///
/// The e2e adds and removes its own two jobs; the scenario cleans them up in
/// its teardown even if a test fails half way.
void main() {
  final credentials = _credentials();

  group('SABnzbd over the local NNTP server', () {
    setUpAll(() => _scenario('apply', 'usenet-sab'));
    tearDownAll(() => _scenario('teardown', 'usenet-sab'));

    test('D-10 the app adds an NZB by URL and SABnzbd downloads it', () async {
      final client = _sab();
      addTearDown(client.close);

      // The scenario's slow job holds the news server's connections. A person
      // would stop it before adding another job, so the test does the same and
      // puts it back afterwards.
      final slow = (await client.getQueue(limit: SabnzbdClient.wholeQueue))
          .slots
          .firstWhere(
            (slot) => slot.filename == _slow,
            orElse: () => fail('the slow job is not in the queue'),
          );
      await client.pauseJob(slow.nzoId);
      await _eventually(
        () => client.getQueue(limit: SabnzbdClient.wholeQueue),
        (current) => _sabStatus(current, _slow) == 'Paused',
        label: 'the slow job stopping',
      );
      addTearDown(() => client.resumeJob(slow.nzoId));

      await client.addUrl(_nzbUrl(_added));
      final history = await _eventually(
        () => client.getHistory(limit: 50),
        (items) => items.any((item) => item.name == _added),
        label: 'the added job reaching the history',
      );
      final added = history.firstWhere((item) => item.name == _added);
      expect(added.status, 'Completed');
      expect(added.bytes, greaterThan(0));
      expect(added.failed, isFalse);

      await client.resumeJob(slow.nzoId);
      await _eventually(
        () => client.getQueue(limit: SabnzbdClient.wholeQueue),
        (current) => _sabStatus(current, _slow) == 'Downloading',
        label: 'the slow job resuming',
      );
    });

    test('D-11 the app reads the queue, and pauses, resumes and deletes '
        'a job', () async {
      final client = _sab();
      addTearDown(client.close);

      // The slow job is the one that cannot finish between two calls, so the
      // pause and the resume are observed for real.
      final queue = await client.getQueue(limit: SabnzbdClient.wholeQueue);
      expect(queue.paused, isFalse);
      final slow = queue.slots.firstWhere(
        (slot) => slot.filename == _slow,
        orElse: () => fail('the slow job is not in the queue'),
      );
      expect(slow.status, 'Downloading');

      await client.pauseJob(slow.nzoId);
      final stopped = await _eventually(
        () => client.getQueue(limit: SabnzbdClient.wholeQueue),
        (current) => _sabStatus(current, _slow) == 'Paused',
        label: 'the job stopping',
      );
      expect(_sabStatus(stopped, _slow), 'Paused');

      await client.resumeJob(slow.nzoId);
      final resumed = await _eventually(
        () => client.getQueue(limit: SabnzbdClient.wholeQueue),
        (current) => _sabStatus(current, _slow) == 'Downloading',
        label: 'the job resuming',
      );
      expect(_sabStatus(resumed, _slow), 'Downloading');

      // The delete path: a job added already paused, so it cannot finish
      // between the add and the delete.
      await client.addUrl(_nzbUrl(_throwaway), priority: -2);
      final added = await _eventually(
        () => client.getQueue(limit: SabnzbdClient.wholeQueue),
        (current) => current.slots.any((slot) => slot.filename == _throwaway),
        label: 'the throwaway job entering the queue',
      );
      final throwaway = added.slots.firstWhere(
        (slot) => slot.filename == _throwaway,
      );
      await client.deleteJob(throwaway.nzoId, deleteFiles: true);
      final removed = await _eventually(
        () => client.getQueue(limit: SabnzbdClient.wholeQueue),
        (current) => current.slots.every((slot) => slot.filename != _throwaway),
        label: 'the throwaway job leaving the queue',
      );
      expect(removed.slots.any((slot) => slot.filename == _throwaway), isFalse);
    });

    test(
      'D-12 the app reads the news servers and the transfer volume',
      () async {
        final client = _sab();
        addTearDown(client.close);

        final servers = await client.getServers();
        final lab = servers.firstWhere(
          (server) => server.name == 'cupola-testlab-nntp',
          orElse: () => fail('SABnzbd lists no lab news server'),
        );
        expect(lab.host, 'host.docker.internal');
        expect(lab.port, 1119);
        expect(lab.connections, 2);
        expect(lab.enabled, isTrue);
        expect(lab.ssl, isFalse);

        final stats = await client.getServerStats();
        expect(stats.total, greaterThan(0));
        expect(
          stats.servers.any(
            (server) =>
                server.name == 'cupola-testlab-nntp' && server.totalBytes > 0,
          ),
          isTrue,
          reason: 'SABnzbd reports no per-server volume for the lab',
        );
      },
    );

    test('D-16 the client states are the queue and the history', () async {
      final client = _sab();
      addTearDown(client.close);

      final queue = await client.getQueue(limit: SabnzbdClient.wholeQueue);
      expect(_sabStatus(queue, _slow), 'Downloading');
      expect(_sabStatus(queue, _paused), 'Paused');

      final history = await client.getHistory(limit: 50);
      expect(_sabHistory(history, _complete)?.status, 'Completed');
      expect(_sabHistory(history, _missing)?.status, 'Failed');
    });
  });

  group('NZBGet over the local NNTP server', () {
    setUpAll(() => _scenario('apply', 'usenet-nzbget'));
    tearDownAll(() => _scenario('teardown', 'usenet-nzbget'));

    // The state tests come first: the ones that follow stop the slow job, and
    // a stopped job is no longer the state the scenario left behind.
    test('D-16 the client states are the queue and the history', () async {
      final client = _nzbget(credentials);
      addTearDown(client.close);

      final groups = await client.listGroups();
      expect(_nzbgetStatus(groups, _slow), 'DOWNLOADING');
      expect(_nzbgetStatus(groups, _waiting), 'QUEUED');
      expect(_nzbgetStatus(groups, _paused), 'PAUSED');

      final history = await client.history();
      final complete = history.firstWhere(
        (item) => item.name == _complete,
        orElse: () => fail('the complete job is not in the history'),
      );
      expect(complete.success, isTrue);
      final missing = history.firstWhere(
        (item) => item.name == _missing,
        orElse: () => fail('the missing job is not in the history'),
      );
      expect(missing.failed, isTrue);
    });

    test('D-14 the app stops, resumes and deletes a job', () async {
      final client = _nzbget(credentials);
      addTearDown(client.close);

      final slow = (await client.listGroups()).firstWhere(
        (group) => group.name == _slow,
        orElse: () => fail('the slow job is not in the queue'),
      );
      expect(slow.status, 'DOWNLOADING');

      await _pauseGroup(client, slow.nzbId);
      final stopped = await _eventually(
        () => client.listGroups(),
        (current) => _nzbgetStatus(current, _slow) == 'PAUSED',
        label: 'the job stopping',
      );
      expect(_nzbgetStatus(stopped, _slow), 'PAUSED');

      expect(await client.resumeGroup(slow.nzbId), isTrue);
      final resumed = await _eventually(
        () => client.listGroups(),
        (current) => _nzbgetStatus(current, _slow) == 'DOWNLOADING',
        label: 'the job resuming',
      );
      expect(_nzbgetStatus(resumed, _slow), 'DOWNLOADING');

      final throwaway = await client.append(
        '$_throwaway.nzb',
        _nzbUrl(_throwaway),
        addPaused: true,
      );
      expect(throwaway, greaterThan(0));
      await _eventually(
        () => client.listGroups(),
        (current) => current.any((group) => group.nzbId == throwaway),
        label: 'the throwaway job entering the queue',
      );
      await _deleteGroup(client, throwaway);
      final removed = await client.listGroups();
      expect(removed.any((group) => group.nzbId == throwaway), isFalse);
    });

    test(
      'D-15 the app reads the history, the feeds and the messages',
      () async {
        final client = _nzbget(credentials);
        addTearDown(client.close);

        final history = await client.history();
        expect(history, isNotEmpty);
        expect(history.any((item) => item.name == _complete), isTrue);
        expect(await client.feeds(), isEmpty);
        expect(await client.messages(), isNotEmpty);
      },
    );

    test('D-13 the app appends an NZB and NZBGet downloads it', () async {
      final client = _nzbget(credentials);
      addTearDown(client.close);

      // NZBGet runs one job per connection and the slow job holds the only
      // one. A person would stop it before adding another, and the stop takes
      // effect at the next article, so this is also a real pause.
      final slow = (await client.listGroups()).firstWhere(
        (group) => group.name == _slow,
        orElse: () => fail('the slow job is not in the queue'),
      );
      await _pauseGroup(client, slow.nzbId);

      final id = await client.append('$_added.nzb', _nzbUrl(_added));
      expect(id, greaterThan(0), reason: 'NZBGet refused the NZB');
      final history = await _eventually(
        () => client.history(),
        (items) => items.any((item) => item.name == _added),
        label: 'the appended job reaching the history',
      );
      final added = history.firstWhere((item) => item.name == _added);
      expect(added.success, isTrue, reason: 'the job reads ${added.status}');
    });
  });
}

// The job names the scenarios leave behind, plus the two the e2e adds itself.
const _complete = 'Cupola.Testlab.Usenet.Complete';
const _missing = 'Cupola.Testlab.Usenet.Missing';
const _slow = 'Cupola.Testlab.Usenet.Slow';
const _waiting = 'Cupola.Testlab.Usenet.Waiting';
const _paused = 'Cupola.Testlab.Usenet.Paused';
const _added = 'Cupola.Testlab.Usenet.Added';
const _throwaway = 'Cupola.Testlab.Usenet.Throwaway';

/// The NZB is fetched by the client inside a container, so it uses the
/// address the containers reach the Mac with, not 127.0.0.1.
String _nzbUrl(String key) => 'http://host.docker.internal:1120/nzb/$key.nzb';

SabnzbdClient _sab() =>
    SabnzbdClient(url: 'http://127.0.0.1:8082', apiKey: 'test-key');

NzbgetClient _nzbget(Map<String, String> credentials) => NzbgetClient(
  url: 'http://127.0.0.1:6789',
  username: credentials['CUPOLA_TESTLAB_NZBGET_USERNAME'],
  password: credentials['CUPOLA_TESTLAB_NZBGET_PASSWORD'],
);

String? _sabStatus(SabnzbdQueue queue, String name) {
  for (final slot in queue.slots) {
    if (slot.filename == name) return slot.status;
  }
  return null;
}

SabnzbdHistorySlot? _sabHistory(List<SabnzbdHistorySlot> history, String name) {
  for (final item in history) {
    if (item.name == name) return item;
  }
  return null;
}

String? _nzbgetStatus(List<NzbgetGroup> groups, String name) {
  for (final group in groups) {
    if (group.name == name) return group.status;
  }
  return null;
}

/// NZBGet can drop a delete asked for while it is still placing the group, so
/// the delete is asked again until the daemon reports the group gone.
Future<void> _deleteGroup(NzbgetClient client, int id) async {
  for (var attempt = 0; attempt < 10; attempt++) {
    await client.deleteGroup(id);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final groups = await client.listGroups();
    if (groups.every((group) => group.nzbId != id)) return;
  }
  fail('NZBGet never removed the job');
}

/// NZBGet can drop a pause asked for while it is still placing the group, so
/// the pause is asked again until the daemon reports the group as stopped.
Future<void> _pauseGroup(NzbgetClient client, int id) async {
  for (var attempt = 0; attempt < 10; attempt++) {
    await client.pauseGroup(id);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final groups = await client.listGroups();
    if (groups.any((group) => group.nzbId == id && group.status == 'PAUSED')) {
      return;
    }
  }
  fail('NZBGet never reported the job as paused');
}

Future<T> _eventually<T>(
  Future<T> Function() read,
  bool Function(T value) predicate, {
  required String label,
  Duration timeout = const Duration(minutes: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  var last = await read();
  while (!predicate(last)) {
    if (DateTime.now().isAfter(deadline)) {
      fail('timed out waiting for $label');
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
    last = await read();
  }
  return last;
}

/// Applies or tears down a scenario through the lab's own control plane.
Future<void> _scenario(String action, String name) async {
  final result = await Process.run('python3', [
    'test/e2e/testlab/testlab.py',
    'scenario',
    action,
    name,
  ], workingDirectory: Directory.current.path);
  if (result.exitCode != 0) {
    fail(
      'testlab.py scenario $action $name answered ${result.exitCode}: '
      '${result.stdout}${result.stderr}',
    );
  }
}

Map<String, String> _credentials() {
  final path =
      Platform.environment['CUPOLA_TESTLAB_CREDENTIALS_FILE'] ??
      '${Directory.current.path}/.ai/scratch/zz_testlab/state/credentials.env';
  final file = File(path);
  if (!file.existsSync()) {
    fail('CUPOLA_TESTLAB_CREDENTIALS_FILE is not set and $path is missing');
  }
  final values = <String, String>{};
  for (final line in file.readAsLinesSync()) {
    if (line.isEmpty || line.startsWith('#') || !line.contains('=')) {
      continue;
    }
    final separator = line.indexOf('=');
    values[line.substring(0, separator)] = line.substring(separator + 1);
  }
  return values;
}
