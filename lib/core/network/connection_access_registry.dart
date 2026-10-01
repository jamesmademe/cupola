import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:cupola/core/utils/url_utils.dart';

/// Each connection's access headers by its address, for the artwork requests
/// that are built from an address and a key rather than through a client.
///
/// A poster from an arr's `/MediaCover` is fetched by `CachedNetworkImage`
/// with its own HTTP stack, from the URL and headers `ImageUtils` builds out
/// of a connection's address and key. Behind Cloudflare Access that request
/// needs the connection's service token as much as an API call does, or every
/// tile turns into a placeholder while the library reads fine. The leaf
/// widgets that build those sources stay off Riverpod on purpose (see
/// `lib/core/widgets/AGENTS.md`), so this snapshot is the bridge, the same
/// shape as `CertTrustRegistry`: [update] is called from the one `ref.listen`
/// in `CupolaApp` that sees the settings, and [headersFor] is a pure function
/// of the address everywhere below it.
///
/// Keyed by the connection's whole address, path included, never by origin:
/// access is per connection (`ConnectionAccess`), and two services behind one
/// host under two paths can each need their own.
class ConnectionAccessRegistry {
  const ConnectionAccessRegistry._();

  static Map<String, Map<String, String>> _byAddress = const {};

  /// Replaces the snapshot with [connections]: each one's address and the
  /// headers its access sends. A connection that sends none is left out.
  static void update(
    Iterable<({String url, Map<String, String> headers})> connections,
  ) {
    final next = <String, Map<String, String>>{};
    for (final (:url, :headers) in connections) {
      if (headers.isEmpty) continue;
      final address = UrlUtils.normalizeBaseUrl(url);
      if (address.isEmpty) continue;
      next.putIfAbsent(address, () => Map.unmodifiable(headers));
    }
    _byAddress = next;
  }

  /// The access headers of the connection at [baseUrl], or an empty map.
  static Map<String, String> headersFor(String baseUrl) {
    if (_byAddress.isEmpty) return const {};
    return _byAddress[UrlUtils.normalizeBaseUrl(baseUrl)] ?? const {};
  }

  /// Test-only: this is process-wide state, not scoped to a container.
  @visibleForTesting
  static void reset() => _byAddress = const {};
}
