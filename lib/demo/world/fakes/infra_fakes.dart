/// TrueNAS, Dockge, Unraid and Nginx Proxy Manager on the fake network.
///
/// TrueNAS and Dockge answer over a real WebSocket upgrade (see
/// `fake_socket.dart`): TrueNAS speaks JSON-RPC 2.0, Dockge speaks Socket.IO
/// over Engine.IO v4. Both are driven by the app's own clients, including
/// the throwaway ones the Dashboard's probe builds, so nothing about them is
/// overridden at the provider level.
library;

import 'dart:convert';

import 'package:cupola/demo/world/fixtures.dart';
import 'package:cupola/demo/world/config_profile.dart';
import 'package:cupola/demo/world/fake_socket.dart';
import 'package:cupola/demo/world/profile_network.dart';
import 'package:cupola/demo/world/service_fakes.dart';

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
  WebSocketPeer? upgrade(NetworkRequest request, ServerContext context) =>
      request.path == '/api/current' ? TrueNasPeer(context) : null;
}

/// The server half of `wss://…/api/current`.
///
/// [ConnectionBehaviour.refusesKey] answers the key login with `false`, as
/// TrueNAS does. [ConnectionBehaviour.readOnly] answers `auth.me` with the
/// READONLY_ADMIN fixture, so the app's capability probe reads read-only on
/// its own, and every write with `EACCES`.
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
          _pool(
            1,
            'tank',
            size: 43.6e12,
            allocated: 31.2e12,
            // Six disks in RAIDZ2; sdd counted the errors its alert reports.
            disks: {
              for (final disk in ['sda', 'sdb', 'sdc', 'sdd', 'sde', 'sdf'])
                disk: disk == 'sdd' ? 8 : 0,
            },
          ),
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
    Map<String, int> disks = const {},
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
    'topology': {
      'data': [
        if (disks.isNotEmpty)
          {
            'type': 'RAIDZ2',
            'status': 'ONLINE',
            'children': [
              for (final MapEntry(key: disk, value: errors) in disks.entries)
                {
                  'disk': disk,
                  'status': 'ONLINE',
                  'stats': {
                    'read_errors': 0,
                    'write_errors': 0,
                    'checksum_errors': errors,
                  },
                },
            ],
          },
      ],
      'cache': const <Object?>[],
    },
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
  WebSocketPeer? upgrade(NetworkRequest request, ServerContext context) =>
      request.path.startsWith('/socket.io') ? DockgePeer(context) : null;
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

  /// The stacks as the world stands: as written, or as the demo left them.
  Map<String, int> get _stacks =>
      context.life?.stacks(context.server.id, stacks) ?? stacks;

  JsonMap get _stackList => {
    'ok': true,
    'stackList': {
      for (final entry in _stacks.entries)
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
    final command = event == 'agent' && args.length > 2 ? '${args[2]}' : '';
    // A relayed command by its own name, `agent:startStack`, so a test can
    // tell a write from the list it reads.
    context.network.rpcCalls.add((
      context.server.id,
      command.isEmpty ? event : 'agent:$command',
    ));
    switch (event) {
      case 'login':
        if (context.behaviour == ConnectionBehaviour.refusesKey) {
          _ack(ackId, {'ok': false, 'msg': 'Incorrect username or password.'});
          return;
        }
        _ack(ackId, {'ok': true, 'token': 'world-dockge-token'});
        _emit('stackList', _stackList);
      case 'agent':
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
        if (write && _act(command, args.length > 3 ? '${args[3]}' : '')) {
          _emit('stackList', _stackList);
        }
      default:
        if (ackId.isNotEmpty) _ack(ackId, {'ok': true});
    }
  }

  /// What a stack command does to a living world, and whether it changed
  /// anything the list shows.
  bool _act(String command, String stack) {
    final life = context.life;
    if (life == null) return false;
    final all = _stacks;
    switch (command) {
      case 'startStack' || 'restartStack' || 'updateStack':
        if (!all.containsKey(stack)) return false;
        all[stack] = 3;
      case 'stopStack':
        if (!all.containsKey(stack)) return false;
        all[stack] = 4;
      case 'downStack':
        if (!all.containsKey(stack)) return false;
        all[stack] = 1;
      case 'deleteStack':
        return all.remove(stack) != null;
      case 'deployStack':
        if (stack.isEmpty) return false;
        all[stack] = 3;
      default:
        return false;
    }
    return true;
  }
}

// === Unraid (World B) ======================================================

/// Unraid's GraphQL at `/graphql`, keyed by `x-api-key`.
///
/// A refused key is a `200` with an `UNAUTHENTICATED` error, and a read-only
/// key answers `me` as a VIEWER (both from the recorded fixtures), so the
/// app's capability probe reaches its own verdict.
class UnraidFake extends ServiceFake {
  const UnraidFake();

  String _query(NetworkRequest r) {
    final body = r.json;
    return body is Map ? '${body['query']}' : '';
  }

  @override
  bool isWrite(NetworkRequest request) =>
      _query(request).trimLeft().startsWith('mutation');

  @override
  NetworkReply refuseKey(NetworkRequest request) =>
      NetworkReply.json(jsonFixtureMap('unraid/error_unauthenticated.json'));

  @override
  NetworkReply refuseWrite(NetworkRequest request) =>
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
    if (query.contains('vms {')) {
      return NetworkReply.json({
        'data': {
          'vms': {'domains': _vms},
        },
      });
    }
    if (query.contains('notifications {')) {
      return NetworkReply.json({'data': _notifications(r, c)});
    }
    if (query.contains('shares {')) {
      return NetworkReply.json({
        'data': {'shares': _shares},
      });
    }
    if (query.trimLeft().startsWith('mutation')) return _mutation(r, c);
    return NetworkReply.json({'data': const <String, Object?>{}});
  }

  // The server's virtual machines: the home automation one that never
  // stops, a build box, and a Windows lab that is off until it is needed.
  static const _vms = [
    {'id': 'vm:homeassistant', 'name': 'Home Assistant', 'state': 'RUNNING'},
    {'id': 'vm:ubuntu', 'name': 'Ubuntu dev box', 'state': 'RUNNING'},
    {'id': 'vm:windows', 'name': 'Windows 11 lab', 'state': 'SHUTOFF'},
  ];

  // The user shares, in kilobytes as the GraphQL `Long` strings carry them.
  // Together they sit under the 6 TB the array fixture reports as used.
  static const _shares = [
    {
      'id': 'share:media',
      'name': 'media',
      'used': '3900000000',
      'size': '10000000000',
      'cache': false,
      'comment': 'Movies, series and music',
      'luksStatus': 'NOT_ENCRYPTED',
    },
    {
      'id': 'share:backups',
      'name': 'backups',
      'used': '1200000000',
      'size': '5000000000',
      'cache': false,
      'comment': 'Nightly backups',
      'luksStatus': 'ENCRYPTED',
    },
    {
      'id': 'share:downloads',
      'name': 'downloads',
      'used': '480000000',
      'size': '2000000000',
      'cache': true,
      'comment': 'Download clients, before the arrs move them',
      'luksStatus': 'NOT_ENCRYPTED',
    },
    {
      'id': 'share:appdata',
      'name': 'appdata',
      'used': '40000000',
      'size': '200000000',
      'cache': true,
      'comment': 'Container appdata',
      'luksStatus': 'NOT_ENCRYPTED',
    },
    {
      'id': 'share:domains',
      'name': 'domains',
      'used': '96000000',
      'size': '500000000',
      'cache': true,
      'comment': 'Virtual machine disks',
      'luksStatus': 'NOT_ENCRYPTED',
    },
  ];

  /// `notifications`: the counts of both piles, and the list of the one
  /// asked for. Nothing unread is a warning or an alert, which the
  /// Dashboard would raise as a decision of its own.
  static JsonMap _notifications(NetworkRequest r, ServerContext c) {
    JsonMap one(
      String id,
      String importance,
      String subject,
      String description,
      Duration age, {
      required String type,
    }) {
      final label = switch (importance) {
        'WARNING' => 'Warning',
        'ALERT' => 'Alert',
        _ => 'Notice',
      };
      final at = c.now.subtract(age).toUtc();
      return {
        'id': 'notification:$id',
        'title': '$label [TOWER] - $subject',
        'subject': subject,
        'description': description,
        'importance': importance,
        'link': '',
        'type': type,
        'timestamp': at.toIso8601String(),
        'formattedTimestamp': at
            .toIso8601String()
            .substring(0, 19)
            .replaceFirst('T', ' '),
      };
    }

    final unread = [
      one(
        'parity-check',
        'INFO',
        'Parity check finished',
        'Parity check found 0 errors in 6 hours 12 minutes.',
        const Duration(days: 2, hours: 5),
        type: 'UNREAD',
      ),
      one(
        'docker-update',
        'INFO',
        'Docker image updates are available',
        'Updates are available for 2 containers.',
        const Duration(hours: 14),
        type: 'UNREAD',
      ),
    ];
    final archive = [
      one(
        'cache-hot',
        'WARNING',
        'Cache drive temperature is 46 C',
        'The cache pool went above the 45 C warning threshold, and cooled '
            'down again.',
        const Duration(days: 9),
        type: 'ARCHIVE',
      ),
      one(
        'array-started',
        'INFO',
        'Array started',
        'The array is started and all disks are online.',
        const Duration(days: 14),
        type: 'ARCHIVE',
      ),
    ];
    final body = r.json;
    final variables = body is Map ? body['variables'] : null;
    final filter = variables is Map ? variables['filter'] : null;
    final asked = filter is Map ? '${filter['type']}' : 'UNREAD';
    Map<String, int> counts(List<JsonMap> list) => {
      'info': list.where((n) => n['importance'] == 'INFO').length,
      'warning': list.where((n) => n['importance'] == 'WARNING').length,
      'alert': list.where((n) => n['importance'] == 'ALERT').length,
      'total': list.length,
    };
    return {
      'notifications': {
        'overview': {'unread': counts(unread), 'archive': counts(archive)},
        'list': asked == 'ARCHIVE' ? archive : unread,
      },
    };
  }

  /// A VM action answers `true` (the daemon ran it), and archiving a
  /// notification echoes it back. Neither is kept: the world draws the
  /// same lists after.
  NetworkReply _mutation(NetworkRequest r, ServerContext c) {
    final query = _query(r);
    final body = r.json;
    final variables = body is Map ? body['variables'] : null;
    if (query.contains('archiveNotification')) {
      final id = variables is Map ? '${variables['id']}' : '';
      return NetworkReply.json({
        'data': {
          'archiveNotification': {
            'id': id,
            'title': '',
            'subject': '',
            'description': '',
            'importance': 'INFO',
            'link': '',
            'type': 'ARCHIVE',
            'timestamp': c.ago(Duration.zero),
            'formattedTimestamp': '',
          },
        },
      });
    }
    final action = RegExp(r'vm \{\s*(\w+)\(').firstMatch(query)?.group(1);
    return NetworkReply.json({
      'data': {
        'vm': {?action: true},
      },
    });
  }
}

// === Nginx Proxy Manager (World B) ==========================================

/// NPM: an unauthenticated `GET /api/`, a `POST /api/tokens` exchange, then
/// bearer calls. A refused password is a `401` from the token exchange; a
/// view-only account answers `users/me` from the recorded fixture.
class NpmFake extends ServiceFake {
  const NpmFake();

  @override
  bool isPublic(NetworkRequest request) =>
      request.method == 'GET' && request.path == '/api/';

  @override
  bool isWrite(NetworkRequest request) =>
      request.method != 'GET' && request.path != '/api/tokens';

  @override
  NetworkReply refuseKey(NetworkRequest request) => NetworkReply.json({
    'error': {'code': 401, 'message': 'Invalid email or password'},
  }, status: 401);

  @override
  NetworkReply refuseWrite(NetworkRequest request) => NetworkReply.json({
    'error': {'code': 403, 'message': 'Permission Denied'},
  }, status: 403);

  @override
  NetworkReply? answer(NetworkRequest r, ServerContext c) {
    switch ((r.method, r.path)) {
      case ('GET', '/api/'):
        return NetworkReply.json({
          'status': 'OK',
          'setup': true,
          // 2.13 is the first release without the seeded default
          // administrator: the household's NPM is a maintained one, so the
          // Overview carries no `changeme` warning.
          'version': {'major': 2, 'minor': 13, 'revision': 4},
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
      return NetworkReply.json(switch (r.path) {
        '/api/nginx/proxy-hosts' => _proxyHosts,
        '/api/nginx/certificates' => _certificates(c),
        '/api/nginx/access-lists' => _accessLists,
        '/api/nginx/redirection-hosts' => _redirectionHosts,
        '/api/nginx/streams' => _streams,
        _ => const <Object?>[],
      });
    }
    if (r.method == 'GET' && r.path == '/api/audit-log') {
      return NetworkReply.json(_auditLog(c));
    }
    return null;
  }

  // The household's services behind this proxy, under the lab's own name.
  // Each forwards to where the world's services listen, so the Overview's
  // reachability probe is asking about the real fakes.
  static JsonMap _host(
    int id,
    String domain,
    String scheme,
    String host,
    int port, {
    int certificate = 0,
    int accessList = 0,
    bool enabled = true,
    bool websockets = false,
  }) => {
    'id': id,
    'created_on': '2026-01-12T10:00:00.000Z',
    'modified_on': '2026-08-02T16:20:00.000Z',
    'owner_user_id': 1,
    'domain_names': [domain],
    'forward_scheme': scheme,
    'forward_host': host,
    'forward_port': port,
    'access_list_id': accessList,
    'certificate_id': certificate,
    'ssl_forced': certificate > 0,
    'hsts_enabled': false,
    'hsts_subdomains': false,
    'http2_support': certificate > 0,
    'caching_enabled': false,
    'block_exploits': true,
    'allow_websocket_upgrade': websockets,
    'advanced_config': '',
    'enabled': enabled,
    'meta': {
      'letsencrypt_agree': true,
      'dns_challenge': false,
      'nginx_online': true,
    },
  };

  static final _proxyHosts = [
    _host(
      1,
      'requests.lab.example.net',
      'http',
      'nas.home.arpa',
      5055,
      certificate: 1,
      websockets: true,
    ),
    _host(
      2,
      'watch.lab.example.net',
      'http',
      'nas.home.arpa',
      8096,
      certificate: 1,
      websockets: true,
    ),
    _host(
      3,
      'plex.lab.example.net',
      'http',
      'nas.home.arpa',
      32400,
      certificate: 2,
      websockets: true,
    ),
    _host(
      4,
      'torrents.lab.example.net',
      'http',
      'nas.home.arpa',
      8080,
      certificate: 3,
      accessList: 1,
    ),
    _host(
      5,
      'stacks.lab.example.net',
      'https',
      'nas.home.arpa',
      5001,
      certificate: 3,
      accessList: 1,
      websockets: true,
    ),
    _host(
      6,
      'tower.lab.example.net',
      'https',
      'tower.home.arpa',
      443,
      certificate: 3,
      accessList: 1,
    ),
    _host(
      7,
      'status.lab.example.net',
      'http',
      'nas.home.arpa',
      3001,
      accessList: 2,
      enabled: false,
    ),
  ];

  static JsonMap _certificate(
    int id,
    String name,
    List<String> domains,
    String expires,
  ) => {
    'id': id,
    'created_on': '2026-01-12T10:05:00.000Z',
    'modified_on': '2026-08-02T16:20:00.000Z',
    'owner_user_id': 1,
    'provider': 'letsencrypt',
    'nice_name': name,
    'domain_names': domains,
    'expires_on': expires,
    'meta': const <String, Object?>{},
  };

  /// Three Let's Encrypt certificates. The Plex one is ten days from lapse,
  /// inside the window where certbot should already have renewed it: the
  /// one thing on this box that wants a person.
  static List<JsonMap> _certificates(ServerContext c) => [
    _certificate(1, 'requests.lab.example.net', [
      'requests.lab.example.net',
      'watch.lab.example.net',
    ], c.ahead(const Duration(days: 61))),
    _certificate(2, 'plex.lab.example.net', [
      'plex.lab.example.net',
    ], c.ahead(const Duration(days: 10))),
    _certificate(3, 'admin.lab.example.net', [
      'torrents.lab.example.net',
      'stacks.lab.example.net',
      'tower.lab.example.net',
    ], c.ahead(const Duration(days: 72))),
  ];

  static const _accessLists = [
    {
      'id': 1,
      'name': 'Home network only',
      'satisfy_any': false,
      'pass_auth': false,
      'proxy_host_count': 3,
      'clients': [
        {'address': '192.168.1.0/24', 'directive': 'allow'},
        {'address': 'all', 'directive': 'deny'},
      ],
    },
    {
      'id': 2,
      'name': 'Family',
      'satisfy_any': true,
      'pass_auth': false,
      'proxy_host_count': 1,
      'clients': [
        {'address': '192.168.1.0/24', 'directive': 'allow'},
      ],
    },
  ];

  static const _redirectionHosts = [
    {
      'id': 1,
      'domain_names': ['www.lab.example.net'],
      'forward_scheme': 'https',
      'forward_domain_name': 'requests.lab.example.net',
      'enabled': true,
      'meta': {'nginx_online': true},
    },
  ];

  static const _streams = [
    {
      'id': 1,
      'incoming_port': 2222,
      'forwarding_host': 'nas.home.arpa',
      'forwarding_port': 22,
      'tcp_forwarding': true,
      'udp_forwarding': false,
      'enabled': true,
      'meta': {'nginx_online': true},
    },
  ];

  /// What the admin did lately, newest first.
  static List<JsonMap> _auditLog(ServerContext c) {
    JsonMap entry(
      int id,
      String type,
      int objectId,
      String action,
      Map<String, Object?> meta,
      Duration age,
    ) => {
      'id': id,
      'created_on': c.ago(age),
      'modified_on': c.ago(age),
      'user_id': 1,
      'object_type': type,
      'object_id': objectId,
      'action': action,
      'meta': meta,
    };
    return [
      entry(6, 'certificate', 3, 'renewed', {
        'name': 'admin.lab.example.net',
      }, const Duration(days: 18)),
      entry(5, 'proxy-host', 7, 'disabled', {
        'domain_names': ['status.lab.example.net'],
      }, const Duration(days: 23)),
      entry(4, 'proxy-host', 6, 'created', {
        'domain_names': ['tower.lab.example.net'],
      }, const Duration(days: 40)),
      entry(3, 'access-list', 1, 'updated', {
        'name': 'Home network only',
      }, const Duration(days: 52)),
      entry(2, 'certificate', 2, 'created', {
        'name': 'plex.lab.example.net',
      }, const Duration(days: 80)),
      entry(1, 'user', 1, 'updated', {
        'email': 'admin@lab.test',
      }, const Duration(days: 104)),
    ];
  }
}
