/// What a tap on a widget opens: `cupola://open?to=/activity`.
///
/// The snapshot names each place as a location of the app's router
/// (`OutsideFace.route`, `OutsideItem.route`); the widget, which runs no
/// Dart, wraps it in this link (`OutsideLink` in `CupolaWidgets`, and the
/// Android widget's intent), and the router takes it back off
/// ([OutsideLink.routeOf]). A notification carries its place in its payload
/// instead (`outside_speaker.dart`), since it never leaves the app.
library;

abstract final class OutsideLink {
  static const scheme = 'cupola';
  static const host = 'open';

  /// The link that opens [route].
  static Uri to(String route) =>
      Uri(scheme: scheme, host: host, queryParameters: {'to': route});

  /// Whether [uri] is a widget's link: as the system hands it over, or its
  /// path once a router has normalised the host away.
  static bool isOpenUri(Uri uri) {
    if (uri.scheme == scheme && uri.host == host) return true;
    final bare = uri.path.endsWith('/')
        ? uri.path.substring(0, uri.path.length - 1)
        : uri.path;
    return bare == '/$host' && uri.queryParameters.containsKey('to');
  }

  /// The location [uri] opens, or null when it is not a widget's link or names
  /// no place of the app's own: anything can open a `cupola://` link, so only
  /// a path survives, never an address or a scheme.
  static String? routeOf(Uri uri) {
    if (!isOpenUri(uri)) return null;
    final to = uri.queryParameters['to'];
    if (to == null || !to.startsWith('/') || to.startsWith('//')) return null;
    final target = Uri.tryParse(to);
    if (target == null || target.hasScheme || target.hasAuthority) return null;
    return to;
  }
}
