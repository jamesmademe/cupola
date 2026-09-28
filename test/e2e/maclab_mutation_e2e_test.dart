@Tags(['e2e'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/npm/data/npm_client.dart';
import 'package:cupola/features/npm/domain/models/npm_models.dart';
import 'package:cupola/features/nzbget/data/nzbget_client.dart';
import 'package:cupola/features/qbittorrent/data/qbittorrent_client.dart';
import 'package:cupola/features/qbittorrent/data/qbittorrent_service.dart';
import 'package:cupola/features/qbittorrent/domain/models/torrent.dart';
import 'package:cupola/features/sabnzbd/data/sabnzbd_client.dart';
import 'package:cupola/features/transmission/data/transmission_client.dart';
import 'package:cupola/features/transmission/domain/models/transmission_models.dart';

/// Safe write probes for the disposable macOS/OrbStack laboratory.
///
/// Every specimen is either a paused, zero-data magnet or an existing seeded
/// row that is restored to its original state. Nothing writes to the user's
/// download directory, and the NPM toggle is restored in a `finally` block.
void main() {
  final credentials = _loadCredentials();

  test('qBittorrent add, pause and delete a zero-data magnet', () async {
    final client = QbittorrentClient(
      url: 'http://127.0.0.1:8080',
      username: credentials['CUPOLA_MACLAB_QBITTORRENT_USERNAME'],
      password: credentials['CUPOLA_MACLAB_QBITTORRENT_PASSWORD'],
    );
    addTearDown(client.close);
    final service = QbittorrentService(client);
    await service.authenticate();
    const marker = 'Cupola Mutation qBittorrent';
    const magnet =
        'magnet:?xt=urn:btih:1234567890abcdef1234567890abcdef12345678'
        '&dn=Cupola%20Mutation%20qBittorrent';

    Future<List<Torrent>> matching() async => (await service.getTorrents())
        .where((torrent) => torrent.name == marker)
        .toList(growable: false);

    Future<void> cleanup() async {
      for (final torrent in await matching()) {
        await service.deleteTorrents([torrent.hash]);
      }
    }

    await cleanup();
    addTearDown(cleanup);
    await service.addTorrentUrl(magnet);
    final added = await _eventually(
      matching,
      (items) => items.isNotEmpty,
      label: 'qBittorrent mutation specimen',
    );
    final torrent = added.single;
    await service.pauseTorrents([torrent.hash]);
    final paused = await _eventually(
      matching,
      (items) => items.single.parsedState.isPaused,
      label: 'qBittorrent pause',
    );
    expect(paused.single.parsedState.isPaused, isTrue);
    await service.deleteTorrents([torrent.hash]);
    expect(
      await _eventually(
        matching,
        (items) => items.isEmpty,
        label: 'qBittorrent delete',
      ),
      isEmpty,
    );
  });

  test('Transmission add, stop and remove a zero-data magnet', () async {
    final client = TransmissionClient(
      url: 'http://127.0.0.1:9091',
      username: credentials['CUPOLA_MACLAB_TRANSMISSION_USERNAME'],
      password: credentials['CUPOLA_MACLAB_TRANSMISSION_PASSWORD'],
    );
    addTearDown(client.close);
    const marker = 'Cupola Mutation Transmission';
    const magnet =
        'magnet:?xt=urn:btih:abcdef1234567890abcdef1234567890abcdef12'
        '&dn=Cupola%20Mutation%20Transmission';

    Future<List<TransmissionTorrent>> matching() async =>
        (await client.torrents())
            .where((torrent) => torrent.name == marker)
            .toList(growable: false);

    Future<void> cleanup() async {
      final torrents = await matching();
      if (torrents.isNotEmpty) {
        await client.removeTorrents(
          torrents.map((torrent) => torrent.hashString).toList(),
        );
      }
    }

    await cleanup();
    addTearDown(cleanup);
    final added = await client.addTorrent(magnet, paused: true);
    final torrent = added.torrent;
    expect(torrent, isNotNull);
    final visible = await _eventually(
      matching,
      (items) => items.isNotEmpty,
      label: 'Transmission mutation specimen',
    );
    final id = visible.single.hashString;
    await client.stop([id]);
    final stopped = await _eventually(
      matching,
      (items) => items.single.status == TransmissionStatus.stopped,
      label: 'Transmission stop',
    );
    expect(stopped.single.status, TransmissionStatus.stopped);
    await client.removeTorrents([id]);
    expect(
      await _eventually(
        matching,
        (items) => items.isEmpty,
        label: 'Transmission remove',
      ),
      isEmpty,
    );
  });

  test('SABnzbd pause and resume the seeded disposable job', () async {
    final client = SabnzbdClient(
      url: 'http://127.0.0.1:8082',
      apiKey: 'test-key',
    );
    addTearDown(client.close);
    final slot = (await client.getQueue()).slots.firstWhere(
      (item) => item.filename.toLowerCase().contains('cupola-test'),
      orElse: () => fail('SABnzbd seed specimen is not queued'),
    );

    await client.resumeJob(slot.nzoId);
    try {
      await client.pauseJob(slot.nzoId);
    } finally {
      // The fixture is intentionally left paused for the next run.
      await client.pauseJob(slot.nzoId);
    }
    final restored = await client.getQueue();
    expect(
      restored.slots.any(
        (item) =>
            item.nzoId == slot.nzoId &&
            item.status.toLowerCase().contains('paused'),
      ),
      isTrue,
    );
  });

  test('NZBGet append and delete a disposable job', () async {
    final client = NzbgetClient(
      url: 'http://127.0.0.1:6789',
      username: credentials['CUPOLA_MACLAB_NZBGET_USERNAME'],
      password: credentials['CUPOLA_MACLAB_NZBGET_PASSWORD'],
    );
    addTearDown(client.close);
    const marker = 'cupola-mutation-nzbget.nzb';
    final content = File(
      'test/e2e/maclab/seed/downloads/cupola-test.nzb',
    ).readAsStringSync();
    var id = 0;
    addTearDown(() async {
      if (id <= 0) return;
      final groups = await client.listGroups();
      if (groups.any((item) => item.nzbId == id)) {
        await client.deleteGroup(id);
        return;
      }
      if ((await client.history()).any((item) => item.id == id)) {
        await client.deleteHistory(id);
      }
    });

    id = await client.append(marker, content, addPaused: true);
    expect(id, greaterThan(0));
    final placement = await _eventually(
      () async =>
          (groups: await client.listGroups(), history: await client.history()),
      (state) =>
          state.groups.any((item) => item.nzbId == id) ||
          state.history.any((item) => item.id == id),
      label: 'NZBGet append',
    );
    final deleted = placement.groups.any((item) => item.nzbId == id)
        ? await client.deleteGroup(id)
        : await client.deleteHistory(id);
    expect(deleted, isTrue);
    final deletedId = id;
    id = 0;
    expect(
      await _eventually(
        () async => (
          groups: await client.listGroups(),
          history: await client.history(),
        ),
        (state) =>
            state.groups.every((item) => item.nzbId != deletedId) &&
            state.history.every((item) => item.id != deletedId),
        label: 'NZBGet delete',
      ),
      isNotNull,
    );
  });

  test(
    'Nginx Proxy Manager toggles and restores the seeded proxy host',
    () async {
      final client = NpmClient(
        url: 'http://127.0.0.1:8181',
        identity: credentials['CUPOLA_MACLAB_NPM_USERNAME'],
        secret: credentials['CUPOLA_MACLAB_NPM_PASSWORD'],
      );
      addTearDown(client.close);
      final host = (await client.proxyHosts()).firstWhere(
        (item) => item.domainNames.contains('cupola.test'),
        orElse: () => fail('NPM seed proxy host is missing'),
      );
      final original = host.enabled;
      try {
        final disabled = await client.setProxyHostEnabled(host.id, !original);
        expect(disabled?.enabled, equals(!original));
      } finally {
        final restored = await client.setProxyHostEnabled(host.id, original);
        expect(restored?.enabled, equals(original));
      }
    },
  );

  test(
    'Nginx Proxy Manager reads a scoped account and refuses its writes',
    () async {
      // A real non-admin account, made and removed through the admin API, so
      // the probe is checked against what NPM itself says rather than against
      // a fixture of what it might say.
      final admin = _NpmAdmin(
        url: 'http://127.0.0.1:8181',
        identity: credentials['CUPOLA_MACLAB_NPM_USERNAME']!,
        secret: credentials['CUPOLA_MACLAB_NPM_PASSWORD']!,
      );
      addTearDown(admin.close);
      const email = 'cupola-scoped@example.com';
      const password = 'cupola-scoped-secret';
      await admin.deleteUserByEmail(email);
      final userId = await admin.createUser(
        email: email,
        password: password,
        // Manages certificates, may only look at proxy hosts: the partial
        // account that gets a banner on one tab and not on the other.
        permissions: const {
          'visibility': 'all',
          'proxy_hosts': 'view',
          'redirection_hosts': 'view',
          'dead_hosts': 'view',
          'streams': 'view',
          'access_lists': 'view',
          'certificates': 'manage',
        },
      );
      addTearDown(() => admin.deleteUser(userId));

      final scoped = NpmClient(
        url: 'http://127.0.0.1:8181',
        identity: email,
        secret: password,
      );
      addTearDown(scoped.close);

      final partial = await scoped.currentUser();
      expect(partial.isAdmin, isFalse);
      expect(partial.canManage(NpmResource.proxyHosts), isFalse);
      expect(partial.canManage(NpmResource.certificates), isTrue);
      expect(partial.isViewOnly, isFalse);

      // The refusal the ledger learns from: a view-only resource answers a
      // write with a refusal, not with a silent success.
      final host = (await scoped.proxyHosts()).firstWhere(
        (item) => item.domainNames.contains('cupola.test'),
        orElse: () => fail('NPM seed proxy host is missing'),
      );
      await expectLater(
        scoped.setProxyHostEnabled(host.id, !host.enabled),
        throwsA(anything),
      );

      await admin.setPermissions(userId, const {
        'visibility': 'all',
        'proxy_hosts': 'view',
        'redirection_hosts': 'view',
        'dead_hosts': 'view',
        'streams': 'view',
        'access_lists': 'view',
        'certificates': 'view',
      });
      final viewOnly = await scoped.currentUser();
      expect(viewOnly.isViewOnly, isTrue);
    },
  );
}

/// The four NPM admin calls the scoped-account probe needs. They are not part
/// of the app's client on purpose: Cupola never manages NPM users.
class _NpmAdmin {
  _NpmAdmin({required this.url, required this.identity, required this.secret});

  final String url;
  final String identity;
  final String secret;
  final HttpClient _http = HttpClient();
  String? _token;

  Future<dynamic> _call(String method, String path, [Object? body]) async {
    _token ??=
        (await _send('POST', '/api/tokens', {
                  'identity': identity,
                  'secret': secret,
                }, auth: false)
                as Map)['token']
            as String;
    return _send(method, path, body);
  }

  Future<dynamic> _send(
    String method,
    String path,
    Object? body, {
    bool auth = true,
  }) async {
    final request = await _http.openUrl(method, Uri.parse('$url$path'));
    request.headers.contentType = ContentType.json;
    if (auth) request.headers.set('Authorization', 'Bearer $_token');
    if (body != null) request.write(jsonEncode(body));
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    if (response.statusCode >= 400) {
      throw StateError('NPM $method $path: ${response.statusCode} $text');
    }
    return text.isEmpty ? null : jsonDecode(text);
  }

  Future<int> createUser({
    required String email,
    required String password,
    required Map<String, String> permissions,
  }) async {
    final user =
        await _call('POST', '/api/users', {
              'name': 'Cupola scoped',
              'nickname': 'scoped',
              'email': email,
              'roles': <String>[],
              'is_disabled': false,
            })
            as Map;
    final id = user['id'] as int;
    await _call('PUT', '/api/users/$id/auth', {
      'type': 'password',
      'secret': password,
    });
    await setPermissions(id, permissions);
    return id;
  }

  Future<void> setPermissions(int id, Map<String, String> permissions) =>
      _call('PUT', '/api/users/$id/permissions', permissions);

  Future<void> deleteUser(int id) => _call('DELETE', '/api/users/$id');

  Future<void> deleteUserByEmail(String email) async {
    final users = await _call('GET', '/api/users') as List;
    for (final user in users.whereType<Map>()) {
      if (user['email'] == email) await deleteUser(user['id'] as int);
    }
  }

  void close() => _http.close(force: true);
}

Future<T> _eventually<T>(
  Future<T> Function() read,
  bool Function(T value) predicate, {
  required String label,
}) async {
  Object? lastError;
  for (var attempt = 0; attempt < 16; attempt++) {
    try {
      final value = await read();
      if (predicate(value)) return value;
    } catch (error) {
      lastError = error;
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  throw StateError(
    '$label did not settle${lastError == null ? '' : ': $lastError'}',
  );
}

Map<String, String> _loadCredentials() {
  final path = Platform.environment['CUPOLA_MACLAB_CREDENTIALS_FILE'];
  if (path == null || path.isEmpty) {
    fail(
      'CUPOLA_MACLAB_CREDENTIALS_FILE must point to the bootstrap output '
      '(.ai/scratch/zz_maclab/state/credentials.env)',
    );
  }
  final file = File(path);
  if (!file.existsSync()) fail('Missing maclab credentials file: $path');
  final values = <String, String>{};
  for (final line in file.readAsLinesSync()) {
    if (line.isEmpty || line.startsWith('#')) continue;
    final separator = line.indexOf('=');
    if (separator <= 0) continue;
    values[line.substring(0, separator)] = line.substring(separator + 1);
  }
  return values;
}
