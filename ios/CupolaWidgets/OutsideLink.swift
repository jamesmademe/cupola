import Foundation

/// What a tap on a widget opens: `cupola://open?to=/activity`.
///
/// The snapshot names each place as a location of the app's router
/// (`OutsideFace.route`, `OutsideItem.route`); the widget, which runs no
/// Dart, wraps it in this link, and the app takes it back off
/// (`OutsideLink.routeOf` in `outside_link.dart`).
enum OutsideLink {
  /// Everything but the unreserved characters is escaped, `/`, `?`, `&`, `=`
  /// and `%` included: the route is one query value, and its own query must
  /// not read as the link's. Dart decodes it whole (`Uri.queryParameters`).
  private static let unreserved = CharacterSet(
    charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

  /// The link that opens [route], or nil where there is nowhere to go.
  static func url(for route: String?) -> URL? {
    guard let route, !route.isEmpty,
      let encoded = route.addingPercentEncoding(withAllowedCharacters: unreserved)
    else { return nil }
    return URL(string: "cupola://open?to=\(encoded)")
  }
}
