import 'package:cupola/features/settings/domain/connection_access.dart';

/// One way to reach a connection's server: an address, and what the gateway
/// in front of that address asks for.
///
/// A connection has its address at home (`ServiceInstance.url` and
/// `ServiceInstance.access`) and may have a second one for away from home
/// (`ServiceInstance.away`), usually behind a tunnel or a reverse proxy, which
/// is why the access travels with the address rather than with the
/// connection: the gateway that asks for a token stands in front of the
/// address away, and the server at home answers without one.
///
/// **Never printed with a value.** [toString] names the address and the kind
/// of access, never what the access sends.
final class ConnectionAddress {
  const ConnectionAddress({required this.url, this.access = const NoAccess()});

  final String url;

  /// What this address's gateway asks for; [NoAccess] when nothing does.
  final ConnectionAccess access;

  ConnectionAddress copyWith({String? url, ConnectionAccess? access}) =>
      ConnectionAddress(url: url ?? this.url, access: access ?? this.access);

  @override
  bool operator ==(Object other) =>
      other is ConnectionAddress && other.url == url && other.access == access;

  @override
  int get hashCode => Object.hash(url, access);

  @override
  String toString() => 'ConnectionAddress("$url", access: ${access.kind.name})';
}

/// Which of a connection's addresses the app reaches it at.
///
/// [home] for every connection without an address away, whatever is stored:
/// the route says which address answered last, and a connection with one
/// address has nothing to choose.
enum ConnectionRoute {
  /// The address the connection was saved with.
  home,

  /// The address away from home, because the one at home did not answer.
  away,
}
