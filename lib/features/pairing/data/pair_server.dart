import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:cupola/features/pairing/domain/pair_cipher.dart';
import 'package:cupola/features/pairing/domain/pair_link.dart';

/// Lists this device's network interfaces. Injectable so a test can stand a
/// server on loopback; the real one is [NetworkInterface.list].
typedef InterfaceLister = Future<List<NetworkInterface>> Function();

/// This device's address on its home network, where a pairing server can
/// stand, or null when it has none: no Wi-Fi, or only a cellular or VPN one.
///
/// An IPv4 address of a home network ([PairLink.isPairHost]) on an interface
/// that is the device's own link to it: never a cellular one (`pdp_ip`,
/// `rmnet`), a VPN tunnel (`utun`, `wg`, `tailscale`), or a bridge a virtual
/// machine or a container hangs off (`bridge100`, `docker0`, `vEthernet`).
/// The Wi-Fi interface first (`en0`, `wlan0`), then any wired one.
Future<InternetAddress?> pairingAddress({InterfaceLister? interfaces}) async {
  final List<NetworkInterface> list;
  try {
    list = await (interfaces ?? _ipv4Interfaces)();
  } on SocketException {
    return null;
  }
  InternetAddress? best;
  var bestRank = 1 << 30;
  for (final interface in list) {
    final name = interface.name.toLowerCase();
    if (_notTheHomeNetwork.any(name.startsWith)) continue;
    for (final address in interface.addresses) {
      if (address.isLoopback || !PairLink.isPairHost(address)) continue;
      final rank = _rank(name);
      if (rank < bestRank) {
        best = address;
        bestRank = rank;
      }
    }
  }
  return best;
}

Future<List<NetworkInterface>> _ipv4Interfaces() =>
    NetworkInterface.list(type: InternetAddressType.IPv4);

const _notTheHomeNetwork = [
  'pdp_ip', 'rmnet', 'ccmni', // cellular: iOS, Android
  'utun', 'ipsec', 'ppp', 'tun', 'tap', 'wg', 'tailscale', 'zt', // VPNs
  'bridge', 'vmnet', 'vboxnet', 'docker', 'br-', 'veth', 'vethernet', // VMs
  'awdl', 'llw', 'anpi', // Apple's peer-to-peer links
];

int _rank(String name) {
  if (name == 'en0' || name == 'wlan0') return 0;
  if (name.startsWith('wl') || name.startsWith('wi-fi')) return 1;
  if (name.startsWith('en') || name.startsWith('eth')) return 2;
  return 3;
}

/// How a pairing server ended.
enum PairServerEnd {
  /// The package went out whole, once.
  sent,

  /// Its two minutes passed.
  expired,

  /// Someone asked for anything but the one path, three times.
  refused,

  /// The person closed it, or left the screen.
  closed,
}

/// The server one device opens for another to copy it: on its home network
/// address, a port the system picks, one path, one package, once.
///
/// It answers `GET` on the path [PairCipher.pathOf] derives from the link's
/// key with the sealed package, and anything else with a 404. It closes on
/// the first package sent whole, when [lifetime] is up, after
/// [maxWrongTries] wrong requests, or on [close]: a code is good for one copy
/// within two minutes, and a neighbour guessing at paths gets three tries.
final class PairServer {
  PairServer._(this._server, this.link, this._path, this._sealed);

  /// Opens a server at [address] for [sealed], under [key]; [invite] when
  /// what is sealed is an invite shown in person, which its link says.
  static Future<PairServer> open({
    required InternetAddress address,
    required Uint8List key,
    required Uint8List sealed,
    bool invite = false,
    Duration lifetime = const Duration(minutes: 2),
    int maxWrongTries = 3,
    DateTime Function() now = DateTime.now,
  }) async {
    final path = await PairCipher.pathOf(key);
    final server = await HttpServer.bind(address, 0);
    server
      ..autoCompress = false
      ..idleTimeout = const Duration(seconds: 10)
      ..serverHeader = null;
    final pair = PairServer._(
      server,
      PairLink(
        host: address,
        port: server.port,
        key: key,
        closesAt: now().add(lifetime),
        invite: invite,
      ),
      path,
      sealed,
    );
    pair
      .._maxWrongTries = maxWrongTries
      .._timer = Timer(lifetime, () => pair._end(PairServerEnd.expired));
    server.listen(pair._answer, onError: (Object _) {});
    return pair;
  }

  final HttpServer _server;
  final String _path;
  final Uint8List _sealed;
  late final int _maxWrongTries;
  late final Timer _timer;
  var _wrongTries = 0;

  /// The link the code on the screen holds.
  final PairLink link;

  /// How it ended, or null while it is open.
  ValueListenable<PairServerEnd?> get ended => _ended;
  final _ended = ValueNotifier<PairServerEnd?>(null);

  /// Closes it now, if it is still open.
  Future<void> close() => _end(PairServerEnd.closed);

  Future<void> _answer(HttpRequest request) async {
    final response = request.response;
    try {
      if (_ended.value != null) {
        response.statusCode = HttpStatus.gone;
        await response.close();
        return;
      }
      if (request.method == 'GET' && _samePath(request.uri.path, _path)) {
        response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.binary
          ..headers.set(HttpHeaders.cacheControlHeader, 'no-store')
          ..contentLength = _sealed.length
          ..add(_sealed);
        await response.close();
        await _end(PairServerEnd.sent);
        return;
      }
      response.statusCode = HttpStatus.notFound;
      await response.close();
      if (++_wrongTries >= _maxWrongTries) await _end(PairServerEnd.refused);
    } on Object {
      // The other side went away mid-answer: the package was not sent whole,
      // so the code stays good for another try.
    }
  }

  Future<void> _end(PairServerEnd how) async {
    if (_ended.value != null) return;
    _ended.value = how;
    _timer.cancel();
    await _server.close(force: true);
  }

  /// Compares in time that does not depend on where the paths differ.
  static bool _samePath(String a, String b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var i = 0; i < a.length; i++) {
      difference |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return difference == 0;
  }

  @override
  String toString() => 'PairServer(${link.authority}, ${_ended.value})';
}
