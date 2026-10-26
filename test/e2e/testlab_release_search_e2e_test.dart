@Tags(['e2e'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The release search through Prowlarr, and a grab that really downloads.
///
/// The app's search sheet is exercised by the journey; this test proves the
/// chain underneath it: Radarr asks its Prowlarr-synced Torznab indexer, the
/// catalogue comes back with the rejections, the accepted row is grabbed, the
/// app's qBittorrent fetches it from the local seeder, and Radarr's history
/// carries the result. The lab is arranged by `golden-l5`.
///
/// Secrets come from the lab's credentials file and Radarr's own configuration,
/// both in the lab's state directory: `CUPOLA_TESTLAB_CREDENTIALS_FILE` names
/// the file. qBittorrent is read on its direct port with the Host its WebUI
/// expects (see docker-compose.testlab.yml).
void main() {
  final credentials = _credentials();

  setUpAll(() async {
    // qBittorrent keeps a negative DNS answer for the tracker in the process,
    // and this client was created before the indexer existed. A restart clears
    // it; the torrents and their data stay on disk.
    final restart = await Process.run('docker', [
      'restart',
      'cupola-testlab-qbittorrent-1',
    ]);
    expect(
      restart.exitCode,
      0,
      reason: 'could not restart the app qBittorrent: ${restart.stderr}',
    );
    for (var attempt = 0; attempt < 60; attempt++) {
      final client = HttpClient();
      try {
        final request = await client.getUrl(Uri.parse(_qbitDirect));
        request.headers.set(HttpHeaders.hostHeader, _qbitHost);
        final response = await request.close();
        await response.drain<void>();
        if (response.statusCode == 200) break;
      } on SocketException {
        // still starting
      } on HttpException {
        // still starting
      } finally {
        client.close(force: true);
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    await Future<void>.delayed(const Duration(seconds: 2));
  });

  test('the indexer returns the catalogue, and a grab completes', () async {
    final movie = await _radarr(credentials, '/movie?tmdbId=10378');
    final id = movie.first['id'] as int;
    final releases = (await _radarr(
      credentials,
      '/release?movieId=$id',
    )).cast<Map>();
    expect(releases.length, greaterThanOrEqualTo(20));
    final italian = releases.where(
      (release) => release['title'].toString().contains('.ITA.'),
    );
    expect(italian, isNotEmpty);
    expect(
      italian.first['rejections'],
      contains('English is wanted, but found Italian'),
    );

    final accepted = releases.firstWhere(
      (release) =>
          release['title'] ==
              'Big.Buck.Bunny.2008.1080p.WEB-DL.DDP5.1.H.264-CUPOLA' &&
          release['rejected'] == false,
    );
    await _radarr(
      credentials,
      '/release',
      method: 'POST',
      payload: {'guid': accepted['guid'], 'indexerId': accepted['indexerId']},
    );
    // The tracker keeps peers in memory: the seeder announces first, then
    // the app's client asks again and receives it.
    await _reannounce(credentials, _seederDirect, _seederHost);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await _reannounce(credentials, _qbitDirect, _qbitHost);

    final deadline = DateTime.now().add(const Duration(minutes: 3));
    var completed = false;
    while (DateTime.now().isBefore(deadline)) {
      final torrents = await _torrents(credentials);
      final torrent = torrents.where(
        (item) =>
            item['name'] ==
            'The.Great.Bunny.2008.1080p.WEB-DL.DDP5.1.H.264-CUPOLA',
      );
      if (torrent.isNotEmpty && (torrent.first['progress'] as num) >= 1) {
        completed = true;
      }
      if (completed) break;
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    expect(
      completed,
      isTrue,
      reason: 'qBittorrent never finished the download',
    );

    final historyPage = await _radarr(
      credentials,
      '/history?page=1&pageSize=20',
    );
    final history = ((historyPage.first as Map)['records'] as List).cast<Map>();
    expect(
      history.any(
        (item) =>
            item['eventType'] == 'downloadFolderImported' ||
            item['eventType'] == 'downloadFailed',
      ),
      isTrue,
      reason: 'Radarr recorded no outcome for the download',
    );
  }, timeout: const Timeout(Duration(minutes: 6)));
}

/// The app's qBittorrent, read directly: the WebUI's own port is 8080, the
/// lab publishes the container on 18080, and the Host must say 8080.
const _qbitDirect = 'http://127.0.0.1:18080';
const _qbitHost = '127.0.0.1:8080';

/// The seeder's WebUI, on its published port.
const _seederDirect = 'http://127.0.0.1:8081';
const _seederHost = '127.0.0.1:8081';

/// The lab's credentials file, named by `CUPOLA_TESTLAB_CREDENTIALS_FILE`.
Map<String, String> _credentials() {
  final path = Platform.environment['CUPOLA_TESTLAB_CREDENTIALS_FILE'];
  if (path == null || path.isEmpty) {
    fail(
      'CUPOLA_TESTLAB_CREDENTIALS_FILE is not set: point it at the lab state',
    );
  }
  final file = File(path);
  if (!file.existsSync()) fail('the lab credentials file is missing: $path');
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

/// Radarr's API key, from the configuration the lab keeps in its state.
String _radarrKey(Map<String, String> credentials) {
  final path =
      credentials['CUPOLA_TESTLAB_CREDENTIALS_FILE'] ??
      Platform.environment['CUPOLA_TESTLAB_CREDENTIALS_FILE']!;
  final config = File('${File(path).parent.path}/radarr/config.xml');
  final match = RegExp(
    r'<ApiKey>([^<]+)</ApiKey>',
  ).firstMatch(config.readAsStringSync());
  if (match == null) fail('Radarr keeps no API key in ${config.path}');
  return match.group(1)!;
}

Future<List<dynamic>> _radarr(
  Map<String, String> credentials,
  String path, {
  String method = 'GET',
  Object? payload,
}) async {
  final client = HttpClient();
  try {
    final request = await client.openUrl(
      method,
      Uri.parse('http://127.0.0.1:7878/api/v3$path'),
    );
    request.headers.set('X-Api-Key', _radarrKey(credentials));
    request.headers.contentType = ContentType.json;
    if (payload != null) {
      final bytes = utf8.encode(jsonEncode(payload));
      request.contentLength = bytes.length;
      request.add(bytes);
    }
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      fail('Radarr $method $path answered ${response.statusCode}: $body');
    }
    if (body.isEmpty) return const [];
    final value = jsonDecode(body);
    return value is List ? value : [value];
  } finally {
    client.close(force: true);
  }
}

/// Signs in to the WebUI at [base] (answering to [host]) and returns the SID
/// cookie, or fails with the status the sign-in got.
Future<String> _signIn(
  HttpClient client,
  Map<String, String> credentials,
  String base,
  String host,
) async {
  final login = await client.postUrl(Uri.parse('$base/api/v2/auth/login'));
  login.headers.set(HttpHeaders.hostHeader, host);
  login.headers.set('Referer', 'http://$host');
  login.headers.set('Origin', 'http://$host');
  login.headers.contentType = ContentType(
    'application',
    'x-www-form-urlencoded',
  );
  final bytes = utf8.encode(
    Uri(
      queryParameters: {
        'username': credentials['CUPOLA_TESTLAB_QBITTORRENT_USERNAME'] ?? '',
        'password': credentials['CUPOLA_TESTLAB_QBITTORRENT_PASSWORD'] ?? '',
      },
    ).query,
  );
  login.contentLength = bytes.length;
  login.add(bytes);
  final response = await login.close();
  final answer = await response.transform(utf8.decoder).join();
  if (response.statusCode != 200 || answer.trim() != 'Ok.') {
    fail('qBittorrent at $base refused the sign-in: ${response.statusCode}');
  }
  return response.cookies
      .map((cookie) => '${cookie.name}=${cookie.value}')
      .join('; ');
}

Future<void> _reannounce(
  Map<String, String> credentials,
  String base,
  String host,
) async {
  final client = HttpClient();
  try {
    final cookie = await _signIn(client, credentials, base, host);
    final info = await client.getUrl(Uri.parse('$base/api/v2/torrents/info'));
    info.headers.set(HttpHeaders.hostHeader, host);
    info.headers.set('Cookie', cookie);
    final infoResponse = await info.close();
    final torrents =
        jsonDecode(await infoResponse.transform(utf8.decoder).join()) as List;
    final hashes = torrents
        .whereType<Map>()
        .map((torrent) => torrent['hash'])
        .whereType<String>()
        .join('|');
    if (hashes.isEmpty) return;
    final call = await client.postUrl(
      Uri.parse('$base/api/v2/torrents/reannounce'),
    );
    call.headers.set(HttpHeaders.hostHeader, host);
    call.headers.contentType = ContentType(
      'application',
      'x-www-form-urlencoded',
    );
    call.headers.set('Cookie', cookie);
    final form = utf8.encode('hashes=$hashes');
    call.contentLength = form.length;
    call.add(form);
    final answer = await call.close();
    await answer.drain<void>();
  } finally {
    client.close(force: true);
  }
}

Future<List<Map>> _torrents(Map<String, String> credentials) async {
  final client = HttpClient();
  try {
    final cookie = await _signIn(client, credentials, _qbitDirect, _qbitHost);
    final request = await client.getUrl(
      Uri.parse('$_qbitDirect/api/v2/torrents/info'),
    );
    request.headers.set(HttpHeaders.hostHeader, _qbitHost);
    request.headers.set('Cookie', cookie);
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    final value = jsonDecode(body);
    return (value as List).cast<Map>();
  } finally {
    client.close(force: true);
  }
}
