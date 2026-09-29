import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:cupola/core/capability/permission_refusal.dart';
import 'package:cupola/core/network/cert_trust.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/core/utils/url_utils.dart';

/// Error surfaced by the TrueNAS WebSocket client. Carries the [reason] so a
/// caller verifying the connection can tell an unreachable host from a
/// rejected API key.
class TrueNasException
    implements Exception, HasFailureReason, HasPermissionRefusal {
  final String message;
  @override
  final ServiceFailureReason reason;

  /// The middleware refused this call for this credential: the session is
  /// authenticated and its user lacks the role the method needs. Never set for
  /// an expired session, which shares the errno and means something else.
  final bool forbidden;

  const TrueNasException(
    this.message, {
    this.reason = ServiceFailureReason.unknown,
    this.forbidden = false,
  });

  @override
  bool get isPermissionRefusal => forbidden;

  @override
  String toString() => 'TrueNasException: $message';
}

/// Thrown instead of dialling an address that would carry the API key in
/// cleartext: an `http://` (or `ws://`) TrueNAS URL.
///
/// TrueNAS 25.04 and later revoke, server side and on sight, an API key that
/// logs in over an insecure transport. So `ws://` does not merely expose the
/// key on the wire — the first attempt destroys it, and the user finds out
/// only when the next app reports it invalid. [TrueNasWsClient] therefore
/// never opens a cleartext socket at all: this is raised while the endpoint is
/// being resolved, before any connection, so no byte leaves the device.
///
/// Reported as [ServiceFailureReason.notFound] because the closed vocabulary
/// has no "insecure transport", and of the reasons it does have this is the
/// one whose consequences are right: amber rather than red (nothing failed to
/// answer), and neither the certificate probe nor the local-network probe
/// runs after it (`certProbeWorthwhile`, `localNetworkCouldExplain`) — both
/// would dial the very address this refused to dial. What the user reads is
/// [failureDetail], which `ServiceDiagnosis.messageFor` prints in place of the
/// generic copy, and which `TrueNasAsyncBody` gives a well of its own.
class TrueNasInsecureTransportException extends TrueNasException
    implements HasFailureDetail {
  const TrueNasInsecureTransportException()
    : super('$_headline $explanation', reason: ServiceFailureReason.notFound);

  // Never let either contain "not configured": `AsyncValueWidget` and
  // `TrueNasAsyncBody` string-match that phrase to mean "no address saved".
  static const _headline = 'TrueNAS needs an https:// address.';

  /// Why, and what to do — the part a surface that already states the
  /// headline in its own title prints beneath it.
  static const explanation =
      'TrueNAS 25.04 and later revoke an API key that arrives over http://, '
      'so Cupola did not send it. Change the address to https://; a '
      'self-signed certificate works, and Cupola offers to trust it when you '
      'test the connection.';

  @override
  String get failureDetail => message;
}

/// The pinned [HttpClient] as `WebSocket.connect` sees it, refusing to follow
/// a redirect on the upgrade request.
///
/// `dart:io` follows a redirect on the upgrade GET like on any other, carrying
/// the WebSocket headers along, and whatever answers `101` at the end of the
/// chain gets the socket. The API key is not in that request — it is the first
/// frame *after* the upgrade — so the redirect alone leaks nothing; the frame
/// does. A `Location: http://…` would put `auth.login_with_api_key` on a
/// cleartext socket after the scheme check had passed, and a `Location` on
/// another host would hand that host the key outright. The Dio clients refuse
/// the same thing through `SameOriginRedirectInterceptor`; this is the guard
/// for the one transport Dio does not carry.
///
/// Only [openUrl] is implemented because it is the only member
/// `WebSocket.connect` calls on its `customClient`. Every loopback test in
/// `truenas_ws_client_test.dart` dials through this wrapper, so an SDK that
/// starts calling another member fails there, loudly, and not in the field.
class _NoRedirectUpgradeClient implements HttpClient {
  _NoRedirectUpgradeClient(this._inner);

  final HttpClient _inner;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      (await _inner.openUrl(method, url))..followRedirects = false;

  @override
  void close({bool force = false}) => _inner.close(force: force);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The exception a JSON-RPC `error` object stands for, from [method].
///
/// The envelope is `{"code": -32001, "message": "Method call error", "data":
/// {"error": 13, "errname": "EACCES", "reason": "[EACCES] Not authorized"}}`
/// (middleware `main.py` / `ws_handler/rpc.py`, TS-25.04.0). Keeping only
/// `message` made every failure read "Method call error"; the `data.reason` is
/// the sentence, and `errname` says what kind of failure it was:
///
///  * `EACCES` (errno 13) is a role refusal — **unless** the reason says the
///    session expired, which reuses the errno and is a login problem;
///  * `EPERM` (errno 1) from a `service.*` method is the second, in-body check
///    those methods make for the service being changed, and is a refusal too.
@visibleForTesting
TrueNasException trueNasRpcError(Object? error, {required String method}) {
  if (error is! Map) return TrueNasException(error.toString());
  final data = error['data'];
  final message = error['message']?.toString() ?? 'RPC error';
  if (data is! Map) return TrueNasException(message);

  final reason = data['reason']?.toString();
  final errname = data['errname']?.toString().toUpperCase();
  final errno = data['error'];
  final text = (reason == null || reason.isEmpty) ? message : reason;

  final eacces = errname == 'EACCES' || (errname == null && errno == 13);
  final eperm = errname == 'EPERM' || (errname == null && errno == 1);
  if (eacces && text.toLowerCase().contains('session is expired')) {
    return TrueNasException(text, reason: ServiceFailureReason.unauthorized);
  }
  if (eacces || (eperm && method.startsWith('service.'))) {
    return TrueNasException(text, forbidden: true);
  }
  return TrueNasException(text);
}

/// An RPC error frame, held until [TrueNasWsClient._rawCall] knows which
/// method it answered.
class _RpcError {
  const _RpcError(this.error);
  final Object? error;
}

/// A minimal JSON-RPC 2.0 over WebSocket client for TrueNAS SCALE 25.x.
///
/// TrueNAS deprecated the REST API in 25.04 (removed in 26); the supported
/// transport is JSON-RPC 2.0 over WebSocket at `wss://<host>/api/current`,
/// authenticated with `auth.login_with_api_key`. TLS certificates are verified
/// against the platform trust store; a self-signed certificate is trusted only
/// after the user explicitly pins it via [certFingerprint]. There is no `ws://`
/// fallback: see [TrueNasInsecureTransportException].
/// Progress callback for long-running [TrueNasWsClient.callJob] operations.
typedef TrueNasJobProgress =
    void Function(double? percent, String? description);

class TrueNasWsClient {
  final String baseUrl;
  final String apiKey;

  /// SHA-256 fingerprint of a self-signed certificate the user chose to trust.
  /// When null/empty, TLS certificates are verified against the platform trust
  /// store like any HTTPS client.
  final String? certFingerprint;

  /// How long a single RPC may go unanswered before it is treated as a
  /// transport failure. Injectable so tests need not wait it out.
  final Duration callTimeout;

  WebSocket? _socket;
  HttpClient? _httpClient;
  bool _authed = false;
  int _nextId = 1;
  Completer<void>? _connecting;
  final Map<int, Completer<dynamic>> _pending = {};

  /// When the socket last delivered a frame — the liveness signal the call
  /// timeout uses to decide whether the connection is worth keeping.
  DateTime? _lastMessageAt;

  TrueNasWsClient({
    required this.baseUrl,
    required this.apiKey,
    this.certFingerprint,
    this.callTimeout = const Duration(seconds: 15),
  });

  /// Derives the `wss://host:port/api/current` endpoint from the base URL.
  ///
  /// Only ever `wss`. An `http://` or `ws://` address throws
  /// [TrueNasInsecureTransportException] rather than resolving to `ws://`: it
  /// used to, and the login that followed sent the API key in cleartext to a
  /// server that revokes a key used that way. A bare host still means https.
  Uri resolveEndpoint() {
    var raw = baseUrl.trim();
    if (raw.isEmpty) {
      throw const TrueNasException('TrueNAS URL is empty');
    }
    if (!raw.contains('://')) raw = 'https://$raw';
    if (!UrlUtils.isSecureScheme(raw)) {
      throw const TrueNasInsecureTransportException();
    }
    final uri = Uri.parse(raw);
    return Uri(
      scheme: 'wss',
      host: uri.host,
      port: uri.hasPort ? uri.port : 443,
      path: '/api/current',
    );
  }

  /// Opens the upgraded WebSocket for [endpoint] over the pinned [client].
  ///
  /// Overridable for the loopback tests alone. They cannot speak TLS — a
  /// certificate fixture would put a private key in a public repository — so
  /// their override dials the same wrapper over `ws://` on 127.0.0.1, while
  /// everything before this call, the cleartext refusal above all, runs exactly
  /// as it does in production. Never override it anywhere else.
  @visibleForTesting
  Future<WebSocket> dial(Uri endpoint, HttpClient client) => WebSocket.connect(
    endpoint.toString(),
    customClient: _NoRedirectUpgradeClient(client),
  );

  Future<void> _ensureConnected() {
    if (_socket != null && _authed) return Future.value();
    final existing = _connecting;
    if (existing != null) return existing.future;

    final completer = Completer<void>();
    _connecting = completer;
    _connect()
        .then((_) => completer.complete())
        .catchError((Object e) => completer.completeError(e))
        .whenComplete(() => _connecting = null);
    return completer.future;
  }

  Future<void> _connect() async {
    // First, and outside the `try`: an address that would carry the key in
    // cleartext throws here, before a client is built or a socket opened.
    final endpoint = resolveEndpoint();
    // Verify TLS against the platform trust store, additionally trusting the
    // user-pinned self-signed certificate (if any). See [buildPinnedHttpClient].
    final httpClient = buildPinnedHttpClient(
      pinnedFingerprint: certFingerprint,
      pinnedHost: endpoint.host,
      pinnedPort: endpoint.port,
    );
    _httpClient = httpClient;
    try {
      final socket = await dial(
        endpoint,
        httpClient,
      ).timeout(const Duration(seconds: 10));
      _socket = socket;
      socket.listen(
        _onMessage,
        // Reset the socket state so the next call forces a fresh reconnection
        // instead of writing to a dead socket. The socket is passed along so a
        // late event from a connection we already replaced cannot tear down its
        // successor.
        onError: (Object e) => _dropConnection(socket, TrueNasException('$e')),
        onDone: () => _dropConnection(
          socket,
          const TrueNasException('Connection closed'),
        ),
        cancelOnError: false,
      );

      final ok = await _rawCall('auth.login_with_api_key', [apiKey]);
      if (ok != true) {
        throw const TrueNasException(
          'Authentication failed (check API key)',
          reason: ServiceFailureReason.unauthorized,
        );
      }
      _authed = true;
    } catch (e) {
      _authed = false;
      final socket = _socket;
      _socket = null;
      // Never `await` this: a socket that failed to authenticate may also be
      // half-open, and a close handshake that never lands would leave
      // `_connecting` pending forever — wedging every later call.
      if (socket != null) _closeQuietly(socket);
      httpClient.close(force: true);
      _httpClient = null;
      if (e is TrueNasException) rethrow;
      // A refused upgrade carries the status the server answered with — a
      // redirect this client will not follow, a 404 from a SCALE build without
      // `/api/current`, a 502 from the proxy in front. The server answered, so
      // "unknown" (drawn as unreachable) was the wrong verdict for all three.
      final status = e is WebSocketException ? e.httpStatusCode : null;
      throw TrueNasException(
        'Could not connect: $e',
        reason: status != null
            ? reasonForStatusCode(status)
            : classifyConnectionFailure(e),
      );
    }
  }

  /// Calls a JSON-RPC method, connecting/authenticating on first use.
  Future<dynamic> call(String method, [List<dynamic> params = const []]) async {
    await _ensureConnected();
    return _rawCall(method, params);
  }

  /// Invokes a *job* method (one that returns an integer job id) and waits for
  /// it to finish, polling `core.get_jobs` until the job reaches a terminal
  /// state. Returns the job result, or throws [TrueNasException] on failure.
  ///
  /// [onProgress] receives progress updates (percent 0..100 and an optional
  /// description) while the job runs.
  Future<dynamic> callJob(
    String method, [
    List<dynamic> params = const [],
    TrueNasJobProgress? onProgress,
    Duration timeout = const Duration(minutes: 5),
    Duration pollInterval = const Duration(seconds: 1),
  ]) async {
    final raw = await call(method, params);
    final jobId = raw is int ? raw : intOrNull(raw);
    if (jobId == null) {
      // Method did not behave like a job; treat its result as the outcome.
      return raw;
    }

    final deadline = DateTime.now().add(timeout);
    while (true) {
      final jobs = await call('core.get_jobs', [
        [
          ['id', '=', jobId],
        ],
      ]);
      final job = (jobs is List && jobs.isNotEmpty && jobs.first is Map)
          ? jobs.first as Map
          : null;
      if (job != null) {
        final progress = job['progress'];
        if (onProgress != null && progress is Map) {
          onProgress(
            doubleOrNull(progress['percent']),
            progress['description']?.toString(),
          );
        }
        final state = job['state']?.toString().toUpperCase();
        if (state == 'SUCCESS') {
          return job['result'];
        }
        if (state == 'FAILED' || state == 'ABORTED') {
          final error = job['error']?.toString();
          throw TrueNasException(
            error?.isNotEmpty == true ? error! : 'Job $method $state',
          );
        }
      }
      if (DateTime.now().isAfter(deadline)) {
        throw TrueNasException(
          'Timed out waiting for job $method',
          reason: ServiceFailureReason.timeout,
        );
      }
      await Future<void>.delayed(pollInterval);
    }
  }

  Future<dynamic> _rawCall(String method, List<dynamic> params) {
    final socket = _socket;
    if (socket == null) {
      return Future.error(const TrueNasException('Not connected'));
    }
    final id = _nextId++;
    final completer = Completer<dynamic>();
    _pending[id] = completer;
    socket.add(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': params,
      }),
    );
    return completer.future
        .catchError(
          (Object e) =>
              throw trueNasRpcError((e as _RpcError).error, method: method),
          test: (e) => e is _RpcError,
        )
        .timeout(
          callTimeout,
          onTimeout: () {
            _pending.remove(id);
            // A call that never came back means one of two things. If the socket
            // answered *something* inside the timeout window it is alive and merely
            // slow, so only this call fails. If it has gone completely silent it is
            // almost certainly half-open — a suspend or a Wi-Fi→cellular handoff
            // drops the TCP connection without ever delivering `onDone`/`onError` —
            // and leaving `_socket`/`_authed` set would wedge `_ensureConnected` on
            // a dead socket for the rest of the app session, with every poll tick
            // stacking another doomed timeout. Drop it so the next call reconnects.
            final lastMessage = _lastMessageAt;
            final alive =
                lastMessage != null &&
                DateTime.now().difference(lastMessage) < callTimeout;
            if (!alive) {
              _dropConnection(
                socket,
                const TrueNasException(
                  'Connection lost',
                  reason: ServiceFailureReason.timeout,
                ),
              );
            }
            throw TrueNasException(
              'Timed out calling $method',
              reason: ServiceFailureReason.timeout,
            );
          },
        );
  }

  /// Tears the transport down so the next call reconnects, failing everything
  /// still in flight with [error].
  ///
  /// [socket] identifies the connection the failure belongs to: a late
  /// `onDone`/`onError` — or a timeout — from a socket that has already been
  /// replaced must not null out its successor or fail the successor's calls.
  void _dropConnection(WebSocket socket, Object error) {
    if (!identical(_socket, socket)) {
      _closeQuietly(socket);
      return;
    }
    _authed = false;
    _socket = null;
    _httpClient?.close(force: true);
    _httpClient = null;
    _failAll(error);
    _closeQuietly(socket);
  }

  /// Closes a socket without waiting on it: a half-open connection may never
  /// complete its close handshake, and no caller can be blocked on that.
  void _closeQuietly(WebSocket socket) {
    unawaited(socket.close().then<void>((_) {}, onError: (Object _) {}));
  }

  void _onMessage(dynamic data) {
    // Any frame at all proves the socket is still alive; the timeout path uses
    // this to tell a slow server from a dead connection.
    _lastMessageAt = DateTime.now();
    if (data is! String) return;
    final Object? decoded;
    try {
      decoded = jsonDecode(data);
    } catch (_) {
      return;
    }
    if (decoded is! Map || decoded['id'] == null) return;
    final id = decoded['id'];
    if (id is! int) return;
    final completer = _pending.remove(id);
    if (completer == null || completer.isCompleted) return;

    final error = decoded['error'];
    if (error != null) {
      completer.completeError(_RpcError(error));
    } else {
      completer.complete(decoded['result']);
    }
  }

  void _failAll(Object error) {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.completeError(error);
    }
    _pending.clear();
  }

  Future<void> close() async {
    _failAll(const TrueNasException('Client closed'));
    _authed = false;
    final socket = _socket;
    _socket = null;
    _httpClient?.close(force: true);
    _httpClient = null;
    await socket?.close();
  }
}
