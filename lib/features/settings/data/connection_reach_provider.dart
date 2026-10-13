import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_address.dart';
import 'package:cupola/features/settings/domain/connection_reach.dart';

/// Which address each connection is reached at, by id: [ConnectionRoute.away]
/// for the ones whose address at home did not answer, absent for the rest.
///
/// Remembered across launches (`SettingsService.loadConnectionRoutes`), so a
/// cold start away from home reaches the address that answered last at once,
/// and the probe that checks it runs behind the first frame rather than in
/// front of it. Moved only by the route probe, never by a screen.
final connectionRoutesProvider =
    NotifierProvider<ConnectionRoutesNotifier, Map<String, ConnectionRoute>>(
      ConnectionRoutesNotifier.new,
    );

class ConnectionRoutesNotifier extends Notifier<Map<String, ConnectionRoute>> {
  @override
  Map<String, ConnectionRoute> build() =>
      ref.read(settingsServiceProvider).loadConnectionRoutes();

  /// Puts connection [id] on [route], and remembers it for next launch.
  Future<void> set(String id, ConnectionRoute route) async {
    if ((state[id] ?? ConnectionRoute.home) == route) return;
    final updated = {...state};
    if (route == ConnectionRoute.home) {
      updated.remove(id);
    } else {
      updated[id] = route;
    }
    state = updated;
    await ref.read(settingsServiceProvider).saveConnectionRoutes(updated);
  }
}

/// The route connection [id] is on: [ConnectionRoute.home] for one without
/// an address away, whatever is remembered for its id, so a connection with
/// one address never watches the routes at all.
ConnectionRoute watchConnectionRoute(
  Ref ref,
  String id, {
  required bool hasAway,
}) {
  if (!hasAway) return ConnectionRoute.home;
  return ref.watch(
    connectionRoutesProvider.select(
      (routes) => routes[id] ?? ConnectionRoute.home,
    ),
  );
}

/// The route connection [id] is on ([watchConnectionRoute]), for a reader
/// that holds the connection by its id and is not a provider of its own: a
/// screen keying its pictures, a selector closing over it.
///
/// Watches the routes only for a connection that has an address away, so a
/// container that stands up no preferences (most tests) never reads them.
final connectionRouteProvider = Provider.family<ConnectionRoute, String>((
  ref,
  id,
) {
  final hasAway = ref.watch(
    currentSettingsProvider.select((s) => s.instanceById(id)?.away != null),
  );
  return watchConnectionRoute(ref, id, hasAway: hasAway);
});

/// Where a request to connection [id] goes now ([reachOf]), or null when no
/// connection has that id.
///
/// For the readers that hold a connection rather than a service: a picture,
/// a link, a client built for one named connection. Narrow on purpose: it
/// changes when this connection's address, access or pin does, or when its
/// route moves, and for nothing else.
///
/// Read rather than watched where a request is sent once (a link opened, a
/// sign-out): the address that answers now is the one to send it to.
final connectionReachProvider = Provider.family<ConnectionReach?, String>((
  ref,
  id,
) {
  final route = ref.watch(connectionRouteProvider(id));
  return ref.watch(
    currentSettingsProvider.select((s) {
      final instance = s.instanceById(id);
      return instance == null ? null : reachOf(s, instance, route);
    }),
  );
});
