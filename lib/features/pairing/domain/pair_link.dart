import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cupola/core/network/local_network_target.dart';

/// Where a new device fetches another device's connections, and the key that
/// opens them: what the code on the sending screen holds.
///
/// `cupola://pair?v=1&h=192.168.1.20:47213&k=<43 characters>&x=<seconds>`:
/// the sending device's address on the home network and the port of the
/// server it opened for this one copy ([host], [port]), 32 random bytes
/// ([key]) that both name the one path the server answers and open what it
/// hands over, and when that server closes ([closesAt]). The link
/// holds no connection and no secret of a connection: it is only good, once,
/// for the two minutes that server stays open, to someone on the same network.
///
/// An invite shown in person adds `&t=invite` ([invite]): what it hands over
/// is one Seerr and what its addresses ask for, not a whole device, and the
/// receiving screen says so before it has fetched anything. The mark is a
/// word, never a secret; the package says the same thing sealed, and the two
/// must agree.
///
/// **Never printed, never routed.** [key] opens every key of the sending
/// device, so [toString] names the address only, and the router takes a link
/// off the location the moment it arrives (`/welcome/pair` holds it in memory).
/// A log, a crash report or a route's history never sees it.
final class PairLink {
  PairLink({
    required this.host,
    required this.port,
    required Uint8List key,
    required DateTime closesAt,
    this.invite = false,
  }) : key = Uint8List.fromList(key),
       closesAt = DateTime.fromMillisecondsSinceEpoch(
         closesAt.millisecondsSinceEpoch ~/ 1000 * 1000,
         isUtc: true,
       ),
       assert(key.length == keyLength, 'a pairing key is $keyLength bytes');

  /// The link's scheme and host: `cupola://pair`.
  static const scheme = 'cupola';
  static const linkHost = 'pair';

  /// The version this build writes and reads. A link of another version is not
  /// read: what it carries may be fetched and opened another way.
  static const version = '1';

  /// The key's length in bytes: 256 bits.
  static const keyLength = 32;

  /// The value of `t` on an invite's link.
  static const inviteMark = 'invite';

  /// The sending device's address on the home network.
  final InternetAddress host;

  /// The port of the server the sending device opened for this copy.
  final int port;

  /// The 32 bytes the path and the package's key are derived from.
  final Uint8List key;

  /// Whether the code is an invite shown in person (`PairPackage.invite`)
  /// rather than a copy of everything.
  final bool invite;

  /// When the sending server closes, to the second.
  ///
  /// What lets the receiving device tell a code that expired from a device it
  /// cannot reach: both end in a connection that fails, and only the clock
  /// says which. Two clocks a few seconds apart are allowed for
  /// ([clockSkew]).
  final DateTime closesAt;

  /// How far apart two devices' clocks may be before [hasClosedBy] guesses
  /// wrong.
  static const clockSkew = Duration(seconds: 30);

  /// Whether the sending server has surely closed by [now].
  bool hasClosedBy(DateTime now) => now.isAfter(closesAt.add(clockSkew));

  /// `192.168.1.20:47213`: what the link says of where it goes.
  String get authority => '${host.address}:$port';

  /// The link as a URI, the key included: for the code on the sending screen
  /// and its Copy link, nowhere else.
  Uri toUri() => Uri(
    scheme: scheme,
    host: linkHost,
    queryParameters: {
      'v': version,
      'h': authority,
      'k': _encodeKey(key),
      'x': '${closesAt.millisecondsSinceEpoch ~/ 1000}',
      if (invite) 't': inviteMark,
    },
  );

  /// [toUri] as text.
  String toLink() => toUri().toString();

  /// Whether [uri] is a pairing link: `cupola://pair?…` as the system hands it
  /// over, or its path once a router has normalised the host away.
  static bool isPairUri(Uri uri) {
    if (uri.scheme == scheme && uri.host == linkHost) return true;
    final bare = uri.path.endsWith('/')
        ? uri.path.substring(0, uri.path.length - 1)
        : uri.path;
    return bare == '/$linkHost' && uri.queryParameters.containsKey('k');
  }

  /// The link a pairing link's query describes, or null when any part of it is
  /// missing or wrong: another version, an address that is not on a home
  /// network, a port out of range, a key that is not 32 bytes, no closing
  /// time, a mark other than an invite's.
  ///
  /// Strict on purpose: the address is where this device is about to connect,
  /// so it has to be one the sending device could have opened a server on,
  /// never a name a crafted code points somewhere else.
  static PairLink? fromQuery(Map<String, String> query) {
    if (query['v'] != version) return null;
    final authority = query['h'];
    final encodedKey = query['k'];
    if (authority == null || encodedKey == null) return null;
    final colon = authority.lastIndexOf(':');
    if (colon <= 0) return null;
    final host = InternetAddress.tryParse(authority.substring(0, colon));
    final port = int.tryParse(authority.substring(colon + 1));
    if (host == null || !isPairHost(host)) return null;
    if (port == null || port < 1024 || port > 65535) return null;
    final key = _decodeKey(encodedKey);
    if (key == null) return null;
    final closes = int.tryParse(query['x'] ?? '');
    if (closes == null || closes <= 0) return null;
    final mark = query['t'];
    if (mark != null && mark != inviteMark) return null;
    return PairLink(
      host: host,
      port: port,
      key: key,
      closesAt: DateTime.fromMillisecondsSinceEpoch(closes * 1000, isUtc: true),
      invite: mark == inviteMark,
    );
  }

  /// The pairing link written in [text], alone or inside a message, or null
  /// when there is none that reads.
  static PairLink? tryParse(String text) {
    final match = RegExp(r'cupola://pair\?[^\s<>"]+').firstMatch(text);
    if (match == null) return null;
    final uri = Uri.tryParse(match.group(0)!);
    if (uri == null || !isPairUri(uri)) return null;
    return fromQuery(uri.queryParameters);
  }

  /// Whether [text] holds something that looks like a pairing link, read or
  /// not: what tells a pasted link that does not read from a pasted address.
  static bool mentionsPair(String text) => text.contains('cupola://pair');

  /// Whether a pairing server can stand at [address]: an IPv4 address of a
  /// home network (10/8, 172.16/12, 192.168/16), or this device itself.
  ///
  /// Never a public address, never a name: the server is opened on the
  /// sending device's own Wi-Fi address and nowhere else, so a link that names
  /// anything else did not come from Cupola. Link-local (169.254/16) is out
  /// too: it is what a device picks when no router answered, and two devices
  /// there are not on a home network.
  static bool isPairHost(InternetAddress address) {
    if (address.type != InternetAddressType.IPv4) return false;
    if (address.isLoopback) return true;
    final bytes = address.rawAddress;
    if (bytes[0] == 169 && bytes[1] == 254) return false;
    return addressIsOnLocalNetwork(address);
  }

  static String _encodeKey(Uint8List key) =>
      base64Url.encode(key).replaceAll('=', '');

  static Uint8List? _decodeKey(String encoded) {
    if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(encoded)) return null;
    try {
      final bytes = base64Url.decode('$encoded=');
      return bytes.length == keyLength ? bytes : null;
    } on FormatException {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is PairLink &&
      other.host == host &&
      other.port == port &&
      other.closesAt == closesAt &&
      other.invite == invite &&
      _sameBytes(other.key, key);

  @override
  int get hashCode =>
      Object.hash(host, port, closesAt, invite, Object.hashAll(key));

  /// The address only, never the key.
  @override
  String toString() => 'PairLink($authority${invite ? ', invite' : ''})';
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var difference = 0;
  for (var i = 0; i < a.length; i++) {
    difference |= a[i] ^ b[i];
  }
  return difference == 0;
}
