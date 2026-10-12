import 'dart:io';

import 'package:cupola/core/utils/url_utils.dart';

/// Whether a service address points at something on the user's own network.
///
/// This exists because the platforms that gate local-network traffic gate it by
/// *destination*, not by app: iOS 14+, macOS 15+ and Android 17+ let an app talk
/// to the internet freely and stop it at the LAN. So a failure only means "the OS
/// is standing in the way" when the address was on the LAN to begin with:
/// without that check, a public Overseerr timing out would raise a Local Network
/// prompt the user cannot make sense of, and a permission the app does not need.
///
/// Deliberately answers from the address alone wherever it can. A DNS lookup is
/// the last resort, not the first move: `nas.local` and a bare `radarr` cannot be
/// resolved at all while access is blocked (mDNS is behind the same gate), so a
/// classifier that needed a lookup would fail exactly in the case it exists for.

/// How [targetIsOnLocalNetwork] resolves a name. Injectable so a test can answer
/// without a resolver: the real one is [InternetAddress.lookup].
typedef HostLookup = Future<List<InternetAddress>> Function(String host);

/// Suffixes that only ever name something on the local network.
///
/// `.local` is mDNS (RFC 6762). `.lan`, `.home`, `.internal` and `.localdomain`
/// are the names home routers and Docker installs hand out: `.internal` is
/// reserved for exactly this by ICANN, and none of the others are delegated, so
/// a name under them cannot be anything but local.
const _localSuffixes = <String>{
  'local',
  'lan',
  'home',
  'internal',
  'localdomain',
};

/// The verdict the address alone supports: true for a host that can only be on
/// the local network, false for one that cannot be, and **null** when only a DNS
/// lookup can tell: the split-horizon case, where `nas.example.com` resolves to
/// a 192.168 address at home and to nothing anywhere else.
bool? localNetworkHostVerdict(String host) {
  final bare = host
      .replaceAll('[', '')
      .replaceAll(']', '')
      .trim()
      .toLowerCase();
  if (bare.isEmpty) return false;

  final literal = InternetAddress.tryParse(bare);
  if (literal != null) return addressIsOnLocalNetwork(literal);

  // Loopback is exempt from the gate on every platform: the traffic never
  // reaches a network, so nothing asks the user about it.
  if (bare == 'localhost') return false;

  final labels = bare.split('.');
  // A single label (`nas`, or a Compose service name) is resolved by mDNS or
  // by the router's own DNS. Both are on the LAN by definition.
  if (labels.length == 1) return true;
  if (_localSuffixes.contains(labels.last)) return true;
  // RFC 8375's designated home-network zone.
  if (bare.endsWith('.home.arpa')) return true;
  return null;
}

/// Whether [address] sits on a network the OS treats as local.
///
/// Loopback is excluded because it is never gated. So is 100.64/10: that range
/// belongs to carrier NAT and, on this app's users' devices, to Tailscale,
/// whose traffic leaves through a tunnel interface and is not what the local
/// network permission covers. Reporting a Tailscale address as local would
/// blame the wrong thing for every failure on a remote connection.
bool addressIsOnLocalNetwork(InternetAddress address) {
  if (address.isLoopback) return false;
  final bytes = address.rawAddress;

  if (address.type == InternetAddressType.IPv4) {
    if (bytes[0] == 10) return true;
    if (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) return true;
    if (bytes[0] == 192 && bytes[1] == 168) return true;
    // 169.254/16: link-local, what a device picks when DHCP never answered.
    if (bytes[0] == 169 && bytes[1] == 254) return true;
    return false;
  }

  if (bytes.length != 16) return false;
  // `::ffff:a.b.c.d`, an IPv4 destination wearing an IPv6 address. The gate
  // follows the real destination, so unwrap it and judge that.
  final isV4Mapped =
      bytes.take(10).every((b) => b == 0) &&
      bytes[10] == 0xff &&
      bytes[11] == 0xff;
  if (isV4Mapped) {
    return addressIsOnLocalNetwork(
      InternetAddress.fromRawAddress(bytes.sublist(12)),
    );
  }
  // fe80::/10 link-local.
  if (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80) return true;
  // fc00::/7 unique local addresses: IPv6's answer to 192.168.
  if ((bytes[0] & 0xfe) == 0xfc) return true;
  return false;
}

/// Whether [rawUrl] addresses the local network, resolving the host only when
/// the name itself cannot answer.
///
/// A lookup that fails or hangs is read as "not local": the permission story is
/// only ever offered as an explanation, and offering it for a host nothing can
/// even resolve would replace one wrong answer with another.
Future<bool> targetIsOnLocalNetwork(
  String rawUrl, {
  HostLookup lookup = InternetAddress.lookup,
  Duration lookupTimeout = const Duration(milliseconds: 1500),
}) async {
  final host = Uri.tryParse(UrlUtils.normalizeBaseUrl(rawUrl))?.host ?? '';
  if (host.isEmpty) return false;

  final fromName = localNetworkHostVerdict(host);
  if (fromName != null) return fromName;

  try {
    final addresses = await lookup(host).timeout(lookupTimeout);
    return addresses.any(addressIsOnLocalNetwork);
  } catch (_) {
    return false;
  }
}
