import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/connection_address.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

/// What the person who runs a Seerr hands a household member, so their
/// Cupola finds it: where it is at home and away, and the certificate each
/// address shows. The server's name is not in it: the receiving app reads the
/// server on arrival and names it from the server itself.
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
///
/// **Shown in person, it carries what a gateway asks for** ([homeAccess],
/// [awayAccess]): an invite made with [SeerrInvite.inPerson] travels sealed,
/// over the home network, inside a code that works once for two minutes
/// (`PairPackage.invite`), never as a link. Still never the key. [toUri]
/// refuses such an invite, and the receiving app holds it in memory, never
/// in a location.
final class SeerrInvite {
  const SeerrInvite({
    required this.home,
    this.away,
    this.homePin,
    this.awayPin,
    this.homeAccess = const NoAccess(),
    this.awayAccess = const NoAccess(),
  });

  /// The invite for [connection], as the operator's app has it: its
  /// addresses and the pin [settings] keeps for each.
  factory SeerrInvite.of(ServiceInstance connection, SettingsModel settings) {
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
    );
  }

  /// The invite for [connection] shown in person: both addresses, the pin
  /// [settings] keeps for each, and what each address asks for in front of
  /// it. Never the key, never an account.
  factory SeerrInvite.inPerson(
    ServiceInstance connection,
    SettingsModel settings,
  ) {
    final home = UrlUtils.normalizeBaseUrl(connection.url);
    final awayAddress = connection.away;
    final away = awayAddress == null || awayAddress.url.isEmpty
        ? null
        : UrlUtils.normalizeBaseUrl(awayAddress.url);
    return SeerrInvite(
      home: home,
      away: away,
      homePin: _httpsPin(home, settings),
      awayPin: away == null ? null : _httpsPin(away, settings),
      homeAccess: connection.access,
      awayAccess: away == null ? const NoAccess() : awayAddress!.access,
    );
  }

  /// The link's scheme and host: `cupola://invite`.
  static const scheme = 'cupola';
  static const host = 'invite';

  /// The version this build writes and reads. A link of another version is
  /// not read: what it carries may mean something else.
  static const version = '1';

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

  /// What a gateway in front of [home] asks for: only ever in an invite
  /// shown in person.
  final ConnectionAccess homeAccess;

  /// The same for [away].
  final ConnectionAccess awayAccess;

  /// Whether the invite carries anything a gateway asks for: what only an
  /// invite shown in person may.
  bool get carriesAccess => !homeAccess.isEmpty || !awayAccess.isEmpty;

  /// The connection an invite draws up under [id]: its two addresses and
  /// what they ask for, no key, no account.
  ServiceInstance draft(String id) => ServiceInstance(
    id: id,
    service: ServiceKey.seerr,
    url: home,
    access: homeAccess,
    away: away == null
        ? null
        : ConnectionAddress(url: away!, access: awayAccess),
  );

  /// [here], a Seerr this device already has at one of the invite's
  /// addresses, with what it lacks and the invite brings: the address away
  /// and what it asks for, what the address at home asks for. Never in place
  /// of anything [here] has: an address, an access, a key or an account it
  /// already holds stays as it is.
  ServiceInstance fill(ServiceInstance here) {
    var filled = here;
    if (filled.access.isEmpty &&
        !homeAccess.isEmpty &&
        UrlUtils.normalizeBaseUrl(filled.url) == home) {
      filled = filled.copyWith(access: homeAccess);
    }
    final away = this.away;
    if (away == null) return filled;
    final saved = filled.away;
    if (saved == null || saved.url.isEmpty) {
      if (UrlUtils.normalizeBaseUrl(filled.url) != away) {
        filled = filled.copyWith(
          away: ConnectionAddress(url: away, access: awayAccess),
        );
      }
    } else if (saved.access.isEmpty &&
        !awayAccess.isEmpty &&
        UrlUtils.normalizeBaseUrl(saved.url) == away) {
      filled = filled.copyWith(
        away: ConnectionAddress(url: saved.url, access: awayAccess),
      );
    }
    return filled;
  }

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

  /// The invite as a link. Throws a [StateError] for an invite that carries
  /// what a gateway asks for: that one is never written out.
  Uri toUri() => carriesAccess
      ? throw StateError('an invite shown in person is never a link')
      : Uri(
          scheme: scheme,
          host: host,
          queryParameters: {
            'v': version,
            'home': home,
            'away': ?away,
            'homePin': ?homePin,
            'awayPin': ?awayPin,
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
  /// trusting part of it. A parameter it does not know (a `title`, from a
  /// link an earlier build wrote) is ignored.
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

  @override
  bool operator ==(Object other) =>
      other is SeerrInvite &&
      other.home == home &&
      other.away == away &&
      other.homePin == homePin &&
      other.awayPin == awayPin &&
      other.homeAccess == homeAccess &&
      other.awayAccess == awayAccess;

  @override
  int get hashCode =>
      Object.hash(home, away, homePin, awayPin, homeAccess, awayAccess);

  @override
  String toString() => 'SeerrInvite(home: $home, away: $away)';
}

/// What an invite's link cannot do for the household member, said beside it
/// so the person who sends it knows before they do.
enum SeerrInviteLimit {
  /// The server has no address away from home: the invite works at home.
  homeOnly,

  /// The address away is behind a gateway that asks for a token, which a
  /// link never carries: it is left out, and the invite works at home.
  awayBehindGateway,

  /// The address at home is behind a gateway that asks for a token: the
  /// household member will be asked for it.
  homeBehindGateway;

  /// Whether the limit is a token the link leaves behind: what an invite
  /// shown in person carries ([SeerrInvite.inPerson]).
  bool get isToken => this != homeOnly;
}

/// Whether an invite to [connection] is better shown in person: an address
/// of it asks for a token, which a link never carries.
bool invitesInPerson(ServiceInstance connection) =>
    inviteLimitsOf(connection).any((limit) => limit.isToken);

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
