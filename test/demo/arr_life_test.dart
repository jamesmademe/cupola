import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/demo/demo_session.dart';
import 'package:cupola/demo/world/profiles.dart';

/// The arrs once the world lives: a film or a series added, monitored, let
/// go, searched for, grabbed by hand, imported by hand, and arrived.
void main() {
  late ProfileNetwork network;

  setUp(() {
    network = ProfileNetwork(demoProfile)..live();
    addTearDown(network.install());
  });

  Future<Object?> send(String method, String url, {Object? json}) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(method, Uri.parse(url));
      if (json != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(json));
      }
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      return body.isEmpty ? null : jsonDecode(body);
    } finally {
      client.close();
    }
  }

  const radarr = '${WorldHosts.radarr}/api/v3';
  const sonarr = '${WorldHosts.sonarr}/api/v3';
  final nosferatu = WorldTitles.catalogue.firstWhere(
    (t) => t.key == 'nosferatu',
  );

  Future<List<Map<String, Object?>>> list(String url) async =>
      ((await send('GET', url)) as List).cast<Map<String, Object?>>();

  Future<List<Map<String, Object?>>> queue(String base) async =>
      (((await send('GET', '$base/queue?pageSize=50')) as Map)['records']
              as List)
          .cast<Map<String, Object?>>();

  Future<Map<String, Object?>> movie(String title) async =>
      (await list('$radarr/movie')).firstWhere((m) => m['title'] == title);

  group('Radarr', () {
    test('a film added with a search is fetched and arrives, newest in the '
        'history', () async {
      final added =
          await send(
                'POST',
                '$radarr/movie',
                json: {
                  'tmdbId': nosferatu.tmdbId,
                  'title': nosferatu.title,
                  'monitored': true,
                  'addOptions': {'searchForMovie': true},
                },
              )
              as Map;
      expect(added['hasFile'], isFalse);
      expect(
        (await queue(radarr)).map((r) => r['title']),
        contains(startsWith('Nosferatu')),
      );

      network.elapse(const Duration(minutes: 2));
      expect((await movie('Nosferatu'))['hasFile'], isTrue);
      expect(
        (await queue(radarr)).map((r) => r['title']),
        isNot(contains(startsWith('Nosferatu'))),
      );
      final history =
          ((await send('GET', '$radarr/history?pageSize=10')) as Map)['records']
              as List;
      expect(((history.first as Map)['movie'] as Map)['title'], 'Nosferatu');
    });

    test('keeps its monitoring and lets a film go', () async {
      final sintel = await movie('Sintel');
      await send(
        'PUT',
        '$radarr/movie/${sintel['id']}',
        json: {...sintel, 'monitored': false},
      );
      expect((await movie('Sintel'))['monitored'], isFalse);
      await send('DELETE', '$radarr/movie/${sintel['id']}?deleteFiles=true');
      expect(
        (await list('$radarr/movie')).map((m) => m['title']),
        isNot(contains('Sintel')),
      );
    });

    test('another download for a stuck one: the row removed, a search, and '
        'a fresh grab', () async {
      final rows = await queue(radarr);
      final stuck = rows.indexWhere(
        (r) => '${r['title']}'.startsWith('Big.Buck.Bunny'),
      );
      await send(
        'DELETE',
        '$radarr/queue/${stuck + 1}?removeFromClient=true&blocklist=true',
      );
      final bunny = await movie('Big Buck Bunny');
      await send(
        'POST',
        '$radarr/command',
        json: {
          'name': 'MoviesSearch',
          'movieIds': [bunny['id']],
        },
      );
      final fresh = (await queue(
        radarr,
      )).where((r) => '${r['title']}'.startsWith('Big.Buck.Bunny'));
      expect(fresh, hasLength(1));
      expect(fresh.single['status'], isNot('warning'));
    });

    test('an interactive search lists releases and a grab fetches the one '
        'picked', () async {
      final added =
          await send(
                'POST',
                '$radarr/movie',
                json: {'tmdbId': nosferatu.tmdbId, 'monitored': true},
              )
              as Map;
      final releases = await list('$radarr/release?movieId=${added['id']}');
      expect(releases, hasLength(3));
      final picked = releases[1];
      await send(
        'POST',
        '$radarr/release',
        json: {'guid': picked['guid'], 'indexerId': picked['indexerId']},
      );
      expect(
        (await queue(radarr)).map((r) => r['title']),
        contains(picked['title']),
      );
    });
  });

  group('Sonarr', () {
    Future<Map<String, Object?>> cosmos() async => (await list(
      '$sonarr/series',
    )).firstWhere((s) => s['title'] == 'Cosmos Laundromat');

    test('an episode that finishes is on disk, and counted', () async {
      final before = (await cosmos())['statistics'] as Map;
      network.elapse(const Duration(minutes: 2));
      final episodes = await list('$sonarr/episode?seriesId=1');
      final e4 = episodes.firstWhere(
        (e) => e['seasonNumber'] == 2 && e['episodeNumber'] == 4,
      );
      expect(e4['hasFile'], isTrue);
      expect(
        ((await cosmos())['statistics'] as Map)['episodeFileCount'],
        (before['episodeFileCount'] as int) + 1,
      );
    });

    test('a series added with a search arrives as a season', () async {
      final breakingBad = WorldTitles.catalogue.firstWhere(
        (t) => t.key == 'breakingBad',
      );
      final added =
          await send(
                'POST',
                '$sonarr/series',
                json: {
                  'tvdbId': breakingBad.tvdbId,
                  'monitored': true,
                  'addOptions': {'searchForMissingEpisodes': true},
                },
              )
              as Map;
      expect((added['statistics'] as Map)['episodeFileCount'], 0);
      network.elapse(const Duration(minutes: 2));
      final series = (await list(
        '$sonarr/series',
      )).firstWhere((s) => s['title'] == breakingBad.title);
      expect((series['statistics'] as Map)['episodeFileCount'], 8);
    });

    test('an import by hand takes a blocked download off the queue', () async {
      final blocked = WorldDownloads.blockedImports.first;
      final before = await queue(sonarr);
      expect(
        before.map((r) => '${r['downloadId']}'.toLowerCase()),
        contains(blocked.id.toLowerCase()),
      );
      await send(
        'POST',
        '$sonarr/command',
        json: {
          'name': 'ManualImport',
          'importMode': 'move',
          'files': [
            {
              'path': '/mnt/tank/downloads/complete/${blocked.release}',
              'downloadId': blocked.id,
              'seriesId': 1,
            },
          ],
        },
      );
      expect(
        (await queue(sonarr)).map((r) => '${r['downloadId']}'.toLowerCase()),
        isNot(contains(blocked.id.toLowerCase())),
      );
    });

    test('keeps a season\'s monitoring', () async {
      final series = await cosmos();
      final seasons = [
        for (final s in (series['seasons'] as List).cast<Map>())
          {...s, 'monitored': s['seasonNumber'] != 3},
      ];
      await send(
        'PUT',
        '$sonarr/series/${series['id']}',
        json: {...series, 'seasons': seasons},
      );
      final third = ((await cosmos())['seasons'] as List)
          .cast<Map>()
          .firstWhere((s) => s['seasonNumber'] == 3);
      expect(third['monitored'], isFalse);
    });
  });
}
