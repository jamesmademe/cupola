import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/cert_trust.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/network/observed_transport.dart';
import 'package:cupola/core/status/media_status.dart';

/// The lab's real transport, not a mocked adapter.
///
/// Dart's HTTP client says `Connection closed before full header was received`
/// both when a peer closes without sending a byte and when it stops halfway
/// through the status line. These two servers do exactly that on loopback,
/// and the app must still put them on opposite sides of the tone rule:
/// silence is red, a partial answer is an amber fault.
void main() {
  // Deliberately no `TestWidgetsFlutterBinding`: it replaces `HttpClient`
  // with a fake that answers every request with a 400, which would test the
  // fake instead of the transport. These tests speak to loopback servers.
  test('a peer that closes without a byte is silence', () async {
    final server = await _server((socket) {
      socket.destroy();
    });
    addTearDown(server.close);

    final failure = await _failureFrom(server.port);

    expect(
      classifyConnectionFailure(failure),
      ServiceFailureReason.unreachable,
    );
    expect(failureDidNotAnswer(classifyConnectionFailure(failure)), isTrue);
    expect(failureTone(classifyConnectionFailure(failure)), StatusTone.error);
    expect(failureRemedy(classifyConnectionFailure(failure)), isNull);
  });

  test(
    'a peer that stops halfway through its status line is a fault',
    () async {
      final server = await _server((socket) {
        socket.write('HTTP/1.1 200 OK\r\nContent-Le');
        socket.destroy();
      });
      addTearDown(server.close);

      final failure = await _failureFrom(server.port);
      final reason = classifyConnectionFailure(failure);

      expect(reason, ServiceFailureReason.invalidResponse);
      expect(failureDidNotAnswer(reason), isFalse);
      expect(failureIsFault(reason), isTrue);
      expect(failureTone(reason), StatusTone.warning);
      expect(failureLabel(reason), 'Unreadable answer');
    },
  );

  group('the pin of a direct TLS connection', () {
    // The factory opens TLS itself, so the decision it installs is the only
    // one that runs for a direct `https` connection. It once checked the
    // pinned host against itself, which left the fingerprint alone deciding.
    final cert = _FakeCert(const [1, 2, 3]);
    bool? accepts(String host, int port, {String? pin}) => pinnedSocketCallback(
      pinnedFingerprint: pin ?? certificateFingerprint(cert),
      host: host,
      port: port,
      pinnedHost: 'nas.local',
      pinnedPort: 9091,
    )?.call(cert);

    test('accepts the pinned certificate at the pinned origin', () {
      expect(accepts('nas.local', 9091), isTrue);
    });

    test('refuses the same certificate from another host or port', () {
      expect(accepts('evil.example.com', 9091), isFalse);
      expect(accepts('nas.local', 443), isFalse);
    });

    test('installs nothing without a pin', () {
      expect(accepts('nas.local', 9091, pin: '  '), isNull);
    });
  });

  test('a complete answer is not a failure', () async {
    final server = await _server((socket) {
      socket.write(
        'HTTP/1.1 200 OK\r\n'
        'Content-Type: application/json\r\n'
        'Content-Length: 2\r\n'
        'Connection: close\r\n'
        '\r\n'
        '[]',
      );
      socket.destroy();
    });
    addTearDown(server.close);

    final dio = _dio(server.port);
    addTearDown(dio.close);
    final answer = await dio.get<dynamic>('/api/v3/system/status');

    expect(answer.statusCode, 200);
    expect(answer.data, isEmpty);
  });
}

Future<ServerSocket> _server(void Function(Socket socket) answer) async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final sockets = <Socket>[];
  server.listen((socket) {
    sockets.add(socket);
    socket.listen((_) => answer(socket), onError: (_) {}, cancelOnError: true);
  });
  // The server owns every accepted socket; closing the listening socket does
  // not close them, and a leaked loopback socket keeps the test process alive.
  return _OwnedServer(server, sockets);
}

class _OwnedServer extends StreamView<Socket> implements ServerSocket {
  _OwnedServer(this._inner, this._sockets) : super(_inner);

  final ServerSocket _inner;
  final List<Socket> _sockets;

  @override
  Future<ServerSocket> close() {
    for (final socket in _sockets) {
      socket.destroy();
    }
    return _inner.close();
  }

  @override
  InternetAddress get address => _inner.address;

  @override
  int get port => _inner.port;
}

Dio _dio(int port) {
  final dio = Dio(
    BaseOptions(
      baseUrl: 'http://127.0.0.1:$port',
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
    ),
  );
  dio.httpClientAdapter = observedHttpClientAdapterFor(dio.options.baseUrl);
  return dio;
}

Future<Object> _failureFrom(int port) async {
  final dio = _dio(port);
  try {
    await dio.get<dynamic>('/api/v3/system/status');
  } on DioException catch (error) {
    return error;
  } finally {
    dio.close();
  }
  fail('the server closed before a complete answer');
}

class _FakeCert implements X509Certificate {
  _FakeCert(List<int> bytes) : der = Uint8List.fromList(bytes);

  @override
  final Uint8List der;

  @override
  String get pem => '';

  @override
  Uint8List get sha1 => Uint8List(0);

  @override
  String get subject => 'CN=nas.local';

  @override
  String get issuer => 'CN=nas.local';

  @override
  DateTime get startValidity => DateTime(2026);

  @override
  DateTime get endValidity => DateTime(2027);
}
