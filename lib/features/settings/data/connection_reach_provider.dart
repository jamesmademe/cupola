import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_address.dart';
import 'package:cupola/features/settings/domain/connection_reach.dart';
import 'package:cupola/features/settings/domain/connection_unanswered.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

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

/// The connections with an address away at which neither address answered
/// the route probe's last knock, by id: the phone is offline, or the server
/// is down.
///
/// Kept by the route probe alone: a connection joins when both knocks go
/// unanswered and leaves as soon as either address answers one. Not
/// remembered across launches: the probe knocks again at start. What makes
/// a connection that did not answer say so of both addresses
/// ([ServiceFailureReason.unreachableAtBoth]): its readouts
/// (`diagnoseSavedInstance`) and every request of its clients
/// (`UnansweredMark`). Read through [unansweredConnectionProvider], which
/// crosses it with the connections that still have an address away.
final unansweredConnectionsProvider =
    NotifierProvider<UnansweredConnectionsNotifier, Set<String>>(
      UnansweredConnectionsNotifier.new,
    );

class UnansweredConnectionsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  /// Neither of connection [id]'s addresses answered.
  void mark(String id) {
    if (state.contains(id)) return;
    state = {...state, id};
  }

  /// One of connection [id]'s addresses answered.
  void clear(String id) {
    if (!state.contains(id)) return;
    state = {...state}..remove(id);
  }
}

/// Where nothing answered for connection [id], as its red names it, or null
/// while it is not unanswered at both addresses (or no longer has an address
/// away).
final unansweredConnectionProvider =
    Provider.family<ConnectionUnanswered?, String>((ref, id) {
      final unanswered = ref.watch(
        unansweredConnectionsProvider.select((ids) => ids.contains(id)),
      );
      if (!unanswered) return null;
      return ref.watch(
        currentSettingsProvider.select((s) {
          final instance = s.instanceById(id);
          return instance == null ? null : connectionUnansweredOf(instance);
        }),
      );
    });

/// Every unanswered connection's two addresses and what its red names: what
/// `CupolaApp` hands `UnansweredAddresses`, for the clients.
final unansweredAddressesProvider =
    Provider<List<({List<String> urls, ConnectionUnanswered unanswered})>>((
      ref,
    ) {
      final ids = ref.watch(unansweredConnectionsProvider);
      if (ids.isEmpty) return const [];
      final settings = ref.watch(currentSettingsProvider);
      return [
        for (final id in ids)
          if (settings.instanceById(id) case final instance?)
            if (connectionUnansweredOf(instance) case final unanswered?)
              (
                urls: [instance.url, instance.away!.url],
                unanswered: unanswered,
              ),
      ];
    });

/// What [instance]'s red names when neither of its addresses answers: its two
/// addresses as a row shows them, or null when it has no address away.
ConnectionUnanswered? connectionUnansweredOf(ServiceInstance instance) {
  final away = instance.away?.url ?? '';
  if (away.trim().isEmpty) return null;
  final service = instance.service;
  return ConnectionUnanswered(
    home: service.extractHost(instance.url) ?? instance.url,
    away: service.extractHost(away) ?? away,
  );
}

/// Whether the app is away from home: at least one connection moved to its
/// address away because the one at home did not answer.
///
/// What makes a connection with no address away read `Only at home` instead
/// of `Did not answer`, and never asked meanwhile (`OnlyAtHomeRefusal`). False
/// while no connection has an address away: without one the app cannot tell
/// away from a server that is down, and says what it said before (spec 3.3).
/// The routes are read only then, so a container that stands up no
/// preferences (most tests) never reads them; they are crossed with the
/// connections that still have an address away, because the map can keep
/// the id of one removed, or whose address away was taken off. Remembered
/// routes count: a cold start away is away before any probe confirms it.
final awayFromHomeProvider = Provider<bool>((ref) {
  final withAway = ref.watch(
    currentSettingsProvider.select(
      (s) => [
        for (final instance in s.instances)
          if (instance.away?.url.trim().isNotEmpty ?? false) instance.id,
      ].join(' '),
    ),
  );
  if (withAway.isEmpty) return false;
  final ids = withAway.split(' ');
  return ref.watch(
    connectionRoutesProvider.select(
      (routes) => ids.any((id) => routes[id] == ConnectionRoute.away),
    ),
  );
});

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
