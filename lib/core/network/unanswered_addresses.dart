import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/features/settings/domain/connection_unanswered.dart';

/// The addresses of each connection at which neither of its addresses
/// answered the route probe, with what the red names: for the clients, which
/// are built off a transport and know nothing of the probe.
///
/// A snapshot, the same shape as `ConnectionAccessRegistry`: [update] is
/// called from the one `ref.listen` in `CupolaApp` that sees
/// `unansweredConnectionsProvider`, and [at] is a pure function of a request's
/// address everywhere below it (`UnansweredMark`). Both of a connection's
/// addresses are listed, so a request to either says it. A client is not
/// rebuilt when a connection joins or leaves: its next request says it.
///
/// Keyed by the connection's whole address, path included: two services
/// behind one host under two paths are two connections.
class UnansweredAddresses {
  const UnansweredAddresses._();

  static List<(Uri, ConnectionUnanswered)> _addresses = const [];

  /// Replaces the snapshot with [connections]: each unanswered connection's
  /// two addresses and what its red names.
  static void update(
    Iterable<({List<String> urls, ConnectionUnanswered unanswered})>
    connections,
  ) {
    _addresses = [
      for (final (:urls, :unanswered) in connections)
        for (final url in urls)
          if (Uri.tryParse(UrlUtils.normalizeBaseUrl(url)) case final address?
              when address.host.isNotEmpty)
            (address, unanswered),
    ];
  }

  /// What the red names for a request to [uri], when it went to an address
  /// of an unanswered connection; null otherwise. Compared by scheme, host,
  /// port (spelled or not) and path, so `https://nas:443` is `https://nas`.
  static ConnectionUnanswered? at(Uri uri) {
    for (final (address, unanswered) in _addresses) {
      if (address.scheme != uri.scheme ||
          address.host != uri.host ||
          address.port != uri.port) {
        continue;
      }
      final base = address.path.endsWith('/')
          ? address.path.substring(0, address.path.length - 1)
          : address.path;
      if (base.isEmpty || uri.path == base || uri.path.startsWith('$base/')) {
        return unanswered;
      }
    }
    return null;
  }

  /// Test-only: this is process-wide state, not scoped to a container.
  @visibleForTesting
  static void reset() => _addresses = const [];
}
