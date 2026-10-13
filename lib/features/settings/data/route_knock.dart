import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/network/host_reach.dart';
import 'package:cupola/core/network/redirect_guard.dart';
import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/features/settings/domain/connection_reach.dart';
import 'package:cupola/features/settings/domain/probe_identity.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/transmission/data/transmission_client.dart';

/// Whether [reach] answered as [service] within [timeout]: the route probe's
/// question, asked of each of a connection's two addresses.
///
/// **No secret of the service goes with it.** A knock asks a route the
/// service answers without its key, and recognises the service by the
/// answer; only the address's own gateway access travels with it, because
/// the gateway would answer in the service's place otherwise. A private
/// address at home can belong to somebody else on another network, and
/// nothing is sent to it until it has answered as the service.
typedef RouteKnock =
    Future<bool> Function(
      ServiceKey service,
      ConnectionReach reach, {
      required Duration timeout,
    });

/// The app's [RouteKnock]. A test hands it one that opens no socket.
final routeKnockProvider = Provider<RouteKnock>((ref) {
  final hostReach = ref.watch(hostReachProvider);
  return (service, reach, {required timeout}) =>
      knockAt(service, reach, timeout: timeout, hostReach: hostReach);
});

/// What a knock reads off an answer.
typedef KnockAnswer = ({
  int status,
  Map<String, List<String>> headers,
  String body,
});

/// Where to knock on [service] and how its answer proves it: a route each
/// service answers without a key, checked against the lab.
///
/// [path] is relative to the connection's address, or a whole URL; null for
/// a service with no plain HTTP route to ask (TrueNAS speaks over a
/// WebSocket), which is knocked by opening a connection to its port.
final class KnockPlan {
  const KnockPlan(
    this.path,
    this.answers, {
    this.query = const {},
    this.headers = const {},
  });

  final String path;
  final Map<String, String> query;
  final Map<String, String> headers;

  /// Whether an answer at [path] is the service's.
  final bool Function(KnockAnswer answer) answers;
}

/// The knock for [service] at [url]; null to open a connection instead.
KnockPlan? knockPlanOf(ServiceKey service, String url) => switch (service) {
  // Every arr, and Bazarr, answer a key-less ping with `{"status": "OK"}`.
  ServiceKey.radarr ||
  ServiceKey.sonarr ||
  ServiceKey.lidarr ||
  ServiceKey.readarr ||
  ServiceKey.prowlarr => const KnockPlan('/ping', _statusOk),
  ServiceKey.bazarr => const KnockPlan('/api/system/ping', _statusOk),
  // Public routes whose answer `identifyProbeAnswer` already recognises.
  ServiceKey.seerr => KnockPlan(
    '/api/v1/status',
    (answer) => _identifies(ServiceKey.seerr, answer),
  ),
  ServiceKey.jellyfin => KnockPlan(
    '/System/Info/Public',
    (answer) => _identifies(ServiceKey.jellyfin, answer),
  ),
  ServiceKey.plex => KnockPlan(
    '/identity',
    (answer) =>
        _identifies(ServiceKey.plex, answer) ||
        (answer.status == 200 && answer.body.contains('<MediaContainer')),
    headers: const {'Accept': 'application/json'},
  ),
  ServiceKey.sabnzbd => KnockPlan(
    '/api',
    (answer) => _identifies(ServiceKey.sabnzbd, answer),
    query: const {'mode': 'version', 'output': 'json'},
  ),
  ServiceKey.nginxProxyManager => KnockPlan(
    '/api/',
    (answer) => _identifies(ServiceKey.nginxProxyManager, answer),
  ),
  // qBittorrent answers its version, or `Forbidden` to a caller not signed
  // in: either is qBittorrent.
  ServiceKey.qbittorrent => KnockPlan('/api/v2/app/version', (answer) {
    final text = answer.body.trim();
    return (answer.status == 200 && RegExp(r'^v\d').hasMatch(text)) ||
        (answer.status == 403 && text == 'Forbidden');
  }),
  // Transmission asks for its session id (409), or for its password (401,
  // in its own realm), at the endpoint its client resolves.
  ServiceKey.transmission => KnockPlan(
    _onOrigin(url, TransmissionClient.resolveRpcPath(url)),
    (answer) =>
        (answer.status == 409 &&
            _header(answer, TransmissionClient.sessionIdHeader) != null) ||
        (answer.status == 401 &&
            (_header(answer, 'www-authenticate') ?? '').contains(
              'Transmission',
            )),
  ),
  // NZBGet asks for its password in its own realm, or answers JSON-RPC.
  ServiceKey.nzbget => KnockPlan('/jsonrpc', (answer) {
    final realm = _header(answer, 'www-authenticate') ?? '';
    final server = (_header(answer, 'server') ?? '').toLowerCase();
    final json = _json(answer);
    return (answer.status == 401 && realm.contains('NZBGet')) ||
        server.startsWith('nzbget') ||
        (json is Map && json.containsKey('version'));
  }),
  // Dockge's Socket.IO opens a polling session without signing in.
  ServiceKey.dockge => KnockPlan(
    '/socket.io/',
    (answer) =>
        answer.status == 200 &&
        answer.body.startsWith('0{') &&
        answer.body.contains('"sid"'),
    query: const {'EIO': '4', 'transport': 'polling'},
  ),
  // Unraid's GraphQL endpoint answers a bare GET with nothing that names
  // it; an answer that is not a redirect is the most a knock can ask.
  ServiceKey.unraid => KnockPlan(
    '/graphql',
    (answer) => answer.status < 300 || answer.status >= 400,
  ),
  ServiceKey.truenas => null,
};

/// Knocks on [service] at [reach]; see [RouteKnock].
Future<bool> knockAt(
  ServiceKey service,
  ConnectionReach reach, {
  required Duration timeout,
  required HostReach hostReach,
}) async {
  final base = UrlUtils.normalizeBaseUrl(reach.url);
  final uri = Uri.tryParse(base);
  if (base.isEmpty || uri == null || uri.host.isEmpty) return false;

  final plan = knockPlanOf(service, base);
  if (plan == null) {
    return hostReach(uri).timeout(timeout, onTimeout: () => false);
  }

  final dio = guardedDio(
    baseUrl: base,
    certFingerprint: reach.pin,
    accessHeaders: reach.access.headers(),
    reportUnreached: false,
  );
  dio.options
    ..connectTimeout = timeout
    ..receiveTimeout = timeout
    ..sendTimeout = timeout;
  try {
    final response = await dio
        .get<String>(
          plan.path,
          queryParameters: plan.query.isEmpty ? null : plan.query,
          options: Options(
            responseType: ResponseType.plain,
            validateStatus: (_) => true,
            headers: plan.headers.isEmpty ? null : plan.headers,
          ),
        )
        .timeout(timeout);
    final status = response.statusCode ?? 0;
    // A redirect is a gateway's sign-in page or a captive portal, never the
    // service's own answer to these routes.
    if (status >= 300 && status < 400) return false;
    return plan.answers((
      status: status,
      headers: response.headers.map,
      body: response.data ?? '',
    ));
  } catch (_) {
    return false;
  } finally {
    dio.close(force: true);
  }
}

bool _statusOk(KnockAnswer answer) {
  final json = _json(answer);
  return answer.status == 200 && json is Map && json['status'] == 'OK';
}

bool _identifies(ServiceKey service, KnockAnswer answer) {
  if (answer.status != 200) return false;
  final json = _json(answer);
  return json != null && identifyProbeAnswer(service, json) is ProbeMatches;
}

Object? _json(KnockAnswer answer) {
  try {
    return jsonDecode(answer.body);
  } on FormatException {
    return null;
  }
}

String? _header(KnockAnswer answer, String name) {
  final lower = name.toLowerCase();
  for (final MapEntry(:key, :value) in answer.headers.entries) {
    if (key.toLowerCase() == lower && value.isNotEmpty) return value.join(',');
  }
  return null;
}

/// [path], an absolute path from [url]'s origin, as a whole URL.
String _onOrigin(String url, String path) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) return path;
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: path,
  ).toString();
}
