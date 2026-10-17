import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/qbittorrent/data/qbittorrent_client.dart';
import 'package:cupola/features/qbittorrent/data/qbittorrent_service.dart';
import 'package:cupola/features/qbittorrent/data/qbittorrent_sync.dart';

/// Answers `sync/maindata` from a script, one answer per request, and keeps
/// the `rid` each request asked from. An answer can be held on a completer
/// (a request in flight) or be an error (the host refusing).
class _Server implements HttpClientAdapter {
  final List<Object> script = [];
  final List<int> rids = [];
  final List<String> posts = [];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.method == 'POST') {
      posts.add(options.path);
      return _reply('Ok.');
    }
    rids.add(int.parse('${options.queryParameters['rid']}'));
    var next = script.removeAt(0);
    if (next is Completer<Object>) next = await next.future;
    if (next is Exception) throw next;
    return _reply(jsonEncode(next), json: true);
  }

  static ResponseBody _reply(String body, {bool json = false}) =>
      ResponseBody.fromBytes(
        Uint8List.fromList(utf8.encode(body)),
        200,
        headers: {
          Headers.contentTypeHeader: [
            json ? 'application/json' : 'text/plain; charset=utf-8',
          ],
        },
      );
}

Map<String, dynamic> _torrent(String name, {String state = 'downloading'}) => {
  'name': name,
  'state': state,
  'progress': 0.25,
  'dlspeed': 100,
  'size': 1000,
};

QbittorrentClient _client(_Server server) => QbittorrentClient(
  url: 'http://qb.test',
  dio: Dio(BaseOptions(baseUrl: 'http://qb.test'))..httpClientAdapter = server,
);

DioException _refused() => DioException.connectionError(
  requestOptions: RequestOptions(path: '/api/v2/sync/maindata'),
  reason: 'Connection refused',
);

void main() {
  late _Server server;
  late QbittorrentSync sync;

  setUp(() {
    server = _Server();
    sync = QbittorrentSync(_client(server));
  });

  test('the first read takes the whole state, each next one asks from the '
      'id the last answer gave', () async {
    server.script
      ..add({
        'rid': 7,
        'full_update': true,
        'torrents': {'aaa': _torrent('Ubuntu'), 'bbb': _torrent('Debian')},
        'server_state': {'dl_info_speed': 200, 'free_space_on_disk': 5000},
      })
      ..add({'rid': 8});

    final first = await sync.read();
    await sync.read();

    expect(server.rids, [0, 7]);
    expect(first.torrents.map((t) => t.hash), unorderedEquals(['aaa', 'bbb']));
    expect(first.torrent('aaa')!.name, 'Ubuntu');
    expect(first.transfer.dlSpeed, 200);
    expect(first.transfer.freeSpace, 5000);
  });

  test('a later answer moves only what it names, adds what is new and drops '
      'what was removed', () async {
    server.script
      ..add({
        'rid': 1,
        'full_update': true,
        'torrents': {'aaa': _torrent('Ubuntu'), 'bbb': _torrent('Debian')},
        'server_state': {'dl_info_speed': 200, 'up_info_speed': 50},
      })
      ..add({
        'rid': 2,
        'torrents': {
          'aaa': {'progress': 0.75, 'state': 'stalledDL'},
          'ccc': _torrent('Fedora'),
        },
        'torrents_removed': ['bbb'],
        'server_state': {'dl_info_speed': 0},
      });

    await sync.read();
    final data = await sync.read();

    expect(data.torrents.map((t) => t.hash), unorderedEquals(['aaa', 'ccc']));
    final aaa = data.torrent('aaa')!;
    expect(aaa.progress, 0.75);
    expect(aaa.state, 'stalledDL');
    expect(aaa.name, 'Ubuntu', reason: 'a field the answer left out stays');
    expect(aaa.size, 1000);
    expect(data.transfer.dlSpeed, 0);
    expect(data.transfer.upSpeed, 50, reason: 'session figures merge too');
  });

  test('an answer that says full_update starts over', () async {
    server.script
      ..add({
        'rid': 4,
        'full_update': true,
        'torrents': {'aaa': _torrent('Ubuntu'), 'bbb': _torrent('Debian')},
        'server_state': {'free_space_on_disk': 5000},
      })
      // The server restarted, or the session is new: everything again, and
      // nothing of the old state survives.
      ..add({
        'rid': 1,
        'full_update': true,
        'torrents': {'ccc': _torrent('Fedora')},
        'server_state': {'dl_info_speed': 9},
      });

    await sync.read();
    final data = await sync.read();

    expect(data.torrents.map((t) => t.hash), ['ccc']);
    expect(data.transfer.freeSpace, isNull);
    expect(sync.rid, 1);
  });

  test('a read that fails changes nothing, and the next asks from the same '
      'id', () async {
    server.script
      ..add({
        'rid': 3,
        'full_update': true,
        'torrents': {'aaa': _torrent('Ubuntu')},
      })
      ..add(_refused())
      ..add({
        'rid': 4,
        'torrents': {
          'aaa': {'progress': 1},
        },
      });

    await sync.read();
    await expectLater(sync.read(), throwsA(isA<DioException>()));
    expect(sync.rid, 3);
    final data = await sync.read();

    expect(server.rids, [0, 3, 3]);
    expect(data.torrent('aaa')!.progress, 1);
  });

  test('an answer that is not an object fails and changes nothing', () async {
    server.script
      ..add({
        'rid': 3,
        'full_update': true,
        'torrents': {'aaa': _torrent('Ubuntu')},
      })
      ..add(<Object>[]);

    await sync.read();
    await expectLater(sync.read(), throwsA(isA<FormatException>()));

    expect(sync.rid, 3);
  });

  test('two reads asked together make one request', () async {
    final held = Completer<Object>();
    server.script.add(held);

    final list = sync.read();
    final session = sync.read();
    held.complete({
      'rid': 1,
      'full_update': true,
      'torrents': {'aaa': _torrent('Ubuntu')},
    });

    expect(identical(await list, await session), isTrue);
    expect(server.rids, [0]);
  });

  test('a write while a read is in flight is never answered from before '
      'it', () async {
    final held = Completer<Object>();
    server.script
      ..add(held)
      ..add({
        'rid': 2,
        'torrents': {
          'aaa': {'state': 'stoppedDL'},
        },
      });
    final service = QbittorrentService(_client(server), sync);

    final before = service.mainData();
    await service.pauseTorrents(['aaa']);
    final after = service.mainData();
    held.complete({
      'rid': 1,
      'full_update': true,
      'torrents': {'aaa': _torrent('Ubuntu')},
    });

    expect((await before).torrent('aaa')!.state, 'downloading');
    expect((await after).torrent('aaa')!.state, 'stoppedDL');
    expect(server.posts, ['/api/v2/torrents/stop']);
    // The second read went after the first, from the id it answered.
    expect(server.rids, [0, 1]);
  });

  test('the hash is the entry key, not a field the server sends', () async {
    server.script.add({
      'rid': 1,
      'full_update': true,
      'torrents': {'c0ffee': _torrent('Sintel')},
    });

    final data = await sync.read();

    expect(data.torrents.single.hash, 'c0ffee');
  });
}
