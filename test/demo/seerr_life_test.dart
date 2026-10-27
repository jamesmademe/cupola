import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/demo/demo_session.dart';
import 'package:cupola/demo/world/profiles.dart';

/// Seerr once the world lives: a request made, approved, declined or taken
/// back stays so, an approved one goes to its arr, and the title's status
/// follows it from waiting to on the server.
void main() {
  late ProfileNetwork network;

  setUp(() {
    network = ProfileNetwork(demoProfile)..live();
    addTearDown(network.install());
  });

  Future<Object?> send(String method, String path, {Object? json}) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(
        method,
        Uri.parse('${WorldHosts.seerr}$path'),
      );
      request.headers.set('x-api-key', worldKey(WorldIds.seerr));
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

  Future<int?> status(WorldTitle title) async {
    final detail = await send('GET', '/api/v1/movie/${title.tmdbId}') as Map;
    return (detail['mediaInfo'] as Map?)?['status'] as int?;
  }

  Future<Map<String, Object?>> request(int id) async =>
      (await send('GET', '/api/v1/request/$id') as Map).cast();

  test('the operator\'s request is approved, fetched and arrives', () async {
    const spring = WorldTitles.spring;
    expect(await status(spring), 1);
    final made =
        await send(
              'POST',
              '/api/v1/request',
              json: {'mediaType': 'movie', 'mediaId': spring.tmdbId},
            )
            as Map;
    expect(made['status'], 2);
    expect(await status(spring), 3);
    final queue = network.life!.downloads.where(
      (d) => d.title == spring && d.arr == WorldIds.radarr,
    );
    expect(queue, hasLength(1));

    network.elapse(const Duration(minutes: 2));
    expect(await status(spring), 5);
    final count = await send('GET', '/api/v1/request/count') as Map;
    expect(count['available'], greaterThanOrEqualTo(1));
  });

  test('an approval sends a waiting request on, and it arrives', () async {
    expect(await status(WorldTitles.charge), 2);
    final approved = await send('POST', '/api/v1/request/1/approve') as Map;
    expect(approved['status'], 2);
    expect(await status(WorldTitles.charge), 3);
    network.elapse(const Duration(minutes: 2));
    expect(await status(WorldTitles.charge), 5);
  });

  test(
    'a declined request stays declined, and the title is unknown again',
    () async {
      await send('POST', '/api/v1/request/2/decline');
      expect((await request(2))['status'], 3);
      expect(await status(WorldTitles.metropolis), 1);
      final pending =
          await send('GET', '/api/v1/request?filter=pending&take=50') as Map;
      expect(
        (pending['results'] as List).map((q) => (q as Map)['id']),
        isNot(contains(2)),
      );
    },
  );

  test('a request taken back is gone', () async {
    await send('DELETE', '/api/v1/request/8');
    final all = await send('GET', '/api/v1/request?take=50') as Map;
    expect(
      (all['results'] as List).map((q) => (q as Map)['id']),
      isNot(contains(8)),
    );
  });
}
