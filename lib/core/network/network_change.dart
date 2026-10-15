import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/lifecycle/gated_poll.dart';
import 'package:cupola/core/lifecycle/poll_clock.dart';

/// How often the phone's own addresses are looked at while the app is on
/// screen: a local read, nothing crosses the network.
const networkLookInterval = Duration(seconds: 3);

/// How long the addresses have to stay put before a change is said: Wi-Fi
/// going away and the mobile network taking over are several changes in a
/// row, and one answer is wanted, after the last. Longer than a look, so two
/// looks in a row that both moved are one change.
const networkSettle = Duration(seconds: 4);

/// When the change is said a second time: a VPN (Tailscale, WireGuard) comes
/// back a few seconds after the network does, and what did not answer
/// through it at the first word answers at the second.
const networkSecondWord = Duration(seconds: 10);

/// The phone's network addresses as one string: it changes when Wi-Fi drops
/// or comes back, when the mobile network takes over, when a VPN goes up.
typedef NetworkAddressesReader = Future<String> Function();

/// Reads the addresses of every interface but loopback and link-local. No
/// Wi-Fi name and no location: which network it is does not matter, only
/// that it changed.
Future<String> readNetworkAddresses() async {
  final interfaces = await NetworkInterface.list();
  final lines = [
    for (final interface in interfaces)
      for (final address in interface.addresses)
        '${interface.name} ${address.address}',
  ]..sort();
  return lines.join('\n');
}

final networkAddressesReaderProvider = Provider<NetworkAddressesReader>(
  (ref) => readNetworkAddresses,
);

/// How many times the phone's network has changed while the app was open:
/// what is watched by everything that has to ask again when it does (the
/// route probe, the connections' readouts). Moved only by
/// [NetworkChangeWatch], which the app's root starts.
final networkChangesProvider = NotifierProvider<NetworkChangesNotifier, int>(
  NetworkChangesNotifier.new,
);

class NetworkChangesNotifier extends Notifier<int> {
  @override
  int build() => 0;

  /// The network changed.
  void changed() => state++;
}

/// Watches the phone's own addresses while the app is on screen and says a
/// change ([networkChangesProvider]) once they settle, then again
/// [networkSecondWord] later.
///
/// Without it a switch between Wi-Fi and the mobile network with the app
/// open is learnt only from a request that fails, and a readout that failed
/// during the switch stays red until someone presses Test all. On return to
/// the foreground the first look compares against the addresses before the
/// app left, so leaving home with the app closed is a change too.
class NetworkChangeWatch {
  NetworkChangeWatch(this._ref);

  final Ref _ref;
  late final GatedPollTimer _look;
  Timer? _settle;
  Timer? _again;
  String? _last;
  var _reading = false;
  var _disposed = false;

  void _start() {
    _look = GatedPollTimer(
      id: 'network.look',
      interval: networkLookInterval,
      onTick: () => unawaited(look()),
      clock: _ref.read(pollClockProvider),
    );
    _look.setLive(true);
    unawaited(look());
  }

  /// Reads the addresses once and says a change when they moved.
  Future<void> look() async {
    if (_disposed || _reading) return;
    _reading = true;
    try {
      final now = await _ref.read(networkAddressesReaderProvider)();
      if (_disposed) return;
      final before = _last;
      _last = now;
      if (before != null && before != now) _moved();
    } on Object {
      // An unreadable look says nothing: the next one reads again.
    } finally {
      _reading = false;
    }
  }

  void _moved() {
    _settle?.cancel();
    _again?.cancel();
    _settle = Timer(networkSettle, () {
      if (_disposed) return;
      _say();
      _again = Timer(networkSecondWord, _say);
    });
  }

  void _say() {
    if (_disposed) return;
    _ref.read(networkChangesProvider.notifier).changed();
  }

  void onResume() {
    _look.setLive(true);
    unawaited(look());
  }

  void onHide() => _look.setLive(false);

  void dispose() {
    _disposed = true;
    _settle?.cancel();
    _again?.cancel();
    _look.dispose();
  }
}

/// The app's [NetworkChangeWatch], started by the app's root and alive for
/// the run.
final networkChangeWatchProvider = Provider<NetworkChangeWatch>((ref) {
  final watch = NetworkChangeWatch(ref).._start();
  final listener = AppLifecycleListener(
    onResume: watch.onResume,
    onHide: watch.onHide,
  );
  ref.onDispose(() {
    listener.dispose();
    watch.dispose();
  });
  return watch;
});
