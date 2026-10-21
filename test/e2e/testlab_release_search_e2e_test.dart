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
void main() {
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
        final request = await client.getUrl(
          Uri.parse('http://127.0.0.1:8080/'),
        );
        final response = await request.close();
        await response.drain<void>();
        if (response.statusCode == 200) break;
      } on SocketException {
        // still starting
      } on HttpException {
        // the WebUI proxy is still coming up
      } finally {
        client.close(force: true);
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    await Future<void>.delayed(const Duration(seconds: 2));
  });

  test(
    'the indexer returns the catalogue, and a grab completes',
    () async {
      final movie = await _radarr('/movie?tmdbId=10378');
      final id = movie.first['id'] as int;
      final releases = (await _radarr('/release?movieId=$id')).cast<Map>();
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
        '/release',
        method: 'POST',
        payload: {'guid': accepted['guid'], 'indexerId': accepted['indexerId']},
      );
      // The tracker keeps peers in memory: the seeder announces first, then
      // the app's client asks again and receives it.
      await _reannounce('8081');
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await _reannounce('8080');

      final deadline = DateTime.now().add(const Duration(minutes: 3));
      var completed = false;
      while (DateTime.now().isBefore(deadline)) {
        final torrents = await _torrents();
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

      final historyPage = await _radarr('/history?page=1&pageSize=20');
      final history = ((historyPage.first as Map)['records'] as List)
          .cast<Map>();
      expect(
        history.any(
          (item) =>
              item['eventType'] == 'downloadFolderImported' ||
              item['eventType'] == 'downloadFailed',
        ),
        isTrue,
        reason: 'Radarr recorded no outcome for the download',
      );
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}

Future<List<dynamic>> _radarr(
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
    request.headers.set('X-Api-Key', 'test-key');
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

Future<void> _reannounce(String port) async {
  final client = HttpClient();
  try {
    final login = await client.postUrl(
      Uri.parse('http://127.0.0.1:$port/api/v2/auth/login'),
    );
    login.headers.contentType = ContentType(
      'application',
      'x-www-form-urlencoded',
    );
    final bytes = utf8.encode('username=admin&password=cupola-pass');
    login.contentLength = bytes.length;
    login.add(bytes);
    final loginResponse = await login.close();
    final cookie = loginResponse.cookies
        .map((cookie) => '${cookie.name}=${cookie.value}')
        .join('; ');
    await loginResponse.drain<void>();
    final info = await client.getUrl(
      Uri.parse('http://127.0.0.1:$port/api/v2/torrents/info'),
    );
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
      Uri.parse('http://127.0.0.1:$port/api/v2/torrents/reannounce'),
    );
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

Future<List<Map>> _torrents() async {
  final client = HttpClient();
  try {
    final login = await client.postUrl(
      Uri.parse('http://127.0.0.1:8080/api/v2/auth/login'),
    );
    login.headers.contentType = ContentType(
      'application',
      'x-www-form-urlencoded',
    );
    final bytes = utf8.encode('username=admin&password=cupola-pass');
    login.contentLength = bytes.length;
    login.add(bytes);
    final loginResponse = await login.close();
    final cookie = loginResponse.cookies
        .map((cookie) => '${cookie.name}=${cookie.value}')
        .join('; ');
    await loginResponse.drain<void>();
    final request = await client.getUrl(
      Uri.parse('http://127.0.0.1:8080/api/v2/torrents/info'),
    );
    request.headers.set('Cookie', cookie);
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    final value = jsonDecode(body);
    return (value as List).cast<Map>();
  } finally {
    client.close(force: true);
  }
}
