import 'dart:math';

import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// One configured connection to one server.
///
/// The unit the app is keyed on. [ServiceKey] answers *what kind of thing is
/// this* — its API, its icon, where its credential lives in its own UI — and a
/// [ServiceInstance] answers *which one*: this Radarr at this address with this
/// key, told apart from the other Radarr by a name the user chose.
///
/// ## Why the id is the route param for the first one
///
/// [id] is opaque, stable and generated once. The first instance of a service
/// takes the service's own [ServiceKeyExtension.routeParam] as its id, and
/// every later one takes `routeParam-xxxxxxxx`. That is not cosmetic — it is
/// what makes this change invisible to an existing install:
///
/// * every storage key on this class derives from [id], and for the first
///   instance each one reproduces **exactly** the key that service already
///   used (`radarr_url`, `secure_radarr_api_key`, `qbittorrent_username`,
///   `jellyfin_user_id`). No credential is ever read from one key and written
///   to another, which is the one migration that cannot be made safe: a
///   half-completed secret move loses the secret.
/// * a saved deep link to `/services/radarr` still names a real instance.
///
/// The id is never derived from the URL. An address is a thing the user edits;
/// an identity is not, and keying on the URL would break every saved link the
/// first time a server moved.
class ServiceInstance {
  /// Opaque, stable, generated once. See the class doc for why the first
  /// instance of a service is named after the service.
  final String id;

  /// Which kind of server this is.
  final ServiceKey service;

  /// The short name the user gave this instance — `4K`, `HD`, `Casa`.
  ///
  /// Empty for a service with only one instance, and that emptiness is the
  /// whole of the "you do not pay for the fold until you need it" rule: with no
  /// label there is no badge in the app bar, no suffix in a title, and no chip
  /// on a search row. Required from the second instance onwards, because two
  /// rows both called "Radarr" is the state this feature exists to prevent.
  final String label;

  final String url;

  /// The secret half of this instance's credential: an API key, a password or
  /// a token, depending on what the service issues. One slot rather than three
  /// because a connection has exactly one secret, and which vocabulary it goes
  /// by is the service's business — see [ServiceKeyExtension.credentialLabel].
  final String credential;

  /// The non-secret half, for the services that authenticate on a pair.
  /// Empty for the API-key services, which have none.
  final String username;

  /// Which viewer's watch state this library is read through. Jellyfin only —
  /// see [ServiceKeyExtension.needsViewerSelection].
  ///
  /// Per instance, not per install: two Jellyfin servers have two different
  /// user tables, and carrying one server's user id to the other binds every
  /// per-viewer query to an id that does not exist there.
  final String viewerId;

  /// What this connection presents to a gateway in front of the service, on
  /// every request it makes. [NoAccess] unless the user set one.
  ///
  /// Per connection rather than per origin, unlike a trusted certificate: see
  /// [ConnectionAccess]. Its non-secret half is stored beside the address
  /// ([accessStorageKey]) and its secrets in secure storage under keys derived
  /// from [id] ([accessSecretStorageKey], [accessHeaderStorageKey]), so
  /// removing the connection removes them.
  final ConnectionAccess access;

  const ServiceInstance({
    required this.id,
    required this.service,
    this.label = '',
    this.url = '',
    this.credential = '',
    this.username = '',
    this.viewerId = '',
    this.access = const NoAccess(),
  });

  /// The id the first instance of [service] takes. See the class doc.
  static String primaryIdFor(ServiceKey service) => service.routeParam;

  /// Mints an id for a new instance of [service] that collides with nothing in
  /// [taken].
  ///
  /// Hands out the primary id first, so a service configured for the first time
  /// lands on the keys it would have used before this class existed. Only once
  /// that is spoken for does it start suffixing.
  static String mintId(
    ServiceKey service,
    Iterable<String> taken, {
    Random? random,
  }) {
    final primary = primaryIdFor(service);
    final used = taken.toSet();
    if (!used.contains(primary)) return primary;

    final rng = random ?? Random.secure();
    while (true) {
      final suffix = rng.nextInt(0xFFFFFFF).toRadixString(16).padLeft(7, '0');
      final candidate = '$primary-$suffix';
      if (!used.contains(candidate)) return candidate;
    }
  }

  /// Whether this instance holds the slot whose storage keys predate the
  /// multi-instance model.
  bool get isPrimarySlot => id == primaryIdFor(service);

  /// Where this instance's address lives in `SharedPreferences`.
  String get urlStorageKey => '${id}_url';

  /// Where the non-secret half of the credential lives.
  String get usernameStorageKey => '${id}_username';

  /// Where the chosen viewer lives, for the one service that needs one.
  String get viewerIdStorageKey => '${id}_user_id';

  /// Where the secret lives, in secure storage.
  ///
  /// The suffix belongs to the *service* — Plex issues a token, qBittorrent
  /// takes a password, the arrs mint an API key — so it comes from the registry
  /// rather than being flattened to one word here. That is what makes the
  /// primary instance's key byte-identical to the one already on disk.
  String get credentialStorageKey =>
      'secure_${id}_${service.credentialStorageSuffix}';

  /// Where the non-secret half of [access] lives in `SharedPreferences`: its
  /// kind, the Cloudflare Client ID, the proxy's username, the custom header
  /// names. Absent for [NoAccess], which is also what an install that predates
  /// access reads, so there is nothing to migrate.
  String get accessStorageKey => '${id}_access';

  /// Where the secret of [access] lives in secure storage: the Cloudflare
  /// Client Secret, or the proxy's password.
  String get accessSecretStorageKey => 'secure_${id}_access_secret';

  /// Where the value of custom header [index] lives in secure storage.
  String accessHeaderStorageKey(int index) =>
      'secure_${id}_access_header_$index';

  /// Whether this instance is set up enough to be worth talking to.
  ///
  /// A credential-authenticated service can legitimately run with no auth at
  /// all behind a reverse proxy, so only the address is strictly required
  /// there. Which services those are is the registry's answer, never a list
  /// repeated at the call site.
  bool get isConfigured {
    if (!service.usesApiKey) return url.isNotEmpty;
    return url.isNotEmpty && credential.isNotEmpty;
  }

  /// The join: `Radarr` with no label, `Radarr · 4K` with one.
  ///
  /// **Formatting only — it cannot answer whether the label should be shown.**
  /// A label outlives the sibling that made it necessary: derive one for the
  /// original Radarr when a second is added, remove the second, and the survivor
  /// still carries `4K` while every badge, chip and section heading has gone
  /// quiet again because they all ask `hasMultipleInstances` first. Reading this
  /// getter directly therefore printed "Added to Radarr · 7878" for the only
  /// Radarr there is.
  ///
  /// Call [SettingsModel.connectionTitle] instead wherever a sentence names a
  /// connection; it applies the same rule as the rest of the app.
  String get displayTitle =>
      label.isEmpty ? service.title : '${service.title} · $label';

  ServiceInstance copyWith({
    String? label,
    String? url,
    String? credential,
    String? username,
    String? viewerId,
    ConnectionAccess? access,
  }) {
    return ServiceInstance(
      id: id,
      service: service,
      label: label ?? this.label,
      url: url ?? this.url,
      credential: credential ?? this.credential,
      username: username ?? this.username,
      viewerId: viewerId ?? this.viewerId,
      access: access ?? this.access,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ServiceInstance &&
        other.id == id &&
        other.service == service &&
        other.label == label &&
        other.url == url &&
        other.credential == credential &&
        other.username == username &&
        other.viewerId == viewerId &&
        other.access == access;
  }

  @override
  int get hashCode => Object.hash(
    id,
    service,
    label,
    url,
    credential,
    username,
    viewerId,
    access,
  );

  /// The kind of access only, never its values.
  @override
  String toString() =>
      'ServiceInstance($id, ${service.name}, label: "$label", url: "$url", '
      'access: ${access.kind.name})';
}
