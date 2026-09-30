/// TrueNAS, Dockge, Unraid and Nginx Proxy Manager on the fake network.
///
/// TrueNAS and Dockge answer over a real WebSocket upgrade (see
/// `fake_socket.dart`): TrueNAS speaks JSON-RPC 2.0, Dockge speaks Socket.IO
/// over Engine.IO v4. Both are driven by the app's own clients — including
/// the throwaway ones the Dashboard's probe builds — so nothing about them is
/// overridden at the provider level.
library;

import 'dart:convert';

import '../../fixtures.dart';
import '../config_profile.dart';
import '../fake_socket.dart';
import '../profile_network.dart';
import '../service_fakes.dart';

// === TrueNAS ===============================================================

/// A JSON-RPC error a test-supplied TrueNAS answer can throw.
class TrueNasRpcFault implements Exception {
  const TrueNasRpcFault(this.error);

  /// The `error` object, as TrueNAS sends it.
  final Object? error;

  /// `[EACCES] Not authorized`, from the recorded fixture.
  static TrueNasRpcFault eacces() =>
      TrueNasRpcFault(jsonFixtureMap('truenas/rpc_error_eacces.json')['error']);
}

class TrueNasFake extends ServiceFake {
  const TrueNasFake();

  @override
  NetworkReply? answer(NetworkRequest r, ServerContext c) => null;

  @override
  WebSocketPeer? upgrade(NetworkRequest r, ServerContext c) =>
      r.path == '/api/current' ? TrueNasPeer(c) : null;
}

/// The server half of `wss://…/api/current`.
///
/// [ConnectionBehaviour.refusesKey] answers the key login with `false`, as
/// TrueNAS does. [ConnectionBehaviour.readOnly] answers `auth.me` with the
/// READONLY_ADMIN fixture — so the app's capability probe reads read-only on
/// its own — and every write with `EACCES`.
class TrueNasPeer extends WebSocketPeer {
  TrueNasPeer(this.context);

  final ServerContext context;
  bool _authed = false;

  static bool isRead(String method) =>
      method.endsWith('.query') ||
      method.endsWith('.config') ||
      method.startsWith('auth.') ||
      const {
        'system.info',
        'system.version',
        'alert.list',
        'core.ping',
        'core.get_jobs',
        'reporting.get_data',
        'update.check_available',
        'virt.instance.device_list',
      }.contains(method);

  @override
  void onText(String text) {
    final message = jsonDecode(text) as Map<String, dynamic>;
    final id = message['id'];
    final method = '${message['method']}';
    final params = (message['params'] as List?) ?? const [];
    context.network.rpcCalls.add((context.server.id, method));
    try {
      send(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': id,
          'result': _call(method, params),
        }),
      );
    } on TrueNasRpcFault catch (fault) {
      send(jsonEncode({'jsonrpc': '2.0', 'id': id, 'error': fault.error}));
    }
  }

  Object? _call(String method, List<dynamic> params) {
    final behaviour = context.behaviour;
    if (method == 'auth.login_with_api_key') {
      _authed = behaviour != ConnectionBehaviour.refusesKey;
      return _authed;
    }
    if (!_authed) {
      throw const TrueNasRpcFault({
        'code': -32001,
        'message': 'Method call error',
        'data': {'errname': 'ENOTAUTHENTICATED', 'reason': 'Not authenticated'},
      });
    }
    final scripted = context.network.rpcRoute(context.server.id, method);
    if (scripted != null) return scripted(params);
    if (behaviour == ConnectionBehaviour.readOnly && !isRead(method)) {
      throw TrueNasRpcFault.eacces();
    }
    return _world(method);
  }

  Object? _world(String method) {
    final now = context.now;
    switch (method) {
      case 'auth.me':
        return jsonFixtureMap(
          context.behaviour == ConnectionBehaviour.readOnly
              ? 'truenas/auth_me_readonly_admin.json'
              : 'truenas/auth_me_full_admin.json',
        );
      case 'system.version':
        return 'TrueNAS-25.10.6';
      case 'system.info':
        return {
          'version': 'TrueNAS-25.10.6',
          'hostname': 'truenas',
          'uptime_seconds': 41 * 86400.0,
          'physmem': 64 * 1024 * 1024 * 1024,
          'cores': 8,
          'model': 'Intel(R) Xeon(R) E-2236',
          'loadavg': [0.4, 0.5, 0.6],
          'system_product': 'X11SCH-F',
          'system_serial': 'WORLD-NAS',
          'datetime': {r'$date': now.millisecondsSinceEpoch},
        };
      case 'alert.list':
        return [
          {
            'uuid': 'alert-sdd',
            'level': 'CRITICAL',
            'klass': 'ZpoolUncorrectedErrors',
            'formatted': '8 uncorrectable errors reported for sdd (ZL2PQR7T).',
            'text': '8 uncorrectable errors reported for sdd (ZL2PQR7T).',
            'dismissed': false,
            'datetime': {
              r'$date': now
                  .subtract(const Duration(hours: 5))
                  .millisecondsSinceEpoch,
            },
          },
        ];
      case 'pool.query':
        return [
          _pool(1, 'tank', size: 43.6e12, allocated: 31.2e12),
          _pool(2, 'fast', size: 1.8e12, allocated: 0.6e12),
        ];
      case 'update.check_available':
        return {'status': 'AVAILABLE', 'version': '25.10.7'};
      case 'core.ping':
        return 'pong';
      case 'system.general.config':
        return {'timezone': 'Europe/Rome', 'ui_port': 80, 'ui_httpsport': 443};
    }
    if (method.endsWith('.query') ||
        method == 'core.get_jobs' ||
        method == 'reporting.get_data') {
      return const <Object?>[];
    }
    if (method.endsWith('.config')) return const <String, Object?>{};
    return true;
  }

  static JsonMap _pool(
    int id,
    String name, {
    required double size,
    required double allocated,
  }) => {
    'id': id,
    'name': name,
    'guid': 'pool-$name',
    'path': '/mnt/$name',
    'status': 'ONLINE',
    'healthy': true,
    'size': size.round(),
    'allocated': allocated.round(),
    'free': (size - allocated).round(),
    'topology': {'data': const <Object?>[], 'cache': const <Object?>[]},
    'scan': {
      'function': 'SCRUB',
      'state': 'FINISHED',
      'errors': 0,
      'end_time': {r'$date': 0},
    },
  };
}

// === Dockge ================================================================

class DockgeFake extends ServiceFake {
  const DockgeFake();

  @override
  NetworkReply? answer(NetworkRequest r, ServerContext c) => null;

  @override
  WebSocketPeer? upgrade(NetworkRequest r, ServerContext c) =>
      r.path.startsWith('/socket.io') ? DockgePeer(c) : null;
}

/// Dockge's Socket.IO server, over Engine.IO v4.
///
/// The ping interval it announces is an hour, so no ping timer of the
/// client's ever fires inside a test; the client closes it on dispose.
/// [ConnectionBehaviour.refusesKey] answers `login` with Dockge's own
/// `Incorrect username or password.`.
class DockgePeer extends WebSocketPeer {
  DockgePeer(this.context);

  final ServerContext context;

  static const stacks = {'media': 3, 'monitoring': 3, 'immich': 4};

  @override
  void onOpen() => send(
    '0${jsonEncode({'sid': 'eio-world', 'upgrades': const <Object?>[], 'pingInterval': 3600000, 'pingTimeout': 3600000, 'maxPayload': 1000000})}',
  );

  void _emit(String event, [Object? payload]) =>
      send('42${jsonEncode([event, ?payload])}');

  void _ack(String id, Object? payload) =>
      send('43$id${jsonEncode([payload])}');

  JsonMap get _stackList => {
    'ok': true,
    'stackList': {
      for (final entry in stacks.entries)
        entry.key: {
          'name': entry.key,
          'status': entry.value,
          'tags': const <Object?>[],
          'isManagedByDockge': true,
          'composeFileName': 'compose.yaml',
          'endpoint': '',
        },
    },
  };

  @override
  void onText(String text) {
    if (text == '2') return send('3');
    if (text.startsWith('40')) {
      send('40${jsonEncode({'sid': 'sio-world'})}');
      _emit('info', {
        'version': '1.4.2',
        'latestVersion': '1.4.2',
        'isContainer': true,
        'primaryHostname': 'nas.home.arpa',
      });
      return;
    }
    if (text.startsWith('41')) return close();
    if (!text.startsWith('42')) return;
    final body = text.substring(2);
    final bracket = body.indexOf('[');
    if (bracket < 0) return;
    final ackId = body.substring(0, bracket);
    final args = jsonDecode(body.substring(bracket)) as List<dynamic>;
    final event = '${args.first}';
    context.network.rpcCalls.add((context.server.id, event));
    switch (event) {
      case 'login':
        if (context.behaviour == ConnectionBehaviour.refusesKey) {
          _ack(ackId, {'ok': false, 'msg': 'Incorrect username or password.'});
          return;
        }
        _ack(ackId, {'ok': true, 'token': 'world-dockge-token'});
        _emit('stackList', _stackList);
      case 'agent':
        final command = args.length > 2 ? '${args[2]}' : '';
        final write = !const {
          'requestStackList',
          'getStack',
          'serviceStatusList',
          'terminalJoin',
          'composerize',
        }.contains(command);
        if (write && context.behaviour == ConnectionBehaviour.readOnly) {
          if (ackId.isNotEmpty) {
            _ack(ackId, {'ok': false, 'msg': 'Permission denied'});
          }
          return;
        }
        if (ackId.isNotEmpty) {
          _ack(ackId, switch (command) {
            'getStack' => {
              'ok': true,
              'stack': {
                'name': args.length > 3 ? args[3] : '',
                'composeYAML': 'services: {}\n',
                'composeENV': '',
                'primaryHostname': 'nas.home.arpa',
              },
            },
            'serviceStatusList' => {
              'ok': true,
              'serviceStatusList': const <String, Object?>{},
            },
            _ => {'ok': true},
          });
        }
        if (command == 'requestStackList') _emit('stackList', _stackList);
      default:
        if (ackId.isNotEmpty) _ack(ackId, {'ok': true});
    }
  }
}

// === Unraid (World B) ======================================================

/// Unraid's GraphQL at `/graphql`, keyed by `x-api-key`.
///
/// A refused key is a `200` with an `UNAUTHENTICATED` error, and a read-only
/// key answers `me` as a VIEWER — both from the recorded fixtures — so the
/// app's capability probe reaches its own verdict.
class UnraidFake extends ServiceFake {
  const UnraidFake();

  String _query(NetworkRequest r) {
    final body = r.json;
    return body is Map ? '${body['query']}' : '';
  }

  @override
  bool isWrite(NetworkRequest r) => _query(r).trimLeft().startsWith('mutation');

  @override
  NetworkReply refuseKey(NetworkRequest r) =>
      NetworkReply.json(jsonFixtureMap('unraid/error_unauthenticated.json'));

  @override
  NetworkReply refuseWrite(NetworkRequest r) =>
      NetworkReply.json(jsonFixtureMap('unraid/error_forbidden.json'));

  @override
  NetworkReply? answer(NetworkRequest r, ServerContext c) {
    if (r.path != '/graphql') return null;
    final query = _query(r);
    if (query.contains('me {')) {
      return NetworkReply.json(
        jsonFixtureMap(
          c.behaviour == ConnectionBehaviour.readOnly
              ? 'unraid/me_viewer.json'
              : 'unraid/me_admin.json',
        ),
      );
    }
    if (query.contains('info {')) {
      return NetworkReply.json(jsonFixtureMap('unraid/info.json'));
    }
    if (query.contains('array {')) {
      return NetworkReply.json(jsonFixtureMap('unraid/array.json'));
    }
    if (query.contains('dockerContainers')) {
      return NetworkReply.json(jsonFixtureMap('unraid/docker.json'));
    }
    return NetworkReply.json({'data': const <String, Object?>{}});
  }
}

// === Nginx Proxy Manager (World B) ==========================================

/// NPM: an unauthenticated `GET /api/`, a `POST /api/tokens` exchange, then
/// bearer calls. A refused password is a `401` from the token exchange; a
/// view-only account answers `users/me` from the recorded fixture.
class NpmFake extends ServiceFake {
  const NpmFake();

  @override
  bool isPublic(NetworkRequest r) => r.method == 'GET' && r.path == '/api/';

  @override
  bool isWrite(NetworkRequest r) =>
      r.method != 'GET' && r.path != '/api/tokens';

  @override
  NetworkReply refuseKey(NetworkRequest r) => NetworkReply.json({
    'error': {'code': 401, 'message': 'Invalid email or password'},
  }, status: 401);

  @override
  NetworkReply refuseWrite(NetworkRequest r) => NetworkReply.json({
    'error': {'code': 403, 'message': 'Permission Denied'},
  }, status: 403);

  @override
  NetworkReply? answer(NetworkRequest r, ServerContext c) {
    switch ((r.method, r.path)) {
      case ('GET', '/api/'):
        return NetworkReply.json({
          'status': 'OK',
          'setup': true,
          'version': {'major': 2, 'minor': 12, 'revision': 1},
        });
      case ('POST', '/api/tokens'):
        return NetworkReply.json({
          'token': 'world-npm-token',
          'expires': c.ahead(const Duration(days: 1)),
        });
      case ('GET', '/api/users/me'):
        return NetworkReply.json(
          jsonFixtureMap(
            c.behaviour == ConnectionBehaviour.readOnly
                ? 'npm/users_me_view_only.json'
                : 'npm/users_me_admin.json',
          ),
        );
    }
    if (r.method == 'GET' && r.path.startsWith('/api/nginx/')) {
      return NetworkReply.json(const <Object?>[]);
    }
    if (r.method == 'GET' && r.path == '/api/audit-log') {
      return NetworkReply.json(const <Object?>[]);
    }
    return null;
  }
}
