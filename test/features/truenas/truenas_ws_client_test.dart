import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/capability/permission_refusal.dart';
import 'package:cupola/features/truenas/data/truenas_ws_client.dart';

import '../../test_helpers/fixtures.dart';

/// A loopback JSON-RPC server standing in for TrueNAS middleware.
///
/// Offline and deterministic — it never leaves the machine — but it is a real
/// socket, which is the only way to exercise a transport bug: the client owns
/// its `WebSocket.connect` call, so there is nothing to inject.
class _FakeMiddleware {
  _FakeMiddleware._(this._server);

  final HttpServer _server;
  final List<WebSocket> _sockets = [];

  /// How many times a client completed the WebSocket upgrade — i.e. how many
  /// connections it opened.
  int upgrades = 0;

  /// Methods the server deliberately never answers, simulating a half-open
  /// connection (suspend, Wi-Fi→cellular handoff): the peer is gone but no
  /// FIN/RST ever arrives, so the client sees neither `onDone` nor `onError`.
  final Set<String> silentMethods = {};

  /// Methods answered after a delay, proving the socket is still alive while a
  /// different call is timing out.
  final Map<String, Duration> delayedMethods = {};

  /// Methods answered with a JSON-RPC `error` object instead of a result.
  final Map<String, Object?> errorMethods = {};

  int get port => _server.port;
  String get url => 'http://127.0.0.1:$port';

  static Future<_FakeMiddleware> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final middleware = _FakeMiddleware._(server);
    unawaited(middleware._serve());
    return middleware;
  }

  Future<void> _serve() async {
    await for (final request in _server) {
      final socket = await WebSocketTransformer.upgrade(request);
      upgrades++;
      _sockets.add(socket);
      socket.listen(
        (dynamic frame) => _onFrame(socket, frame),
        onError: (Object _) {},
        cancelOnError: false,
      );
    }
  }

  void _onFrame(WebSocket socket, dynamic frame) {
    if (frame is! String) return;
    final message = jsonDecode(frame) as Map<String, dynamic>;
    final method = message['method'] as String;
    final id = message['id'];
    if (silentMethods.contains(method)) return;

    void reply() {
      if (socket.readyState != WebSocket.open) return;
      if (errorMethods.containsKey(method)) {
        socket.add(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': id,
            'error': errorMethods[method],
          }),
        );
        return;
      }
      socket.add(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': id,
          'result': method == 'auth.login_with_api_key' ? true : 'ok',
        }),
      );
    }

    final delay = delayedMethods[method];
    if (delay == null) {
      reply();
    } else {
      Timer(delay, reply);
    }
  }

  Future<void> stop() async {
    for (final socket in _sockets) {
      await socket.close().catchError((Object _) => null);
    }
    await _server.close(force: true);
  }
}

void main() {
  late _FakeMiddleware server;

  setUp(() async => server = await _FakeMiddleware.start());
  tearDown(() async => server.stop());

  test('a timed-out call drops a half-open socket so the next call '
      'reconnects', () async {
    // The regression: the timeout only removed the pending completer, leaving
    // `_socket`/`_authed` set. `_ensureConnected` then short-circuited on a
    // dead socket for the rest of the app session, and the 3s dashboard poll
    // stacked a fresh doomed timeout every tick.
    server.silentMethods.add('system.info');
    final client = TrueNasWsClient(
      baseUrl: server.url,
      apiKey: 'key',
      callTimeout: const Duration(milliseconds: 300),
    );
    addTearDown(client.close);

    await expectLater(
      client.call('system.info'),
      throwsA(
        isA<TrueNasException>().having(
          (e) => e.reason,
          'reason',
          ServiceFailureReason.timeout,
        ),
      ),
    );
    expect(server.upgrades, 1);

    // The next call must succeed on a fresh connection rather than time out
    // again against the socket that already stopped answering.
    server.silentMethods.clear();
    expect(await client.call('pool.query'), 'ok');
    expect(server.upgrades, 2);
  });

  test('in-flight calls fail when the connection is dropped', () async {
    server.silentMethods.addAll({'a.slow', 'b.slow'});
    final client = TrueNasWsClient(
      baseUrl: server.url,
      apiKey: 'key',
      callTimeout: const Duration(milliseconds: 300),
    );
    addTearDown(client.close);

    final first = client.call('a.slow');
    final second = client.call('b.slow');

    await expectLater(first, throwsA(isA<TrueNasException>()));
    await expectLater(second, throwsA(isA<TrueNasException>()));
  });

  test('a slow-but-alive socket is kept, not torn down', () async {
    // Only silence is evidence of a dead connection. A server that answers
    // *something* inside the window is merely slow, and reconnecting on every
    // slow call would churn the socket for no reason.
    server.silentMethods.add('very.slow');
    server.delayedMethods['keepalive'] = const Duration(milliseconds: 400);
    final client = TrueNasWsClient(
      baseUrl: server.url,
      apiKey: 'key',
      callTimeout: const Duration(seconds: 1),
    );
    addTearDown(client.close);

    final slow = client.call('very.slow');
    final keepalive = client.call('keepalive');

    expect(await keepalive, 'ok');
    await expectLater(slow, throwsA(isA<TrueNasException>()));
    expect(server.upgrades, 1);

    // Still the same connection, still usable.
    expect(await client.call('pool.query'), 'ok');
    expect(server.upgrades, 1);
  });

  group('the RPC error envelope', () {
    Future<Object> refusal(String method, String fixture) async {
      server.errorMethods[method] = jsonFixtureMap(
        'truenas/$fixture.json',
      )['error'];
      final client = TrueNasWsClient(baseUrl: server.url, apiKey: 'key');
      addTearDown(client.close);
      return client
          .call(method)
          .then<Object>((_) => 'no error', onError: (Object e) => e);
    }

    test(
      'EACCES is a permission refusal, and the reason is the message',
      () async {
        final error = await refusal('pool.dataset.delete', 'rpc_error_eacces');
        expect(error, isA<TrueNasException>());
        final truenas = error as TrueNasException;
        expect(truenas.forbidden, isTrue);
        expect(isPermissionRefusal(truenas), isTrue);
        // Not "Method call error", which is what every failure used to read.
        expect(truenas.message, '[EACCES] Not authorized');
        expect(truenas.reason, isNot(ServiceFailureReason.unauthorized));
      },
    );

    test(
      'an expired session shares the errno and is never a refusal',
      () async {
        final error = await refusal('pool.query', 'rpc_error_session_expired');
        final truenas = error as TrueNasException;
        expect(truenas.forbidden, isFalse);
        expect(truenas.reason, ServiceFailureReason.unauthorized);
      },
    );

    test('EPERM from service.* is the in-body refusal', () async {
      final error = await refusal('service.start', 'rpc_error_eperm_service');
      expect((error as TrueNasException).forbidden, isTrue);
    });

    test('EPERM from anything else is an ordinary failure', () async {
      final error = await refusal(
        'pool.dataset.update',
        'rpc_error_eperm_service',
      );
      expect((error as TrueNasException).forbidden, isFalse);
    });
  });
}
