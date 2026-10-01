import 'package:flutter/foundation.dart';

/// How a Seerr connection signs in.
///
/// Exhaustive on purpose: a new way in must be answered by the transport
/// (`seerrClientFor`), the storage and the gate before it compiles.
@immutable
sealed class SeerrSignIn {
  const SeerrSignIn();
}

/// The operator's way: the instance's API key. Seerr treats it as user 1, its
/// first admin.
final class SeerrApiKeySignIn extends SeerrSignIn {
  const SeerrApiKeySignIn(this.key);

  /// Secret. Lives in secure storage, under the connection's credential key.
  final String key;

  @override
  bool operator ==(Object other) =>
      other is SeerrApiKeySignIn && other.key == key;

  @override
  int get hashCode => Object.hash(SeerrApiKeySignIn, key);

  /// Never the key.
  @override
  String toString() => 'SeerrApiKeySignIn()';
}

/// Which account a household member signs in to Seerr with.
enum SeerrAccountKind {
  /// The server's own email and password: `POST /auth/local`.
  local,

  /// A Jellyfin user the server knows: `POST /auth/jellyfin`, or a code
  /// approved from a Jellyfin app (Quick Connect).
  jellyfin,

  /// An Emby user: the Jellyfin route, under its own name.
  emby,

  /// A Plex account, through plex.tv: `POST /auth/plex`.
  plex;

  /// The kind [name] spells, or null for one this build does not know.
  static SeerrAccountKind? byName(String? name) =>
      values.where((kind) => kind.name == name).firstOrNull;
}

/// A household member's own Seerr account.
///
/// The password never lives here, nor the Plex token: only the session the
/// server handed back ([session], the `connect.sid` cookie's value) and what
/// the app read about the account. Signing out empties [session] and keeps the
/// rest, so signing in again is one step.
@immutable
final class SeerrAccountSignIn extends SeerrSignIn {
  const SeerrAccountSignIn({
    required this.kind,
    this.login = '',
    this.userId = 0,
    this.displayName = '',
    this.session = '',
    this.permissions = 0,
    this.checkedAt,
  });

  final SeerrAccountKind kind;

  /// What the person typed to sign in: the email of a local account, the
  /// Jellyfin or Emby username. Empty for Plex. Not secret, so the form can
  /// be filled in again.
  final String login;

  /// Seerr's own id for the account, from the sign-in answer.
  final int userId;

  /// The name the server knows the account by: "Signed in as Anna".
  final String displayName;

  /// Secret: the `connect.sid` value, as the cookie carries it. Empty while
  /// signed out.
  final String session;

  /// The `permissions` of the last `/auth/me` answer, so the app knows what
  /// the account may do on its first frame.
  final int permissions;

  /// When that answer arrived. Null before the first one.
  final DateTime? checkedAt;

  /// Whether a session is held: an account without one is signed out.
  bool get isSignedIn => session.isNotEmpty;

  SeerrAccountSignIn copyWith({
    String? login,
    int? userId,
    String? displayName,
    String? session,
    int? permissions,
    DateTime? checkedAt,
  }) => SeerrAccountSignIn(
    kind: kind,
    login: login ?? this.login,
    userId: userId ?? this.userId,
    displayName: displayName ?? this.displayName,
    session: session ?? this.session,
    permissions: permissions ?? this.permissions,
    checkedAt: checkedAt ?? this.checkedAt,
  );

  /// This account signed out: the session gone, the rest kept.
  SeerrAccountSignIn get signedOut => copyWith(session: '');

  @override
  bool operator ==(Object other) =>
      other is SeerrAccountSignIn &&
      other.kind == kind &&
      other.login == login &&
      other.userId == userId &&
      other.displayName == displayName &&
      other.session == session &&
      other.permissions == permissions &&
      other.checkedAt == checkedAt;

  @override
  int get hashCode => Object.hash(
    kind,
    login,
    userId,
    displayName,
    session,
    permissions,
    checkedAt,
  );

  /// The kind and the name only: never the session, never the login (an
  /// email is personal).
  @override
  String toString() => 'SeerrAccountSignIn(${kind.name}, "$displayName")';
}
