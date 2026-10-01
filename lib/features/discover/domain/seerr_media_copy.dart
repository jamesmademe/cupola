import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/features/discover/domain/seerr_arr_server.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// One copy of a title that an arr holds for Seerr: which of Seerr's servers
/// it is on, and its id there.
///
/// Seerr's media row keeps the two copies apart: `serviceId` and
/// `externalServiceId` for the standard one, `serviceId4k` and
/// `externalServiceId4k` for the 4K one. Manage used to read
/// `externalServiceId` alone, so a title only in 4K had no Media section, and
/// "Remove from Radarr" on a title in both removed the standard copy whichever
/// the person meant.
class SeerrMediaCopy {
  const SeerrMediaCopy({
    required this.is4k,
    required this.externalId,
    this.serverId,
  });

  final bool is4k;

  /// The item's id on the server that holds it: a Radarr movie id or a Sonarr
  /// series id.
  final int externalId;

  /// Seerr's id of that server, or null when the row does not say (Seerr then
  /// means the default server of the copy).
  final int? serverId;

  /// The copies [mediaInfo] says an arr holds, the standard one first.
  static List<SeerrMediaCopy> fromMediaInfo(Map<String, dynamic>? mediaInfo) {
    final standard = intOrNull(mediaInfo?['externalServiceId']);
    final uhd = intOrNull(mediaInfo?['externalServiceId4k']);
    return [
      if (standard != null)
        SeerrMediaCopy(
          is4k: false,
          externalId: standard,
          serverId: intOrNull(mediaInfo?['serviceId']),
        ),
      if (uhd != null)
        SeerrMediaCopy(
          is4k: true,
          externalId: uhd,
          serverId: intOrNull(mediaInfo?['serviceId4k']),
        ),
    ];
  }
}

/// A copy bound to the server Seerr keeps it on, and to Cupola's connection
/// to that server when there is one.
class SeerrBoundCopy {
  const SeerrBoundCopy({
    required this.copy,
    required this.arr,
    required this.serversRead,
    this.server,
    this.connection,
  });

  /// [servers] is Seerr's list of [arr] servers, null when it was not read;
  /// [connections] the connections Cupola has. The server is found the way
  /// Seerr finds it when it removes the files (`DELETE /media/{id}/file`): the
  /// row's own server id, else the default server of the copy.
  factory SeerrBoundCopy.of(
    SeerrMediaCopy copy, {
    required ServiceKey arr,
    required List<SeerrArrServer>? servers,
    Iterable<ServiceInstance> connections = const [],
  }) {
    final server = servers == null
        ? null
        : seerrTargetServer(servers, serverId: copy.serverId, is4k: copy.is4k);
    return SeerrBoundCopy(
      copy: copy,
      arr: arr,
      serversRead: servers != null,
      server: server,
      connection: server?.connectionIn(
        connections.where((connection) => connection.service == arr),
      ),
    );
  }

  final SeerrMediaCopy copy;

  /// Radarr or Sonarr.
  final ServiceKey arr;

  /// Seerr's server list was read; without it [server] is unknown.
  final bool serversRead;
  final SeerrArrServer? server;

  /// Cupola's connection to [server], or null.
  final ServiceInstance? connection;

  /// The server is known, and Cupola has no connection to it.
  bool get isKnownOnlyToSeerr => server != null && connection == null;

  /// What the copy's controls call its server: Cupola's name for the
  /// connection when there is one ([connectionTitle]), else Seerr's name for
  /// the server, else the kind (`Radarr`, `4K Radarr`).
  String serverName({
    required String Function(ServiceInstance connection) connectionTitle,
  }) {
    final connection = this.connection;
    if (connection != null) return connectionTitle(connection);
    final name = server?.name ?? '';
    if (name.isNotEmpty) return name;
    return copy.is4k ? '4K ${arr.title}' : arr.title;
  }
}
