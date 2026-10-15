import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/features/settings/domain/connection_address.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

/// What the person who runs a Seerr hands a household member, so their
/// Cupola finds it: where it is at home and away, the certificate each
/// address shows, and the name the server goes by.
///
/// **Never a secret.** No key, no session, no gateway access: an invite
/// travels as a link, in a chat or a QR on a screen, and anyone who sees it
/// learns only where the server is. The household member signs in with an
/// account of their own. An address away behind a gateway that asks for a
/// token is left out, since without the token it answers in the server's
/// place ([SeerrInviteLimit.awayBehindGateway]).
///
/// The link is `cupola://invite?v=1&home=…`, each address percent-encoded
/// so a chat does not cut a link of its own out of it.
final class SeerrInvite {
  const SeerrInvite({
    required this.home,
    this.away,
    this.homePin,
    this.awayPin,
    this.title,
  });

  /// The invite for [connection], as the operator's app has it: its
  /// addresses, the pin [settings] keeps for each, and [title], the name the
  /// server gave itself.
  factory SeerrInvite.of(
    ServiceInstance connection,
    SettingsModel settings, {
    String? title,
  }) {
    final home = UrlUtils.normalizeBaseUrl(connection.url);
    final awayAddress = connection.away;
    final away = awayAddress == null || !awayAddress.access.isEmpty
        ? null
        : UrlUtils.normalizeBaseUrl(awayAddress.url);
    return SeerrInvite(
      home: home,
      away: away,
      homePin: _httpsPin(home, settings),
      awayPin: away == null ? null : _httpsPin(away, settings),
      title: _cleanTitle(title),
    );
  }

  /// The link's scheme and host: `cupola://invite`.
  static const scheme = 'cupola';
  static const host = 'invite';

  /// The version this build writes and reads. A link of another version is
  /// not read: what it carries may mean something else.
  static const version = '1';

  /// The longest name an invite carries; a longer one is cut.
  static const titleLength = 64;

  /// The address at home, as [UrlUtils.normalizeBaseUrl] writes it.
  final String home;

  /// The address away from home, when the server has one an invite can
  /// carry.
  final String? away;

  /// The fingerprint the operator's app trusts at [home]'s origin, as
  /// stored: lowercase hex SHA-256. Only an `https` address has one.
  final String? homePin;

  /// The same for [away].
  final String? awayPin;

  /// The name the operator gave the server (`applicationTitle`).
  final String? title;

  /// The connection an invite draws up under [id]: its two addresses, no
  /// key, no account, no access.
  ServiceInstance draft(String id) => ServiceInstance(
    id: id,
    service: ServiceKey.seerr,
    url: home,
    away: away == null ? null : ConnectionAddress(url: away!),
  );

  /// The Seerr connection [settings] already has at one of the invite's
  /// addresses, signed in or not; null when there is none.
  ServiceInstance? connectedIn(SettingsModel settings) {
    final addresses = {home, ?away};
    for (final instance in settings.instancesOf(ServiceKey.seerr)) {
      final its = {
        UrlUtils.normalizeBaseUrl(instance.url),
        if (instance.away case final away?) UrlUtils.normalizeBaseUrl(away.url),
      }..remove('');
      if (its.any(addresses.contains)) return instance;
    }
    return null;
  }

  /// The fingerprint the invite vouches for at [url]'s origin, or null when
  /// it vouches for none there.
  String? pinFor(String url) {
    final origin = UrlUtils.certOrigin(url);
    if (origin == null) return null;
    if (homePin != null && UrlUtils.certOrigin(home) == origin) return homePin;
    final away = this.away;
    if (awayPin != null &&
        away != null &&
        UrlUtils.certOrigin(away) == origin) {
      return awayPin;
    }
    return null;
  }

  /// The invite as a link.
  Uri toUri() => Uri(
    scheme: scheme,
    host: host,
    queryParameters: {
      'v': version,
      'home': home,
      'away': ?away,
      'homePin': ?homePin,
      'awayPin': ?awayPin,
      'title': ?title,
    },
  );

  /// The invite as the text a person copies.
  String toLink() => toUri().toString();

  /// Whether [uri] is an invite's link, as the app is opened with it: the
  /// whole `cupola://invite?…`, or the path `/invite?…` a platform may hand
  /// over in its place.
  static bool isInviteUri(Uri uri) =>
      (uri.scheme.toLowerCase() == scheme && uri.host.toLowerCase() == host) ||
      uri.path == '/$host';

  /// The invite in [query], the link's parameters; null when they are not
  /// one this build can read whole.
  ///
  /// Strict on what it vouches for: an address that is not one, or a pin
  /// that is not a fingerprint, refuses the whole invite rather than
  /// trusting part of it.
  static SeerrInvite? fromQuery(Map<String, String> query) {
    if (query['v'] != version) return null;
    final home = _address(query['home']);
    if (home == null) return null;
    final rawAway = query['away'];
    final away = rawAway == null ? null : _address(rawAway);
    if (rawAway != null && away == null) return null;
    final homePin = query['homePin'];
    final awayPin = query['awayPin'];
    if (homePin != null && !_isFingerprint(homePin)) return null;
    if (awayPin != null && !_isFingerprint(awayPin)) return null;
    return SeerrInvite(
      home: home,
      away: away,
      homePin: _isHttps(home) ? homePin : null,
      awayPin: away != null && _isHttps(away) ? awayPin : null,
      title: _cleanTitle(query['title']),
    );
  }

  /// The invite in [text], a link pasted alone or inside a message; null
  /// when [text] holds none, or one that is not whole.
  static SeerrInvite? tryParse(String text) {
    final match = _linkIn.firstMatch(text);
    if (match == null) return null;
    final uri = Uri.tryParse(match.group(0)!);
    if (uri == null || !isInviteUri(uri)) return null;
    return fromQuery(uri.queryParameters);
  }

  /// Whether [text] holds an invite's link at all, read or not.
  static bool mentionsInvite(String text) => _linkIn.hasMatch(text);

  static final _linkIn = RegExp(r'cupola://invite\S*', caseSensitive: false);

  static String? _address(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(trimmed)) {
      return null;
    }
    if (UrlUtils.validateServiceHost(trimmed) != null) return null;
    return UrlUtils.normalizeBaseUrl(trimmed);
  }

  static bool _isHttps(String url) => url.toLowerCase().startsWith('https://');

  static bool _isFingerprint(String value) =>
      RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

  static String? _httpsPin(String url, SettingsModel settings) =>
      _isHttps(url) ? settings.pinForUrl(url) : null;

  static String? _cleanTitle(String? raw) {
    if (raw == null) return null;
    final clean = raw.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), ' ').trim();
    if (clean.isEmpty) return null;
    return clean.length <= titleLength
        ? clean
        : clean.substring(0, titleLength).trimRight();
  }

  @override
  bool operator ==(Object other) =>
      other is SeerrInvite &&
      other.home == home &&
      other.away == away &&
      other.homePin == homePin &&
      other.awayPin == awayPin &&
      other.title == title;

  @override
  int get hashCode => Object.hash(home, away, homePin, awayPin, title);

  @override
  String toString() => 'SeerrInvite(home: $home, away: $away)';
}

/// What an invite cannot do for the household member, said beside it so the
/// person who sends it knows before they do.
enum SeerrInviteLimit {
  /// The server has no address away from home: the invite works at home.
  homeOnly,

  /// The address away is behind a gateway that asks for a token, which an
  /// invite never carries: it is left out, and the invite works at home.
  awayBehindGateway,

  /// The address at home is behind a gateway that asks for a token: the
  /// household member will be asked for it.
  homeBehindGateway,
}

/// What [connection]'s invite cannot do, in the order the sheet says it.
List<SeerrInviteLimit> inviteLimitsOf(ServiceInstance connection) {
  final away = connection.away;
  return [
    if (!connection.access.isEmpty) SeerrInviteLimit.homeBehindGateway,
    if (away == null)
      SeerrInviteLimit.homeOnly
    else if (!away.access.isEmpty)
      SeerrInviteLimit.awayBehindGateway,
  ];
}
