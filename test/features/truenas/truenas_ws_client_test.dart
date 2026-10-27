import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/capability/permission_refusal.dart';
import 'package:cupola/features/settings/data/service_verification.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/truenas/data/truenas_ws_client.dart';

import '../../test_helpers/fixtures.dart';

/// A loopback JSON-RPC server standing in for TrueNAS middleware.
///
/// Offline and deterministic (it never leaves the machine), but it is a real
/// socket, which is the only way to exercise a transport bug. It speaks plain
/// `ws://`: a TLS fixture would put a private key in a public repository. So
/// the tests that talk to it use [_LoopbackClient], which dials it through the
/// production upgrade path with only the scheme lowered, and the ones about
/// the cleartext refusal use the real client, which must never reach it.
class _FakeMiddleware {
  _FakeMiddleware._(this._server);

  final HttpServer _server;
  final List<WebSocket> _sockets = [];

  /// Every HTTP request that reached the server, upgrade or not. Zero is the
  /// proof that a client refused to dial.
  int requests = 0;

  /// How many times a client completed the WebSocket upgrade, i.e. how many
  /// connections it opened.
  int upgrades = 0;

  /// Every text frame a client sent, verbatim, where an API key would show up.
  final List<String> frames = [];

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

  /// The address a user would save: `https://`, so the client resolves it to
  /// `wss://` and passes its own cleartext check before [_LoopbackClient]
  /// lowers the scheme for the fixture.
  String get url => 'https://127.0.0.1:$port';

  static Future<_FakeMiddleware> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final middleware = _FakeMiddleware._(server);
    unawaited(middleware._serve());
    return middleware;
  }

  Future<void> _serve() async {
    await for (final request in _server) {
      requests++;
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
    frames.add(frame);
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

/// Answers every request with a redirect to [location], counting them.
class _Redirector {
  _Redirector._(this._server, this.location);

  final HttpServer _server;
  final String location;
  int requests = 0;

  int get port => _server.port;

  static Future<_Redirector> start(String location) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirector = _Redirector._(server, location);
    unawaited(redirector._serve());
    return redirector;
  }

  Future<void> _serve() async {
    await for (final request in _server) {
      requests++;
      request.response
        ..statusCode = HttpStatus.movedPermanently
        ..headers.set(HttpHeaders.locationHeader, location);
      await request.response.close();
    }
  }

  Future<void> stop() => _server.close(force: true);
}

/// The real client, dialling the plain-`ws://` fixture.
///
/// Overrides [TrueNasWsClient.dial] and nothing else, and even that only lowers
/// the scheme before calling the production dialer, so the endpoint
/// resolution, the cleartext refusal, the redirect guard, the login and the
/// RPC plumbing under test are all the shipping code.
class _LoopbackClient extends TrueNasWsClient {
  _LoopbackClient({
    required super.baseUrl,
    super.apiKey = 'key',
    super.callTimeout,
    super.idleTimeout,
  });

  @override
  Future<WebSocket> dial(Uri endpoint, HttpClient client) {
    expect(
      endpoint.scheme,
      'wss',
      reason: 'the client resolved a cleartext URL',
    );
    return super.dial(endpoint.replace(scheme: 'ws'), client);
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
    final client = _LoopbackClient(
      baseUrl: server.url,
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

  test('a socket with nothing asked of it is closed, and the next call '
      'opens a new one', () async {
    final client = _LoopbackClient(
      baseUrl: server.url,
      idleTimeout: const Duration(milliseconds: 200),
    );
    addTearDown(client.close);

    expect(await client.call('pool.query'), 'ok');
    expect(await client.call('system.info'), 'ok');
    expect(server.upgrades, 1, reason: 'calls in a row share one socket');

    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(await client.call('pool.query'), 'ok');
    expect(server.upgrades, 2, reason: 'the idle socket was closed');
  });

  test(
    'a call that timed out does not keep the socket from going idle',
    () async {
      // The regression: a timeout removed the call from the pending map without
      // completing it, so the count of what was using the socket stayed at one for
      // the life of the client and the idle close never ran again.
      server.silentMethods.add('system.info');
      final client = _LoopbackClient(
        baseUrl: server.url,
        callTimeout: const Duration(milliseconds: 300),
        idleTimeout: const Duration(milliseconds: 200),
      );
      addTearDown(client.close);

      await expectLater(
        client.call('system.info'),
        throwsA(isA<TrueNasException>()),
      );
      server.silentMethods.clear();
      expect(await client.call('pool.query'), 'ok');
      expect(server.upgrades, 2);

      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(await client.call('pool.query'), 'ok');
      expect(server.upgrades, 3, reason: 'the idle socket was closed');
    },
  );

  test('in-flight calls fail when the connection is dropped', () async {
    server.silentMethods.addAll({'a.slow', 'b.slow'});
    final client = _LoopbackClient(
      baseUrl: server.url,
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
    final client = _LoopbackClient(
      baseUrl: server.url,
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

  test('after a network change a live socket is pinged, not replaced, '
      'however many notices arrive', () async {
    final client = _LoopbackClient(baseUrl: server.url);
    addTearDown(client.close);
    expect(await client.call('pool.query'), 'ok');

    client
      ..markSuspect()
      ..markSuspect();
    expect(await client.call('pool.query'), 'ok');
    expect(await client.call('pool.query'), 'ok');

    expect(server.upgrades, 1, reason: 'the socket answered, so it stays');
    final pings = server.frames.where((f) => f.contains('"core.ping"'));
    expect(pings, hasLength(1), reason: 'one check for the change');
  });

  test('a suspect socket that does not answer the ping is replaced by the '
      'next call, well inside the call timeout', () async {
    final client = _LoopbackClient(
      baseUrl: server.url,
      callTimeout: const Duration(seconds: 30),
    );
    addTearDown(client.close);
    expect(await client.call('pool.query'), 'ok');
    expect(server.upgrades, 1);

    server.silentMethods.add('core.ping');
    client.markSuspect();
    final started = DateTime.now();
    expect(await client.call('pool.query'), 'ok');

    expect(server.upgrades, 2, reason: 'the silent socket was replaced');
    expect(
      DateTime.now().difference(started),
      lessThan(const Duration(seconds: 10)),
      reason: 'the ping timeout, not the 30 s call timeout',
    );
  });

  test('markSuspect with no socket open does nothing, and the first call '
      'connects normally', () async {
    final client = _LoopbackClient(baseUrl: server.url);
    addTearDown(client.close);

    client.markSuspect();

    expect(await client.call('pool.query'), 'ok');
    expect(server.upgrades, 1);
    expect(server.frames.where((f) => f.contains('"core.ping"')), isEmpty);
  });

  group('the RPC error envelope', () {
    Future<Object> refusal(String method, String fixture) async {
      server.errorMethods[method] = jsonFixtureMap(
        'truenas/$fixture.json',
      )['error'];
      final client = _LoopbackClient(baseUrl: server.url);
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

  group('the API key never travels in cleartext', () {
    const secret = 'truenas-secret-key';

    // TrueNAS 25.04+ revokes a key that logs in over an insecure transport, so
    // the regression is not "the key was visible on the wire" but "the first
    // attempt destroyed it". The only acceptable number of requests is zero.
    for (final scheme in ['http', 'ws', 'HTTP']) {
      test(
        'a $scheme:// address is refused before anything is dialled',
        () async {
          final client = TrueNasWsClient(
            baseUrl: '$scheme://127.0.0.1:${server.port}',
            apiKey: secret,
          );
          addTearDown(client.close);

          final error = await client
              .call('core.ping')
              .then<Object>((_) => 'answered', onError: (Object e) => e);

          expect(error, isA<TrueNasInsecureTransportException>());
          expect(server.requests, 0);
          expect(server.frames, isEmpty);

          // Asking again is refused the same way: no state left half-set by the
          // first attempt lets a second one through.
          await expectLater(
            client.call('pool.query'),
            throwsA(isA<TrueNasInsecureTransportException>()),
          );
          expect(server.requests, 0);
        },
      );
    }

    test('the refusal names the fix, and nothing probes the address', () {
      const error = TrueNasInsecureTransportException();

      expect(
        classifyConnectionFailure(error),
        ServiceFailureReason.insecureTransport,
      );
      expect(connectionFailureDetail(error), contains('https://'));
      expect(error.toString(), isNot(contains('not configured')));
      // A fault, never silence: nothing failed to answer, nothing was dialled.
      expect(failureDidNotAnswer(classifyConnectionFailure(error)), isFalse);
      // And neither probe runs: a certificate probe or a local network probe
      // would dial the address the client just refused to dial.
      expect(
        certProbeWorthwhile(ServiceFailureReason.insecureTransport),
        isFalse,
      );
      expect(
        localNetworkCouldExplain(ServiceFailureReason.insecureTransport),
        isFalse,
      );
    });

    test('the connection test reports it, and sends nothing', () async {
      final diagnosis = await diagnoseCredentials(
        ServiceKey.truenas,
        url: 'http://127.0.0.1:${server.port}',
        apiKey: secret,
      );

      expect(diagnosis.isDisconnected, isTrue);
      expect(diagnosis.reason, ServiceFailureReason.insecureTransport);
      expect(
        diagnosis.messageFor(ServiceKey.truenas),
        const TrueNasInsecureTransportException().failureDetail,
      );
      expect(server.requests, 0);
    });

    test('over https the key is sent, once, in the login frame', () async {
      // The positive control for the counters above: the same fixture does see
      // the key when the address is allowed to carry it.
      final client = _LoopbackClient(baseUrl: server.url, apiKey: secret);
      addTearDown(client.close);

      expect(await client.call('core.ping'), 'ok');
      final carrying = server.frames.where((f) => f.contains(secret)).toList();
      expect(carrying, hasLength(1));
      expect(
        (jsonDecode(carrying.single) as Map<String, dynamic>)['method'],
        'auth.login_with_api_key',
      );
    });

    test('a redirect on the upgrade is refused, not followed', () async {
      // `dart:io` follows a redirect on the upgrade GET, and the login frame
      // then goes to whatever answered 101 at the end of the chain: here a
      // cleartext socket on another port, after the scheme check had passed.
      final redirector = await _Redirector.start(
        'http://127.0.0.1:${server.port}/api/current',
      );
      addTearDown(redirector.stop);
      final client = _LoopbackClient(
        baseUrl: 'https://127.0.0.1:${redirector.port}',
        apiKey: secret,
      );
      addTearDown(client.close);

      await expectLater(
        client.call('core.ping'),
        throwsA(
          isA<TrueNasException>().having(
            (e) => e.reason,
            'reason',
            ServiceFailureReason.redirected,
          ),
        ),
      );
      expect(redirector.requests, 1);
      expect(server.requests, 0);
      expect(server.frames, isEmpty);
    });

    test('control: without the guard dart:io does follow it', () async {
      // Proves the test above is not passing on a quirk of the fixture: a bare
      // `WebSocket.connect` walks straight through the same redirect.
      final redirector = await _Redirector.start(
        'http://127.0.0.1:${server.port}/api/current',
      );
      addTearDown(redirector.stop);

      final socket = await WebSocket.connect(
        'ws://127.0.0.1:${redirector.port}/api/current',
      );
      addTearDown(socket.close);
      expect(server.upgrades, 1);
    });
  });
}
