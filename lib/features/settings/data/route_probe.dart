import 'dart:async';

import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/lifecycle/gated_poll.dart';
import 'package:cupola/core/lifecycle/poll_clock.dart';
import 'package:cupola/core/network/unreached_origins.dart';
import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/features/discover/presentation/library_calendar_provider.dart'
    show calendarClockProvider;
import 'package:cupola/features/settings/data/connection_reach_provider.dart';
import 'package:cupola/features/settings/data/route_knock.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_address.dart';
import 'package:cupola/features/settings/domain/connection_reach.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

/// How long the address at home has to answer a knock before the one away
/// wins: a server on the same network answers in a few milliseconds, and a
/// phone away from home should not wait long to learn it is away.
const homeKnockTimeout = Duration(milliseconds: 1500);

/// How long the address away has: it crosses the internet, often a tunnel.
const awayKnockTimeout = Duration(seconds: 6);

/// How often a connection whose address stopped answering is probed again
/// on that account: a screen that retries in a loop must not knock in one.
const unreachedProbeInterval = Duration(seconds: 30);

/// How often the connections away are probed for home while the app is
/// open: the way back home, since the address away usually answers from
/// home too and nothing would fail to say so.
const awayRecheckInterval = Duration(minutes: 5);

/// Which address answers, from two knocks started together: home when it
/// answered, away when only away did, null when neither did.
///
/// Null keeps the route as it is. A connection that answers at neither
/// address is down or out of reach, and its failure says so where it is
/// read; moving it would only change which address the failure names.
Future<ConnectionRoute?> decideRoute({
  required Future<bool> home,
  required Future<bool> away,
}) async {
  if (await home) return ConnectionRoute.home;
  if (await away) return ConnectionRoute.away;
  return null;
}

/// Moves each connection that has an address away from home to the address
/// that answers (`connectionRoutesProvider`).
///
/// Asked at start, when the app comes back to the foreground, when a request
/// to a connection's current address opens no connection
/// ([UnreachedOrigins]), and every [awayRecheckInterval] while a connection
/// is away and the app is on screen. No Wi-Fi name and no location: the knocks themselves say where
/// the phone is. A move is not a fault and is not said: the connection's
/// clients rebuild on the new address, and the screens keep what they last
/// drew while they read again.
///
/// A connection with one address is never knocked on.
class RouteProbe {
  RouteProbe(this._ref);

  final Ref _ref;
  final _inFlight = <String, Future<void>>{};
  final _lastUnreachedProbe = <String, DateTime>{};
  StreamSubscription<String>? _unreached;
  late final GatedPollTimer _recheck;
  var _foreground = true;
  var _disposed = false;

  void _start() {
    _recheck = GatedPollTimer(
      id: 'route.away',
      interval: awayRecheckInterval,
      onTick: () => unawaited(probeAll()),
      clock: _ref.read(pollClockProvider),
    );
    _unreached = UnreachedOrigins.stream.listen(_onUnreached);
    _ref.listen(currentSettingsProvider.select(_awaySignature), (
      previous,
      next,
    ) {
      if (previous != next) unawaited(probeAll());
    });
    scheduleMicrotask(() => unawaited(probeAll()));
  }

  /// Knocks on every connection that has an address away.
  Future<void> probeAll() async {
    if (_disposed) return;
    final settings = _ref.read(currentSettingsProvider);
    await Future.wait([
      for (final instance in settings.instances)
        if (instance.away != null) probe(instance.id),
    ]);
  }

  /// The app came back to the foreground: where it is may have changed.
  void onResume() {
    _foreground = true;
    unawaited(probeAll());
  }

  /// The app left the screen: nothing is rechecked from the background.
  void onHide() {
    _foreground = false;
    _recheck.setLive(false);
  }

  /// Knocks on connection [id]'s two addresses and moves it to the one that
  /// answers; one probe per connection at a time.
  Future<void> probe(String id) =>
      _inFlight[id] ??= _probe(id).whenComplete(() => _inFlight.remove(id));

  Future<void> _probe(String id) async {
    final settings = _ref.read(currentSettingsProvider);
    final instance = settings.instanceById(id);
    if (instance == null || instance.away == null) return;

    final knock = _ref.read(routeKnockProvider);
    final route = await decideRoute(
      home: knock(
        instance.service,
        reachOf(settings, instance, ConnectionRoute.home),
        timeout: homeKnockTimeout,
      ),
      away: knock(
        instance.service,
        reachOf(settings, instance, ConnectionRoute.away),
        timeout: awayKnockTimeout,
      ),
    );
    if (_disposed) return;
    if (route != null) {
      await _ref.read(connectionRoutesProvider.notifier).set(id, route);
    }
    _syncRecheck();
  }

  /// A request to [origin] opened no connection: each connection with an
  /// address away whose current address is there is probed, once per
  /// [unreachedProbeInterval].
  void _onUnreached(String origin) {
    if (_disposed) return;
    final settings = _ref.read(currentSettingsProvider);
    final away = [
      for (final instance in settings.instances)
        if (instance.away != null) instance,
    ];
    if (away.isEmpty) return;

    final routes = _ref.read(connectionRoutesProvider);
    final now = _ref.read(calendarClockProvider)();
    for (final instance in away) {
      final reach = reachOf(
        settings,
        instance,
        routes[instance.id] ?? ConnectionRoute.home,
      );
      final uri = Uri.tryParse(UrlUtils.normalizeBaseUrl(reach.url));
      if (uri == null || UnreachedOrigins.originOf(uri) != origin) continue;
      final last = _lastUnreachedProbe[instance.id];
      if (last != null && now.difference(last) < unreachedProbeInterval) {
        continue;
      }
      _lastUnreachedProbe[instance.id] = now;
      unawaited(probe(instance.id));
    }
  }

  /// Rechecks every [awayRecheckInterval] while a connection is away and
  /// the app is on screen, and not at all otherwise.
  void _syncRecheck() {
    final settings = _ref.read(currentSettingsProvider);
    final routes = _ref.read(connectionRoutesProvider);
    final anyAway = settings.instances.any(
      (instance) =>
          instance.away != null && routes[instance.id] == ConnectionRoute.away,
    );
    _recheck.setLive(anyAway && _foreground);
  }

  /// Whether the periodic recheck is armed: for a test.
  bool get recheckArmed => _recheck.isLive;

  void dispose() {
    _disposed = true;
    unawaited(_unreached?.cancel());
    _recheck.dispose();
  }
}

/// Which connections have an address away, and which: what makes a new
/// probe worth running when the settings change.
String _awaySignature(SettingsModel settings) => [
  for (final instance in settings.instances)
    if (instance.away case final away?)
      '${instance.id} ${instance.url} ${away.url}',
].join('\n');

/// The app's [RouteProbe], started by the app's root and alive for the run.
final routeProbeProvider = Provider<RouteProbe>((ref) {
  final probe = RouteProbe(ref).._start();
  final listener = AppLifecycleListener(
    onResume: probe.onResume,
    onHide: probe.onHide,
  );
  ref.onDispose(() {
    listener.dispose();
    probe.dispose();
  });
  return probe;
});
