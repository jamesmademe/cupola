import 'package:cupola/core/network/found_address.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// One Radarr or Sonarr server Seerr sends requests to, as Seerr's own
/// settings describe it (`GET /api/v1/settings/radarr|sonarr`).
///
/// The settings route rather than `/api/v1/service/*`, which a requester may
/// read too: only the settings say **where** the server is and with which
/// key, and those are how Cupola tells a server it also connects to from one
/// known only to Seerr. The route is admin-only: the API key reads it, and so
/// does an account with ADMIN; any other account is refused.
///
/// The settings carry each server's API key as well. It is held for one
/// thing, telling which of Cupola's connections the server is ([reaches]),
/// and compared in memory there: no getter hands it out and nothing prints
/// it. Setting a server up from Seerr reads it through `SeerrKnownArr`.
class SeerrArrServer {
  const SeerrArrServer({
    required this.service,
    required this.id,
    required this.name,
    this.is4k = false,
    this.isDefault = false,
    this.activeProfileId,
    this.activeProfileName,
    this.activeDirectory,
    this.hostname,
    this.port,
    this.baseUrl = '',
    this.seenFrom,
    String? apiKey,
  }) : _apiKey = apiKey;

  /// [service] is the kind the list was read for: Seerr's settings say
  /// nothing about it, the route does. [seenFrom] is the address Cupola read
  /// the settings at, the Seerr connection's own.
  factory SeerrArrServer.fromSettingsJson(
    Map<String, dynamic> json, {
    required ServiceKey service,
    String? seenFrom,
  }) {
    return SeerrArrServer(
      service: service,
      id: intOrNull(json['id']) ?? 0,
      name: stringOrNull(json['name'])?.trim() ?? '',
      is4k: boolOrFalse(json['is4k']),
      isDefault: boolOrFalse(json['isDefault']),
      activeProfileId: intOrNull(json['activeProfileId']),
      activeProfileName: stringOrNull(json['activeProfileName']),
      activeDirectory: stringOrNull(json['activeDirectory']),
      hostname: stringOrNull(json['hostname']),
      port: intOrNull(json['port']),
      baseUrl: stringOrNull(json['baseUrl']) ?? '',
      seenFrom: stringOrNull(seenFrom),
      apiKey: stringOrNull(json['apiKey']),
    );
  }

  /// [ServiceKey.radarr] or [ServiceKey.sonarr].
  final ServiceKey service;

  /// Seerr's own id for the server, which a request's `serverId` and a media
  /// row's `serviceId`/`serviceId4k` name.
  final int id;

  /// What the Seerr admin called it, e.g. `Radarr 4K`. May be empty.
  final String name;

  /// The server takes 4K requests: Seerr files what it fetches on the 4K copy
  /// of the title.
  final bool is4k;

  /// The server a request of its resolution goes to when it names none.
  final bool isDefault;

  final int? activeProfileId;
  final String? activeProfileName;
  final String? activeDirectory;

  final String? hostname;
  final int? port;

  /// The path Seerr reaches the server under, e.g. `/radarr`. Empty for none.
  final String baseUrl;

  /// The address Cupola reaches the Seerr these settings came from at, or
  /// null when whoever read them did not say. A host only that Seerr resolves
  /// (a container name, `localhost`) is looked for on this address's host.
  final String? seenFrom;

  /// The key Seerr reaches the server with, or null. Compared, never handed
  /// out: see the class comment.
  final String? _apiKey;

  /// Whether [instance] is a connection to this same server.
  ///
  /// - **The same key** is the same server, wherever each side reaches it: a
  ///   key names one instance.
  /// - **The same address**: host, port and base path, the scheme left out
  ///   since one port does not speak both. Seerr and Cupola reaching one
  ///   address reach one server, whatever key each holds.
  /// - **A host only Seerr resolves** (a container name, `localhost`; see
  ///   `foundHostIsLocalToSource`) is looked for at Seerr's own host with the
  ///   port Seerr knows, the proposal `proposeFoundAddress` makes. A
  ///   proposal and nothing more: a connection there whose key differs from
  ///   the one Seerr uses is another server. Docker republishing Radarr 4K's
  ///   7878 as 7879 puts the other Radarr at that address.
  ///
  /// Never the name: a name is whatever each side chose to call it.
  bool reaches(ServiceInstance instance) {
    if (instance.service != service) return false;
    final key = _keyAgreesWith(instance);
    if (key == true) return true;
    final host = _host(hostname);
    final port = this.port;
    if (host == null || port == null) return false;
    if (_isAt(instance, host: host, port: port, path: baseUrl)) return true;
    if (key == false) return false;

    final source = seenFrom;
    if (source == null) return false;
    final String reported;
    try {
      reported = Uri(scheme: 'http', host: host, port: port).toString();
    } on FormatException {
      return false;
    }
    final proposal = proposeFoundAddress(reported, sourceUrl: source);
    if (proposal == null || proposal.basis != FoundAddressBasis.sourceHost) {
      return false;
    }
    final at = Uri.parse(proposal.url);
    return _isAt(instance, host: at.host, port: at.port, path: baseUrl);
  }

  /// The configured connection among [connections] that is this server, or
  /// null when Cupola has no connection to it.
  ///
  /// A connection holding the key Seerr uses comes first, before any address
  /// matches: of two Radarrs both answering near Seerr's own host, the key
  /// says which one this is.
  ServiceInstance? connectionIn(Iterable<ServiceInstance> connections) {
    final configured = [
      for (final connection in connections)
        if (connection.isConfigured) connection,
    ];
    for (final connection in configured) {
      if (connection.service == service && _keyAgreesWith(connection) == true) {
        return connection;
      }
    }
    for (final connection in configured) {
      if (reaches(connection)) return connection;
    }
    return null;
  }

  /// True when [instance] holds the key Seerr uses for this server, false
  /// when both hold one and they differ, null when either holds none.
  bool? _keyAgreesWith(ServiceInstance instance) {
    final ours = _apiKey?.trim() ?? '';
    final theirs = instance.credential.trim();
    if (ours.isEmpty || theirs.isEmpty) return null;
    return ours == theirs;
  }

  /// Whether [instance] is reached at [host], [port] and [path].
  static bool _isAt(
    ServiceInstance instance, {
    required String host,
    required int port,
    required String path,
  }) {
    final normalized = UrlUtils.normalizeBaseUrl(instance.url);
    if (normalized.isEmpty) return false;
    final uri = Uri.tryParse(normalized);
    if (uri == null || uri.host.isEmpty) return false;
    final theirPort = uri.hasPort
        ? uri.port
        : (uri.scheme.toLowerCase() == 'http' ? 80 : 443);

    return uri.host.toLowerCase() == host.toLowerCase() &&
        theirPort == port &&
        _path(uri.path) == _path(path);
  }

  /// A hostname as Seerr stores it, bare; tolerating a scheme or a path a
  /// hand-edited settings file may carry.
  static String? _host(String? raw) {
    var text = raw?.trim().toLowerCase() ?? '';
    if (text.isEmpty) return null;
    final scheme = text.indexOf('://');
    if (scheme >= 0) text = text.substring(scheme + 3);
    final slash = text.indexOf('/');
    if (slash >= 0) text = text.substring(0, slash);
    final colon = text.lastIndexOf(':');
    if (colon > 0 && !text.contains(']')) text = text.substring(0, colon);
    return text.isEmpty ? null : text;
  }

  static String _path(String raw) {
    var text = raw.trim().toLowerCase();
    while (text.startsWith('/')) {
      text = text.substring(1);
    }
    while (text.endsWith('/')) {
      text = text.substring(0, text.length - 1);
    }
    return text;
  }
}

/// The server Seerr sends a request to, chosen the way Seerr chooses it when
/// the request is approved (`MediaRequestSubscriber` in `seerr-team/seerr`):
/// the default server of the request's resolution, unless the request names
/// another by [serverId]. Null when there is no such server, and Seerr then
/// sends the request nowhere.
SeerrArrServer? seerrTargetServer(
  List<SeerrArrServer> servers, {
  required int? serverId,
  required bool is4k,
}) {
  var target = servers.where((s) => s.isDefault && s.is4k == is4k).firstOrNull;
  if (serverId != null && serverId >= 0 && target?.id != serverId) {
    target = servers.where((s) => s.id == serverId).firstOrNull;
  }
  return target;
}

/// Where approving a request sends it.
///
/// Read from the request's own `serverId`, `profileId`, `rootFolder` and
/// `is4k`, against Seerr's list of servers, and against the connections
/// Cupola has: a server Cupola also connects to and a server known only to
/// Seerr are not the same promise, and approving used to treat them as one.
class SeerrApproveTarget {
  const SeerrApproveTarget({
    required this.arr,
    required this.is4k,
    required this.serversRead,
    this.server,
    this.connection,
    this.profileId,
    this.rootFolder,
  });

  /// [servers] is Seerr's list for the request's kind, or null when it could
  /// not be read; [connections] the connections Cupola has.
  factory SeerrApproveTarget.of(
    SeerrRequest request, {
    required List<SeerrArrServer>? servers,
    Iterable<ServiceInstance> connections = const [],
  }) {
    final arr = request.type == 'tv' ? ServiceKey.sonarr : ServiceKey.radarr;
    final server = servers == null
        ? null
        : seerrTargetServer(
            servers,
            serverId: request.serverId,
            is4k: request.is4k,
          );
    final ownFolder = request.rootFolder?.trim();
    return SeerrApproveTarget(
      arr: arr,
      is4k: request.is4k,
      serversRead: servers != null,
      server: server,
      connection: server?.connectionIn(
        connections.where((connection) => connection.service == arr),
      ),
      // What Seerr sends when the request carries none of its own.
      profileId: request.profileId ?? server?.activeProfileId,
      rootFolder: ownFolder != null && ownFolder.isNotEmpty
          ? ownFolder
          : server?.activeDirectory,
    );
  }

  /// Radarr for a movie, Sonarr for a series.
  final ServiceKey arr;
  final bool is4k;

  /// Seerr's server list was read. Without it [server] is unknown rather
  /// than absent.
  final bool serversRead;

  /// The server the request goes to; null when [serversRead] is false, or
  /// when Seerr has none for it.
  final SeerrArrServer? server;

  /// The connection in Cupola to [server], or null when the server is known
  /// only to Seerr.
  final ServiceInstance? connection;

  /// The quality profile and folder the request is sent with.
  final int? profileId;
  final String? rootFolder;

  /// Seerr answered with its servers, and none would take the request.
  bool get hasNoServer => serversRead && server == null;

  /// `4K Radarr`, `Sonarr`: the kind of server, when there is no name for it.
  String get _kind => is4k ? '4K ${arr.title}' : arr.title;

  /// What a row says once the request is approved: where Seerr sent it,
  /// `Approved · sent to Radarr 4K`, named as [confirmation] names it.
  String approvedLine({
    required String Function(ServiceInstance connection) connectionTitle,
  }) {
    final server = this.server;
    final connection = this.connection;
    final to = connection != null
        ? connectionTitle(connection)
        : server != null
        ? (server.name.isEmpty ? "Seerr's $_kind" : server.name)
        : serversRead
        ? null
        : "Seerr's $_kind";
    if (to == null) return 'Approved\u00A0· Seerr has no $_kind for it';
    return 'Approved\u00A0· sent to $to';
  }

  /// What the approve confirmation says about where [title] goes.
  ///
  /// [connectionTitle] names a connection the way the rest of the app does
  /// in a sentence (`SettingsModel.connectionTitle` with a space joiner):
  /// `Radarr` while there is one, `Radarr 4K` or `Radarr 1` once there are
  /// two. A server Cupola has no connection to goes by
  /// Seerr's name for it, and a second sentence says Cupola has no
  /// connection to it.
  String confirmation(
    String title, {
    required String Function(ServiceInstance connection) connectionTitle,
  }) {
    final server = this.server;
    final connection = this.connection;
    if (connection != null) {
      return '$title goes to ${connectionTitle(connection)} and starts '
          'downloading.';
    }
    if (server != null) {
      final name = server.name.isEmpty ? "Seerr's $_kind" : server.name;
      // "Connected" is on the brand book's Never list; a connection is
      // the word Settings uses for what Cupola has.
      return '$title goes to $name and starts downloading. Cupola has no '
          'connection to that server.';
    }
    if (serversRead) {
      return 'Seerr has no $_kind to send $title to, so nothing will '
          'download.';
    }
    return "$title goes to Seerr's $_kind and starts downloading.";
  }
}
