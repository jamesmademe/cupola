import 'package:cupola/features/discover/domain/seerr_server_facts.dart';
import 'package:cupola/features/discover/domain/seerr_sign_in.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import 'fakes/seerr_sessions.dart' show worldSeerrSessionOf;
import 'world.dart';

/// The six ways one household's configuration differs from another's, as the
/// config inventory's legend names them (a–f).
///
/// Declared on each profile so a test can ask "which profiles exercise the b
/// case" rather than hard-coding a list that drifts from the table.
enum ConfigCase {
  /// a — not set up in Cupola, and unknown to anything else.
  notSetUp('a'),

  /// b — not set up in Cupola, but known through another service (Seerr's
  /// settings know a Radarr that Cupola has no connection to).
  knownThroughAnother('b'),

  /// c — set up, and did not answer.
  didNotAnswer('c'),

  /// d — answered, but not allowed: a refused or read-only credential, or the
  /// Seerr requester.
  notAllowed('d'),

  /// e — more than one connection of one service.
  severalInstances('e'),

  /// f — the media server has an item, but its match is not verified.
  matchNotVerified('f');

  const ConfigCase(this.mark);

  /// The letter the inventory uses.
  final String mark;
}

/// How one connection behaves on the fake network.
///
/// Each value is mapped onto what the real client would see on the wire —
/// a refused socket, a 401, qBittorrent's `Fails.`, a proxy's web page — so
/// the app's own classification code (`classifyConnectionFailure`, the qB
/// login reader, the capability probes) is what turns it into a verdict.
/// Nothing here hands the app a pre-classified error.
///
/// A sealed type rather than an enum because some behaviours carry a value
/// (which service answers instead, which gateway mode). The plain ones are
/// [PlainBehaviour] values, reachable under the names they always had
/// (`ConnectionBehaviour.refusesKey`), so a call site reads the same whether
/// the behaviour it names takes a value or not.
sealed class ConnectionBehaviour {
  const ConnectionBehaviour();

  /// Every request answers from the world's canned data.
  static const answers = PlainBehaviour.answers;

  /// The host refuses the connection. See [PlainBehaviour.didNotAnswer].
  static const didNotAnswer = PlainBehaviour.didNotAnswer;

  /// The host never completes the handshake. See [PlainBehaviour.timesOut].
  static const timesOut = PlainBehaviour.timesOut;

  /// The server refuses the credential. See [PlainBehaviour.refusesKey].
  static const refusesKey = PlainBehaviour.refusesKey;

  /// The credential may read and not write. See [PlainBehaviour.readOnly].
  static const readOnly = PlainBehaviour.readOnly;

  /// A web page answers every request. See [PlainBehaviour.servesHtmlPage].
  static const servesHtmlPage = PlainBehaviour.servesHtmlPage;

  /// Seerr: the account's saved session is over. See
  /// [PlainSeerrBehaviour.sessionExpired].
  static const sessionExpired = PlainSeerrBehaviour.sessionExpired;

  /// Seerr: CSRF protection is on. See [PlainSeerrBehaviour.csrfProtected].
  static const csrfProtected = PlainSeerrBehaviour.csrfProtected;

  /// Seerr: still in its first setup. See
  /// [PlainSeerrBehaviour.notInitialized].
  static const notInitialized = PlainSeerrBehaviour.notInitialized;

  /// Seerr: every account's request limit is reached. See
  /// [PlainSeerrBehaviour.quotaReached].
  static const quotaReached = PlainSeerrBehaviour.quotaReached;

  /// Seerr: one way of signing in is turned off. See [SeerrSignInDisabled].
  const factory ConnectionBehaviour.signInDisabled(SeerrSignInMethod method) =
      SeerrSignInDisabled;

  /// [service] answers at this connection's address. See
  /// [AnswersAsOtherService].
  const factory ConnectionBehaviour.answersAsOtherService(ServiceKey service) =
      AnswersAsOtherService;

  /// Cloudflare Access is in front of the service. See
  /// [BehindCloudflareAccess].
  const factory ConnectionBehaviour.behindCloudflareAccess({
    CloudflareAccessMode mode,
    String team,
    ({String id, String secret})? serviceToken,
    bool tokenHasPolicy,
  }) = BehindCloudflareAccess;

  /// A sign-in page is in front of the service. See [BehindSignInPage].
  const factory ConnectionBehaviour.behindSignInPage({SignInPageMode mode}) =
      BehindSignInPage;

  /// A proxy's password prompt is in front of the service. See
  /// [BehindPasswordPrompt].
  const factory ConnectionBehaviour.behindPasswordPrompt({
    ({String username, String password})? credentials,
  }) = BehindPasswordPrompt;

  /// A short name for a test's description.
  String get label;
}

/// How Cloudflare Access turns away a request it does not let through.
enum CloudflareAccessMode {
  /// A `302` to the team's login (`TEAM.cloudflareaccess.com/cdn-cgi/
  /// access/login/…`), which is what a browser gets.
  redirect,

  /// A `401` with Cloudflare's page (`Server: cloudflare`, a `CF-Ray`).
  unauthorized,
}

/// Cloudflare Access in front of every HTTP request to this connection,
/// public routes and WebSocket upgrades included.
///
/// A request carrying [serviceToken] (`CF-Access-Client-Id` and
/// `CF-Access-Client-Secret`) is let through to the service when
/// [tokenHasPolicy]; without a Service Auth policy the token is turned away
/// like no token at all, which is Access's own behaviour.
final class BehindCloudflareAccess extends ConnectionBehaviour {
  const BehindCloudflareAccess({
    this.mode = CloudflareAccessMode.redirect,
    this.team = 'cupola-home',
    this.serviceToken,
    this.tokenHasPolicy = true,
  });

  final CloudflareAccessMode mode;

  /// The Access team, whose domain is [teamDomain].
  final String team;

  /// The service token Access knows, or null for none.
  final ({String id, String secret})? serviceToken;

  /// Whether a Service Auth policy admits [serviceToken].
  final bool tokenHasPolicy;

  String get teamDomain => '$team.cloudflareaccess.com';

  /// Whether [headers] (lower-cased names) carry a token Access lets through.
  bool admits(Map<String, String> headers) {
    final token = serviceToken;
    return token != null &&
        tokenHasPolicy &&
        headers['cf-access-client-id'] == token.id &&
        headers['cf-access-client-secret'] == token.secret;
  }

  @override
  String get label => 'behind Cloudflare Access (${mode.name})';
}

/// Where a sign-in page answers.
enum SignInPageMode {
  /// A `302` to another host's login: `auth.example.net/login`.
  redirect,

  /// A `200` page with a password field, on the service's own host.
  sameHostForm,
}

/// A sign-in page (Authelia, Authentik, a proxy's login) in front of every
/// HTTP request to this connection, WebSocket upgrades included. Nothing gets
/// through: Cupola cannot sign in to it.
final class BehindSignInPage extends ConnectionBehaviour {
  const BehindSignInPage({this.mode = SignInPageMode.redirect});

  final SignInPageMode mode;

  @override
  String get label => 'behind a sign-in page (${mode.name})';
}

/// A proxy's password prompt (`401`, `WWW-Authenticate: Basic`) in front of
/// every HTTP request to this connection, WebSocket upgrades included. A
/// request whose `Authorization` carries [credentials] is let through.
final class BehindPasswordPrompt extends ConnectionBehaviour {
  const BehindPasswordPrompt({this.credentials});

  final ({String username, String password})? credentials;

  @override
  String get label => 'behind a password prompt';
}

/// Another service of the stack answers at this connection's address, from
/// its own canned data: a Sonarr reached on Radarr's port. Every request,
/// WebSocket upgrades included, is answered by [service]'s fake.
final class AnswersAsOtherService extends ConnectionBehaviour {
  const AnswersAsOtherService(this.service);

  /// Who answers instead.
  final ServiceKey service;

  @override
  String get label => 'answers as ${service.title}';
}

/// The behaviours that take no value.
enum PlainBehaviour implements ConnectionBehaviour {
  /// Every request answers from the world's canned data.
  answers,

  /// The host refuses the connection: `SocketException('Connection refused')`
  /// at dial time, which Dio reports as `connectionError` — a dead host.
  didNotAnswer,

  /// The host never completes the handshake: `SocketException('Connection
  /// timed out')`, which Dio reports as `connectionTimeout`. Raised at once,
  /// so a test never waits out a real deadline. The app classifies it as did
  /// not answer, like [didNotAnswer]: the connection never completed. A
  /// server reached and then slow is `withLatency` past the app's deadline.
  timesOut,

  /// The server answers and refuses the credential, each service in its own
  /// way (401, 403, qBittorrent's `200 Fails.`, SABnzbd's `status: false`,
  /// TrueNAS's `false` login). Its unauthenticated routes — the Jellyfin, Plex,
  /// NPM and Seerr status probes — still answer, as they do live.
  refusesKey,

  /// The credential may read and not write.
  ///
  /// Where the app probes scope (TrueNAS `auth.me`, NPM `users/me`, Unraid
  /// `me`) the probe answers read-only. Jellyfin and Plex answer as a
  /// non-admin / non-owner token: their admin reads are refused too. Every
  /// other service has one admin key, so read-only there means only "a write
  /// is refused with 403" — the generic failure path the legend describes.
  readOnly,

  /// Something other than the service answers every HTTP request with `200`
  /// and a web page: a reverse proxy's default page, an address missing its
  /// base path. The case behind "answering, and the library is empty".
  /// WebSocket upgrades are not affected.
  servesHtmlPage;

  @override
  String get label => name;
}

/// The behaviours only Seerr has: how its sign-in, its sessions and its CSRF
/// guard answer. Every other service answers as [ConnectionBehaviour.answers]
/// under one of these.
///
/// Each one is a state of the server or of the account, sent the way Seerr
/// sends it (the bodies of `server/routes/auth.ts`, `server/middleware/auth.ts`
/// and `@dr.pogodin/csurf`, Seerr v3.5.0), so the app's own refusal reader is
/// what tells them apart.
sealed class SeerrBehaviour extends ConnectionBehaviour {
  const SeerrBehaviour();
}

/// The Seerr behaviours that take no value.
enum PlainSeerrBehaviour implements SeerrBehaviour {
  /// The account's saved session is over: it expired on the server, or the
  /// user signed out somewhere else. The session the profile starts with is
  /// already gone, so every route it reaches answers `403 {status: 403,
  /// error: 'You do not have permission to access this endpoint'}`, and
  /// `/auth/me` too. The API key is untouched, and a new sign-in starts a new
  /// session that works.
  sessionExpired,

  /// CSRF protection is on (Settings › Network). Every POST, PUT, PATCH and
  /// DELETE, sign-ins and the API key included, needs the `_csrf` cookie and
  /// its token in `X-XSRF-TOKEN` (or `csrf-token`, `xsrf-token`,
  /// `x-csrf-token`); without them it is refused with `403 {message:
  /// 'invalid csrf token'}`. Every answer that gets past the guard sets
  /// `XSRF-TOKEN`, and an answer to a request without the secret sets `_csrf`.
  csrfProtected,

  /// The server is still in its first setup: `/settings/public` answers
  /// `initialized: false` with no media server and no user exists, so the
  /// API key reaches nobody. A Plex sign-in there **creates the admin**, as
  /// upstream's does: the trap the app's guard exists for.
  notInitialized,

  /// Every account's request limit is full: `GET /user/{id}/quota` answers
  /// `restricted: true` for both kinds and `POST /request` is refused with
  /// `Movie Quota exceeded.` or `Series Quota exceeded.`. An account with
  /// MANAGE_USERS has no limit, and the API key is the admin.
  quotaReached;

  @override
  String get label => name;
}

/// One way of signing in to Seerr is turned off.
///
/// [SeerrSignInMethod.local] turns `localLogin` off and `/auth/local` answers
/// `500 {error: 'Password sign-in is disabled.'}`. The media-server methods
/// turn `mediaServerLogin` off, which closes Plex, Jellyfin and Emby together:
/// `500 {error: 'Plex login is disabled'}` and `{error: 'Jellyfin login is
/// disabled'}`. [SeerrSignInMethod.jellyfinQuickConnect] turns Quick Connect
/// off in Jellyfin itself: `/settings/public` does not say so, and the
/// `initiate` call fails with `500 {message: 'Failed to initiate quick
/// connect.'}`.
final class SeerrSignInDisabled extends SeerrBehaviour {
  const SeerrSignInDisabled(this.method);

  final SeerrSignInMethod method;

  /// Whether `localLogin` reads false.
  bool get localLoginOff => method == SeerrSignInMethod.local;

  /// Whether `mediaServerLogin` reads false.
  bool get mediaServerLoginOff => switch (method) {
    SeerrSignInMethod.plex ||
    SeerrSignInMethod.jellyfin ||
    SeerrSignInMethod.emby => true,
    SeerrSignInMethod.jellyfinQuickConnect || SeerrSignInMethod.local => false,
  };

  /// Whether Jellyfin's own Quick Connect is off.
  bool get quickConnectOff => method == SeerrSignInMethod.jellyfinQuickConnect;

  @override
  bool operator ==(Object other) =>
      other is SeerrSignInDisabled && other.method == method;

  @override
  int get hashCode => method.hashCode;

  @override
  String get label => 'sign-in turned off (${method.name})';
}

/// The install's `X-Plex-Client-Identifier` in every profile.
const worldPlexClientId = 'world-plex-client-id';

/// Where the device is, for [ProfileConnection.homeOnly].
enum NetworkPlace { home, away }

/// One configured connection and how it behaves.
class ProfileConnection {
  const ProfileConnection(
    this.instance, {
    this.behaviour = ConnectionBehaviour.answers,
    this.homeOnly = false,
    this.latency = Duration.zero,
    this.seerrAccount,
    this.seerrRelease = SeerrRelease.jellyseerr2,
    this.seerrMediaServer,
  });

  final ServiceInstance instance;

  /// How it behaves wherever it is reachable.
  final ConnectionBehaviour behaviour;

  /// Reachable on the home network only: [behaviour] at
  /// [NetworkPlace.home], a refused connection at [NetworkPlace.away].
  ///
  /// A flag beside [behaviour] rather than a value of it, because the two
  /// compose: P7's TrueNAS is read-only *and* home-only, so it does not answer
  /// away and reads read-only at home. A connection carries one URL
  /// (`service_instance.dart` has no away address), so away is exactly
  /// [ConnectionBehaviour.didNotAnswer] in code today.
  final bool homeOnly;

  /// How long every answer takes, in fake time. Zero answers at once.
  ///
  /// For the slow source rather than the dead one: Dockge's ten-second
  /// deadline holding back every decision on Home, a probe's five-second
  /// timeout firing on a box that would have answered at six. The app's own
  /// deadlines (Dio's receive timeout, each probe's `.timeout`) run on fake
  /// timers too, so a latency past one of them fails exactly as it would live.
  final Duration latency;

  /// Seerr only: the account this connection is signed in to Seerr as, or
  /// null for the server's API key.
  ///
  /// The instance carries it as the app saves it ([withSeerrAccount]): no
  /// key, the account's kind, login, id, name and permissions, and the
  /// session the network starts with for it ([worldSeerrSessionOf],
  /// `ProfileNetwork.seerrSessionOf`). So the app reaches this server as the
  /// account, with its own requests only and the operator's routes refused.
  final WorldSeerrUser? seerrAccount;

  /// Seerr only: which release answers here, and so what `/api/v1/status` and
  /// `/api/v1/settings/public` say.
  final SeerrRelease seerrRelease;

  /// Seerr only: the media server Seerr is set up with, its
  /// `mediaServerType`. Null is Plex when the profile has a Plex connection
  /// and Jellyfin otherwise. Overseerr sends no `mediaServerType` at all.
  final SeerrMediaServer? seerrMediaServer;

  String get id => instance.id;
  ServiceKey get service => instance.service;

  ProfileConnection withBehaviour(ConnectionBehaviour behaviour) =>
      _copy(behaviour: behaviour);

  ProfileConnection withHomeOnly(bool homeOnly) => _copy(homeOnly: homeOnly);

  ProfileConnection withLatency(Duration latency) => _copy(latency: latency);

  /// A copy signed in to Seerr as [account]: the instance drops the key and
  /// carries the account with the session the network starts with.
  ProfileConnection withSeerrAccount(WorldSeerrUser account) => _copy(
    seerrAccount: account,
    instance: instance.copyWith(
      credential: '',
      account: SeerrAccountSignIn(
        kind: switch (account.kind) {
          WorldSeerrUserType.local => SeerrAccountKind.local,
          WorldSeerrUserType.jellyfin => SeerrAccountKind.jellyfin,
          WorldSeerrUserType.emby => SeerrAccountKind.emby,
          WorldSeerrUserType.plex => SeerrAccountKind.plex,
        },
        login: switch (account.kind) {
          WorldSeerrUserType.local => account.email,
          WorldSeerrUserType.jellyfin ||
          WorldSeerrUserType.emby => account.login,
          WorldSeerrUserType.plex => '',
        },
        userId: account.id,
        displayName: account.displayName,
        session: worldSeerrSessionOf(instance.id),
        permissions: account.permissions,
      ),
    ),
  );

  /// A copy answered by Seerr [release].
  ProfileConnection withSeerrRelease(SeerrRelease release) =>
      _copy(seerrRelease: release);

  /// A copy whose Seerr is set up with [mediaServer].
  ProfileConnection withSeerrMediaServer(SeerrMediaServer mediaServer) =>
      _copy(seerrMediaServer: mediaServer);

  /// A copy whose connection presents [access] to the gateway in front.
  ProfileConnection withAccess(ConnectionAccess access) =>
      _copy(instance: instance.copyWith(access: access));

  ProfileConnection _copy({
    ServiceInstance? instance,
    ConnectionBehaviour? behaviour,
    bool? homeOnly,
    Duration? latency,
    WorldSeerrUser? seerrAccount,
    SeerrRelease? seerrRelease,
    SeerrMediaServer? seerrMediaServer,
  }) => ProfileConnection(
    instance ?? this.instance,
    behaviour: behaviour ?? this.behaviour,
    homeOnly: homeOnly ?? this.homeOnly,
    latency: latency ?? this.latency,
    seerrAccount: seerrAccount ?? this.seerrAccount,
    seerrRelease: seerrRelease ?? this.seerrRelease,
    seerrMediaServer: seerrMediaServer ?? this.seerrMediaServer,
  );

  /// How it behaves from [place].
  ConnectionBehaviour behaviourAt(NetworkPlace place) =>
      homeOnly && place == NetworkPlace.away
      ? ConnectionBehaviour.didNotAnswer
      : behaviour;
}

/// A Radarr or Sonarr that Seerr's own settings know, whether or not Cupola
/// has a connection to it — the raw material of the b case.
///
/// It is served twice by the fake Seerr, in the two shapes Seerr itself uses:
/// `GET /api/v1/settings/{radarr,sonarr}` (the admin view, address and key
/// included) and `GET /api/v1/service/{radarr,sonarr}` (the request-sheet
/// view the app reads today). The network also answers at [url], so a flow
/// that sets a connection up from Seerr's knowledge finds a live server there.
class SeerrKnownServer {
  const SeerrKnownServer({
    required this.seerrId,
    required this.service,
    required this.name,
    required this.url,
    required this.apiKey,
    this.is4k = false,
    this.isDefault = false,
    this.activeProfileId = 1,
    this.activeProfileName = 'HD-1080p',
    this.activeDirectory = '/mnt/tank/media/films',
  }) : assert(
         service == ServiceKey.radarr || service == ServiceKey.sonarr,
         'Seerr only knows Radarr and Sonarr servers.',
       );

  /// Seerr's own id for the server (0, 1, …), which is what a request's
  /// `serverId` names.
  final int seerrId;
  final ServiceKey service;

  /// The name the Seerr admin gave it: "Radarr 4K".
  final String name;
  final String url;
  final String apiKey;
  final bool is4k;
  final bool isDefault;
  final int activeProfileId;
  final String activeProfileName;
  final String activeDirectory;

  Uri get uri => Uri.parse(url);
}

/// What kind of account a Seerr user is: its `userType`
/// (`server/constants/user.ts`).
enum WorldSeerrUserType {
  plex(1),
  local(2),
  jellyfin(3),
  emby(4);

  const WorldSeerrUserType(this.wire);

  /// The number Seerr sends.
  final int wire;
}

/// One Seerr user of the world, with what each way of signing in checks.
///
/// Every user can be signed in every way: `email` and `password` for the
/// local sign-in, `login` and `password` for Jellyfin, Emby and Quick Connect,
/// `plexToken` for Plex. [kind] is what Seerr says the account is. The
/// secrets are the world's fakes (`world-anna-password`), derived from the
/// name unless a profile gives its own.
class WorldSeerrUser {
  const WorldSeerrUser({
    required this.id,
    required this.displayName,
    required this.permissions,
    this.kind = WorldSeerrUserType.jellyfin,
    String? email,
    String? login,
    String? password,
    String? plexToken,
  }) : _email = email,
       _login = login,
       _password = password,
       _plexToken = plexToken;

  final int id;
  final String displayName;

  /// Seerr's permission bitmask: `2` is ADMIN, `32` REQUEST.
  final int permissions;

  /// What Seerr says the account is. The household's users came from its
  /// Jellyfin, so that is the default.
  final WorldSeerrUserType kind;

  final String? _email;
  final String? _login;
  final String? _password;
  final String? _plexToken;

  /// The local sign-in's email, lower case as Seerr stores it.
  String get email => _email ?? '${displayName.toLowerCase()}@home.arpa';

  /// The Jellyfin or Emby username.
  String get login => _login ?? displayName.toLowerCase();

  /// The password of the local and the Jellyfin sign-in.
  String get password => _password ?? 'world-$login-password';

  /// The plex.tv token of the user's Plex account.
  String get plexToken => _plexToken ?? 'world-$login-plex-token';

  /// A copy with [permissions].
  WorldSeerrUser withPermissions(int permissions) =>
      _copy(permissions: permissions);

  /// A copy whose account is [kind].
  WorldSeerrUser asKind(WorldSeerrUserType kind) => _copy(kind: kind);

  WorldSeerrUser _copy({int? permissions, WorldSeerrUserType? kind}) =>
      WorldSeerrUser(
        id: id,
        displayName: displayName,
        permissions: permissions ?? this.permissions,
        kind: kind ?? this.kind,
        email: _email,
        login: _login,
        password: _password,
        plexToken: _plexToken,
      );

  @override
  String toString() => 'WorldSeerrUser($id, $displayName, ${kind.name})';
}

/// The household's Seerr users, as every Seerr of the world knows them.
abstract final class WorldSeerrUsers {
  /// User 1, the admin whose API key the operator holds.
  static const admin = WorldSeerrUser(
    id: 1,
    displayName: 'Operator',
    permissions: 2,
  );

  static const anna = WorldSeerrUser(
    id: 2,
    displayName: WorldPeople.anna,
    permissions: 32,
  );

  static const luca = WorldSeerrUser(
    id: 3,
    displayName: WorldPeople.luca,
    permissions: 32,
  );

  static const household = [admin, anna, luca];

  /// Anna's own local account (P2): REQUEST only.
  static const annaLocal = WorldSeerrUser(
    id: 2,
    displayName: WorldPeople.anna,
    permissions: 32,
    kind: WorldSeerrUserType.local,
  );

  /// Anna as the Jellyfin user Seerr imported (P2-J).
  static const annaJellyfin = anna;

  /// Anna as a Plex user, signed in through plex.tv (P2-P).
  static const annaPlex = WorldSeerrUser(
    id: 2,
    displayName: WorldPeople.anna,
    permissions: 32,
    kind: WorldSeerrUserType.plex,
  );

  /// The operator's own account on Sara's Seerr (P9): user 4 there, a local
  /// account with REQUEST only. Sara's server answers from the same canned
  /// world as the household's, so it knows the household too.
  static const operatorAtFriend = WorldSeerrUser(
    id: 4,
    displayName: WorldPeople.operatorName,
    permissions: 32,
    kind: WorldSeerrUserType.local,
    email: 'matt@example.net',
  );
}

/// One release of a Seerr-compatible server: what its `/api/v1/status`
/// says, and the `/api/v1/settings/public` it answers, recorded in
/// `test/fixtures/seerr/`.
class SeerrRelease {
  const SeerrRelease._(this.version, this.publicSettingsFixture);

  /// Overseerr 1.35.0, the last before the repository was archived: Plex
  /// only, no `mediaServerType`.
  static const overseerr = SeerrRelease._(
    '1.35.0',
    'seerr/public_settings_overseerr_1.35.0.json',
  );

  /// Jellyseerr 1.9.2: `mediaServerType` but no `mediaServerLogin`.
  static const jellyseerr1 = SeerrRelease._(
    '1.9.2',
    'seerr/public_settings_jellyseerr_1.9.2.json',
  );

  /// Jellyseerr 2.7.3, what the world's Seerr has always answered as.
  static const jellyseerr2 = SeerrRelease._(
    '2.7.3',
    'seerr/public_settings_jellyseerr_2.7.3.json',
  );

  /// Seerr 3.5.0: Quick Connect, and the public `plexClientIdentifier`.
  static const seerr = SeerrRelease._(
    '3.5.0',
    'seerr/public_settings_seerr_3.5.0.json',
  );

  /// The same line at another [version]: Seerr `3.3.0`, before Quick
  /// Connect, answers the 3.5.0 settings shape.
  SeerrRelease at(String version) =>
      SeerrRelease._(version, publicSettingsFixture);

  /// As `/api/v1/status` reports it.
  final String version;

  /// Under `test/fixtures/`.
  final String publicSettingsFixture;

  String get commitTag => 'v$version';

  @override
  bool operator ==(Object other) =>
      other is SeerrRelease &&
      other.version == version &&
      other.publicSettingsFixture == publicSettingsFixture;

  @override
  int get hashCode => Object.hash(version, publicSettingsFixture);

  @override
  String toString() => 'SeerrRelease($version)';
}

/// One configuration of Cupola, as the config inventory's profile table
/// describes it: which connections exist, how each behaves, where the lens
/// rests, and what Seerr knows beyond them.
///
/// A value, never a harness: [settings] is plain data, and turning a profile
/// into overrides and a fake network is `ProfileHarness`'s job. That split is
/// what lets a test derive a variant — P7 with qBittorrent answering, P6 with
/// the lens on the 4K Radarr — without rebuilding either.
class ConfigProfile {
  const ConfigProfile({
    required this.id,
    required this.title,
    required this.summary,
    required this.cases,
    required this.connections,
    this.lens = const {},
    this.place = NetworkPlace.home,
    this.seerrKnows = const [],
    this.unverifiedMatches = const {},
    this.seerrRequester,
    this.trustedCertificates = const {},
    this.bazarrFollows = const {ServiceKey.radarr, ServiceKey.sonarr},
    this.extraDownloads = const [],
    this.fullDisks = const {},
    this.pausedQueues = const {},
  });

  /// `P1` … `P9`, as the inventory numbers them.
  final String id;
  final String title;
  final String summary;
  final Set<ConfigCase> cases;

  /// Every connection, in the user's own order: the first of a service is its
  /// primary, which is what `settings.radarrUrl` and a bare `/dashboard/radarr`
  /// resolve to.
  final List<ProfileConnection> connections;

  /// Where the instance lens rests, per service. Absent means the first
  /// connection, which is also what the app does with an empty lens map.
  final Map<ServiceKey, String> lens;

  final NetworkPlace place;

  /// The Radarr and Sonarr servers Seerr's settings list. Empty when the
  /// profile has no Seerr.
  final List<SeerrKnownServer> seerrKnows;

  /// Titles (world title keys) the media server holds under an id that does
  /// not match the arr's — case f. The fake Jellyfin and Plex carry them with
  /// a different TMDB id, so `streamExternalMatchScore` rejects the item.
  final Set<String> unverifiedMatches;

  /// The Seerr user this profile is lived by, or null for the operator.
  ///
  /// The same account the profile's Seerr connection is signed in as
  /// ([ProfileConnection.seerrAccount]): the network answers a client signed
  /// in as her the way Seerr would, her own requests only and the admin routes
  /// refused, and the app reaches it as her.
  final WorldSeerrUser? seerrRequester;

  /// Pinned certificates by TLS origin. The fake network presents no
  /// certificate at all, so a pin here only proves the app threads it through
  /// the pinned adapter without breaking the request.
  final Map<String, String> trustedCertificates;

  /// Which arrs Bazarr's own settings point it at. P6's Bazarr follows Radarr
  /// only, so its episode side answers empty. Bazarr knows no Cupola
  /// connection: it follows one server of each, whichever that is.
  final Set<ServiceKey> bazarrFollows;

  /// Downloads this profile's world holds beside [WorldDownloads.all]: a
  /// torrent in error, a usenet job its client paused. Each is drawn by its
  /// client's fake and, when it names an arr, by that arr's queue, the way
  /// the world's own rows are. See [withDownloads].
  final List<WorldDownload> extraDownloads;

  /// The download clients (connection ids) whose download disk is full. A
  /// usenet client stops its own queue on a full disk, through the same
  /// switch a user's pause flips: its fake answers paused, with almost no
  /// free space. See [withFullDisk].
  final Set<String> fullDisks;

  /// The usenet clients (connection ids) whose download queue somebody
  /// paused, with plenty of room left. See [withPausedQueue].
  final Set<String> pausedQueues;

  /// Every download of this profile's world.
  List<WorldDownload> get downloads => [
    ...WorldDownloads.all,
    ...extraDownloads,
  ];

  /// The settings model the app starts from.
  SettingsModel get settings => SettingsModel(
    instances: [for (final c in connections) c.instance],
    trustedCertificates: trustedCertificates,
    region: 'IT',
    // What every install mints once: the identifier plex.tv is asked a PIN
    // with, and Plex knows Cupola by.
    plexClientId: worldPlexClientId,
  );

  ProfileConnection connection(String instanceId) => connections.firstWhere(
    (c) => c.id == instanceId,
    orElse: () => throw ArgumentError.value(
      instanceId,
      'instanceId',
      '$id has no such connection',
    ),
  );

  List<ProfileConnection> connectionsOf(ServiceKey service) =>
      connections.where((c) => c.service == service).toList(growable: false);

  bool has(ServiceKey service) => connections.any((c) => c.service == service);

  /// The connection the lens rests on for [service], or null when the
  /// profile has none — resolved the way `activeInstanceProvider` resolves it.
  ServiceInstance? lensOn(ServiceKey service) {
    final all = connectionsOf(service);
    if (all.isEmpty) return null;
    final named = lens[service];
    return all.where((c) => c.id == named).firstOrNull?.instance ??
        all.first.instance;
  }

  /// How [instanceId] behaves *here*, with [ProfileConnection.homeOnly]
  /// resolved against [place].
  ConnectionBehaviour behaviourOf(String instanceId) =>
      connection(instanceId).behaviourAt(place);

  /// A copy with [instanceId] behaving as [behaviour].
  ConfigProfile withBehaviour(
    String instanceId,
    ConnectionBehaviour behaviour,
  ) {
    connection(instanceId); // throws for an id the profile does not have
    return _copy(
      connections: [
        for (final c in connections)
          c.id == instanceId ? c.withBehaviour(behaviour) : c,
      ],
    );
  }

  /// A copy where every answer from [instanceId] takes [latency].
  ConfigProfile withLatency(String instanceId, Duration latency) {
    connection(instanceId);
    return _copy(
      connections: [
        for (final c in connections)
          c.id == instanceId ? c.withLatency(latency) : c,
      ],
    );
  }

  /// A copy with [connection] added after the others — a World-B service
  /// for the read-only cases only Unraid and NPM can show, say. Replaces a
  /// connection with the same id.
  ConfigProfile withConnection(ProfileConnection connection) => _copy(
    connections: [
      for (final c in connections)
        if (c.id != connection.id) c,
      connection,
    ],
  );

  /// A copy with the lens on [instanceId].
  ConfigProfile withLens(ServiceKey service, String instanceId) {
    if (connection(instanceId).service != service) {
      throw ArgumentError.value(instanceId, 'instanceId', 'not a $service');
    }
    return _copy(lens: {...lens, service: instanceId});
  }

  /// A copy whose world also holds [downloads]. The world as written has no
  /// client fault in it; a test that needs one adds it here.
  ConfigProfile withDownloads(List<WorldDownload> downloads) =>
      _copy(extraDownloads: [...extraDownloads, ...downloads]);

  /// A copy where [instanceId]'s download disk is full.
  ConfigProfile withFullDisk(String instanceId) {
    connection(instanceId);
    return _copy(fullDisks: {...fullDisks, instanceId});
  }

  /// A copy where somebody paused [instanceId]'s download queue.
  ConfigProfile withPausedQueue(String instanceId) {
    connection(instanceId);
    return _copy(pausedQueues: {...pausedQueues, instanceId});
  }

  /// A copy with the device at [place].
  ConfigProfile at(NetworkPlace place) => _copy(place: place);

  /// A copy where every Seerr account of the profile holds [permissions]:
  /// the requester and each connection's [ProfileConnection.seerrAccount].
  /// For 4K (`1024`), auto-approval (`128`), REQUEST_ADVANCED (`8192`) and the
  /// like, built from `SeerrPermission` values.
  ConfigProfile withSeerrPermissions(int permissions) {
    if (seerrRequester == null &&
        !connections.any((c) => c.seerrAccount != null)) {
      throw ArgumentError('$id has no Seerr account to change');
    }
    return _copy(
      connections: [
        for (final c in connections)
          switch (c.seerrAccount) {
            final account? => c.withSeerrAccount(
              account.withPermissions(permissions),
            ),
            null => c,
          },
      ],
      seerrRequester: seerrRequester?.withPermissions(permissions),
    );
  }

  /// A copy where Seerr [release] answers at [instanceId], or at every Seerr
  /// connection when it is null.
  ConfigProfile withSeerrRelease(SeerrRelease release, {String? instanceId}) {
    if (instanceId != null) connection(instanceId);
    return _copy(
      connections: [
        for (final c in connections)
          c.service == ServiceKey.seerr &&
                  (instanceId == null || c.id == instanceId)
              ? c.withSeerrRelease(release)
              : c,
      ],
    );
  }

  /// A copy without any connection of [service] — its a case.
  ConfigProfile without(ServiceKey service) => _copy(
    connections: [
      for (final c in connections)
        if (c.service != service) c,
    ],
    lens: {...lens}..remove(service),
  );

  ConfigProfile _copy({
    List<ProfileConnection>? connections,
    Map<ServiceKey, String>? lens,
    NetworkPlace? place,
    WorldSeerrUser? seerrRequester,
    List<WorldDownload>? extraDownloads,
    Set<String>? fullDisks,
    Set<String>? pausedQueues,
  }) => ConfigProfile(
    id: id,
    title: title,
    summary: summary,
    cases: cases,
    connections: connections ?? this.connections,
    lens: lens ?? this.lens,
    place: place ?? this.place,
    seerrKnows: seerrKnows,
    unverifiedMatches: unverifiedMatches,
    seerrRequester: seerrRequester ?? this.seerrRequester,
    trustedCertificates: trustedCertificates,
    bazarrFollows: bazarrFollows,
    extraDownloads: extraDownloads ?? this.extraDownloads,
    fullDisks: fullDisks ?? this.fullDisks,
    pausedQueues: pausedQueues ?? this.pausedQueues,
  );

  @override
  String toString() => '$id · $title';
}
