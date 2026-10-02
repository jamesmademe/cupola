import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/features/discover/domain/seerr_arr_server.dart';
import 'package:cupola/features/settings/domain/connection_candidate.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// A Radarr or Sonarr that Seerr knows, as its own settings hold it, key
/// included (`GET /api/v1/settings/radarr|sonarr`, which answers
/// `settings.radarr` whole: `server/routes/settings/radarr.ts`).
///
/// The shortest way to set up a household's arrs is to read what its Seerr
/// already knows: where Seerr reaches each one, and the key it reaches it
/// with. [server] is the part the approve and Manage paths already read;
/// this adds the scheme, the key and the browser address beside it.
///
/// The address is Seerr's, not this device's. A Seerr in Docker usually
/// names its arrs by container (`http://radarr:7878`), which nothing outside
/// that network resolves; see `proposeFoundAddress`.
///
/// **The key is a secret.** It is kept, because Seerr already holds it and a
/// found server that works with it needs nothing typed, and it is never
/// printed: [toString] says only whether a key came, and no failure sentence
/// or log line is built from it. `seerr_known_arr_test.dart` proves it with a
/// sentinel.
class SeerrKnownArr {
  const SeerrKnownArr({
    required this.server,
    this.address,
    this.apiKey,
    this.externalUrl,
  });

  /// [service] is the kind the list was read for: Seerr's settings say
  /// nothing about it, the route does.
  factory SeerrKnownArr.fromSettingsJson(
    Map<String, dynamic> json, {
    required ServiceKey service,
  }) {
    final server = SeerrArrServer.fromSettingsJson(json, service: service);
    return SeerrKnownArr(
      server: server,
      address: _address(
        hostname: server.hostname,
        port: server.port,
        useSsl: boolOrFalse(json['useSsl']),
        baseUrl: server.baseUrl,
      ),
      apiKey: stringOrNull(json['apiKey']),
      externalUrl: stringOrNull(json['externalUrl']),
    );
  }

  /// Seerr's id, name, flags, host, port and base path for the server.
  final SeerrArrServer server;

  /// The address Seerr reaches the server at, built as Seerr builds it
  /// (`ServarrBase.buildUrl`: the scheme `useSsl` says, the host, the port,
  /// the base path): `http://radarr:7878`, `https://nas.home.arpa:7879`.
  /// Null when the settings do not say where the server is.
  final String? address;

  /// The key Seerr reaches the server with, or null when its settings hold
  /// none.
  final String? apiKey;

  /// The address the Seerr admin gave for opening the server in a browser
  /// (Seerr's "External URL"), or null. Not where Seerr reaches it, and not
  /// necessarily where the API answers: it can sit behind a sign-in page.
  final String? externalUrl;

  /// [ServiceKey.radarr] or [ServiceKey.sonarr].
  ServiceKey get service => server.service;

  /// What the Seerr admin called it, e.g. `Radarr 4K`. May be empty.
  String get name => server.name;

  bool get is4k => server.is4k;
  bool get isDefault => server.isDefault;

  /// This server as a candidate found through [seerr], the connection it
  /// was read from, with the key Seerr uses. Null when Seerr's settings do
  /// not say where it is.
  ConnectionCandidate? toCandidate(ServiceInstance seerr) {
    assert(seerr.service == ServiceKey.seerr, 'not a Seerr connection');
    final address = this.address;
    if (address == null) return null;
    return ConnectionCandidate(
      service: service,
      name: name,
      reportedUrl: address,
      source: CandidateSource(
        service: seerr.service,
        connectionId: seerr.id,
        url: seerr.url,
      ),
      apiKey: apiKey,
      externalUrl: externalUrl,
      is4k: is4k,
      isDefault: isDefault,
    );
  }

  /// The server, its address, and whether a key came: never the key.
  @override
  String toString() =>
      'SeerrKnownArr(${service.name} ${server.id}, "$name", '
      '${address ?? 'no address'}, key: ${apiKey == null ? 'none' : 'given'})';

  /// `ServarrBase.buildUrl` (`server/api/servarr/base.ts`), tolerating what
  /// a hand-edited settings file may carry: a scheme or a path on the host, a
  /// base path without its leading slash.
  static String? _address({
    required String? hostname,
    required int? port,
    required bool useSsl,
    required String baseUrl,
  }) {
    var host = hostname?.trim() ?? '';
    final scheme = host.indexOf('://');
    if (scheme >= 0) host = host.substring(scheme + 3);
    final slash = host.indexOf('/');
    if (slash >= 0) host = host.substring(0, slash);
    if (host.startsWith('[') && host.endsWith(']')) {
      host = host.substring(1, host.length - 1);
    }
    if (host.isEmpty || port == null || port <= 0 || port > 65535) {
      return null;
    }
    var path = baseUrl.trim();
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    if (path.isNotEmpty && !path.startsWith('/')) path = '/$path';
    try {
      return Uri(
        scheme: useSsl ? 'https' : 'http',
        host: host,
        port: port,
        path: path,
      ).toString();
    } on FormatException {
      return null;
    }
  }
}

/// What Seerr answered when asked which Radarr and Sonarr it knows.
sealed class SeerrKnownArrs {
  const SeerrKnownArrs();
}

/// Seerr answered with its servers, Radarr's first. An empty list means it
/// knows none.
final class SeerrKnownArrsRead extends SeerrKnownArrs {
  const SeerrKnownArrsRead(this.servers);

  final List<SeerrKnownArr> servers;

  @override
  String toString() => 'SeerrKnownArrsRead(${servers.length})';
}

/// The account may not read Seerr's settings: a household member's own
/// session, or any account without ADMIN (`server/routes/index.ts` guards
/// every `/settings` route with `isAuthenticated(Permission.ADMIN)`).
///
/// An answer, not a failure: the server is up and said no. Never an empty
/// list either, which would claim Seerr knows nothing.
final class SeerrKnownArrsNotAllowed extends SeerrKnownArrs {
  const SeerrKnownArrsNotAllowed();

  @override
  String toString() => 'SeerrKnownArrsNotAllowed';
}
