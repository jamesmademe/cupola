@Tags(['e2e'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/dockge/data/dockge_client.dart';
import 'package:cupola/features/dockge/domain/models/dockge_stack.dart';

/// Dockge for real: the three stacks the lab's own `docker:dind` holds, read
/// and driven through the app's client.
///
/// The `dockge-lab` scenario writes the compose files in
/// `test/e2e/testlab/dind_stacks` through Dockge's `saveStack`, then tries to
/// deploy the log stack and measures whether this dind can create a container
/// at all. It cannot, because its `/var/lib/docker` is a bind mount of the
/// state folder on the Mac and overlayfs refuses that upperdir (the kernel says
/// `failed to create directory …/work/work (errno: 13)`, mounts the snapshot
/// read-only, and every `docker run` dies with `mount callback failed`). The
/// marker carries that verdict, so the tests below assert the branch the lab is
/// actually in: with a working dind the stacks walk Running, Stopped and
/// Inactive; here every one of them stays Inactive and the actions that would
/// create a container are refused by Dockge with `Failed to …`. That refusal is
/// not a lie worth skipping: it is what the socket really answers, and the
/// action terminal carries the daemon's own words for it.
///
/// What this suite does not cover, and says so: `stackStatusList`, the lighter
/// status push the app tolerates, does not exist in Dockge 1.5.0 (the backend
/// never emits it), so the oracle is the pushed `stackList`, which carries the
/// same `status` field. `getStack` is not a status oracle either: it answers a
/// freshly built stack whose status is always `Unknown`.
void main() {
  late Map<String, String> credentials;
  late Map<String, dynamic> marker;

  setUpAll(() {
    _scenario('apply', 'dockge-lab');
    credentials = _credentials();
    marker = _marker();
  });

  tearDownAll(() => _scenario('teardown', 'dockge-lab'));

  test('I-01 the list and the detail are what Dockge knows', () async {
    final client = _dockge(credentials);
    addTearDown(client.close);
    final expected = _expectedStatuses(marker);

    final stacks = await _stacks(client);
    for (final name in _labStacks) {
      expect(stacks[name], isNotNull, reason: 'Dockge does not list $name');
      expect(stacks[name]!.status, expected[name], reason: name);
      expect(stacks[name]!.isManagedByDockge, isTrue, reason: name);
      expect(stacks[name]!.composeFileName, 'compose.yaml', reason: name);
    }

    // The compose file round-trips: what the scenario handed to `saveStack` is
    // what `getStack` reads back, byte for byte.
    for (final name in _labStacks) {
      final detail = await client.getStack(name);
      expect(detail.name, name);
      expect(
        detail.composeYAML.trim(),
        _composeFile(name).trim(),
        reason: 'Dockge holds a different compose file for $name',
      );
      expect(detail.composeYAML, contains('cupola-lab/base:1'));

      // Dockge 1.5.0's `getStack` builds a fresh stack and never refreshes its
      // status, so it reads `Unknown` even for a stack the list reports as
      // `Inactive`. The list push is the oracle; this pins the trap.
      expect(
        detail.status,
        DockgeStackStatus.unknown,
        reason: 'if this changed, the detail page may start trusting it again',
      );

      final services = await client.getServiceStatusList(name);
      if (marker['runtime']['available'] as bool) {
        if (name == _idle || name == _crash) {
          // The idle stack was never started, and the crash's container wrote
          // one line and exited: neither is a service Dockge still lists.
          expect(services, isEmpty, reason: '$name has no live container');
        } else {
          expect(services, isNotEmpty, reason: '$name runs a service');
        }
      } else {
        expect(services, isEmpty, reason: '$name cannot have containers here');
      }
    }

    // The stack the lab already had is still there: the scenario touches only
    // its own three.
    for (final before in (marker['before'] as List).cast<String>()) {
      expect(stacks[before], isNotNull, reason: 'the lab lost $before');
    }
  });

  test('I-01 start, stop, restart, update and down a stack', () async {
    final client = _dockge(credentials);
    addTearDown(client.close);
    final available = marker['runtime']['available'] as bool;
    final chunks = <DockgeTerminalOutput>[];
    final listening = client.terminalOutput.listen(chunks.add);
    addTearDown(listening.cancel);

    final stacks = await _stacks(client);
    expect(stacks[_log], isNotNull, reason: 'the log stack is not listed');

    if (!available) {
      // Without a runtime, the command that creates a container is refused and
      // Dockge says so with its own message. The others acknowledge: there is
      // no container to stop, restart or take down, so `compose` exits 0 and
      // the stack keeps reading Inactive.
      await expectLater(
        client.startStack(_log),
        throwsA(_refusal('Failed to start')),
        reason: 'starting a stack on a dind that cannot build a container',
      );

      await client.restartStack(_log);
      await client.stopStack(_log);
      // Update is `docker compose pull`, and every compose here says
      // `pull_policy: never`, so it is skipped instead of reaching a registry.
      await client.updateStack(_log);
      await client.downStack(_log);

      final after = await _stacks(client);
      expect(after[_log]!.status, DockgeStackStatus.createdFile);
      expect(after[_idle]!.status, DockgeStackStatus.createdFile);
      // The compose file survives every one of those actions.
      final detail = await client.getStack(_log);
      expect(detail.composeYAML.trim(), _composeFile(_log).trim());

      final requested = await _stacks(client);
      expect(requested.keys, contains(_crash));
      return;
    }

    await client.startStack(_log);
    await _statusBecomes(client, _log, DockgeStackStatus.running);

    await client.stopStack(_log);
    await _statusBecomes(client, _log, DockgeStackStatus.exited);

    await client.restartStack(_log);
    await _statusBecomes(client, _log, DockgeStackStatus.running);

    // Update is `docker compose pull`, and every compose here says
    // `pull_policy: never`, so it is skipped instead of reaching a registry.
    await client.updateStack(_log);
    await _statusBecomes(client, _log, DockgeStackStatus.running);

    await client.downStack(_log);
    await _statusBecomes(client, _log, DockgeStackStatus.createdFile);

    // Down removes the containers, not the compose file.
    final detail = await client.getStack(_log);
    expect(detail.composeYAML.trim(), _composeFile(_log).trim());

    // The failing stack settled on Stopped on its own.
    final crash = await _stacks(client);
    expect(crash[_crash]!.status, DockgeStackStatus.exited);
  });

  test('I-02 create, edit and delete a stack', () async {
    final client = _dockge(credentials);
    addTearDown(client.close);

    // A previous failed run can leave the throwaway stack behind. An empty
    // compose cannot be deleted (see below), so a real file is written first.
    if ((await _stacks(client))[_empty] != null) {
      await client.saveStack(
        name: _empty,
        composeYAML: _composeFile(_idle),
        isAdd: false,
      );
      await client.deleteStack(_empty);
    }

    // A stack created from a blank editor: the client lets an add through
    // (nothing is overwritten), Dockge writes an empty file, and the `compose
    // up` that follows fails on it. This is the app's "New stack, blank
    // editor, Deploy" path.
    await expectLater(
      client.deployStack(name: _empty, composeYAML: '', isAdd: true),
      throwsA(_refusal('Failed to deploy')),
    );
    final stacks = await _stacks(client);
    expect(stacks[_empty], isNotNull, reason: 'the new stack is not listed');
    expect((await client.getStack(_empty)).composeYAML, isEmpty);

    // And so does deleting it, because Dockge's delete is `docker compose
    // down`, which reads the same empty file and fails. A stack the app can
    // create this way cannot be removed until a real compose is written back.
    await expectLater(
      client.deleteStack(_empty),
      throwsA(_refusal('Failed to delete')),
    );

    await client.saveStack(
      name: _empty,
      composeYAML: _composeFile(_idle),
      isAdd: false,
    );
    expect(
      (await client.getStack(_empty)).composeYAML.trim(),
      _composeFile(_idle).trim(),
    );
    await client.deleteStack(_empty);
    final after = await _stacks(client);
    expect(after[_empty], isNull, reason: 'the deleted stack is still listed');

    // Editing an existing stack: save and read back, then put the lab's own
    // file back so the scenario's state survives the test.
    final original = _composeFile(_idle);
    final edited = '$original    labels:\n      cupola.lab: edited\n';
    addTearDown(
      () => client.saveStack(name: _idle, composeYAML: original, isAdd: false),
    );
    await client.saveStack(name: _idle, composeYAML: edited, isAdd: false);
    expect((await client.getStack(_idle)).composeYAML.trim(), edited.trim());
    await client.saveStack(name: _idle, composeYAML: original, isAdd: false);
    expect((await client.getStack(_idle)).composeYAML.trim(), original.trim());
  });

  test('I-02 a save that must not happen and a save Dockge refuses', () async {
    final client = _dockge(credentials);
    addTearDown(client.close);

    final original = _composeFile(_idle);

    // The guard that saves the stack: an empty compose over a stack that
    // exists is refused before a byte is sent, so the file stays whole.
    await expectLater(
      client.saveStack(name: _idle, composeYAML: '   ', isAdd: false),
      throwsA(
        isA<DockgeException>().having(
          (error) => error.message,
          'message',
          contains('Refusing to save an empty compose file'),
        ),
      ),
    );
    expect((await client.getStack(_idle)).composeYAML.trim(), original.trim());

    // The server's own refusal: Dockge answers `Stack not found`, which the
    // app turns into `Save failed`.
    await expectLater(
      client.saveStack(
        name: 'cupola-lab-absent',
        composeYAML: original,
        isAdd: false,
      ),
      throwsA(
        isA<DockgeException>().having(
          (error) => error.message,
          'message',
          'Stack not found',
        ),
      ),
    );

    // And an add on a name that is taken is refused too.
    await expectLater(
      client.saveStack(name: _idle, composeYAML: original, isAdd: true),
      throwsA(
        isA<DockgeException>().having(
          (error) => error.message,
          'message',
          contains('already exists'),
        ),
      ),
    );
  });

  test('I-03 the combined log and the action terminal', () async {
    final client = _dockge(credentials);
    addTearDown(client.close);
    final available = marker['runtime']['available'] as bool;
    final chunks = <DockgeTerminalOutput>[];
    final listening = client.terminalOutput.listen(chunks.add);
    addTearDown(listening.cancel);

    // I-01 brings the log stack down; the combined log can only speak while it
    // runs again. The start's own action output happens before the marks below.
    if (available) {
      await client.startStack(_log);
      await _statusBecomes(client, _log, DockgeStackStatus.running);
      await Future<void>.delayed(const Duration(seconds: 2));
    }

    // The name the app joins is the one Dockge builds server side.
    expect(client.combinedTerminalName(_log), 'combined--$_log');
    final combined = client.combinedTerminalName(_log);
    final action = 'compose--$_log';

    // Joining is accepted, and the client exposes output only: Dockge has no
    // shell-input event in this flow, which is why the screen says so.
    await client.joinCombinedTerminal(_log);
    await Future<void>.delayed(const Duration(milliseconds: 2500));

    final said = chunks
        .where((chunk) => chunk.terminalName == combined)
        .toList();
    if (available) {
      expect(
        said.map((chunk) => chunk.data).join(),
        contains('cupola-log line'),
        reason: 'the running stack writes a line a second',
      );
    } else {
      // A stack with no container has nothing to stream: the combined log stays
      // silent, which is the state the pane draws as waiting for output.
      expect(
        said,
        isEmpty,
        reason: 'the stack never ran, so its combined log cannot have output',
      );
    }

    // The action terminal does carry output, and it is the transport this test
    // is about: Dockge streams the compose command to the socket that asked.
    final mark = chunks.length;
    if (available) {
      await client.startStack(_log);
      await _statusBecomes(client, _log, DockgeStackStatus.running);
    } else {
      await expectLater(
        client.startStack(_log),
        throwsA(_refusal('Failed to start')),
      );
    }
    final fromAction = await _eventually(
      () async =>
          chunks.skip(mark).where((chunk) => chunk.terminalName == action),
      (live) => live.isNotEmpty,
      label: 'the action terminal saying something',
    );
    final text = fromAction.map((chunk) => chunk.data).join();
    expect(text, isNotEmpty);
    if (!available) {
      // The daemon's own words, which is the lab's evidence for the limit. The
      // tail of the message moves with which step of the rootfs prep the kernel
      // fails on (dev/shm, dev/pts, dev/console, etc/mtab), so the assertion
      // pins the sentence that is always there.
      expect(text.toLowerCase(), contains('mount callback failed'));

      // The combined log is not the action log: on a lab that cannot run the
      // stack, nothing arrives under the combined name while an action runs.
      expect(
        chunks.skip(mark).where((chunk) => chunk.terminalName == combined),
        isEmpty,
        reason: 'the action terminal is not the combined log',
      );
    }
  });
}

// The three stacks `dockge-lab` creates, and the one this suite creates itself.
const _log = 'cupola-log';
const _idle = 'cupola-idle';
const _crash = 'cupola-crash';
const _empty = 'cupola-empty';
const _labStacks = [_log, _idle, _crash];

/// The statuses the scenario recorded, so a test compares against what the lab
/// measured instead of a guess.
Map<String, DockgeStackStatus> _expectedStatuses(Map<String, dynamic> marker) {
  final statuses = (marker['statuses'] as Map).cast<String, dynamic>();
  return {
    for (final name in _labStacks)
      name: DockgeStackStatus.fromCode((statuses[name] as num).toInt()),
  };
}

String _composeFile(String name) {
  final file = File(
    '${Directory.current.path}/test/e2e/testlab/dind_stacks/$name.yaml',
  );
  if (!file.existsSync()) {
    fail('${file.path} is missing');
  }
  return file.readAsStringSync();
}

DockgeClient _dockge(Map<String, String> credentials) => DockgeClient(
  baseUrl: 'http://127.0.0.1:5001',
  username: credentials['CUPOLA_TESTLAB_DOCKGE_USERNAME'],
  password: credentials['CUPOLA_TESTLAB_DOCKGE_PASSWORD'],
  idleTimeout: const Duration(minutes: 5),
);

/// The pushed stack list, asked for and waited for.
///
/// Dockge starts its `stackList` push without awaiting it, so the frame for a
/// command can land after that command's ack and carry the state from before
/// it. The first push is therefore not trusted: the list is read again once the
/// round trip has settled.
Future<Map<String, DockgeStack>> _stacks(DockgeClient client) async {
  await client.ensureConnected();
  final pushed = client.stackListStream.first.timeout(
    const Duration(seconds: 15),
  );
  await client.requestStackList();
  await pushed;
  await Future<void>.delayed(const Duration(milliseconds: 300));
  return {for (final stack in client.latestStacks) stack.name: stack};
}

Future<void> _statusBecomes(
  DockgeClient client,
  String name,
  DockgeStackStatus status, {
  Duration timeout = const Duration(minutes: 2),
}) async {
  await _eventually(
    () => _stacks(client),
    (stacks) => stacks[name]?.status == status,
    label: '$name reading ${status.label}',
    timeout: timeout,
  );
}

Matcher _refusal(String message) => isA<DockgeException>().having(
  (error) => error.message,
  'message',
  contains(message),
);

Future<T> _eventually<T>(
  Future<T> Function() read,
  bool Function(T value) predicate, {
  required String label,
  Duration timeout = const Duration(seconds: 90),
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

Map<String, dynamic> _marker() {
  final file = File('${_stateRoot()}/backup/dockge_lab/state.json');
  if (!file.existsSync()) {
    fail('the scenario left no marker at ${file.path}');
  }
  return (jsonDecode(file.readAsStringSync()) as Map).cast<String, dynamic>();
}

String _stateRoot() =>
    Platform.environment['CUPOLA_TESTLAB_STATE_DIR'] ??
    '${Directory.current.path}/.ai/scratch/zz_testlab/state';

Map<String, String> _credentials() {
  final file = File('${_stateRoot()}/credentials.env');
  if (!file.existsSync()) {
    fail('the lab credentials are not at ${file.path}');
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
