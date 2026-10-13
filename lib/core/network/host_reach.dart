import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether a connection to [url]'s host and port opens: the question a probe
/// that ran out of time asks before it says anything.
///
/// A probe's own deadline cannot tell a host that is not there from one that
/// took the connection and never replied: both are a timer that fired. The
/// first is red, `did not answer`; the second is a server reached and stuck,
/// amber, and the remedy is the server rather than the network. One plain
/// TCP connection settles it, and it is asked only when the deadline has
/// already passed, so a server that answers costs nothing.
typedef HostReach = Future<bool> Function(Uri url);

/// How long the connection may take to open before the host counts as not
/// there.
const hostReachTimeout = Duration(seconds: 2);

/// Opens a TCP connection to [url]'s host and port (the scheme's own when it
/// names none) and closes it at once; false when it does not open within
/// [hostReachTimeout], or [url] names no host.
Future<bool> tcpHostReach(Uri url) async {
  if (url.host.isEmpty) return false;
  try {
    final socket = await Socket.connect(
      url.host,
      url.port,
      timeout: hostReachTimeout,
    );
    socket.destroy();
    return true;
  } catch (_) {
    return false;
  }
}

/// The app's [HostReach]. A test hands it one that opens no socket.
final hostReachProvider = Provider<HostReach>((ref) => tcpHostReach);
