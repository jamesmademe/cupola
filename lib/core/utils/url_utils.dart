import 'dart:io' show InternetAddress, InternetAddressType;

import 'package:cupola/core/network/local_network_target.dart';

class UrlUtils {
  /// [host] as it goes into a sentence: never broken after one of its
  /// hyphens.
  ///
  /// A line that ends `sonarr-` reads as a word hyphenated to fit, and the
  /// reader who types what they see types `sonarrtest`. A word joiner (U+2060,
  /// invisible, silent to a screen reader) after each hyphen leaves the line
  /// free to break before the host instead, which then moves down whole.
  static String hostInProse(String host) => host.replaceAll('-', '-\u2060');

  /// Constructs a URL for accessing images or other resources.
  /// Handles correct slash joining. API key authentication is handled via
  /// HTTP headers, not query parameters.
  static String buildUrl(String baseUrl, String path) {
    if (baseUrl.isEmpty || path.isEmpty) return '';

    final cleanBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;

    final cleanPath = path.startsWith('/') ? path : '/$path';

    return '$cleanBaseUrl$cleanPath';
  }

  /// The base URL every client feeds to Dio: trimmed, scheme-qualified, with no
  /// trailing slash.
  ///
  /// A scheme-less host defaults to HTTPS so an omitted scheme never downgrades
  /// an API key or a Basic-auth password to cleartext (security standard
  /// §10.2 #9); an explicit `http://` is honoured.
  ///
  /// Qualifying the scheme is not cosmetic: `BaseOptions(baseUrl: 'host:7878')`
  /// throws `ArgumentError` from Dio's own setter, and the onboarding and
  /// settings fields both accept a bare host; so without this a plausible
  /// address wedged the caller instead of failing as a connection error.
  static String normalizeBaseUrl(String url) {
    var normalized = url.trim();
    if (normalized.isEmpty) return '';
    if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(normalized)) {
      normalized = 'https://$normalized';
    }
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return _withoutUserInfo(normalized);
  }

  /// Strips any `user:password@` from an address.
  ///
  /// The connection form and the first-run walk both take embedded
  /// credentials off the address before they save ([credentialsInAddress]),
  /// so nothing reaches storage with them today. This is
  /// the belt to that braces, and it belongs here rather than only in the
  /// validator because *this* is the function whose output becomes
  /// `BaseOptions.baseUrl`: a credential that ever slipped past the form would
  /// be interpolated into every request URI, land in `HttpException`'s
  /// `uri = …` text on any transport failure, and be persisted in plain
  /// `SharedPreferences` rather than the Keychain.
  ///
  /// It is not hypothetical for Transmission specifically: `http://user:pass@
  /// host:9091/` is an idiomatic way to write that daemon's address, so anything
  /// that ever offers "paste your existing Transmission URL" walks straight
  /// into it.
  static String _withoutUserInfo(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.userInfo.isEmpty) return url;
    return uri.replace(userInfo: '').toString();
  }

  static const _invalidUrl =
      'Enter a valid URL (e.g. https://192.168.1.100:7878)';
  static const _credentialsInUrl =
      'Remove the username:password from the URL, enter credentials in their '
      'own fields';

  /// Validates a service URL that may omit the scheme.
  ///
  /// The single rule for every address field in the app: onboarding and the
  /// settings form share it, so an address accepted during setup is still
  /// accepted when reopened for editing.
  ///
  /// [normalizeBaseUrl] turns a scheme-less host into `https://`, so accepting
  /// it here matches what actually happens on connect. Anything that is not a
  /// plausible host (an unknown scheme, embedded whitespace, embedded
  /// credentials, characters no hostname may contain) is rejected up front so
  /// the user is told the address is malformed instead of being told the server
  /// is unreachable.
  ///
  /// A bare single-label host (`nas`, a Docker Compose service name) is
  /// deliberately accepted: on a home network those resolve, and the previous
  /// "must look like a domain" rule turned working addresses into form errors.
  /// So is an internationalised name (`münchen.de`): same class of input, and
  /// telling the user their address is malformed because it is not ASCII is the
  /// same false report the character rule exists to prevent.
  ///
  /// [allowCredentials] is for the connection form, which takes an address's
  /// `user:password@` off it on save and puts it where it belongs (the proxy
  /// password on the Access row, or the service's own sign-in): see
  /// [credentialsInAddress]. Everywhere else such an address is refused.
  static String? validateServiceHost(
    String? value, {
    bool allowCredentials = false,
  }) {
    if (value == null || value.trim().isEmpty) {
      return 'Server URL is required';
    }

    var trimmed = value.trim();
    final schemeMatch = RegExp(
      r'^([A-Za-z][A-Za-z0-9+.\-]*):\/\/',
    ).firstMatch(trimmed);
    if (schemeMatch != null) {
      final scheme = schemeMatch.group(1)!.toLowerCase();
      if (scheme != 'http' && scheme != 'https') {
        return 'Only http:// and https:// addresses are supported';
      }
    } else {
      if (trimmed.contains('://')) return _invalidUrl;
      // Mirror the clients: a bare host means HTTPS.
      trimmed = 'https://$trimmed';
    }

    return _validateParsed(trimmed, allowCredentials: allowCredentials);
  }

  /// The `user:password@` an address carries, decoded, or null when it
  /// carries none: `https://matt:p%40ss@radarr.example.com` reads as `matt`
  /// and `p@ss`. A user with no password reads with an empty one.
  static ({String username, String password})? credentialsInAddress(
    String url,
  ) {
    final trimmed = url.trim();
    final schemed =
        RegExp(r'^https?://', caseSensitive: false).hasMatch(trimmed)
        ? trimmed
        : 'https://$trimmed';
    final userInfo = Uri.tryParse(schemed)?.userInfo ?? '';
    if (userInfo.isEmpty) return null;
    final colon = userInfo.indexOf(':');
    String decoded(String part) {
      try {
        return Uri.decodeComponent(part);
      } on ArgumentError {
        return part;
      }
    }

    return colon < 0
        ? (username: decoded(userInfo), password: '')
        : (
            username: decoded(userInfo.substring(0, colon)),
            password: decoded(userInfo.substring(colon + 1)),
          );
  }

  /// [url] without the `user:password@` it carries, as typed otherwise.
  static String withoutCredentials(String url) {
    final trimmed = url.trim();
    if (credentialsInAddress(trimmed) == null) return trimmed;
    final scheme = RegExp(
      r'^https?://',
      caseSensitive: false,
    ).firstMatch(trimmed)?.group(0);
    final rest = scheme == null ? trimmed : trimmed.substring(scheme.length);
    // The authority ends at the path, the query or the fragment, and its
    // user info at the last `@` before that.
    final end = rest.indexOf(RegExp('[/?#]'));
    final authority = end < 0 ? rest : rest.substring(0, end);
    final at = authority.lastIndexOf('@');
    if (at < 0) return trimmed;
    return '${scheme ?? ''}${rest.substring(at + 1)}';
  }

  static String? _validateParsed(String url, {bool allowCredentials = false}) {
    if (RegExp(r'\s').hasMatch(url)) return _invalidUrl;

    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return _invalidUrl;
    if (uri.userInfo.isNotEmpty && !allowCredentials) return _credentialsInUrl;
    if (!_isPlausibleHost(uri.host)) return _invalidUrl;

    return null;
  }

  /// One host label: letters, digits, hyphens and underscores, never starting
  /// or ending with a hyphen.
  ///
  /// Underscore is tolerated on purpose: it is illegal in a hostname per
  /// RFC 1123 but legal in a Docker/Compose service name, and reaching a
  /// container by its service name is a normal way to run this stack.
  ///
  /// "Letter" is `\p{L}`, not `A-Za-z`, so an internationalised name
  /// (`münchen.de`, a Cyrillic or CJK host) is a valid address rather than a
  /// malformed one. It is matched against the *decoded* label; see
  /// [_isPlausibleHost], because `Uri.host` percent-encodes anything
  /// non-ASCII, and `%` is not a character any host may contain.
  static final _hostLabel = RegExp(
    r'^[\p{L}\p{N}_]([\p{L}\p{N}_\-]*[\p{L}\p{N}_])?$',
    unicode: true,
  );

  /// Whether [host] could be a host at all.
  ///
  /// `Uri.tryParse` is far more permissive than DNS: it happily reports
  /// `hello!world`, `a,b.com` or a percent-encoded blob as a "host", so free
  /// text typed into an address field parsed cleanly and the user learned it
  /// was wrong only when the connection test came back "couldn't reach it".
  /// This is the check that turns that into "that address is malformed".
  ///
  /// Deliberately *not* a "must contain a dot" rule: a single label is a
  /// legitimate address here.
  static bool _isPlausibleHost(String host) {
    if (host.isEmpty || host.length > 253) return false;
    // `Uri.host` strips the brackets from an IPv6 literal, and a DNS name can
    // never contain a colon; so this is an exact test, not a guess.
    if (host.contains(':')) return _parseIpv6(host) != null;

    // A single trailing dot is a legal fully-qualified name.
    final name = host.endsWith('.') ? host.substring(0, host.length - 1) : host;
    if (name.isEmpty) return false;

    // Split *before* decoding: a label is decoded only to be character-checked,
    // and decoding first would let `a%2Eb.com` present itself as two labels.
    return name.split('.').every((label) {
      if (label.isEmpty || label.length > 63) return false;
      final decoded = _percentDecoded(label);
      return decoded != null && _hostLabel.hasMatch(decoded);
    });
  }

  /// [label] with its percent-escapes resolved, or null when they are malformed.
  static String? _percentDecoded(String label) {
    if (!label.contains('%')) return label;
    try {
      return Uri.decodeFull(label);
    } on ArgumentError {
      return null;
    } on FormatException {
      return null;
    }
  }

  /// The 16 bytes of [host] as an IPv6 literal, or null when it is not one.
  ///
  /// Strips a zone id (`fe80::1%eth0`, which `Uri.host` hands back percent-
  /// encoded as `%25eth0`); `Uri.parseIPv6Address` rejects it, and the zone
  /// says nothing about which range the address is in.
  static List<int>? _parseIpv6(String host) {
    final zone = host.indexOf('%');
    final literal = zone == -1 ? host : host.substring(0, zone);
    try {
      return Uri.parseIPv6Address(literal);
    } on FormatException {
      return null;
    }
  }

  /// Hosts for which cleartext HTTP is a normal, supported home-lab setup:
  /// loopback, where nothing crosses a network, and every host the local
  /// network verdict (`localNetworkHostVerdict`) knows is local.
  ///
  /// One answer to "is this host on the local network", shared with the
  /// local-network permission, so the address field never warns "off your
  /// local network" for a host the permission treats as local
  /// (`nas.home.arpa`, `nas.internal`, a bare `nas`). Carrier NAT (100.64/10,
  /// Tailscale's range) is not local there and is not here either.
  static bool _isPrivateHost(String host) {
    final bare = host.replaceAll('[', '').replaceAll(']', '').toLowerCase();
    if (bare == 'localhost') return true;
    if (InternetAddress.tryParse(bare)?.isLoopback ?? false) return true;
    return localNetworkHostVerdict(bare) == true;
  }

  /// Whether a service's default port is worth offering beside [raw], the
  /// address typed so far.
  ///
  /// Yes while nothing is typed (the suggestion carries the last host over),
  /// and for a host the port belongs on: an address, a name on the local
  /// network, a Tailscale name, or one that names another port already
  /// (perhaps another service's). No for an address that names [port]
  /// already, where the chip would do nothing (`:5055` beside
  /// `http://nas:5055`, 13/10), for an address with a path, and for an https
  /// name on the internet, which a reverse proxy answers on 443: `:5055` beside
  /// `https://seerr.example.com` invited a port that breaks it (11/10).
  static bool offersDefaultPort(String raw, {required int port}) {
    final value = raw.trim();
    if (value.isEmpty) return true;
    final uri = Uri.tryParse(normalizeBaseUrl(value));
    if (uri == null || uri.host.isEmpty) return true;
    // A port typed already may be another service's: the chip swaps it.
    if (uri.hasPort) return uri.port != port;
    if (uri.path.isNotEmpty && uri.path != '/') return false;
    final host = uri.host.toLowerCase();
    if (InternetAddress.tryParse(host.replaceAll(RegExp(r'[\[\]]'), '')) !=
        null) {
      return true;
    }
    if (_isPrivateHost(host) || isTailnetHost(host)) return true;
    return uri.scheme != 'https';
  }

  /// Whether [host] is reached through a Tailscale tunnel: an address in its
  /// range (100.64.0.0/10, carrier NAT, which no server on the internet
  /// answers from) or a MagicDNS name (`*.ts.net`).
  ///
  /// WireGuard encrypts the whole way, so `http://` there sends nothing in the
  /// clear: no warning and no refusal. Not a local host for the local-network
  /// permission, though: the traffic leaves through the tunnel, not the Wi-Fi.
  static bool isTailnetHost(String host) {
    final bare = host.replaceAll('[', '').replaceAll(']', '').toLowerCase();
    if (bare.endsWith('.ts.net')) return true;
    final address = InternetAddress.tryParse(bare);
    if (address == null || address.type != InternetAddressType.IPv4) {
      return false;
    }
    final bytes = address.rawAddress;
    return bytes[0] == 100 && bytes[1] >= 64 && bytes[1] <= 127;
  }

  /// Warns when [rawUrl] would send credentials in cleartext to a host outside
  /// the local network, and null when there is nothing to warn about.
  ///
  /// A plain `http://` LAN address is a supported setup, so it is not flagged,
  /// and neither is one on a tailnet ([isTailnetHost]), which travels
  /// encrypted. A public hostname over `http://` is: an on-path attacker there
  /// can read the API key or password and, before
  /// [SameOriginRedirectInterceptor], could also have redirected the request
  /// elsewhere.
  static String? cleartextWarning(String? rawUrl) {
    final value = rawUrl?.trim() ?? '';
    if (value.isEmpty) return null;
    if (!value.toLowerCase().startsWith('http://')) return null;

    final host = Uri.tryParse(value)?.host ?? '';
    if (host.isEmpty || _isPrivateHost(host) || isTailnetHost(host)) {
      return null;
    }

    // The one wording, for the connection form and the first-run walk alike,
    // and it names the three routes this audience uses rather than only
    // "use https".
    return 'This address is off your local network and http:// sends your '
        'credentials in the clear. Reach it over a reverse proxy with TLS, a '
        'VPN like Tailscale, or a Cloudflare Tunnel instead.';
  }

  /// Whether [url] is an absolute http(s) address safe to hand to the platform
  /// via `launchUrl`.
  ///
  /// `Uri.tryParse` is a syntax check, not a scheme check: `javascript:alert(1)`,
  /// `data:text/html,…`, `intent://…` and `file:///…` all parse. Launching one
  /// of those externally hands whatever a remote service put in a field to the
  /// OS, so the scheme is allow-listed and a host is required.
  ///
  /// This lives here rather than in either feature because two of them need it
  /// for the same reason: TrueNAS renders app portal URLs the NAS supplies, and
  /// Seerr/TMDB supplies trailer URLs. Both are strings from a server the app
  /// does not control, and one allowlist is one place to fix.
  static bool isLaunchableWebUrl(String url) =>
      isLaunchableWebUri(Uri.tryParse(url.trim()));

  /// [isLaunchableWebUrl] for a caller that has already parsed the string:
  /// notably one using `Uri.tryParse` to keep a `FormatException` out of a tap
  /// handler, which then holds a nullable [Uri] rather than the raw text.
  static bool isLaunchableWebUri(Uri? uri) {
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return false;
    return uri.isScheme('http') || uri.isScheme('https');
  }

  /// Whether a service URL should be reached over TLS.
  ///
  /// Secure unless the user explicitly asked for cleartext with `http://`. The
  /// polarity matters: testing `== 'https'` instead would silently downgrade a
  /// typo (`htps://host`) or a well-meant `wss://host` to an unencrypted
  /// connection and send login credentials in the clear.
  static bool isSecureScheme(String rawUrl) {
    final scheme = Uri.tryParse(rawUrl.trim())?.scheme.toLowerCase();
    return scheme != 'http' && scheme != 'ws';
  }

  /// The canonical `https://host:port` origin [rawUrl] belongs to, or null
  /// when it cannot carry a TLS certificate at all (unparseable, or an
  /// explicit `http://`/`ws://`).
  ///
  /// A certificate is a property of the host that presents it, not of any one
  /// service reached through it: this is the single place that turns a
  /// service's saved URL into the key trusted-certificate pins are stored
  /// under, so two services behind the same reverse proxy resolve to the same
  /// key and share one trust decision. Every saved service URL is http(s):
  /// the WebSocket-based clients (TrueNAS, Dockge) derive their own `wss://`
  /// internally; so only that pair needs handling here.
  static String? certOrigin(String rawUrl) {
    var raw = rawUrl.trim();
    if (raw.isEmpty) return null;
    if (!raw.contains('://')) raw = 'https://$raw';
    if (!isSecureScheme(raw)) return null;

    final uri = Uri.tryParse(raw);
    if (uri == null || uri.host.isEmpty) return null;

    final port = uri.hasPort ? uri.port : 443;
    return 'https://${uri.host}:$port';
  }
}
