import 'dart:async';
import 'dart:convert' show Encoding;
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:cupola/core/network/cert_trust.dart';
import 'package:cupola/core/network/connection_failure.dart';

/// The zone value that carries one request's byte count down to the socket
/// that serves it.
const _observationKey = #cupolaResponseObservation;

/// What arrived on one request's connection before it failed.
class _Observation {
  int received = 0;
}

/// A Dio adapter that knows whether the server sent anything before it closed.
///
/// Dart's `HttpClient` throws the same [HttpException] for a peer that closes
/// without a byte and for one that closes partway through its status line.
/// The classifier cannot tell them apart from the exception, and doing so from
/// its message is a guess. This adapter installs a connection factory on the
/// `HttpClient`; every socket it opens counts the bytes it delivers, in the
/// zone of the request that wrote on it. When a header never completes, the
/// count travels with [ClosedBeforeHeaders]:
///
/// * zero is silence, red;
/// * one or more is a partial answer, a fault, amber.
class ObservedIOHttpClientAdapter extends IOHttpClientAdapter {
  ObservedIOHttpClientAdapter({required super.createHttpClient});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    final observation = _Observation();
    return runZoned(() async {
      try {
        final body = await super.fetch(options, requestStream, cancelFuture);
        // A truncated header may surface while Dio reads the body stream,
        // after `fetch` has returned. Replace that error with the observed
        // count as well, so the verdict does not depend on which side of the
        // await Dart reported it.
        body.stream = body.stream.handleError((Object error, StackTrace stack) {
          if (error is HttpException) {
            throw ClosedBeforeHeaders(observation.received, cause: error);
          }
          Error.throwWithStackTrace(error, stack);
        }, test: (error) => error is HttpException);
        return body;
      } on HttpException catch (error) {
        throw ClosedBeforeHeaders(observation.received, cause: error);
      }
    }, zoneValues: {_observationKey: observation});
  }
}

/// The adapter every HTTP client in the app gets: pinned when a fingerprint
/// is known, observed always.
///
/// The observation is not a test harness: it is the only way the app can keep
/// the brand book's promise that red means *nothing answered* while a partial
/// header stays an amber fault.
HttpClientAdapter observedHttpClientAdapterFor(
  String baseUrl, {
  String? pinnedFingerprint,
}) {
  final origin = Uri.parse(baseUrl);
  final port = origin.hasPort
      ? origin.port
      : (origin.scheme == 'https' ? 443 : 80);
  return ObservedIOHttpClientAdapter(
    createHttpClient: () => buildObservedHttpClient(
      pinnedFingerprint: pinnedFingerprint,
      pinnedHost: origin.host,
      pinnedPort: port,
    ),
  );
}

/// An [HttpClient] whose sockets report how many bytes they delivered.
///
/// The connection factory is the same one `dart:io` would use: a direct TLS
/// connection for `https`, a plain socket otherwise, and the proxy's address
/// when the client's own proxy rules name one. The one difference is the
/// [StreamView] around the socket, which counts without consuming.
HttpClient buildObservedHttpClient({
  String? pinnedFingerprint,
  String? pinnedHost,
  int? pinnedPort,
}) {
  final pin = pinnedFingerprint?.trim().toLowerCase() ?? '';
  final acceptBadCertificateAt = pin.isEmpty
      ? null
      : (X509Certificate certificate, String host, int port) =>
            pinnedCertificateIsTrusted(
              certificate,
              host: host,
              port: port,
              pinnedFingerprint: pin,
              pinnedHost: pinnedHost,
              pinnedPort: pinnedPort,
            );

  final client = HttpClient()
    ..idleTimeout = const Duration(seconds: 3)
    ..connectionFactory = (uri, proxyHost, proxyPort) async {
      final ConnectionTask<Socket> task;
      if (proxyHost != null) {
        task = await Socket.startConnect(proxyHost, proxyPort ?? uri.port);
      } else if (uri.scheme == 'https') {
        task = await SecureSocket.startConnect(
          uri.host,
          uri.port,
          onBadCertificate: pinnedSocketCallback(
            pinnedFingerprint: pin,
            host: uri.host,
            port: uri.port,
            pinnedHost: pinnedHost,
            pinnedPort: pinnedPort,
          ),
        );
      } else {
        task = await Socket.startConnect(uri.host, uri.port);
      }
      return ConnectionTask.fromSocket(
        task.socket.then<Socket>(_ObservedSocket.new),
        task.cancel,
      );
    };
  // Only a pin installs a callback, as `buildPinnedHttpClient` does: without
  // one the platform's verification is the sole authority. This one decides
  // for a proxied `https` connection, which `dart:io` tunnels itself.
  if (acceptBadCertificateAt != null) {
    client.badCertificateCallback = acceptBadCertificateAt;
  }
  return client;
}

/// The certificate decision for one TLS connection the factory opens to
/// [host]:[port], or null (platform trust alone) when there is no pin.
///
/// The connection's own host and port go to [pinnedCertificateIsTrusted], so
/// a pin stays bound to the origin it was granted for (ADR-6): the same
/// certificate presented by any other host this client reaches is refused.
@visibleForTesting
bool Function(X509Certificate certificate)? pinnedSocketCallback({
  required String pinnedFingerprint,
  required String host,
  required int port,
  String? pinnedHost,
  int? pinnedPort,
}) {
  final pin = pinnedFingerprint.trim().toLowerCase();
  if (pin.isEmpty) return null;
  return (certificate) => pinnedCertificateIsTrusted(
    certificate,
    host: host,
    port: port,
    pinnedFingerprint: pin,
    pinnedHost: pinnedHost,
    pinnedPort: pinnedPort,
  );
}

/// A socket that counts the bytes of the answer to the request in whose zone
/// they were asked for.
///
/// The count starts when the request writes on the socket, which is also the
/// moment the zone names its observation. A connection reused by the client
/// therefore attributes the next answer to the next request, and a socket
/// read by `HttpClient` before any request was written simply counts nothing.
class _ObservedSocket extends StreamView<Uint8List> implements Socket {
  _ObservedSocket(this._inner) : super(_inner);

  final Socket _inner;
  _Observation? _active;

  void _beginRequest() {
    final zone = Zone.current[_observationKey];
    if (zone is _Observation && !identical(zone, _active)) {
      _active = zone;
      zone.received = 0;
    }
  }

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return super.listen(
      (chunk) {
        _active?.received += chunk.length;
        onData?.call(chunk);
      },
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  void add(List<int> data) {
    _beginRequest();
    _inner.add(data);
  }

  @override
  Future<void> addStream(Stream<List<int>> stream) {
    _beginRequest();
    return _inner.addStream(stream);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    _inner.addError(error, stackTrace);
  }

  @override
  Future<void> close() => _inner.close();

  @override
  Future<void> get done => _inner.done;

  @override
  Future<void> flush() => _inner.flush();

  @override
  void destroy() => _inner.destroy();

  @override
  bool setOption(SocketOption option, bool enabled) =>
      _inner.setOption(option, enabled);

  @override
  Uint8List getRawOption(RawSocketOption option) => _inner.getRawOption(option);

  @override
  void setRawOption(RawSocketOption option) => _inner.setRawOption(option);

  @override
  InternetAddress get address => _inner.address;

  @override
  int get port => _inner.port;

  @override
  InternetAddress get remoteAddress => _inner.remoteAddress;

  @override
  int get remotePort => _inner.remotePort;

  @override
  Encoding get encoding => _inner.encoding;

  @override
  set encoding(Encoding value) => _inner.encoding = value;

  @override
  void write(Object? object) {
    _beginRequest();
    _inner.write(object);
  }

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) {
    _beginRequest();
    _inner.writeAll(objects, separator);
  }

  @override
  void writeCharCode(int charCode) {
    _beginRequest();
    _inner.writeCharCode(charCode);
  }

  @override
  void writeln([Object? object = '']) {
    _beginRequest();
    _inner.writeln(object);
  }
}
