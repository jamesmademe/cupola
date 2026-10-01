import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart' show addTearDown;

import 'package:cupola/features/settings/domain/service_key.dart';

import 'config_profile.dart';
import 'fake_socket.dart';
import 'service_fakes.dart';

/// One request that reached the fake network.
class NetworkRequest {
  NetworkRequest({
    required this.method,
    required this.uri,
    required this.headers,
    required this.body,
    required this.server,
    this.dialRefused = false,
  });

  final String method;
  final Uri uri;

  /// Lower-cased names, values joined with `, `.
  final Map<String, String> headers;

  /// The raw body, decoded as UTF-8.
  final String body;

  /// Who answered, or null for a host nothing on the network owns.
  final ProfileServer? server;

  /// True for an attempt that failed at dial time — a server that did not
  /// answer, or a host nobody owns. Nothing was sent; [headers] and [body]
  /// are empty.
  final bool dialRefused;

  String get path => uri.path;
  Map<String, String> get query => uri.queryParameters;

  bool get isUpgrade => headers['upgrade']?.toLowerCase() == 'websocket';

  /// The body as JSON, or null when it is empty or not JSON.
  dynamic get json {
    if (body.isEmpty) return null;
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }

  /// The body as `application/x-www-form-urlencoded` fields.
  Map<String, String> get form =>
      body.isEmpty ? const {} : Uri.splitQueryString(body);

  @override
  String toString() =>
      '$method ${uri.path}${uri.hasQuery ? '?${uri.query}' : ''}'
      ' → ${server?.id ?? 'no such host'}${dialRefused ? ' (refused)' : ''}';
}

/// One canned reply.
class NetworkReply {
  const NetworkReply(
    this.status, {
    this.body = '',
    this.contentType = 'application/json; charset=utf-8',
    this.headers = const {},
  });

  /// [body] encoded as JSON.
  factory NetworkReply.json(Object? body, {int status = 200}) =>
      NetworkReply(status, body: jsonEncode(body));

  /// A plain-text body, the way qBittorrent answers its login.
  factory NetworkReply.text(
    String body, {
    int status = 200,
    Map<String, List<String>> headers = const {},
  }) => NetworkReply(
    status,
    body: body,
    contentType: 'text/plain; charset=UTF-8',
    headers: headers,
  );

  /// A web page, the way a reverse proxy, a sign-in page or a gateway
  /// answers.
  factory NetworkReply.html(
    String body, {
    int status = 200,
    Map<String, List<String>> headers = const {},
  }) => NetworkReply(
    status,
    body: body,
    contentType: 'text/html; charset=utf-8',
    headers: headers,
  );

  final int status;
  final String body;
  final String contentType;
  final Map<String, List<String>> headers;
}

/// What a gateway in front of [server] answers [request] with, or null when
/// there is none or it lets the request through.
NetworkReply? gatewayReply(NetworkRequest request, ProfileServer server) {
  final target = Uri.encodeQueryComponent(request.uri.toString());
  switch (server.behaviour) {
    case final BehindCloudflareAccess access:
      if (access.admits(request.headers)) return null;
      return switch (access.mode) {
        CloudflareAccessMode.redirect => NetworkReply(
          302,
          contentType: 'text/html',
          headers: {
            'location': [
              'https://${access.teamDomain}/cdn-cgi/access/login/'
                  '${request.uri.host}?kid=4f1c&redirect_url=$target',
            ],
            'server': ['cloudflare'],
            'cf-ray': ['8c1f2e3d4b5a6978-MXP'],
          },
        ),
        CloudflareAccessMode.unauthorized => NetworkReply.html(
          cloudflareAccessPage,
          status: 401,
          headers: {
            'server': ['cloudflare'],
            'cf-ray': ['8c1f2e3d4b5a6978-MXP'],
          },
        ),
      };
    case BehindSignInPage(:final mode):
      return switch (mode) {
        SignInPageMode.redirect => NetworkReply(
          302,
          contentType: 'text/html',
          headers: {
            'location': ['https://auth.example.net/login?rd=$target'],
          },
        ),
        SignInPageMode.sameHostForm => NetworkReply.html(signInPage),
      };
    case BehindPasswordPrompt(:final credentials):
      if (credentials != null) {
        final token = base64Encode(
          utf8.encode('${credentials.username}:${credentials.password}'),
        );
        if (request.headers['authorization'] == 'Basic $token') return null;
      }
      return NetworkReply.html(
        passwordPromptPage,
        status: 401,
        headers: {
          'www-authenticate': ['Basic realm="Restricted"'],
          'server': ['nginx'],
        },
      );
    default:
      return null;
  }
}

/// Cloudflare's page for a request Access turned away.
const cloudflareAccessPage =
    '<!DOCTYPE html><html><head><title>Forbidden · Cloudflare Access</title>'
    '</head><body><h1>Forbidden</h1><p>You don\'t have permission to view '
    'this application.</p></body></html>';

/// A sign-in page served where the API should be.
const signInPage =
    '<!DOCTYPE html><html><head><title>Sign in</title></head><body>'
    '<form method="post" action="/login"><input type="text" name="username">'
    '<input type="password" name="password"><button>Sign in</button></form>'
    '</body></html>';

/// nginx's page for a request its `auth_basic` turned away.
const passwordPromptPage =
    '<html><head><title>401 Authorization Required</title></head><body>'
    '<center><h1>401 Authorization Required</h1></center><hr>'
    '<center>nginx</center></body></html>';

/// The page a reverse proxy serves when nothing is routed to the path asked
/// for: what answers an address missing its base path.
const proxyDefaultPage =
    '<!DOCTYPE html><html><head><title>Welcome to nginx!</title></head>'
    '<body><h1>Welcome to nginx!</h1><p>If you see this page, the nginx web '
    'server is successfully installed and working.</p></body></html>';

/// A test-supplied answer for one route. Returning null falls through to the
/// world's canned answer.
typedef NetworkRoute = NetworkReply? Function(NetworkRequest request);

/// A server the network answers for: one of Cupola's connections, or a
/// Radarr/Sonarr only Seerr's settings know (case b).
class ProfileServer {
  const ProfileServer({
    required this.id,
    required this.service,
    required this.url,
    required this.label,
    required this.behaviour,
    required this.configuredInCupola,
    this.latency = Duration.zero,
  });

  /// The connection id for one of Cupola's; `seerr-known-<service>-<seerrId>`
  /// for a server only Seerr names.
  final String id;
  final ServiceKey service;
  final String url;

  /// The instance label (`4K`, `Anime`), or Seerr's name for a Seerr-known one.
  final String label;

  /// Already resolved against the profile's [NetworkPlace].
  final ConnectionBehaviour behaviour;
  final bool configuredInCupola;

  /// See `ProfileConnection.latency`.
  final Duration latency;

  /// The service whose fake answers here: [service], unless the behaviour
  /// puts another one at this address.
  ServiceKey get answeringService => switch (behaviour) {
    AnswersAsOtherService(:final service) => service,
    _ => service,
  };

  Uri get uri => Uri.parse(url);

  String get origin => originOf(uri);

  /// Radarr 4K and the like: a server whose label says it holds 4K copies.
  bool get is4k => label.toUpperCase().contains('4K');

  static String originOf(Uri uri) => '${uri.host}:${uri.port}';
}

/// The fake network a profile lives on.
///
/// Installed as `HttpOverrides.global`, so **every** `HttpClient` the app
/// builds — the `Dio` inside `ApiClient`, the four clients with their own
/// `Dio`, the pinned adapter of ADR-6, and the `WebSocket.connect` TrueNAS and
/// Dockge dial through — lands here instead of on a socket. That is the point:
/// the real service classes, the real providers and the Dashboard's own
/// throwaway probe clients all run, and a test asserts on what they made of
/// the answer. Nothing leaves the process; a host no server owns fails the way
/// a DNS miss does.
///
/// Replies come from, in order: the connection's behaviour (a refused dial, a
/// refused key, a refused write), then routes a test added with [on], then the
/// world's canned data in `service_fakes.dart`. A request none of them answers
/// is served `404` and kept in [unanswered], which is the first thing to read
/// when a screen under a profile shows an error nobody expected.
class ProfileNetwork {
  ProfileNetwork(this.profile, {DateTime? now}) : now = now ?? DateTime.now() {
    for (final connection in profile.connections) {
      final server = ProfileServer(
        id: connection.id,
        service: connection.service,
        url: connection.instance.url,
        label: connection.instance.label,
        behaviour: profile.behaviourOf(connection.id),
        configuredInCupola: true,
        latency: connection.latency,
      );
      _servers.putIfAbsent(server.origin, () => server);
    }
    // A server Seerr knows answers at its address too, so a flow that sets a
    // connection up from Seerr's settings finds something there. Where Cupola
    // already reaches the same origin, that connection is the server.
    for (final known in profile.seerrKnows) {
      final origin = ProfileServer.originOf(known.uri);
      _servers.putIfAbsent(
        origin,
        () => ProfileServer(
          id: 'seerr-known-${known.service.name}-${known.seerrId}',
          service: known.service,
          url: known.url,
          label: known.name,
          behaviour: ConnectionBehaviour.answers,
          configuredInCupola: false,
        ),
      );
    }
  }

  final ConfigProfile profile;

  /// The moment the world's relative times ("2 h ago") are measured from.
  final DateTime now;

  final Map<String, ProfileServer> _servers = {};
  final Map<String, List<(String, Pattern, NetworkRoute)>> _routes = {};
  final Map<String, Map<String, Object? Function(List<dynamic> params)>>
  _rpcRoutes = {};

  /// Every request that reached the network, in order — including the dials
  /// that failed ([NetworkRequest.dialRefused]).
  final List<NetworkRequest> requests = [];

  /// Every TrueNAS JSON-RPC call, as `connectionId → method`, in order.
  final List<(String, String)> rpcCalls = [];

  /// The requests no behaviour, route or canned answer covered (served 404).
  final List<NetworkRequest> unanswered = [];

  Iterable<ProfileServer> get servers => _servers.values;

  ProfileServer server(String id) => _servers.values.firstWhere(
    (s) => s.id == id,
    orElse: () => throw ArgumentError.value(id, 'id', 'no server'),
  );

  ProfileServer? serverAt(Uri uri) => _servers[ProfileServer.originOf(uri)];

  /// The requests that reached connection [id].
  List<NetworkRequest> requestsTo(String id) =>
      requests.where((r) => r.server?.id == id).toList(growable: false);

  /// Answers [method] [path] on server [serverId] with [route], ahead of the
  /// world's canned data. A [path] `String` matches the whole path; a
  /// `RegExp` matches anywhere in it.
  void on(String serverId, String method, Pattern path, NetworkRoute route) {
    server(serverId);
    (_routes[serverId] ??= []).add((method.toUpperCase(), path, route));
  }

  /// Answers TrueNAS JSON-RPC [method] on [serverId] with [result], ahead of
  /// the canned data. Throw a `TrueNasRpcFault` from [result] to answer with
  /// a JSON-RPC error.
  void onRpc(
    String serverId,
    String method,
    Object? Function(List<dynamic> params) result,
  ) {
    server(serverId);
    (_rpcRoutes[serverId] ??= {})[method] = result;
  }

  /// A test-supplied RPC answer, if any.
  Object? Function(List<dynamic> params)? rpcRoute(
    String serverId,
    String method,
  ) => _rpcRoutes[serverId]?[method];

  /// Makes this the network every `HttpClient` in the test is built on, and
  /// restores the previous one when the test ends.
  ///
  /// Global rather than zoned on purpose: a provider's request starts in
  /// whatever zone built the widget, never inside a `runZoned` a helper could
  /// wrap around `pumpWidget`. `flutter_test` installs its own global (every
  /// request answers 400), and this replaces it for the test's duration only.
  void install() {
    final previous = HttpOverrides.current;
    HttpOverrides.global = _ProfileHttpOverrides(this);
    addTearDown(() => HttpOverrides.global = previous);
  }

  // === Dialling ============================================================

  SocketException? _dialFailure(String method, Uri uri) {
    final server = serverAt(uri);
    final failure = _dialVerdict(server, uri);
    if (failure != null) {
      // Logged here because no request will ever exist for it: a test that
      // asks "did the app try Radarr 4K" must see the attempt that failed.
      final attempt = NetworkRequest(
        method: method,
        uri: uri,
        headers: const {},
        body: '',
        server: server,
        dialRefused: true,
      );
      requests.add(attempt);
    }
    return failure;
  }

  SocketException? _dialVerdict(ProfileServer? server, Uri uri) {
    if (server == null) {
      return SocketException(
        "Failed host lookup: '${uri.host}'",
        osError: const OSError('nodename nor servname provided', 8),
      );
    }
    return switch (server.behaviour) {
      ConnectionBehaviour.didNotAnswer => SocketException(
        'Connection refused',
        osError: const OSError('Connection refused', 61),
        port: uri.port,
      ),
      ConnectionBehaviour.timesOut => SocketException(
        'Connection timed out',
        osError: const OSError('Operation timed out', 60),
        port: uri.port,
      ),
      _ => null,
    };
  }

  // === Answering ===========================================================

  _FakeResponse _respond(_FakeRequest raw) {
    final server = serverAt(raw.uri);
    final request = NetworkRequest(
      method: raw.method,
      uri: raw.uri,
      headers: raw.headers.flattened,
      body: utf8.decode(raw.body.takeBytes(), allowMalformed: true),
      server: server,
    );
    requests.add(request);
    if (server == null) {
      // Unreachable: dialling already failed. Kept for the type system.
      return _FakeResponse.fromReply(const NetworkReply(502));
    }

    final fake = serviceFakeFor(server.answeringService);
    final context = ServerContext(network: this, server: server);

    if (request.isUpgrade) {
      final peer = fake.upgrade(request, context);
      final key = raw.headers.value('sec-websocket-key');
      if (peer == null || key == null) {
        return _FakeResponse.fromReply(const NetworkReply(404));
      }
      return _FakeResponse.upgrade(webSocketAccept(key), WebSocketLink(peer));
    }

    // In front of the service, so before anything the service would say.
    final gateway = gatewayReply(request, server);
    if (gateway != null) return _FakeResponse.fromReply(gateway);

    final gated = fake.gate(request, context);
    if (gated != null) return _FakeResponse.fromReply(gated);

    final routes =
        _routes[server.id] ?? const <(String, Pattern, NetworkRoute)>[];
    for (final (method, path, route) in routes) {
      if (method != request.method) continue;
      final matches = path is String
          ? path == request.path
          : path.allMatches(request.path).isNotEmpty;
      if (!matches) continue;
      final reply = route(request);
      if (reply != null) return _FakeResponse.fromReply(reply);
    }

    final answer = fake.answer(request, context);
    if (answer != null) return _FakeResponse.fromReply(answer);

    unanswered.add(request);
    return _FakeResponse.fromReply(
      NetworkReply.json({'message': 'NotFound'}, status: 404),
    );
  }
}

// === The dart:io surface ===================================================
//
// Only what Dio's `IOHttpClientAdapter`, `buildPinnedHttpClient` and
// `WebSocket.connect` touch is implemented. Setters nothing reads are accepted
// and dropped; any other member throws through `noSuchMethod`, so a new
// dependency on this surface fails loudly instead of returning null.

class _ProfileHttpOverrides extends HttpOverrides {
  _ProfileHttpOverrides(this.network);

  final ProfileNetwork network;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _FakeHttpClient(network);
}

class _FakeHttpClient implements HttpClient {
  _FakeHttpClient(this._network);

  final ProfileNetwork _network;

  @override
  Duration? connectionTimeout;

  @override
  Duration idleTimeout = const Duration(seconds: 15);

  @override
  bool autoUncompress = true;

  @override
  String? userAgent;

  @override
  int? maxConnectionsPerHost;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    final failure = _network._dialFailure(method.toUpperCase(), url);
    if (failure != null) throw failure;
    return _FakeRequest(_network, method.toUpperCase(), url);
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);

  @override
  Future<HttpClientRequest> postUrl(Uri url) => openUrl('POST', url);

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) {
    // `badCertificateCallback`, `findProxy` and friends: accepted, never
    // consulted — no certificate or proxy crosses this network.
    if (invocation.isSetter) return null;
    return super.noSuchMethod(invocation);
  }
}

class _FakeHeaders implements HttpHeaders {
  final Map<String, List<String>> _values = {};

  Map<String, String> get flattened => {
    for (final entry in _values.entries) entry.key: entry.value.join(', '),
  };

  @override
  List<String>? operator [](String name) => _values[name.toLowerCase()];

  @override
  String? value(String name) {
    final values = this[name];
    if (values == null || values.isEmpty) return null;
    if (values.length > 1) {
      throw HttpException('More than one value for header $name');
    }
    return values.single;
  }

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {
    final values = _values.putIfAbsent(name.toLowerCase(), () => []);
    if (value is Iterable) {
      values.addAll(value.map((v) => '$v'));
    } else {
      values.add('$value');
    }
  }

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _values.remove(name.toLowerCase());
    add(name, value);
  }

  @override
  void remove(String name, Object value) =>
      _values[name.toLowerCase()]?.remove('$value');

  @override
  void removeAll(String name) => _values.remove(name.toLowerCase());

  @override
  void forEach(void Function(String name, List<String> values) action) =>
      _values.forEach(action);

  @override
  void noFolding(String name) {}

  @override
  void clear() => _values.clear();

  @override
  int contentLength = -1;

  @override
  ContentType? contentType;

  @override
  bool chunkedTransferEncoding = false;

  @override
  bool persistentConnection = true;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isSetter) return null;
    return super.noSuchMethod(invocation);
  }
}

class _FakeRequest implements HttpClientRequest {
  _FakeRequest(this._network, this.method, this.uri);

  final ProfileNetwork _network;

  @override
  final String method;

  @override
  final Uri uri;

  @override
  final _FakeHeaders headers = _FakeHeaders();

  final BytesBuilder body = BytesBuilder();
  final Completer<HttpClientResponse> _done = Completer<HttpClientResponse>();

  @override
  bool followRedirects = true;

  @override
  int maxRedirects = 5;

  @override
  bool persistentConnection = true;

  @override
  bool bufferOutput = true;

  @override
  int contentLength = -1;

  @override
  Encoding encoding = utf8;

  @override
  List<Cookie> get cookies => [];

  @override
  HttpConnectionInfo? get connectionInfo => null;

  @override
  void add(List<int> data) => body.add(data);

  @override
  void write(Object? object) => body.add(encoding.encode('$object'));

  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.forEach(body.add);

  @override
  Future<void> flush() async {}

  @override
  Future<HttpClientResponse> close() async {
    if (_done.isCompleted) return _done.future;
    final latency = _network.serverAt(uri)?.latency ?? Duration.zero;
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    if (!_done.isCompleted) _done.complete(_network._respond(this));
    return _done.future;
  }

  @override
  Future<HttpClientResponse> get done => _done.future;

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {}

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isSetter) return null;
    return super.noSuchMethod(invocation);
  }
}

class _FakeResponse extends Stream<List<int>> implements HttpClientResponse {
  _FakeResponse._(this.statusCode, this._bytes, this.headers, [this._socket]);

  factory _FakeResponse.fromReply(NetworkReply reply) {
    final headers = _FakeHeaders()..set('content-type', reply.contentType);
    reply.headers.forEach(headers.set);
    return _FakeResponse._(reply.status, utf8.encode(reply.body), headers);
  }

  factory _FakeResponse.upgrade(String accept, WebSocketLink socket) {
    final headers = _FakeHeaders()
      ..set('connection', 'Upgrade')
      ..set('upgrade', 'websocket')
      ..set('sec-websocket-accept', accept);
    return _FakeResponse._(101, const [], headers, socket);
  }

  final List<int> _bytes;
  final WebSocketLink? _socket;

  @override
  final int statusCode;

  @override
  final _FakeHeaders headers;

  @override
  String get reasonPhrase => switch (statusCode) {
    101 => 'Switching Protocols',
    200 => 'OK',
    401 => 'Unauthorized',
    403 => 'Forbidden',
    404 => 'Not Found',
    _ => '',
  };

  @override
  int get contentLength => _bytes.length;

  @override
  bool get isRedirect => false;

  @override
  List<RedirectInfo> get redirects => const [];

  @override
  bool get persistentConnection => true;

  @override
  X509Certificate? get certificate => null;

  @override
  HttpConnectionInfo? get connectionInfo => null;

  @override
  List<Cookie> get cookies => const [];

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  Future<Socket> detachSocket() async =>
      _socket ?? (throw const SocketException('Nothing to detach'));

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      Stream<List<int>>.fromIterable([
        if (_bytes.isNotEmpty) Uint8List.fromList(_bytes),
      ]).listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
