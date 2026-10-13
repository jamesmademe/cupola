import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/connection_address.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

/// Where a request to a connection goes: the address, what its gateway asks
/// for, and the certificate trusted at its origin. A record, so a `select`
/// over it settles.
typedef ConnectionReach = ({String url, ConnectionAccess access, String? pin});

/// The one answer to "which address reaches [instance] now": the address away
/// when [route] says so and the connection has one, the address at home
/// otherwise.
///
/// Every client, picture and link that reaches a server asks this (through
/// `watchTransport` or `connectionReachProvider`) rather than reading
/// `ServiceInstance.url`, which is the address the connection is saved and
/// known by, not necessarily the one that answers. The pin is the one of the
/// address chosen: a certificate is trusted per origin, and the two
/// addresses are two origins.
ConnectionReach reachOf(
  SettingsModel settings,
  ServiceInstance instance,
  ConnectionRoute route,
) {
  final address = instance.addressOn(route);
  return (
    url: address.url,
    access: address.access,
    pin: settings.pinForUrl(address.url),
  );
}
