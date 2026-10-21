import 'dart:io' show InternetAddress;

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:cupola/core/network/local_network_target.dart';
import 'package:cupola/core/utils/url_utils.dart';

/// The poster a route's `posterUrl` names, when it is safe to fetch.
///
/// The parameter is a preload: the picture the tile already showed, so the
/// page opens on it while its own artwork loads. It is also part of a deep
/// link anybody can compose, and the image cache fetches it verbatim, so
/// `cupola://media/movie/603?posterUrl=http://192.168.1.1/admin` would have
/// the app send a GET to any host and path on the network it is on.
///
/// A route's poster is kept only when it points at:
/// * the address of a configured connection (home or away), because a tile's
///   own artwork comes from there; or
/// * a public host over `https`, because that is where TMDB, TheTVDB and
///   fanart.tv serve the artwork an arr names, and a GET there reaches nobody
///   on the person's network. A name that resolves to a private address
///   anyway gets no GET either: the request only leaves after a certificate
///   valid for that name, which a router or a NAS on the LAN does not hold.
///
/// Anything else (a private, loopback or tailnet host the person did not
/// configure, cleartext off the connections, an address with credentials in
/// it) reads as no preload: the page draws its own artwork as it would have.
///
/// The configured origins are a snapshot kept by `networkRegistriesProvider`,
/// the same bridge as `CertTrustRegistry`, because the route builders that
/// read the parameter have no provider to watch.
abstract final class RoutePoster {
  static Set<String> _origins = const {};

  /// Replaces the snapshot with the origins of [addresses].
  static void update(Iterable<String> addresses) {
    _origins = {
      for (final address in addresses) ?_originOf(Uri.tryParse(address)),
    };
  }

  /// [raw] when a route may preload it, else null.
  static String? accept(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri == null || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      return null;
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    if (_origins.contains(_originOf(uri))) return value;
    if (uri.scheme != 'https') return null;
    return _isOnPersonsNetwork(uri.host) ? null : value;
  }

  static String? _originOf(Uri? uri) {
    if (uri == null || uri.host.isEmpty) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    return '${uri.scheme}://${uri.host.toLowerCase()}:${uri.port}';
  }

  static bool _isOnPersonsNetwork(String host) {
    final bare = host.replaceAll('[', '').replaceAll(']', '').toLowerCase();
    if (bare == 'localhost') return true;
    final address = InternetAddress.tryParse(bare);
    if (address != null && (address.isLoopback || address.isLinkLocal)) {
      return true;
    }
    return localNetworkHostVerdict(bare) == true ||
        UrlUtils.isTailnetHost(bare);
  }

  /// Test-only: this is process-wide state, not scoped to a container.
  @visibleForTesting
  static void reset() => _origins = const {};
}
