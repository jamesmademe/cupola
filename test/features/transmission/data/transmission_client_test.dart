import 'dart:typed_data';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/network/redirect_guard.dart';
import 'package:cupola/features/transmission/data/transmission_client.dart';
import 'package:cupola/features/transmission/domain/models/transmission_models.dart';

import '../../../test_helpers/scripted_http_adapter.dart';

/// A Dio shaped exactly like the one [TransmissionClient] builds for itself, so
/// an injected transport still exercises the redirect/status contract the real
/// one runs under.
Dio _dio(
  ScriptedHttpAdapter adapter, {
  String base = 'https://nas.local:9091',
}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: base,
      followRedirects: false,
      validateStatus: allowRedirectStatus,
    ),
  );
  dio.httpClientAdapter = adapter;
  return dio;
}

ScriptedReply _ok(Map<String, dynamic> arguments) =>
    ScriptedReply(body: {'result': 'success', 'arguments': arguments});

void main() {
  group('resolveRpcPath', () {
    // The daemon's `rpc-url` setting and any reverse proxy in front of it both
    // move this endpoint, so a hardcoded path is the most common reason a
    // working Transmission looks unreachable.
    test('appends the default path when the URL carries none', () {
      expect(
        TransmissionClient.resolveRpcPath('https://nas.local:9091'),
        '/transmission/rpc',
      );
      expect(
        TransmissionClient.resolveRpcPath('nas.local:9091/'),
        '/transmission/rpc',
      );
    });

    test('appends /rpc to a relocated rpc-url', () {
      expect(
        TransmissionClient.resolveRpcPath('https://nas.local/tr'),
        '/tr/rpc',
      );
      expect(
        TransmissionClient.resolveRpcPath('https://nas.local/tr/'),
        '/tr/rpc',
      );
    });

    test('uses a full endpoint verbatim', () {
      expect(
        TransmissionClient.resolveRpcPath('https://nas.local/tr/rpc'),
        '/tr/rpc',
      );
      expect(
        TransmissionClient.resolveRpcPath('https://nas.local/tr/rpc/'),
        '/tr/rpc',
      );
    });

    test('maps a pasted Web UI address onto its sibling endpoint', () {
      // The address bar of the Web UI is what people copy. Transmission serves
      // that page at `<rpc-url>web/`, and `/transmission/web/rpc` does not
      // exist.
      expect(
        TransmissionClient.resolveRpcPath(
          'http://nas.local:9091/transmission/web/',
        ),
        '/transmission/rpc',
      );
      expect(
        TransmissionClient.resolveRpcPath('https://nas.local/tr/web'),
        '/tr/rpc',
      );
      // At the root, `/web` is as likely a proxy mount as a Web UI: left alone.
      expect(
        TransmissionClient.resolveRpcPath('https://nas.local/web'),
        '/web/rpc',
      );
    });
  });

  // OPS-01. Every test above this group injects a Dio rooted at the bare
  // origin, which is exactly the one shape where joining `baseUrl` with a
  // full path happens to come out right: the client stored the configured path
  // in the transport's `baseUrl` *and* in `rpcPath`, and Dio concatenates the
  // two, so `https://nas/tr` went on the wire as `/tr/tr/rpc`. These build the
  // client through its real constructor (the transport it makes for itself),
  // and only swap the socket underneath.
  group('RPC endpoint on the wire', () {
    Future<Uri> endpointFor(String url) async {
      final client = TransmissionClient(url: url);
      addTearDown(client.close);
      final adapter = ScriptedHttpAdapter([
        _ok({'version': '4.0.6'}),
      ]);
      client.dio.httpClientAdapter = adapter;

      await client.session();

      expect(adapter.callCount, 1);
      return adapter.lastRequest.uri;
    }

    const cases = {
      'https://nas.local': 'https://nas.local/transmission/rpc',
      'https://nas.local/': 'https://nas.local/transmission/rpc',
      'http://nas.local:9091': 'http://nas.local:9091/transmission/rpc',
      'https://nas.local/tr': 'https://nas.local/tr/rpc',
      'https://nas.local/tr/': 'https://nas.local/tr/rpc',
      'https://nas.local/tr/rpc': 'https://nas.local/tr/rpc',
      'https://nas.local:8443/proxy/torrents/rpc':
          'https://nas.local:8443/proxy/torrents/rpc',
      'http://nas.local:9091/transmission':
          'http://nas.local:9091/transmission/rpc',
      'http://nas.local:9091/transmission/web/':
          'http://nas.local:9091/transmission/rpc',
      'nas.local/tr': 'https://nas.local/tr/rpc',
    };

    for (final entry in cases.entries) {
      test('${entry.key} posts to exactly ${entry.value}', () async {
        expect((await endpointFor(entry.key)).toString(), entry.value);
      });
    }

    test('the transport is rooted at the origin, not the path', () {
      final client = TransmissionClient(url: 'https://nas.local/tr');
      addTearDown(client.close);

      expect(client.dio.options.baseUrl, 'https://nas.local');
      expect(client.baseUrl, 'https://nas.local/tr');
      expect(client.rpcUrl, 'https://nas.local/tr/rpc');
    });

    test(
      'an injected Dio whose base carries the path still hits it once',
      () async {
        // The endpoint is posted as an absolute URL, so it no longer depends on
        // what `baseUrl` the transport happens to carry.
        final adapter = ScriptedHttpAdapter([
          _ok({'version': '4.0.6'}),
        ]);
        final client = TransmissionClient(
          url: 'https://nas.local/tr',
          dio: _dio(adapter, base: 'https://nas.local/tr'),
        );

        await client.session();

        expect(adapter.lastRequest.uri.toString(), 'https://nas.local/tr/rpc');
      },
    );

    test('a seedbox\'s worth of torrents reads the same off the UI '
        'isolate', () async {
      final adapter = ScriptedHttpAdapter([
        _ok({
          'torrents': [
            for (var i = 0; i < 250; i++)
              {'id': i, 'name': 'Torrent $i', 'hashString': 'h$i'},
          ],
        }),
      ]);
      final client = TransmissionClient(
        url: 'https://nas.local:9091',
        dio: _dio(adapter),
      );

      final torrents = await client.torrents();

      expect(torrents, hasLength(250));
      expect(torrents.first.name, 'Torrent 0');
      expect(torrents.last.name, 'Torrent 249');
    });

    group('the poll\'s list reads what moved', () {
      Map<String, dynamic> torrent(int id, {double done = 0.5}) => {
        'id': id,
        'name': 'Torrent $id',
        'hashString': 'h$id',
        'percentDone': done,
      };

      Object? argumentsOf(ScriptedRequest request) =>
          (request.body as Map)['arguments'];

      TransmissionClient clientOver(ScriptedHttpAdapter adapter) =>
          TransmissionClient(url: 'https://nas.local:9091', dio: _dio(adapter));

      test('the first read is whole, the poll\'s next one a delta', () async {
        final adapter = ScriptedHttpAdapter([
          _ok({
            'torrents': [torrent(1), torrent(2), torrent(3)],
          }),
          _ok({
            'torrents': [torrent(2, done: 0.9), torrent(4)],
            'removed': [3],
          }),
        ]);
        final client = clientOver(adapter);

        final first = await client.torrentsSynced();
        expect(first.map((t) => t.id), [1, 2, 3]);
        expect(argumentsOf(adapter.requests.first), isNot(contains('ids')));

        client.allowDeltaRead();
        final second = await client.torrentsSynced();

        expect(
          argumentsOf(adapter.requests.last),
          containsPair('ids', 'recently-active'),
        );
        // 3 is gone, 2 moved on, 4 is new and goes last; 1 is as it was.
        expect(second.map((t) => t.id), [1, 2, 4]);
        expect(second.firstWhere((t) => t.id == 2).percentDone, 0.9);
        expect(second.firstWhere((t) => t.id == 1).percentDone, 0.5);
      });

      test('a read the poll did not ask for is the whole list', () async {
        final adapter = ScriptedHttpAdapter([
          _ok({
            'torrents': [torrent(1)],
          }),
          _ok({
            'torrents': [torrent(1), torrent(2)],
          }),
        ]);
        final client = clientOver(adapter);

        await client.torrentsSynced();
        // A pull, a Retry, a read after a write: no `allowDeltaRead`.
        final again = await client.torrentsSynced();

        expect(argumentsOf(adapter.requests.last), isNot(contains('ids')));
        expect(again.map((t) => t.id), [1, 2]);
      });

      test('after half a minute the poll reads the whole list again', () async {
        final origin = DateTime(2026, 10, 26, 12);
        var elapsed = Duration.zero;
        final adapter = ScriptedHttpAdapter([
          _ok({
            'torrents': [torrent(1)],
          }),
          _ok({
            'torrents': [torrent(1), torrent(7)],
          }),
        ]);
        final client = clientOver(adapter)..clock = () => origin.add(elapsed);

        await client.torrentsSynced();
        elapsed = TransmissionClient.fullEvery + const Duration(seconds: 1);
        client.allowDeltaRead();
        final late = await client.torrentsSynced();

        expect(argumentsOf(adapter.requests.last), isNot(contains('ids')));
        // What a delta would have missed (another client's change to a torrent
        // that did not move) is in the whole list.
        expect(late.map((t) => t.id), [1, 7]);
      });

      test(
        'a delta that fails leaves what is held for the next read',
        () async {
          final adapter = ScriptedHttpAdapter([
            _ok({
              'torrents': [torrent(1)],
            }),
            const ScriptedReply(statusCode: 500),
            _ok({
              'torrents': [torrent(1, done: 0.7)],
            }),
          ]);
          final client = clientOver(adapter);

          await client.torrentsSynced();
          client.allowDeltaRead();
          await expectLater(client.torrentsSynced(), throwsA(anything));
          client.allowDeltaRead();
          final after = await client.torrentsSynced();

          expect(after.single.percentDone, 0.7);
        },
      );
    });

    test('the 409 replay goes to the same single-path endpoint', () async {
      final client = TransmissionClient(url: 'https://nas.local/tr/');
      addTearDown(client.close);
      final adapter = ScriptedHttpAdapter([
        const ScriptedReply(
          statusCode: 409,
          headers: {
            'x-transmission-session-id': ['abc123'],
          },
        ),
        _ok({'version': '4.0.6'}),
      ]);
      client.dio.httpClientAdapter = adapter;

      await client.session();

      expect(adapter.requests.map((r) => r.uri.path), ['/tr/rpc', '/tr/rpc']);
    });
  });

  group('transport contract', () {
    test('installs the redirect guard and refuses to auto-follow', () {
      final client = TransmissionClient(url: 'https://nas.local:9091');
      addTearDown(client.close);

      // `dart:io` copies `Authorization` on a redirect to a *parent* domain, so
      // without this guard `transmission.homelab.net` → `homelab.net` hands the
      // Basic password to the apex host.
      expect(
        client.dio.interceptors.whereType<SameOriginRedirectInterceptor>(),
        isNotEmpty,
      );
      expect(client.dio.options.followRedirects, isFalse);
    });

    test('installs a pinned adapter only when a fingerprint is given', () {
      final unpinned = TransmissionClient(url: 'https://nas.local:9091');
      final pinned = TransmissionClient(
        url: 'https://nas.local:9091',
        certFingerprint: 'ab12cd34',
      );
      addTearDown(unpinned.close);
      addTearDown(pinned.close);

      expect(
        pinned.dio.httpClientAdapter,
        isNot(unpinned.dio.httpClientAdapter),
      );
    });
  });

  group('authentication', () {
    test(
      'sends HTTP Basic credentials in the header, never in the URL',
      () async {
        final adapter = ScriptedHttpAdapter([
          _ok({'version': '4.0.6', 'rpc-version': 17}),
        ]);
        final client = TransmissionClient(
          url: 'https://nas.local:9091',
          username: 'matt',
          password: 'hunter2',
          dio: _dio(adapter),
        );

        await client.session();

        final auth = adapter.lastRequest.headers['Authorization'] as String;
        expect(auth, 'Basic ${base64Encode(utf8.encode('matt:hunter2'))}');
        expect(adapter.lastRequest.uri.toString(), isNot(contains('hunter2')));
        expect(adapter.lastRequest.uri.userInfo, isEmpty);
      },
    );

    test('sends no Authorization header when there is no username', () async {
      final adapter = ScriptedHttpAdapter([
        _ok({'version': '4.0.6'}),
      ]);
      final client = TransmissionClient(
        url: 'https://nas.local:9091',
        dio: _dio(adapter),
      );

      await client.session();

      expect(adapter.lastRequest.headers.containsKey('Authorization'), isFalse);
    });

    test('a 401 is terminal and is not retried on the next call', () async {
      // Transmission's anti-brute-force guard flips to a 403 lockout that
      // survives until the daemon restarts, so a polling client that re-sends a
      // wrong password locks the user out of their own box.
      final adapter = ScriptedHttpAdapter([
        const ScriptedReply(statusCode: 401),
      ]);
      final client = TransmissionClient(
        url: 'https://nas.local:9091',
        username: 'matt',
        password: 'wrong',
        dio: _dio(adapter),
      );

      await expectLater(
        client.session(),
        throwsA(
          isA<TransmissionException>().having(
            (e) => e.reason,
            'reason',
            ServiceFailureReason.unauthorized,
          ),
        ),
      );
      final afterFirst = adapter.callCount;

      await expectLater(
        client.session(),
        throwsA(isA<TransmissionException>()),
      );
      expect(
        adapter.callCount,
        afterFirst,
        reason: 'a rejected credential must not reach the network again',
      );
    });

    test(
      '403 and 421 are reported as configuration, not bad credentials',
      () async {
        for (final status in [403, 421]) {
          final client = TransmissionClient(
            url: 'https://nas.local:9091',
            username: 'matt',
            password: 'hunter2',
            dio: _dio(ScriptedHttpAdapter([ScriptedReply(statusCode: status)])),
          );
          await expectLater(
            client.session(),
            throwsA(
              isA<TransmissionException>().having(
                (e) => e.message,
                'message',
                contains('whitelist'),
              ),
            ),
          );
        }
      },
    );
  });

  group('CSRF session-id handshake', () {
    test('replays once with the id from the 409 response headers', () async {
      final adapter = ScriptedHttpAdapter([
        const ScriptedReply(
          statusCode: 409,
          headers: {
            'x-transmission-session-id': ['abc123'],
          },
        ),
        _ok({'version': '4.0.6', 'rpc-version': 17}),
      ]);
      final client = TransmissionClient(
        url: 'https://nas.local:9091',
        dio: _dio(adapter),
      );

      final session = await client.session();

      expect(session.version, '4.0.6');
      expect(adapter.callCount, 2);
      expect(
        adapter.requests.first.headers.containsKey(
          TransmissionClient.sessionIdHeader,
        ),
        isFalse,
      );
      expect(
        adapter.requests[1].headers[TransmissionClient.sessionIdHeader],
        'abc123',
      );
    });

    test('reuses the learned id on the next call', () async {
      final adapter = ScriptedHttpAdapter([
        const ScriptedReply(
          statusCode: 409,
          headers: {
            'x-transmission-session-id': ['abc123'],
          },
        ),
        _ok({'version': '4.0.6'}),
      ]);
      final client = TransmissionClient(
        url: 'https://nas.local:9091',
        dio: _dio(adapter),
      );

      await client.session();
      await client.session();

      expect(adapter.callCount, 3);
      expect(
        adapter.requests.last.headers[TransmissionClient.sessionIdHeader],
        'abc123',
      );
    });

    test('a second 409 fails instead of looping forever', () async {
      // The id rotates hourly with **no grace window**, so this path is hit in
      // normal operation, and retrying without a usable id is the classic way
      // clients against this API hang.
      final adapter = ScriptedHttpAdapter([
        const ScriptedReply(
          statusCode: 409,
          headers: {
            'x-transmission-session-id': ['abc123'],
          },
        ),
        const ScriptedReply(
          statusCode: 409,
          headers: {
            'x-transmission-session-id': ['def456'],
          },
        ),
      ]);
      final client = TransmissionClient(
        url: 'https://nas.local:9091',
        dio: _dio(adapter),
      );

      await expectLater(
        client.session(),
        throwsA(isA<TransmissionException>()),
      );
      expect(
        adapter.callCount,
        2,
        reason: 'exactly one replay, never recursive',
      );
    });

    test(
      'a 409 with no session-id header fails rather than replaying',
      () async {
        final adapter = ScriptedHttpAdapter([
          const ScriptedReply(statusCode: 409),
        ]);
        final client = TransmissionClient(
          url: 'https://nas.local:9091',
          dio: _dio(adapter),
        );

        await expectLater(
          client.session(),
          throwsA(
            isA<TransmissionException>().having(
              (e) => e.message,
              'message',
              contains('reverse proxy'),
            ),
          ),
        );
        expect(adapter.callCount, 1);
      },
    );
  });

  group('the RPC envelope', () {
    test('HTTP 200 with a non-success result is a failure', () async {
      final adapter = ScriptedHttpAdapter([
        const ScriptedReply(body: {'result': 'invalid argument'}),
      ]);
      final client = TransmissionClient(
        url: 'https://nas.local:9091',
        dio: _dio(adapter),
      );

      await expectLater(
        client.session(),
        throwsA(
          isA<TransmissionException>().having(
            (e) => e.message,
            'message',
            'invalid argument',
          ),
        ),
      );
    });

    test('HTML on a 200 is reported as "the API is not here"', () async {
      final adapter = ScriptedHttpAdapter([
        const ScriptedReply(body: '<html>Transmission Web UI</html>'),
      ]);
      final client = TransmissionClient(
        url: 'https://nas.local:9091',
        dio: _dio(adapter),
      );

      await expectLater(
        client.session(),
        throwsA(
          isA<TransmissionException>().having(
            (e) => e.reason,
            'reason',
            ServiceFailureReason.notFound,
          ),
        ),
      );
    });
  });

  group('writes', () {
    test(
      'a .torrent file on this device goes as metainfo, in base64',
      () async {
        final adapter = ScriptedHttpAdapter([_ok(const {})]);
        final client = TransmissionClient(
          url: 'https://nas.local:9091',
          dio: _dio(adapter),
        );

        await client.addTorrentFile(Uint8List.fromList([1, 2, 3]));
        final body = adapter.lastRequest.body as Map<String, dynamic>;
        expect(body['method'], 'torrent-add');
        expect(body['arguments']['metainfo'], base64Encode([1, 2, 3]));
        expect(body['arguments'], isNot(contains('filename')));
      },
    );

    test(
      'a torrent with no hash is addressed by its id, as a number',
      () async {
        final adapter = ScriptedHttpAdapter([_ok(const {})]);
        final client = TransmissionClient(
          url: 'https://nas.local:9091',
          dio: _dio(adapter),
        );

        await client.stop(['12', 'a' * 40]);
        final body = adapter.lastRequest.body as Map<String, dynamic>;
        expect(body['arguments']['ids'], [12, 'a' * 40]);
      },
    );

    test('every write sends an ids key, and an empty selection throws', () async {
      // An **absent** `ids` means "all torrents" to this API, so a write
      // assembled with `if (ids.isNotEmpty)` would escalate an empty selection
      // into the whole library: with `delete-local-data` that is the files too.
      final adapter = ScriptedHttpAdapter([_ok(const {})]);
      final client = TransmissionClient(
        url: 'https://nas.local:9091',
        dio: _dio(adapter),
      );

      await client.removeTorrents(['abc'], deleteLocalData: true);
      final body = adapter.lastRequest.body as Map<String, dynamic>;
      expect(body['method'], 'torrent-remove');
      expect(body['arguments']['ids'], ['abc']);
      expect(body['arguments']['delete-local-data'], isTrue);

      await expectLater(
        client.removeTorrents(const [], deleteLocalData: true),
        throwsA(isA<TransmissionException>()),
      );
      expect(
        adapter.callCount,
        1,
        reason: 'an empty selection must never reach the daemon',
      );
    });

    test('remove defaults to keeping the downloaded files', () async {
      final adapter = ScriptedHttpAdapter([_ok(const {})]);
      final client = TransmissionClient(
        url: 'https://nas.local:9091',
        dio: _dio(adapter),
      );

      await client.removeTorrents(['abc']);

      final body = adapter.lastRequest.body as Map<String, dynamic>;
      expect(body['arguments']['delete-local-data'], isFalse);
    });

    test('a duplicate add is reported as duplicate, not as added', () async {
      // Transmission answers `result: "success"` with a `torrent-duplicate`
      // key, so a client checking only `result` claims it added something it
      // did not.
      final adapter = ScriptedHttpAdapter([
        _ok({
          'torrent-duplicate': {'id': 4, 'hashString': 'aa', 'name': 'Dune'},
        }),
      ]);
      final client = TransmissionClient(
        url: 'https://nas.local:9091',
        dio: _dio(adapter),
      );

      final outcome = await client.addTorrent('magnet:?xt=urn:btih:aa');

      expect(outcome.isDuplicate, isTrue);
      expect(outcome.torrent?.name, 'Dune');
    });

    test('speed limits are sent with their matching enabled flag', () async {
      final adapter = ScriptedHttpAdapter([_ok(const {})]);
      final client = TransmissionClient(
        url: 'https://nas.local:9091',
        dio: _dio(adapter),
      );

      await client.setSpeedLimits(['abc'], downloadKbPerSec: 0);

      final args =
          (adapter.lastRequest.body as Map<String, dynamic>)['arguments']
              as Map<String, dynamic>;
      // A limit without its `*Limited` flag stores a value that never applies,
      // which reads on screen as a broken toggle.
      expect(args['downloadLimit'], 0);
      expect(args['downloadLimited'], isFalse);
      expect(args.containsKey('uploadLimit'), isFalse);
    });

    test('labels are trimmed and replaced through torrent-set', () async {
      final adapter = ScriptedHttpAdapter([_ok(const {})]);
      final client = TransmissionClient(
        url: 'https://nas.local:9091',
        dio: _dio(adapter),
      );

      await client.setLabels(['abc'], [' movies ', '', '4k']);

      final body = adapter.lastRequest.body as Map<String, dynamic>;
      expect(body['method'], 'torrent-set');
      expect(body['arguments'], {
        'ids': ['abc'],
        'labels': ['movies', '4k'],
      });
    });

    test(
      'session preferences use Transmission session-set field names',
      () async {
        final adapter = ScriptedHttpAdapter([_ok(const {})]);
        final client = TransmissionClient(
          url: 'https://nas.local:9091',
          dio: _dio(adapter),
        );

        await client.setSessionPreferences(
          peerPort: 51413,
          encryption: 'required',
          seedRatioLimit: 2.5,
          seedRatioLimited: true,
          downloadQueueEnabled: true,
          downloadQueueSize: 8,
        );

        final body = adapter.lastRequest.body as Map<String, dynamic>;
        expect(body['method'], 'session-set');
        expect(body['arguments'], {
          'peer-port': 51413,
          'encryption': 'required',
          'seedRatioLimit': 2.5,
          'seedRatioLimited': true,
          'download-queue-enabled': true,
          'download-queue-size': 8,
        });
      },
    );

    test(
      'an empty session preference write never reaches the daemon',
      () async {
        final adapter = ScriptedHttpAdapter(const []);
        final client = TransmissionClient(
          url: 'https://nas.local:9091',
          dio: _dio(adapter),
        );

        await client.setSessionPreferences();

        expect(adapter.callCount, 0);
      },
    );
  });

  group('model parsing', () {
    test('an infinite ratio reads as one, the unknown one as a dash', () {
      TransmissionTorrent ratio(double value) => TransmissionTorrent.fromJson({
        'id': 7,
        'name': 'Arrival',
        'status': 6,
        'uploadRatio': value,
      });

      expect(ratio(-2).ratioLabel, '∞');
      expect(ratio(-1).ratioLabel, '—');
      expect(ratio(1.234).ratioLabel, '1.23');
    });

    test('reads the sentinels Transmission actually uses', () {
      final torrent = TransmissionTorrent.fromJson(const {
        'id': 7,
        'hashString': 'deadbeef',
        'name': 'Arrival',
        'status': 4,
        'percentDone': 0.5,
        'eta': -1,
        'uploadRatio': -1,
        'isStalled': true,
        'error': 3,
        'errorString': 'No data found',
        'doneDate': 0,
      });

      expect(torrent.status, TransmissionStatus.download);
      expect(torrent.status.isIncoming, isTrue);
      expect(torrent.etaLabel, 'Unknown');
      expect(torrent.ratioLabel, '—');
      expect(torrent.errorKind, TransmissionErrorKind.localError);
      // A local error outranks the stalled flag: it is the reason.
      expect(torrent.warning, 'No data found');
      expect(torrent.rpcId, 'deadbeef');
    });

    test('falls back to the session id only when there is no hash', () {
      final torrent = TransmissionTorrent.fromJson(const {'id': 7});
      expect(torrent.rpcId, '7');
    });

    test('an absent eta reads as unknown rather than "arriving now"', () {
      final torrent = TransmissionTorrent.fromJson(const {'id': 1});
      expect(torrent.eta, -1);
      expect(torrent.etaLabel, 'Unknown');
    });
  });

  group('free-space', () {
    TransmissionClient clientFor(ScriptedHttpAdapter adapter) =>
        TransmissionClient(url: 'https://nas.local:9091', dio: _dio(adapter));

    test('asks for the path it was given', () async {
      final adapter = ScriptedHttpAdapter([
        _ok({'path': '/downloads', 'size-bytes': 1024}),
      ]);
      final client = clientFor(adapter);

      expect(await client.freeSpace('/downloads'), 1024);
      final body = adapter.lastRequest.body as Map<String, dynamic>;
      expect(body['method'], 'free-space');
      expect((body['arguments'] as Map)['path'], '/downloads');
    });

    test('a daemon that reported no size answers null, not zero', () async {
      // The defect: collapsing a missing `size-bytes` to 0 made "the daemon
      // did not say" and "the disk is full" the same int, and the only way to
      // recover the first was to throw the second away.
      final client = clientFor(ScriptedHttpAdapter([_ok({})]));

      expect(await client.freeSpace('/downloads'), isNull);
    });

    test('a non-numeric size is silence too', () async {
      final client = clientFor(
        ScriptedHttpAdapter([
          _ok({'size-bytes': 'plenty'}),
        ]),
      );

      expect(await client.freeSpace('/downloads'), isNull);
    });

    test('a full disk answers zero and keeps it', () async {
      final client = clientFor(
        ScriptedHttpAdapter([
          _ok({'path': '/downloads', 'size-bytes': 0}),
        ]),
      );

      expect(await client.freeSpace('/downloads'), 0);
    });

    test('a negative size is not a measurement', () async {
      // Transmission documents `size-bytes` as a count of free bytes; a
      // negative one is a daemon saying it could not measure, and printing it
      // would render a size below zero.
      final client = clientFor(
        ScriptedHttpAdapter([
          _ok({'size-bytes': -1}),
        ]),
      );

      expect(await client.freeSpace('/downloads'), isNull);
    });
  });
}
