import 'dart:async';
import 'dart:io' as io;

import 'package:socket_io_client/socket_io_client.dart' as socket_io;
import 'package:web_socket/io_web_socket.dart';
import 'package:web_socket/web_socket.dart' as ws;

import 'package:cupola/core/network/cert_trust.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/features/dockge/domain/models/dockge_agent.dart';
import 'package:cupola/features/dockge/domain/models/dockge_stack.dart';
import 'package:cupola/features/dockge/domain/models/dockge_stack_detail.dart';

/// Error surfaced by the Dockge client. Carries the [reason] so a caller
/// verifying the connection can tell an unreachable host from a rejected
/// login.
class DockgeException implements Exception, HasFailureReason {
  final String message;
  @override
  final ServiceFailureReason reason;
  const DockgeException(
    this.message, {
    this.reason = ServiceFailureReason.unknown,
  });
  @override
  String toString() => 'DockgeException: $message';
}

/// A chunk of terminal output pushed by Dockge (`terminalWrite` event).
class DockgeTerminalOutput {
  final String terminalName;
  final String data;
  const DockgeTerminalOutput(this.terminalName, this.data);
}

/// Socket.IO client for a single Dockge instance.
///
/// Dockge exposes no REST API — everything goes over Socket.IO (v4). Commands
/// are wrapped in an `agent` envelope (`emit("agent", endpoint, event, ...)`)
/// so the same protocol works for both the local instance and remote agents;
/// this client targets a single direct instance, so [_endpoint] is always the
/// empty string. Authentication is username/password → JWT, matching Dockge's
/// login flow; when Dockge runs with auth disabled (behind a reverse proxy) the
/// server emits `autoLogin` and no credentials are required.
///
/// TLS certificates are verified against the platform trust store; a self-signed
/// certificate is trusted only after the user explicitly pins it via
/// [certFingerprint], mirroring the TrueNAS client.
class DockgeClient {
  final String baseUrl;
  final String? username;
  final String? password;

  /// SHA-256 fingerprint of a self-signed certificate the user chose to trust.
  final String? certFingerprint;

  /// The agent every command is addressed to. Instance state, not a constant:
  /// this is what the app-bar lens moves.
  String _endpoint = '';

  /// How long to wait for `autoLogin` after connecting without credentials
  /// before concluding the instance requires a login.
  static const Duration _autoLoginGrace = Duration(milliseconds: 1500);

  socket_io.Socket? _socket;
  bool _authed = false;
  Completer<void>? _connecting;

  /// Server info from the `info` event (contains the Dockge version).
  Map<String, dynamic>? _serverInfo;

  List<DockgeStack> _latestStacks = const [];
  Map<String, DockgeAgent> _latestAgents = const {};

  final StreamController<List<DockgeStack>> _stackListController =
      StreamController<List<DockgeStack>>.broadcast();
  final StreamController<DockgeTerminalOutput> _terminalController =
      StreamController<DockgeTerminalOutput>.broadcast();
  final StreamController<List<DockgeAgent>> _agentListController =
      StreamController<List<DockgeAgent>>.broadcast();

  DockgeClient({
    required this.baseUrl,
    this.username,
    this.password,
    this.certFingerprint,
  });

  /// The most recent parsed stack list (empty until the first push).
  List<DockgeStack> get latestStacks => _latestStacks;

  /// The agent commands are currently addressed to.
  String get endpoint => _endpoint;

  /// Points this client at [endpoint] and returns whether that changed
  /// anything. The caller re-requests the stack list; nothing is cached per
  /// agent, because a stack belongs to exactly one of them and keeping the
  /// previous agent's rows on screen would show stacks the next command cannot
  /// reach.
  bool selectAgent(String endpoint) {
    if (_endpoint == endpoint) return false;
    _endpoint = endpoint;
    _latestStacks = const [];
    return true;
  }

  /// Every instance reachable from this login, the hub first. Always at least
  /// [DockgeAgent.local]: a Dockge without the multi-agent feature never sends
  /// an `agentList`, and "no agents at all" would be a worse lie than "one".
  List<DockgeAgent> get latestAgents => _agentsInOrder(_latestAgents);

  /// Broadcasts the agent list whenever Dockge pushes one.
  Stream<List<DockgeAgent>> get agentListStream => _agentListController.stream;

  /// Broadcasts the full stack list whenever Dockge pushes an update.
  Stream<List<DockgeStack>> get stackListStream => _stackListController.stream;

  /// Broadcasts terminal output (deploy/up/down logs) as it arrives.
  Stream<DockgeTerminalOutput> get terminalOutput => _terminalController.stream;

  String? get version => stringOrNull(_serverInfo?['version']);

  bool get _hasCredentials =>
      (username?.isNotEmpty ?? false) && (password?.isNotEmpty ?? false);

  /// The combined-terminal name Dockge uses for a stack's aggregated logs.
  String combinedTerminalName(String stackName) =>
      'combined-$_endpoint-$stackName';

  /// Derives the Socket.IO base origin (`http(s)://host:port`) from [baseUrl].
  Uri resolveEndpoint() {
    var raw = baseUrl.trim();
    if (raw.isEmpty) {
      throw const DockgeException('Dockge URL is empty');
    }
    // Default a scheme-less URL to HTTPS/WSS so login credentials are not sent
    // over an unencrypted socket. An explicit http:// is honoured.
    if (!raw.contains('://')) raw = 'https://$raw';
    final uri = Uri.parse(raw);
    // Secure unless the user explicitly asked for cleartext: an unrecognised
    // scheme must never downgrade the socket carrying the login credentials.
    final secure = UrlUtils.isSecureScheme(raw);
    return Uri(
      scheme: secure ? 'https' : 'http',
      host: uri.host,
      port: uri.hasPort ? uri.port : (secure ? 443 : 80),
    );
  }

  /// WebSocket connector that verifies TLS against the platform trust store,
  /// additionally trusting the user-pinned self-signed certificate (if any).
  Future<ws.WebSocket> _pinnedConnector(
    Uri uri, {
    Iterable<String>? protocols,
    Map<String, String>? headers,
  }) async {
    final httpClient = buildPinnedHttpClient(
      pinnedFingerprint: certFingerprint,
      pinnedHost: uri.host,
      pinnedPort: uri.port,
    );
    final socket = await io.WebSocket.connect(
      uri.toString(),
      protocols: protocols,
      headers: headers,
      customClient: httpClient,
    );
    return IOWebSocket.fromWebSocket(socket);
  }

  Future<void> ensureConnected() {
    if (_socket != null && _authed) return Future.value();
    final existing = _connecting;
    if (existing != null) return existing.future;

    final completer = Completer<void>();
    _connecting = completer;
    _connect()
        .then((_) {
          if (!completer.isCompleted) completer.complete();
        })
        .catchError((Object e) {
          if (!completer.isCompleted) completer.completeError(e);
        })
        .whenComplete(() {
          if (identical(_connecting, completer)) _connecting = null;
        });
    return completer.future;
  }

  Future<void> _connect() async {
    final authCompleter = Completer<void>();

    final options = socket_io.OptionBuilder()
        .setTransports(['websocket'])
        .disableAutoConnect()
        .enableForceNew()
        .setReconnectionAttempts(3)
        .setWebSocketConnector(_pinnedConnector)
        .build();

    // Dispose any previous socket before replacing it: a reconnection through
    // `ensureConnected` would otherwise leak the old socket (double streams +
    // dangling reconnection timers).
    _socket?.dispose();

    final socket = socket_io.io(resolveEndpoint().toString(), options);
    _socket = socket;

    socket.onConnect((_) {
      if (!_hasCredentials) {
        // Auth-disabled instances answer `autoLogin` almost immediately. If that
        // has not arrived shortly after connect, the server wants credentials we
        // do not have — report that instead of letting the connection time out,
        // which surfaced as "check the address" and sent the user looking for a
        // network fault rather than filling in the login fields.
        Timer(_autoLoginGrace, () {
          if (_authed || authCompleter.isCompleted) return;
          authCompleter.completeError(
            const DockgeException(
              'Dockge requires a username and password',
              reason: ServiceFailureReason.unauthorized,
            ),
          );
        });
      }
      if (_hasCredentials) {
        socket.emitWithAck(
          'login',
          {'username': username, 'password': password},
          ack: (dynamic res) {
            final map = mapOrNull(res);
            if (map?['ok'] == true) {
              _authed = true;
              if (!authCompleter.isCompleted) authCompleter.complete();
            } else if (map?['tokenRequired'] == true) {
              if (!authCompleter.isCompleted) {
                authCompleter.completeError(
                  const DockgeException(
                    'Two-factor authentication is not supported',
                    reason: ServiceFailureReason.unauthorized,
                  ),
                );
              }
            } else if (!authCompleter.isCompleted) {
              authCompleter.completeError(
                DockgeException(
                  _msg(map) ?? 'Login failed',
                  reason: ServiceFailureReason.unauthorized,
                ),
              );
            }
          },
        );
      }
      // With auth disabled the server emits `autoLogin` instead, handled below.
    });

    socket.on('autoLogin', (_) {
      _authed = true;
      if (!authCompleter.isCompleted) authCompleter.complete();
    });

    socket.on('info', (dynamic data) {
      final map = mapOrNull(data);
      if (map != null) _serverInfo = map;
    });

    socket.on('agent', _onAgentEvent);
    socket.on('stackStatusList', _onStackStatusList);
    // Dockge pushes these at the top level rather than inside the `agent`
    // envelope — the envelope is for commands *to* an agent, and this is the
    // hub describing itself. Both shapes are tolerated anyway (see
    // `_onAgentEvent`), because an instance without the multi-agent feature
    // sends neither and must still work.
    socket.on('agentList', _handleAgentList);
    socket.on('agentStatus', _handleAgentStatus);

    socket.onConnectError((dynamic e) {
      if (!authCompleter.isCompleted) {
        authCompleter.completeError(
          DockgeException(
            'Connection error: $e',
            // Socket.IO hands us an untyped connect error.
            reason: classifyConnectionFailure(
              e,
              fallback: ServiceFailureReason.unreachable,
            ),
          ),
        );
      }
    });

    socket.onDisconnect((_) {
      _authed = false;
    });

    // Only surface a connection error once reconnection is definitively
    // exhausted — intermediate retries must not error out the stream, or the
    // UI would flap between error and data on every transient drop.
    socket.onReconnectFailed((_) {
      _authed = false;
      if (!_stackListController.isClosed) {
        _stackListController.addError(
          const DockgeException(
            'Lost connection to Dockge (reconnection failed)',
          ),
        );
      }
    });

    socket.connect();

    try {
      await authCompleter.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw const DockgeException(
          'Timed out connecting to Dockge (check URL and credentials)',
          reason: ServiceFailureReason.timeout,
        ),
      );
    } catch (e) {
      _authed = false;
      socket.dispose();
      _socket = null;
      if (e is DockgeException) rethrow;
      throw DockgeException(
        'Could not connect: $e',
        reason: classifyConnectionFailure(
          e,
          fallback: ServiceFailureReason.unreachable,
        ),
      );
    }
  }

  void _onAgentEvent(dynamic data) {
    if (data is! List || data.isEmpty) return;
    final eventName = data.first?.toString();
    final args = data.length > 1 ? data.sublist(1) : const [];
    switch (eventName) {
      case 'stackList':
        final payload = args.isNotEmpty ? mapOrNull(args.first) : null;
        if (payload != null) _handleStackList(payload);
        break;
      case 'agentList':
        if (args.isNotEmpty) _handleAgentList(args.first);
        break;
      case 'agentStatus':
        if (args.isNotEmpty) _handleAgentStatus(args.first);
        break;
      case 'terminalWrite':
        if (args.length >= 2) {
          _terminalController.add(
            DockgeTerminalOutput(
              args[0]?.toString() ?? '',
              args[1]?.toString() ?? '',
            ),
          );
        }
        break;
    }
  }

  void _handleStackList(Map<String, dynamic> payload) {
    final raw = mapOrNull(payload['stackList']);
    if (raw == null) return;
    final stacks = <DockgeStack>[];
    raw.forEach((name, value) {
      final map = mapOrNull(value);
      if (map != null) stacks.add(DockgeStack.fromJson(map));
    });
    stacks.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _latestStacks = stacks;
    if (!_stackListController.isClosed) _stackListController.add(stacks);
  }

  /// Parses Dockge's `agentList`, which arrives as a map keyed by endpoint (and
  /// has been seen as a bare list), each value describing one agent.
  ///
  /// Deliberately forgiving: an unexpected shape leaves the list at "just the
  /// hub" instead of throwing on a socket callback, where nothing could catch
  /// it. The lens then offers one agent, which is the truth for every
  /// single-instance Dockge anyway.
  void _handleAgentList(dynamic data) {
    final payload = mapOrNull(data);
    final raw = payload?['agentList'] ?? payload ?? data;
    final agents = <String, DockgeAgent>{};
    if (raw is Map) {
      raw.forEach((key, value) {
        final map = mapOrNull(value);
        if (map == null) return;
        final agent = DockgeAgent.fromJson({'endpoint': key, ...map});
        agents[agent.endpoint] = agent;
      });
    } else if (raw is List) {
      for (final value in raw) {
        final map = mapOrNull(value);
        if (map == null) continue;
        final agent = DockgeAgent.fromJson(map);
        agents[agent.endpoint] = agent;
      }
    }
    _latestAgents = agents;
    if (!_agentListController.isClosed) {
      _agentListController.add(_agentsInOrder(agents));
    }
  }

  /// Patches one agent's connection state from `agentStatus`.
  void _handleAgentStatus(dynamic data) {
    final map = mapOrNull(data);
    if (map == null) return;
    final endpoint = stringOrNull(map['endpoint']) ?? '';
    final status = stringOrNull(map['status']);
    if (status == null) return;
    final known = _latestAgents[endpoint];
    final patched = Map<String, DockgeAgent>.from(_latestAgents);
    patched[endpoint] =
        known?.copyWith(status: status) ??
        DockgeAgent(
          endpoint: endpoint,
          name: endpoint.isEmpty ? 'local' : endpoint,
          status: status,
        );
    _latestAgents = patched;
    if (!_agentListController.isClosed) {
      _agentListController.add(_agentsInOrder(patched));
    }
  }

  /// The hub first, then the agents by name. The hub is synthesised when Dockge
  /// did not name it, because it is always there.
  static List<DockgeAgent> _agentsInOrder(Map<String, DockgeAgent> agents) {
    final local = agents[''] ?? DockgeAgent.local;
    final remote = agents.values.where((a) => !a.isLocal).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return [local, ...remote];
  }

  /// Handles the lighter `stackStatusList` event which patches only statuses.
  void _onStackStatusList(dynamic data) {
    final map = mapOrNull(data);
    final statuses = mapOrNull(map?['stackStatusList']);
    if (statuses == null || _latestStacks.isEmpty) return;
    final patched = _latestStacks
        .map((stack) {
          if (!statuses.containsKey(stack.name)) return stack;
          return stack.copyWith(
            status: DockgeStackStatus.fromCode(intOrNull(statuses[stack.name])),
          );
        })
        .toList(growable: false);
    _latestStacks = patched;
    if (!_stackListController.isClosed) _stackListController.add(patched);
  }

  /// Emits an `agent`-wrapped command and awaits its acknowledgement.
  Future<Map<String, dynamic>> _agent(
    String event, {
    List<dynamic> args = const [],
    Duration timeout = const Duration(seconds: 30),
  }) async {
    await ensureConnected();
    final socket = _socket;
    if (socket == null) throw const DockgeException('Not connected');

    final completer = Completer<Map<String, dynamic>>();
    socket.emitWithAck(
      'agent',
      [_endpoint, event, ...args],
      ack: (dynamic res) {
        if (completer.isCompleted) return;
        final map = mapOrNull(res) ?? <String, dynamic>{};
        if (map['ok'] == true) {
          completer.complete(map);
        } else {
          completer.completeError(
            DockgeException(_msg(map) ?? 'Dockge error ($event)'),
          );
        }
      },
    );
    return completer.future.timeout(
      timeout,
      onTimeout: () => throw DockgeException('Timed out calling $event'),
    );
  }

  static String? _msg(Map<String, dynamic>? map) => stringOrNull(map?['msg']);

  // ---- Reads -------------------------------------------------------------

  /// Asks Dockge to (re)push the full stack list.
  Future<void> requestStackList() => _agent('requestStackList');

  Future<DockgeStackDetail> getStack(String name) async {
    final res = await _agent('getStack', args: [name]);
    final stack = mapOrNull(res['stack']);
    if (stack == null) {
      throw const DockgeException('Stack not found');
    }
    return DockgeStackDetail.fromJson(stack);
  }

  Future<List<DockgeServiceStatus>> getServiceStatusList(String name) async {
    final res = await _agent('serviceStatusList', args: [name]);
    final map = mapOrNull(res['serviceStatusList']) ?? <String, dynamic>{};
    return DockgeServiceStatus.listFromMap(map);
  }

  /// Converts a `docker run ...` command into compose YAML via Dockge.
  Future<String?> composerize(String dockerRunCommand) async {
    final res = await _agent('composerize', args: [dockerRunCommand]);
    return stringOrNull(res['composeTemplate']);
  }

  // ---- Stack lifecycle ---------------------------------------------------

  static const Duration _longOp = Duration(minutes: 10);

  Future<void> startStack(String name) =>
      _agent('startStack', args: [name], timeout: _longOp);

  Future<void> stopStack(String name) =>
      _agent('stopStack', args: [name], timeout: _longOp);

  Future<void> restartStack(String name) =>
      _agent('restartStack', args: [name], timeout: _longOp);

  Future<void> updateStack(String name) =>
      _agent('updateStack', args: [name], timeout: _longOp);

  Future<void> downStack(String name) =>
      _agent('downStack', args: [name], timeout: _longOp);

  Future<void> deleteStack(String name) => _agent('deleteStack', args: [name]);

  /// Creates or updates and deploys a stack (`docker compose up -d`).
  Future<void> deployStack({
    required String name,
    required String composeYAML,
    String composeENV = '',
    required bool isAdd,
  }) async {
    _refuseEmptyCompose(composeYAML, isAdd: isAdd, op: 'deploy');
    await _agent(
      'deployStack',
      args: [name, composeYAML, composeENV, isAdd],
      timeout: _longOp,
    );
  }

  /// Saves a stack's compose files without deploying.
  Future<void> saveStack({
    required String name,
    required String composeYAML,
    String composeENV = '',
    required bool isAdd,
  }) async {
    _refuseEmptyCompose(composeYAML, isAdd: isAdd, op: 'save');
    await _agent('saveStack', args: [name, composeYAML, composeENV, isAdd]);
  }

  /// Refuses to write an empty compose file over a stack that already exists.
  ///
  /// Dockge takes the YAML it is handed as the new truth for the stack, so a
  /// blank string is not a no-op — it is `docker-compose.yaml` replaced by
  /// nothing, and for `deployStack` it is that followed by a `compose up` on the
  /// result. The editor screen produced exactly that whenever it rendered before
  /// its detail fetch resolved, so the guard belongs here as well: this is the
  /// call that destroys the file, and any future caller inherits the protection
  /// rather than having to remember it.
  ///
  /// `isAdd` is the exemption, not an oversight — creating a stack from a blank
  /// editor overwrites nothing.
  void _refuseEmptyCompose(
    String composeYAML, {
    required bool isAdd,
    required String op,
  }) {
    if (isAdd || composeYAML.trim().isNotEmpty) return;
    throw DockgeException(
      'Refusing to $op an empty compose file over an existing stack.',
    );
  }

  // ---- Per-service actions ----------------------------------------------

  Future<void> startService(String stackName, String serviceName) =>
      _agent('startService', args: [stackName, serviceName], timeout: _longOp);

  Future<void> stopService(String stackName, String serviceName) =>
      _agent('stopService', args: [stackName, serviceName], timeout: _longOp);

  Future<void> restartService(String stackName, String serviceName) => _agent(
    'restartService',
    args: [stackName, serviceName],
    timeout: _longOp,
  );

  // ---- Terminal ----------------------------------------------------------

  /// Joins a stack's combined terminal so Dockge streams its logs. Reads and
  /// lifecycle actions join it server-side automatically, but this lets a
  /// screen (re)subscribe explicitly.
  Future<void> joinCombinedTerminal(String stackName) =>
      _agent('terminalJoin', args: [combinedTerminalName(stackName)]);

  /// Lightweight connectivity probe used by the connection health check.
  ///
  /// A genuine credential rejection throws a [DockgeException] carrying
  /// `unauthorized`, so a `false` here means only that the socket dropped
  /// between authenticating and returning — a connection problem, not a wrong
  /// password.
  Future<bool> ping() async {
    await ensureConnected();
    return _authed;
  }

  Future<void> close() async {
    _authed = false;
    // Fail any in-flight connect so `ensureConnected` callers don't hang.
    final connecting = _connecting;
    _connecting = null;
    if (connecting != null && !connecting.isCompleted) {
      connecting.completeError(const DockgeException('Client closed'));
    }
    final socket = _socket;
    _socket = null;
    socket?.dispose();
    await _stackListController.close();
    await _terminalController.close();
    await _agentListController.close();
  }
}
