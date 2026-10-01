import 'dart:convert';

import 'package:flutter/foundation.dart' show listEquals;

/// One header a connection adds for whatever stands in front of its service.
typedef AccessHeader = ({String name, String value});

/// What a connection presents to a gateway in front of its service (Cloudflare
/// Access, a reverse proxy's password prompt, a custom header a proxy checks),
/// on every request it makes: API calls, posters, WebSocket upgrades and the
/// background release search.
///
/// **Per connection, not per origin.** A certificate belongs to the host that
/// presents it (ADR-6), and is shared by every connection reaching that host.
/// Access is different: a Cloudflare service token belongs to one Access
/// application, and a proxy can ask for a different password on each path, so
/// two connections behind one host can need two different credentials.
/// Sharing one is an explicit offer, never an inference.
///
/// Lives on `ServiceInstance` today because a connection has one address. It
/// is shaped to move onto an address unchanged when a connection gains a
/// second one (the access almost always belongs to the address away from
/// home, where the tunnel is).
///
/// **Never printed.** No [toString] here or on a subclass names a value, and
/// none of them reaches a failure sentence, a log line or Diagnostics:
/// `connection_access_test.dart` proves it with a sentinel.
sealed class ConnectionAccess {
  const ConnectionAccess();

  /// What goes on every request of the connection, or an empty map when there
  /// is nothing complete to send: a half-filled token is not sent at all,
  /// because a gateway that refuses it would read as a token refused.
  Map<String, String> headers();

  /// Which of the four choices this is.
  AccessKind get kind;

  /// Whether there is anything to send.
  bool get isEmpty => headers().isEmpty;

  /// The names [headers] sends, as a gateway's answer reads them to tell
  /// whether it was sent anything.
  List<String> get headerNames => headers().keys.toList(growable: false);
}

/// The four choices of a connection's Access row, in the order the form
/// offers them.
enum AccessKind {
  none('None'),
  cloudflare('Cloudflare Access'),
  password('Password'),
  custom('Custom headers');

  const AccessKind(this.label);

  /// The choice as the Access row names it.
  final String label;

  /// The kind stored under [name], or null for one this build does not know.
  static AccessKind? byName(String? name) {
    for (final kind in values) {
      if (kind.name == name) return kind;
    }
    return null;
  }
}

/// Nothing in front of the service asks for anything. The default, and what a
/// connection saved before access existed reads as.
final class NoAccess extends ConnectionAccess {
  const NoAccess();

  @override
  Map<String, String> headers() => const {};

  @override
  AccessKind get kind => AccessKind.none;

  @override
  bool operator ==(Object other) => other is NoAccess;

  @override
  int get hashCode => (NoAccess).hashCode;

  @override
  String toString() => 'NoAccess';
}

/// A Cloudflare Access service token: `CF-Access-Client-Id` and
/// `CF-Access-Client-Secret` on every request, which an Access application
/// lets through when a Service Auth policy names the token.
///
/// [clientId] is not a secret (Cloudflare shows it in the clear, and it is
/// stored beside the address); [clientSecret] is, and lives in secure storage.
final class CloudflareServiceToken extends ConnectionAccess {
  const CloudflareServiceToken({
    required this.clientId,
    required this.clientSecret,
  });

  static const idHeader = 'CF-Access-Client-Id';
  static const secretHeader = 'CF-Access-Client-Secret';

  final String clientId;
  final String clientSecret;

  @override
  Map<String, String> headers() {
    final id = clientId.trim();
    final secret = clientSecret.trim();
    if (id.isEmpty || secret.isEmpty) return const {};
    return {idHeader: id, secretHeader: secret};
  }

  @override
  AccessKind get kind => AccessKind.cloudflare;

  @override
  bool operator ==(Object other) =>
      other is CloudflareServiceToken &&
      other.clientId == clientId &&
      other.clientSecret == clientSecret;

  @override
  int get hashCode =>
      Object.hash(AccessKind.cloudflare, clientId, clientSecret);

  @override
  String toString() => 'CloudflareServiceToken';
}

/// A reverse proxy's username and password: `Authorization: Basic …` on every
/// request.
///
/// [username] is stored beside the address; [password] in secure storage.
final class ProxyPassword extends ConnectionAccess {
  const ProxyPassword({required this.username, required this.password});

  static const header = 'Authorization';

  final String username;
  final String password;

  @override
  Map<String, String> headers() {
    if (username.isEmpty) return const {};
    final token = base64Encode(utf8.encode('$username:$password'));
    return {header: 'Basic $token'};
  }

  @override
  AccessKind get kind => AccessKind.password;

  @override
  bool operator ==(Object other) =>
      other is ProxyPassword &&
      other.username == username &&
      other.password == password;

  @override
  int get hashCode => Object.hash(AccessKind.password, username, password);

  @override
  String toString() => 'ProxyPassword';
}

/// Headers a proxy in front of the service checks, by name and value.
///
/// The names are stored beside the address; every value in secure storage,
/// since a header a gateway checks is a credential whatever it is called.
final class CustomHeaders extends ConnectionAccess {
  const CustomHeaders(this.entries);

  final List<AccessHeader> entries;

  @override
  Map<String, String> headers() => {
    for (final entry in entries)
      if (entry.name.trim().isNotEmpty && entry.value.isNotEmpty)
        entry.name.trim(): entry.value,
  };

  @override
  AccessKind get kind => AccessKind.custom;

  @override
  bool operator ==(Object other) =>
      other is CustomHeaders && listEquals(other.entries, entries);

  @override
  int get hashCode => Object.hash(AccessKind.custom, Object.hashAll(entries));

  @override
  String toString() => 'CustomHeaders(${entries.length})';
}
