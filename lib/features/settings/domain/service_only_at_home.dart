import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// A request to [service] while the app is away from home, for a connection
/// with no address away: refused before it was sent.
///
/// The error of every request such a client makes (`OnlyAtHomeRefusal`, which
/// `guardedDio` installs first), and of the TrueNAS and Dockge connections,
/// which refuse to open. The client is still built: refusing at the request
/// is what keeps every reader that copes with a server that is down coping
/// with this too, where a client that refused to build took an aggregate of
/// eight queues down for one Lidarr. A server reached only on the home
/// network is a setup, not a fault: asking its address from elsewhere costs a
/// timeout to learn what the route already says, and reading the silence as
/// `Did not answer` paints red what nobody could have reached (Q1, 13/10).
/// Recognised through its [reason], [ServiceFailureReason.onlyAtHome]:
/// neutral, `Only at home`, with `Add an address away` as its remedy.
///
/// [toString] is a marker for logs and tests, never drawn.
class ServiceOnlyAtHome implements Exception, HasFailureReason {
  const ServiceOnlyAtHome(this.service);

  /// The service whose connection is reached only at home.
  final ServiceKey service;

  @override
  ServiceFailureReason get reason => ServiceFailureReason.onlyAtHome;

  @override
  String toString() => '${service.title} only at home';
}
