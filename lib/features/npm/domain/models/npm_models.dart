import 'package:cupola/features/qbittorrent/domain/models/parse_utils.dart';

class NpmAccessClient {
  const NpmAccessClient({required this.address, required this.directive});
  final String address;
  final String directive;

  factory NpmAccessClient.fromJson(Map<String, dynamic> json) =>
      NpmAccessClient(
        address: json['address']?.toString() ?? '',
        directive: json['directive']?.toString() ?? '',
      );
}

class NpmAccessList {
  const NpmAccessList({
    required this.id,
    required this.name,
    required this.satisfyAny,
    required this.passAuth,
    required this.proxyHostCount,
    required this.clients,
  });
  final int id;
  final String name;
  final bool satisfyAny;
  final bool passAuth;
  final int? proxyHostCount;
  final List<NpmAccessClient> clients;

  factory NpmAccessList.fromJson(Map<String, dynamic> json) => NpmAccessList(
    id: parseInt(json['id']),
    name: json['name']?.toString().trim().isNotEmpty == true
        ? json['name'].toString()
        : 'Unnamed access list',
    satisfyAny: parseBool(json['satisfy_any']),
    passAuth: parseBool(json['pass_auth']),
    proxyHostCount: int.tryParse(json['proxy_host_count']?.toString() ?? ''),
    clients: ((json['clients'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => NpmAccessClient.fromJson(e.cast<String, dynamic>()))
        .toList(growable: false),
  );
}

class NpmAuditEntry {
  const NpmAuditEntry({
    required this.id,
    required this.objectType,
    required this.objectId,
    required this.action,
    required this.summary,
    this.createdOn,
  });
  final int id;
  final String objectType;
  final int? objectId;
  final String action;
  final String summary;
  final DateTime? createdOn;

  factory NpmAuditEntry.fromJson(Map<String, dynamic> json) {
    final meta = (json['meta'] as Map?)?.cast<String, dynamic>() ?? const {};
    final candidate =
        [
              meta['name'],
              meta['domain_names'] is List
                  ? (meta['domain_names'] as List).join(', ')
                  : null,
              meta['email'],
            ]
            .whereType<Object>()
            .map((e) => e.toString())
            .firstWhere((e) => e.trim().isNotEmpty, orElse: () => '');
    return NpmAuditEntry(
      id: parseInt(json['id']),
      objectType: json['object_type']?.toString() ?? 'object',
      objectId: int.tryParse(json['object_id']?.toString() ?? ''),
      action: json['action']?.toString() ?? 'changed',
      summary: candidate,
      createdOn: DateTime.tryParse(json['created_on']?.toString() ?? ''),
    );
  }
}

/// `GET /api/` — the unauthenticated health document.
///
/// The only response that proves an Nginx Proxy Manager backend is at the other
/// end. A bare 200 does not: the admin port serves a single-page app through
/// `try_files … /index.html`, so almost any path returns 200 HTML — including
/// against a wrong port, a wrong host, or an entirely different web server.
class NpmServerInfo {
  const NpmServerInfo({
    required this.status,
    required this.version,
    required this.setupComplete,
    required this.major,
    required this.minor,
  });

  final String status;

  /// `major.minor.revision`, flattened for display.
  final String version;

  /// False while NPM is still showing its first-run wizard (no user exists
  /// yet). Absent before 2.13, where it reads as true rather than pretending to
  /// know.
  final bool setupComplete;

  final int major;
  final int minor;

  bool get isHealthy => status.toUpperCase() == 'OK';

  /// Whether this install predates the removal of the hard-coded default
  /// administrator (`admin@example.com` / `changeme`).
  ///
  /// Surfaced rather than ignored because on an untouched 2.12-or-older install
  /// that account still works, and it hands full control of every route on the
  /// box to anyone who can reach port 81.
  bool get hasDefaultAdminRisk => major < 2 || (major == 2 && minor <= 12);

  factory NpmServerInfo.fromJson(Map<String, dynamic> json) {
    final version = json['version'];
    final versionMap = version is Map
        ? version.cast<String, dynamic>()
        : const <String, dynamic>{};
    final major = parseInt(versionMap['major']);
    final minor = parseInt(versionMap['minor']);
    return NpmServerInfo(
      status: json['status']?.toString() ?? '',
      version: '$major.$minor.${parseInt(versionMap['revision'])}',
      // Missing before 2.13. Defaulting to true keeps an older install from
      // being reported as "not set up" on the strength of an absent field.
      setupComplete: json.containsKey('setup')
          ? parseBool(json['setup'])
          : true,
      major: major,
      minor: minor,
    );
  }
}

/// A hostname Nginx Proxy Manager fronts, and where it sends the traffic.
class NpmProxyHost {
  const NpmProxyHost({
    required this.id,
    required this.domainNames,
    required this.forwardScheme,
    required this.forwardHost,
    required this.forwardPort,
    required this.enabled,
    required this.sslForced,
    required this.certificateId,
    required this.accessListId,
    required this.cachingEnabled,
    required this.blockExploits,
    required this.allowWebsocketUpgrade,
    required this.configLoaded,
    required this.errorText,
    required this.advancedConfig,
  });

  final int id;
  final List<String> domainNames;
  final String forwardScheme;
  final String forwardHost;
  final int forwardPort;
  final bool enabled;
  final bool sslForced;

  /// 0 when no certificate is attached.
  ///
  /// Never write this back as 0 to "clear" a certificate casually: NPM cascades
  /// a falsy `certificate_id` into `ssl_forced = false` and
  /// `http2_support = false`, and `ssl_forced = false` cascades again into
  /// `hsts_enabled = false` and then `hsts_subdomains = false`. One field
  /// silently wipes four.
  final int certificateId;

  final int accessListId;
  final bool cachingEnabled;
  final bool blockExploits;
  final bool allowWebsocketUpgrade;

  /// Whether the **last configuration attempt** for this host succeeded, from
  /// `meta.nginx_online`.
  ///
  /// **Not a live health signal, and must never be rendered as one.** NPM
  /// writes this only from `internalNginx.configure()` — on create, on updating
  /// an already-enabled host, and on enable. Nothing polls, nothing re-checks.
  /// A host whose backend died an hour ago still reads true here, and a host
  /// that failed to load stays false until someone edits it again.
  ///
  /// So the honest reading is "nginx refused this configuration the last time
  /// it was asked to load it", which is genuinely useful — it is invisible
  /// everywhere else and it means the hostname is not being served — but it is
  /// a config verdict, not an uptime probe. Calling it "Online" in the UI would
  /// promise monitoring this app does not do.
  final bool configLoaded;

  /// From `meta.nginx_err`, empty when the last configuration attempt was fine.
  ///
  /// NPM's own `nginx: [emerg] …` line, and the design prints it verbatim: it
  /// names the directive and the line number, which is the entire difference
  /// between "your config is broken" and a fix.
  final String errorText;

  /// The custom Nginx block NPM writes into this host's `server` section.
  ///
  /// Empty for the overwhelming majority of hosts. NPM keeps exactly one block
  /// per host and **no history**, which is why the editor holds the text it
  /// opened with for the session: that copy is the only undo that exists.
  final String advancedConfig;

  /// Lines, for the "· 10 lines" subtitle. An empty block is 0 lines, not 1.
  int get advancedConfigLines => advancedConfig.trim().isEmpty
      ? 0
      : advancedConfig.trim().split('\n').length;

  /// The name to show. NPM allows several hostnames per host; the first is the
  /// canonical one in its own UI too.
  String get primaryDomain =>
      domainNames.isEmpty ? 'Unnamed host' : domainNames.first;

  String get target => '$forwardScheme://$forwardHost:$forwardPort';

  bool get hasCertificate => certificateId > 0;

  bool get hasAccessList => accessListId > 0;

  /// A host that is switched on but whose configuration nginx refused. The only
  /// state worth an alarm: a disabled host is *meant* not to be served, and a
  /// healthy-looking one is only as fresh as the last time it was configured
  /// (see [configLoaded]).
  bool get hasConfigError => enabled && !configLoaded;

  factory NpmProxyHost.fromJson(Map<String, dynamic> json) {
    final meta = json['meta'];
    final metaMap = meta is Map
        ? meta.cast<String, dynamic>()
        : const <String, dynamic>{};
    final domains = json['domain_names'];
    return NpmProxyHost(
      id: parseInt(json['id']),
      domainNames: domains is List
          ? domains.map((e) => e.toString()).toList(growable: false)
          : const [],
      forwardScheme: json['forward_scheme']?.toString() ?? 'http',
      forwardHost: json['forward_host']?.toString() ?? '',
      forwardPort: parseInt(json['forward_port']),
      enabled: parseBool(json['enabled']),
      sslForced: parseBool(json['ssl_forced']),
      certificateId: parseInt(json['certificate_id']),
      accessListId: parseInt(json['access_list_id']),
      cachingEnabled: parseBool(json['caching_enabled']),
      blockExploits: parseBool(json['block_exploits']),
      allowWebsocketUpgrade: parseBool(json['allow_websocket_upgrade']),
      // Absent means nginx has not complained, which is the healthy reading.
      configLoaded: metaMap.containsKey('nginx_online')
          ? parseBool(metaMap['nginx_online'])
          : true,
      errorText: metaMap['nginx_err']?.toString() ?? '',
      advancedConfig: json['advanced_config']?.toString() ?? '',
    );
  }
}

/// A TLS certificate NPM holds.
///
/// Deliberately does **not** model `meta`. For an uploaded certificate that
/// object contains private key material, and for a Let's Encrypt one it holds
/// the DNS-provider credentials used for the challenge. None of it is needed to
/// show an expiry date, and a field that is never parsed is a field that cannot
/// end up in a cache, a log or a diagnostics export.
class NpmCertificate {
  const NpmCertificate({
    required this.id,
    required this.provider,
    required this.niceName,
    required this.domainNames,
    required this.expiresOn,
  });

  final int id;

  /// `letsencrypt` or `other` (an uploaded certificate).
  final String provider;

  final String niceName;
  final List<String> domainNames;
  final DateTime? expiresOn;

  bool get isLetsEncrypt => provider == 'letsencrypt';

  /// Whole days until expiry, or null when NPM did not give a date.
  ///
  /// **Truncated toward zero, so it cannot be used to ask whether a
  /// certificate has lapsed.** `Duration.inDays` on a date six hours in the
  /// past is 0, not -1, which makes `days < 0` blind for a full day — and that
  /// day is exactly the one somebody opens the app on. [hasExpired] is the
  /// question; this is only the magnitude.
  int? daysUntilExpiry(DateTime now) {
    final expiry = expiresOn;
    if (expiry == null) return null;
    return expiry.difference(now).inDays;
  }

  /// Whether the date NPM gave is already behind us.
  ///
  /// A date comparison rather than a day count, for the reason spelled out on
  /// [daysUntilExpiry]: the truncated count says 0 for the whole twenty-four
  /// hours after a certificate lapses, and 0 reads as "expires today" — a
  /// deadline — about something every browser is already refusing.
  ///
  /// False for an undated certificate: no date, no claim in either direction.
  bool hasExpired(DateTime now) {
    final expiry = expiresOn;
    return expiry != null && !expiry.isAfter(now);
  }

  /// Certificates worth surfacing. Let's Encrypt renews at 30 days out, so a
  /// shorter window than that would only ever fire on one that is already
  /// failing to renew — which is exactly the case this is for.
  ///
  /// **Deliberately still true for a lapsed certificate.** This is the "needs
  /// a human" window, and the Dashboard's decision feed
  /// (`_expiringCertificateDecisions`) is built straight off it — narrowing it
  /// here would make an expired certificate vanish from the one surface that
  /// collects faults across services. Anything that *prints the word
  /// "expiring"* has to pair it with [hasExpired] instead, so a lapse is never
  /// reported as a deadline.
  bool isExpiringSoon(DateTime now) {
    final days = daysUntilExpiry(now);
    return days != null && days <= 21;
  }

  /// A Let's Encrypt certificate inside its own renewal window that has not
  /// renewed.
  ///
  /// This is the *only* honest failed-renewal reason this app can give, and it
  /// is derived rather than quoted. NPM keeps no renewal-error field on the
  /// certificate record: the text exists in `/api/audit-log` (not modelled) and
  /// in the body of the renew call, which [NpmClient] deliberately never
  /// renders — certbot failures carry the DNS-provider credentials used for the
  /// challenge. What is left is the fact itself, and the fact is enough:
  /// certbot renews from 30 days out, so a certificate still short-dated inside
  /// that window is one whose renewal is not completing. The board says exactly
  /// that — "renewal not completing · Let's Encrypt renews from 30 days out".
  ///
  /// The copy stays on the safe side of the inference — "renewal has not run"
  /// rather than "renewal failed" — because the window is the only evidence
  /// there is. Inside it, that sentence is true whether certbot is erroring or
  /// simply never being reached.
  ///
  /// False for an uploaded certificate: nothing renews it, so nothing is
  /// failing to.
  bool renewalNotCompleting(DateTime now) {
    if (!isLetsEncrypt) return false;
    final days = daysUntilExpiry(now);
    return days != null && days <= _letsEncryptRenewalWindowDays;
  }

  /// certbot's own window, not a number picked here.
  static const int _letsEncryptRenewalWindowDays = 30;

  String get displayName =>
      niceName.isNotEmpty ? niceName : (domainNames.firstOrNull ?? 'Untitled');

  factory NpmCertificate.fromJson(Map<String, dynamic> json) {
    final domains = json['domain_names'];
    return NpmCertificate(
      id: parseInt(json['id']),
      provider: json['provider']?.toString() ?? '',
      niceName: json['nice_name']?.toString() ?? '',
      domainNames: domains is List
          ? domains.map((e) => e.toString()).toList(growable: false)
          : const [],
      expiresOn: DateTime.tryParse(json['expires_on']?.toString() ?? ''),
    );
  }
}

/// The things an NPM account's permission map can be scoped to.
///
/// NPM's own keys, spelled as it spells them. A non-admin account carries one
/// of `hidden` / `view` / `manage` per entry, and the app has to ask per
/// resource rather than once: an account that may edit proxy hosts but not
/// certificates is a shape NPM allows, and a single "can this user write"
/// boolean would dim the wrong half of the screen.
enum NpmResource {
  proxyHosts('proxy_hosts'),
  redirectionHosts('redirection_hosts'),
  deadHosts('dead_hosts'),
  streams('streams'),
  certificates('certificates'),
  accessLists('access_lists');

  const NpmResource(this.key);

  final String key;
}

/// `GET /api/users/me` — who this token belongs to and what it may do.
///
/// Decision 34: the screen knows before a write is attempted. NPM says so
/// itself, so the alternative — offering every control and letting a 403 teach
/// the user — is a choice rather than a limitation.
///
/// **The email is deliberately not modelled.** The role is what the UI needs;
/// the address identifies a person and would end up in every diagnostics dump
/// that touches this object. [name] is NPM's `nickname`, which is what its own
/// UI shows.
class NpmAccount {
  const NpmAccount({
    required this.id,
    required this.name,
    required this.isAdmin,
    required Map<String, String> permissions,
  }) : _permissions = permissions;

  final int id;
  final String name;

  /// `roles` contains `admin`. An admin's permission map is not populated by
  /// NPM at all, so this has to short-circuit the lookup rather than fall
  /// through it — reading the map for an admin finds nothing and would dim
  /// every control on the screen for the one account that can use them.
  final bool isAdmin;

  final Map<String, String> _permissions;

  bool canManage(NpmResource resource) =>
      isAdmin || _permissions[resource.key] == 'manage';

  /// Nothing on this connection can be changed. What the banner is for; the
  /// per-resource [canManage] is what each control is for.
  bool get isViewOnly => !NpmResource.values.any(canManage);

  factory NpmAccount.fromJson(Map<String, dynamic> json) {
    final roles = json['roles'];
    final permissions = json['permissions'];
    return NpmAccount(
      id: parseInt(json['id']),
      // `nickname` is what NPM's own header shows; `name` is the fallback.
      name: (json['nickname']?.toString().trim().isNotEmpty ?? false)
          ? json['nickname'].toString()
          : json['name']?.toString() ?? 'this account',
      isAdmin:
          roles is List &&
          roles.any((r) => r.toString().toLowerCase() == 'admin'),
      permissions: permissions is Map
          ? {
              for (final entry in permissions.entries)
                entry.key.toString(): entry.value.toString(),
            }
          : const {},
    );
  }
}

/// What a client-side probe found at a proxy host's forward target.
///
/// Three values, not two: a host nobody probed is not a host that failed. The
/// probe is budgeted — the board heads the table "reachability checked for 8 of
/// 23" — so [unchecked] is the normal state for most rows and must read as the
/// absence of a measurement rather than as a verdict.
enum NpmUpstream {
  /// Something accepted a TCP connection on the forward host and port.
  answering,

  /// Nothing accepted, or nothing answered in time.
  down,

  /// Outside this pass's budget, or the host is disabled so nothing is being
  /// served through it anyway.
  unchecked,
}

/// A `302`/`301` hostname, a `404` host, or a TCP/UDP stream — the three
/// smaller host kinds, which differ enough to name but not enough to model
/// separately for a dashboard.
class NpmSimpleHost {
  const NpmSimpleHost({
    required this.id,
    required this.label,
    required this.detail,
    required this.enabled,
    required this.configLoaded,
  });

  final int id;
  final String label;
  final String detail;
  final bool enabled;

  /// Same caveat as [NpmProxyHost.configLoaded]: the result of the last
  /// configuration attempt, not a live probe.
  final bool configLoaded;

  bool get hasConfigError => enabled && !configLoaded;

  static bool _configLoaded(Map<String, dynamic> json) {
    final meta = json['meta'];
    final metaMap = meta is Map
        ? meta.cast<String, dynamic>()
        : const <String, dynamic>{};
    return metaMap.containsKey('nginx_online')
        ? parseBool(metaMap['nginx_online'])
        : true;
  }

  static String _firstDomain(Map<String, dynamic> json) {
    final domains = json['domain_names'];
    if (domains is List && domains.isNotEmpty) return domains.first.toString();
    return 'Unnamed';
  }

  factory NpmSimpleHost.redirection(Map<String, dynamic> json) {
    final scheme = json['forward_scheme']?.toString() ?? 'auto';
    final target = json['forward_domain_name']?.toString() ?? '';
    return NpmSimpleHost(
      id: parseInt(json['id']),
      label: _firstDomain(json),
      detail: '→ $scheme://$target',
      enabled: parseBool(json['enabled']),
      configLoaded: _configLoaded(json),
    );
  }

  factory NpmSimpleHost.dead(Map<String, dynamic> json) {
    return NpmSimpleHost(
      id: parseInt(json['id']),
      label: _firstDomain(json),
      detail: '404 host',
      enabled: parseBool(json['enabled']),
      configLoaded: _configLoaded(json),
    );
  }

  factory NpmSimpleHost.stream(Map<String, dynamic> json) {
    final incoming = parseInt(json['incoming_port']);
    final host = json['forwarding_host']?.toString() ?? '';
    final port = parseInt(json['forwarding_port']);
    final protocols = <String>[
      if (parseBool(json['tcp_forwarding'])) 'TCP',
      if (parseBool(json['udp_forwarding'])) 'UDP',
    ];
    return NpmSimpleHost(
      id: parseInt(json['id']),
      label: ':$incoming',
      detail: '${protocols.join('/')} → $host:$port',
      enabled: parseBool(json['enabled']),
      configLoaded: _configLoaded(json),
    );
  }
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
