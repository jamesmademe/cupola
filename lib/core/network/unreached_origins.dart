import 'dart:async';

/// The origins a request just failed to reach: no connection opened, or none
/// opened in time.
///
/// Told by every client built through `guardedDio`, heard by the route probe
/// (`RouteProbe`): a connection with an address away from home whose current
/// address stops answering is probed again at once, rather than at the next
/// return to the foreground. A server that was reached and then failed is not
/// told here; its route is right, and its fault is its own.
abstract final class UnreachedOrigins {
  static final _controller = StreamController<String>.broadcast();

  /// The origins, as `scheme://host:port`, one event per failed request.
  static Stream<String> get stream => _controller.stream;

  /// Tells [uri]'s origin; nothing for a URI that has none.
  static void report(Uri uri) {
    if (!uri.hasScheme || uri.host.isEmpty) return;
    _controller.add(originOf(uri));
  }

  /// [uri]'s origin with its port spelled out, so `http://nas` and
  /// `http://nas:80` are the same.
  static String originOf(Uri uri) => '${uri.scheme}://${uri.host}:${uri.port}';
}
