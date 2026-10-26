import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/demo/demo_session.dart';
import 'package:cupola/demo/world/fakes/client_fakes.dart';
import 'package:cupola/demo/world/profiles.dart';

/// The world once it lives: what a client is told stays done, and time moves
/// the downloads on. A test's network, not live, answers as written.
void main() {
  late ProfileNetwork network;

  setUp(() {
    network = ProfileNetwork(demoProfile);
    addTearDown(network.install());
  });

  Future<Object?> send(
    String method,
    String url, {
    Object? json,
    Map<String, String>? form,
    Map<String, String> headers = const {},
  }) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(method, Uri.parse(url));
      headers.forEach(request.headers.set);
      if (json != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(json));
      } else if (form != null) {
        request.headers.contentType = ContentType(
          'application',
          'x-www-form-urlencoded',
        );
        request.write(Uri(queryParameters: form).query);
      }
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      try {
        return jsonDecode(body);
      } on FormatException {
        return body;
      }
    } finally {
      client.close();
    }
  }

  Future<List<Map<String, Object?>>> radarrQueue() async {
    final page = await send('GET', '${WorldHosts.radarr}/api/v3/queue') as Map;
    return (page['records'] as List).cast<Map<String, Object?>>();
  }

  Future<Map<String, Map<String, Object?>>> torrents() async {
    final list =
        await send('GET', '${WorldHosts.qbittorrent}/api/v2/torrents/info')
            as List;
    return {
      for (final t in list.cast<Map<String, Object?>>()) t['hash'] as String: t,
    };
  }

  final spriteFright = WorldDownloads.spriteFright.id.toLowerCase();

  group('a world that does not live', () {
    test('answers a write and changes nothing', () async {
      await send(
        'POST',
        '${WorldHosts.qbittorrent}/api/v2/torrents/stop',
        form: {'hashes': spriteFright},
      );
      expect((await torrents())[spriteFright]!['state'], 'downloading');
    });
  });

  group('a living world', () {
    setUp(() => network.live());

    test(
      'moves a download on with its clock, and says how long is left',
      () async {
        final before = (await torrents())[spriteFright]!['progress'] as num;
        network.elapse(const Duration(seconds: 30));
        final after = (await torrents())[spriteFright]!;
        expect(after['progress'] as num, greaterThan(before));
        expect(after['eta'] as num, lessThan(11 * 60));
      },
    );

    test('a torrent that finishes seeds, leaves its arr\'s queue and is '
        'handed over', () async {
      final finished = <String>[];
      network.life!.onFinished((d, at) => finished.add(d.id));
      network.elapse(const Duration(minutes: 10));
      final torrent = (await torrents())[spriteFright]!;
      expect(torrent['progress'], 1);
      expect(torrent['state'], 'stalledUP');
      expect(
        (await radarrQueue()).map((r) => r['downloadId']),
        isNot(contains(WorldDownloads.spriteFright.id.toUpperCase())),
      );
      expect(finished, contains(WorldDownloads.spriteFright.id));
    });

    test('qBittorrent pauses, resumes and deletes', () async {
      final url = '${WorldHosts.qbittorrent}/api/v2/torrents';
      await send('POST', '$url/stop', form: {'hashes': spriteFright});
      expect((await torrents())[spriteFright]!['state'], 'stoppedDL');
      final paused = (await torrents())[spriteFright]!['progress'];
      network.elapse(const Duration(minutes: 1));
      expect((await torrents())[spriteFright]!['progress'], paused);

      await send('POST', '$url/start', form: {'hashes': spriteFright});
      expect((await torrents())[spriteFright]!['state'], 'downloading');

      await send(
        'POST',
        '$url/delete',
        form: {'hashes': spriteFright, 'deleteFiles': 'true'},
      );
      expect(await torrents(), isNot(contains(spriteFright)));
    });

    test('an arr\'s queue lets a row go, from the client or only from '
        'itself', () async {
      final rows = await radarrQueue();
      final place = rows.indexWhere(
        (r) => '${r['downloadId']}'.toLowerCase() == spriteFright,
      );
      await send(
        'DELETE',
        '${WorldHosts.radarr}/api/v3/queue/${place + 1}'
            '?removeFromClient=false',
      );
      expect(
        (await radarrQueue()).map((r) => '${r['downloadId']}'.toLowerCase()),
        isNot(contains(spriteFright)),
      );
      expect(await torrents(), contains(spriteFright));
    });

    test('SABnzbd pauses a job, deletes one, and starts the next when the '
        'queue is free', () async {
      Future<List<Map<String, Object?>>> slots() async {
        final queue =
            await send('GET', '${WorldHosts.sabnzbd}/api?mode=queue') as Map;
        return ((queue['queue'] as Map)['slots'] as List)
            .cast<Map<String, Object?>>();
      }

      final elephants = WorldDownloads.elephantsDream4k.id;
      final sintel = WorldDownloads.sintel4k.id;
      await send(
        'GET',
        '${WorldHosts.sabnzbd}/api?mode=queue&name=pause&value=$elephants',
      );
      expect(
        (await slots()).firstWhere((s) => s['nzo_id'] == elephants)['status'],
        'Paused',
      );
      await send(
        'GET',
        '${WorldHosts.sabnzbd}/api?mode=queue&name=delete&value=$elephants',
      );
      network.elapse(const Duration(seconds: 1));
      final left = await slots();
      expect(left.map((s) => s['nzo_id']), isNot(contains(elephants)));
      expect(
        left.firstWhere((s) => s['nzo_id'] == sintel)['status'],
        'Downloading',
      );
    });

    test('a paused SABnzbd queue holds every job where it is', () async {
      await send('GET', '${WorldHosts.sabnzbd}/api?mode=pause');
      final queue =
          await send('GET', '${WorldHosts.sabnzbd}/api?mode=queue') as Map;
      expect((queue['queue'] as Map)['paused'], isTrue);
      final before = network.life!.byId(WorldDownloads.elephantsDream4k.id);
      network.elapse(const Duration(minutes: 1));
      await send('GET', '${WorldHosts.sabnzbd}/api?mode=queue');
      expect(
        network.life!.byId(WorldDownloads.elephantsDream4k.id)!.progress,
        before!.progress,
      );
    });

    test('Transmission stops a torrent by its id', () async {
      Future<List<Map<String, Object?>>> list() async {
        final reply =
            await send(
                  'POST',
                  '${WorldHosts.transmission}/transmission/rpc',
                  json: {'method': 'torrent-get', 'arguments': {}},
                  headers: {
                    'x-transmission-session-id': TransmissionFake.sessionId,
                  },
                )
                as Map;
        return ((reply['arguments'] as Map)['torrents'] as List)
            .cast<Map<String, Object?>>();
      }

      final first = (await list()).first;
      await send(
        'POST',
        '${WorldHosts.transmission}/transmission/rpc',
        json: {
          'method': 'torrent-stop',
          'arguments': {
            'ids': [first['id']],
          },
        },
        headers: {'x-transmission-session-id': TransmissionFake.sessionId},
      );
      expect((await list()).first['status'], 0);
    });
  });
}
