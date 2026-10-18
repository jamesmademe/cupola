import 'dart:async';

/// The origins a request just failed to reach: no connection opened, or none
/// opened in time.
///
/// Told by every client built through `guardedDio`, heard by the route probe
/// (`RouteProbe`): a connection with an address away from home whose current
/// address stops answering is probed again at once, rather than at the next
/// return to the foreground. A server that was reached and then failed is not
/// told here; its route is right, and its fault is its own.
///
/// A failed request also waits, a little, for what its origin set going
/// ([reportAndSettle]): a reader that hears of the failure only once the
/// connection has moved to the address that answers is rebuilt on that
/// address first, and never draws a failure that was only the way out of
/// home.
abstract final class UnreachedOrigins {
  static final _controller = StreamController<String>.broadcast();
  static final _settlers = <Future<void> Function(String origin)>[];

  /// The longest a failed request waits for its origin to settle: longer than
  /// the slowest knock, the six seconds the address away is given.
  static const settleCap = Duration(seconds: 7);

  /// The origins, as `scheme://host:port`, one event per failed request.
  static Stream<String> get stream => _controller.stream;

  /// Tells [uri]'s origin; nothing for a URI that has none.
  static void report(Uri uri) {
    if (!uri.hasScheme || uri.host.isEmpty) return;
    _controller.add(originOf(uri));
  }

  /// Registers [settle], which says when what was started for an origin is
  /// done: the route probe's knocks on the connections there. Returns what
  /// unregisters it.
  static void Function() settleWith(
    Future<void> Function(String origin) settle,
  ) {
    _settlers.add(settle);
    return () => _settlers.remove(settle);
  }

  /// [report]s [uri]'s origin, then waits out what its listeners started for
  /// it, at most [settleCap]. Nothing to wait for (no connection there has an
  /// address away) is no wait at all.
  static Future<void> reportAndSettle(Uri uri) async {
    report(uri);
    if (!uri.hasScheme || uri.host.isEmpty || _settlers.isEmpty) return;
    // The listeners hear of the origin on a microtask: let them start.
    await Future<void>.delayed(Duration.zero);
    final origin = originOf(uri);
    await Future.wait([
      for (final settle in List.of(_settlers)) settle(origin),
    ]).timeout(settleCap, onTimeout: () => const []);
  }

  /// [uri]'s origin with its port spelled out, so `http://nas` and
  /// `http://nas:80` are the same.
  static String originOf(Uri uri) => '${uri.scheme}://${uri.host}:${uri.port}';
}
