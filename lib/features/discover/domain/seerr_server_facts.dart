import 'package:flutter/foundation.dart';

import 'package:cupola/features/discover/domain/seerr_grant.dart';

/// Which project a Seerr-compatible server is.
///
/// Not readable from the version alone: Jellyseerr shipped 1.0.0 to 1.9.2
/// before its 2.x, so a `1.x` is either Overseerr or Jellyseerr. The shape of
/// `/settings/public` tells them apart (see [SeerrServerFacts.family]).
enum SeerrFamily {
  /// `sct/overseerr`, Plex only, archived after 1.35.0.
  overseerr,

  /// `seerr-team/seerr` before the merge: Jellyseerr 1.x and 2.x.
  jellyseerr,

  /// `seerr-team/seerr` from 3.0.0.
  seerr,
}

/// The media server a Seerr server is set up with: its `mediaServerType`.
enum SeerrMediaServer {
  plex,
  jellyfin,
  emby,

  /// `mediaServerType` 4: the server has none yet.
  notConfigured,
}

/// A way to sign in to a Seerr server with one's own account.
enum SeerrSignInMethod {
  /// Plex, through plex.tv: `POST /auth/plex`.
  plex,

  /// Jellyfin username and password: `POST /auth/jellyfin`.
  jellyfin,

  /// A code approved from a Jellyfin app already signed in:
  /// `/auth/jellyfin/quickconnect/*`, Seerr 3.4.0 and later.
  jellyfinQuickConnect,

  /// Emby username and password: the Jellyfin route, under its own name.
  emby,

  /// The server's own email and password: `POST /auth/local`.
  local,
}

/// Whether a server can be signed in to at all.
enum SeerrSignInState {
  /// `initialized` is not true: the server is still in its first setup. The
  /// first media-server sign-in there **creates an admin** and sets the
  /// server up (`auth.ts:100-118`, `:334-430`), so the app never calls a
  /// sign-in route on it.
  notSetUp,

  /// Set up, and every way of signing in is turned off.
  turnedOff,

  /// At least one method is offered.
  open,
}

/// The sign-in methods a server offers, read from its `/settings/public`.
///
/// The one place that decides which `/auth/*` route the app may call. A method
/// is offered only when the server would take it **and** calling it cannot
/// change the server: never on a server still in setup, never a media-server
/// sign-in on a server without a media server.
@immutable
final class SeerrSignInMethods {
  const SeerrSignInMethods._(this.state, this.offered);

  /// The methods `/settings/public` ([json]) offers, from a server whose
  /// `/status` reported [version].
  ///
  /// The rules, from the `fullPublicSettings` of each tag:
  ///
  ///  1. `initialized` not true: [SeerrSignInState.notSetUp], nothing offered.
  ///  2. No `mediaServerType` (Overseerr): Plex always, local if `localLogin`.
  ///  3. Otherwise the media server's own method (1 Plex, 2 Jellyfin, 3 Emby,
  ///     4 none) unless `mediaServerLogin` is false, which Jellyseerr 1.x does
  ///     not send and so leaves on. Local if `localLogin`.
  ///  4. Quick Connect with the Jellyfin method, from Seerr 3.4.0.
  ///  5. Nothing left: [SeerrSignInState.turnedOff].
  ///
  /// In the order Seerr's own sign-in page shows them: the media server first,
  /// then the local account (`src/components/Login/index.tsx`).
  factory SeerrSignInMethods.fromPublicSettings(
    Map<String, dynamic> json, {
    String? version,
  }) {
    if (json['initialized'] != true) {
      return const SeerrSignInMethods._(SeerrSignInState.notSetUp, []);
    }
    final local = json['localLogin'] == true;
    final server = _mediaServerOf(json);
    final serverLogin =
        !json.containsKey('mediaServerType') ||
        json['mediaServerLogin'] != false;

    final offered = <SeerrSignInMethod>[
      if (serverLogin)
        ...switch (server) {
          SeerrMediaServer.plex => [SeerrSignInMethod.plex],
          SeerrMediaServer.jellyfin => [
            SeerrSignInMethod.jellyfin,
            if (_atLeast(version, 3, 4)) SeerrSignInMethod.jellyfinQuickConnect,
          ],
          SeerrMediaServer.emby => [SeerrSignInMethod.emby],
          SeerrMediaServer.notConfigured || null => const <SeerrSignInMethod>[],
        },
      if (local) SeerrSignInMethod.local,
    ];
    return SeerrSignInMethods._(
      offered.isEmpty ? SeerrSignInState.turnedOff : SeerrSignInState.open,
      List.unmodifiable(offered),
    );
  }

  final SeerrSignInState state;

  /// The methods, in the order they are offered. Empty unless [state] is
  /// [SeerrSignInState.open].
  final List<SeerrSignInMethod> offered;

  bool offers(SeerrSignInMethod method) => offered.contains(method);

  @override
  bool operator ==(Object other) =>
      other is SeerrSignInMethods &&
      other.state == state &&
      listEquals(other.offered, offered);

  @override
  int get hashCode => Object.hash(state, Object.hashAll(offered));

  @override
  String toString() =>
      'SeerrSignInMethods(${state.name}, '
      '${offered.map((method) => method.name).join(', ')})';
}

/// What a Seerr server says about itself before anyone signs in: its
/// `/settings/public` and the version its `/status` reported.
///
/// Facts about the **server**, the same for every account on it. What one
/// account may do is a `SeerrGrant`.
@immutable
final class SeerrServerFacts {
  const SeerrServerFacts({
    required this.signIn,
    this.family,
    this.version,
    this.mediaServer,
    this.applicationTitle,
    this.movie4kEnabled = false,
    this.series4kEnabled = false,
    this.partialRequestsEnabled = false,
    this.emailEnabled = false,
    this.jellyfinForgotPasswordUrl,
  });

  /// The facts in `/settings/public` ([json]), from a server whose `/status`
  /// reported [version].
  ///
  /// A missing or malformed flag reads as off: a 4K option, a partial request
  /// or a password reset the server did not say it has is not offered.
  factory SeerrServerFacts.fromPublicSettings(
    Map<String, dynamic> json, {
    String? version,
  }) {
    String? text(Object? value) =>
        value is String && value.trim().isNotEmpty ? value.trim() : null;
    return SeerrServerFacts(
      signIn: SeerrSignInMethods.fromPublicSettings(json, version: version),
      family: _familyOf(json, version),
      version: text(version),
      mediaServer: _mediaServerOf(json),
      applicationTitle: text(json['applicationTitle']),
      movie4kEnabled: json['movie4kEnabled'] == true,
      series4kEnabled: json['series4kEnabled'] == true,
      partialRequestsEnabled: json['partialRequestsEnabled'] == true,
      emailEnabled: json['emailEnabled'] == true,
      jellyfinForgotPasswordUrl: text(json['jellyfinForgotPasswordUrl']),
    );
  }

  final SeerrSignInMethods signIn;

  /// Null when the shape and the version disagree with every known release:
  /// a `develop-<sha>` build, say.
  final SeerrFamily? family;

  /// As `/status` said it: `3.5.0`, `develop-4f2a9c1`.
  final String? version;

  /// Null when the server named a media server this app does not know.
  final SeerrMediaServer? mediaServer;

  /// The name the operator gave the server, `applicationTitle`. Null when
  /// blank; [title] has the fallback.
  final String? applicationTitle;

  /// Whether a default 4K Radarr is set up: the server would route a 4K movie
  /// request somewhere.
  final bool movie4kEnabled;

  /// Whether a default 4K Sonarr is set up.
  final bool series4kEnabled;

  /// Whether a series may be requested season by season.
  final bool partialRequestsEnabled;

  /// Whether the server sends email, and so can send a password reset to a
  /// local account.
  final bool emailEnabled;

  /// Where a Jellyfin user resets a password, when the operator set one.
  final String? jellyfinForgotPasswordUrl;

  /// What the server calls itself.
  String get title => applicationTitle ?? 'Seerr';

  /// Whether the server has somewhere to send a 4K request of [kind].
  bool has4k(SeerrMediaKind kind) => switch (kind) {
    SeerrMediaKind.movie => movie4kEnabled,
    SeerrMediaKind.tv => series4kEnabled,
  };

  @override
  bool operator ==(Object other) =>
      other is SeerrServerFacts &&
      other.signIn == signIn &&
      other.family == family &&
      other.version == version &&
      other.mediaServer == mediaServer &&
      other.applicationTitle == applicationTitle &&
      other.movie4kEnabled == movie4kEnabled &&
      other.series4kEnabled == series4kEnabled &&
      other.partialRequestsEnabled == partialRequestsEnabled &&
      other.emailEnabled == emailEnabled &&
      other.jellyfinForgotPasswordUrl == jellyfinForgotPasswordUrl;

  @override
  int get hashCode => Object.hash(
    signIn,
    family,
    version,
    mediaServer,
    applicationTitle,
    movie4kEnabled,
    series4kEnabled,
    partialRequestsEnabled,
    emailEnabled,
    jellyfinForgotPasswordUrl,
  );

  /// Names, flags and methods only: no address, the reset link included.
  @override
  String toString() =>
      'SeerrServerFacts(${family?.name}, ${mediaServer?.name}, $signIn, '
      '4k: $movie4kEnabled/$series4kEnabled)';
}

/// The media server `mediaServerType` names. Overseerr sends no
/// `mediaServerType` and is always Plex.
SeerrMediaServer? _mediaServerOf(Map<String, dynamic> json) {
  if (!json.containsKey('mediaServerType')) return SeerrMediaServer.plex;
  return switch (json['mediaServerType']) {
    1 => SeerrMediaServer.plex,
    2 => SeerrMediaServer.jellyfin,
    3 => SeerrMediaServer.emby,
    4 => SeerrMediaServer.notConfigured,
    _ => null,
  };
}

/// Overseerr has no `mediaServerType`, Jellyseerr 1.x has no
/// `mediaServerLogin`, and from there the major version decides.
SeerrFamily? _familyOf(Map<String, dynamic> json, String? version) {
  if (!json.containsKey('mediaServerType')) return SeerrFamily.overseerr;
  if (!json.containsKey('mediaServerLogin')) return SeerrFamily.jellyseerr;
  final major = _versionOf(version)?.$1;
  if (major == null) return null;
  return major >= 3 ? SeerrFamily.seerr : SeerrFamily.jellyseerr;
}

/// Whether [version] is at least [major].[minor]. An unreadable version is
/// not: a method only some builds have is not offered on a guess.
bool _atLeast(String? version, int major, int minor) {
  final parsed = _versionOf(version);
  if (parsed == null) return false;
  final (actualMajor, actualMinor) = parsed;
  return actualMajor > major || (actualMajor == major && actualMinor >= minor);
}

/// `3.5.0`, `v3.4.1` → (3, 5), (3, 4). Null for `develop-<sha>` and the like.
(int, int)? _versionOf(String? version) {
  final match = RegExp(r'^[vV]?(\d+)\.(\d+)').firstMatch(version?.trim() ?? '');
  if (match == null) return null;
  return (int.parse(match.group(1)!), int.parse(match.group(2)!));
}
