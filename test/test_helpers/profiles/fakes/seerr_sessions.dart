/// Seerr's sign-in on the fake network: who a request reaches Seerr as, the
/// sessions it keeps, its CSRF guard and Jellyfin Quick Connect.
///
/// Read from Seerr v3.5.0: `server/middleware/auth.ts` (`checkUser`,
/// `isAuthenticated`), `server/routes/auth.ts`, `server/routes/index.ts`, the
/// session and CSRF set-up of `server/index.ts`, and `@dr.pogodin/csurf`
/// 1.16.9. Every refusal is sent in the body the server sends, in its own two
/// shapes: `{message}` from the error handler and `{status, error}` from the
/// permission check. Where the server only relays another program's answer
/// (Jellyfin's Quick Connect, plex.tv), the comment says it is not verified.
///
/// [SeerrFake] keeps the canned data and asks this file who is calling; the
/// state lives per server on the network, between requests.
library;

import 'dart:convert';
import 'dart:io' show HttpDate;

import 'package:crypto/crypto.dart';

import 'package:cupola/features/discover/domain/seerr_permission.dart';
import 'package:cupola/features/discover/domain/seerr_server_facts.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../fixtures.dart';
import '../config_profile.dart';
import '../profile_network.dart';
import '../service_fakes.dart';
import '../world.dart';
import 'media_fakes.dart' show JellyfinFake;

/// How long a session lives after it was last used: the cookie's `maxAge`
/// and the store's `ttl`, 30 days. The store moves the expiry on every request
/// (`connect-typeorm` `touch`), the cookie's `Expires` does not move.
const seerrSessionLifetime = Duration(days: 30);

/// How long a Quick Connect code waits to be approved. Jellyfin's own
/// timeout, not Seerr's: Jellyfin 12.1 behind Seerr 3.4.1 still knew a code
/// after nine minutes and no longer after ten (live).
const seerrQuickConnectLifetime = Duration(minutes: 10);

/// The session a Seerr connection [serverId] signed in with an account
/// starts with, as the app saved it: the `connect.sid` value, URL encoded.
///
/// The same value the connection's instance carries
/// (`ProfileConnection.withSeerrAccount`) and the network opens when it is
/// built ([openSavedSeerrSessions]), so the app and the fake meet on it with
/// nothing passed between them.
String worldSeerrSessionOf(String serverId) {
  final id = _savedSessionId(serverId);
  return Uri.encodeComponent('s:$id.${_signatureOf(serverId, id)}');
}

String _savedSessionId(String serverId) => base64Url
    .encode(sha256.convert(utf8.encode('$serverId/saved-session')).bytes)
    .replaceAll('=', '')
    .substring(0, 32);

/// express-session's signature of session [id] on server [serverId].
String _signatureOf(String serverId, String id) => base64
    .encode(
      Hmac(
        sha256,
        utf8.encode('world-$serverId-session-secret'),
      ).convert(utf8.encode(id)).bytes,
    )
    .replaceAll(RegExp(r'=+$'), '');

/// The body `isAuthenticated` refuses with (`server/middleware/auth.ts`):
/// no caller, or a caller without the route's permission.
NetworkReply seerrEndpointRefused() => NetworkReply.json({
  'status': 403,
  'error': 'You do not have permission to access this endpoint',
}, status: 403);

/// A refusal through Seerr's error handler: `next({status, message})`
/// arrives as `{message}` (`server/index.ts`, `errors` is undefined).
NetworkReply seerrError(int status, String message) =>
    NetworkReply.json({'message': message}, status: status);

/// A refusal a route writes itself: `res.status(…).json({error})`.
NetworkReply seerrErrorField(int status, String error) =>
    NetworkReply.json({'error': error}, status: status);

/// One signed-in session.
class SeerrSession {
  SeerrSession._(this.id, this.userId, this.expiresAt);

  /// express-session's id: what the cookie carries before its signature.
  final String id;

  /// `req.session.userId`. A sign-in over a live session writes the new user
  /// into it without a new id: Seerr never regenerates.
  int userId;

  /// The store's `expiredAt`.
  DateTime expiresAt;

  bool destroyed = false;

  bool liveAt(DateTime time) => !destroyed && time.isBefore(expiresAt);
}

/// One Quick Connect code, from `initiate` to `authenticate`.
class SeerrQuickConnectCode {
  SeerrQuickConnectCode._(this.code, this.secret, this.expiresAt);

  /// The six digits a person types into Jellyfin.
  final String code;

  /// What the app polls and authenticates with.
  final String secret;

  final DateTime expiresAt;

  /// Who approved it from a signed-in Jellyfin app, or null while it waits.
  WorldSeerrUser? approvedBy;

  /// Set once `authenticate` has used it. Used, it still signs in.
  bool spent = false;
}

/// Who a request reached Seerr as: `req.user` after `checkUser`.
class SeerrCaller {
  const SeerrCaller(this.user, {this.session});

  final WorldSeerrUser user;

  /// The session it came in on, or null for the API key.
  final SeerrSession? session;

  bool get byKey => session == null;

  bool has(SeerrPermission permission) =>
      hasSeerrPermission(user.permissions, permission);

  bool hasAny(List<SeerrPermission> permissions) => hasSeerrPermissions(
    user.permissions,
    permissions,
    check: SeerrPermissionCheck.any,
  );

  /// MANAGE_REQUESTS or REQUEST_VIEW: sees everybody's requests.
  bool get seesEveryone => hasAny(const [
    SeerrPermission.manageRequests,
    SeerrPermission.requestView,
  ]);
}

/// How one Seerr of the world is set up, read from its connection and the
/// profile: the release, the media server, the users, the key it accepts.
class SeerrSetup {
  SeerrSetup._(this._context, this.connection, this.state);

  factory SeerrSetup.of(ServerContext context) {
    final id = context.server.id;
    return SeerrSetup._(
      context,
      context.profile.connections.where((c) => c.id == id).firstOrNull,
      seerrStateOf(context.network, id),
    );
  }

  final ServerContext _context;

  /// The connection at this address. Under `answersAsOtherService` it is
  /// another service's, with no Seerr account; null for an address that is
  /// none of the profile's connections.
  final ProfileConnection? connection;

  final SeerrServerState state;

  ConnectionBehaviour get behaviour => _context.behaviour;

  SeerrRelease get release =>
      connection?.seerrRelease ?? SeerrRelease.jellyseerr2;

  /// The only key `checkUser` takes: the world's key for this address.
  String get apiKey => worldKey(_context.server.id);

  /// `secure: 'auto'`: the session cookie is Secure where Seerr is reached
  /// over TLS.
  bool get overTls => _context.server.uri.scheme == 'https';

  bool get csrfProtected => behaviour == ConnectionBehaviour.csrfProtected;

  bool get initialized => behaviour != ConnectionBehaviour.notInitialized;

  bool get quotaReached => behaviour == ConnectionBehaviour.quotaReached;

  SeerrSignInDisabled? get _off => switch (behaviour) {
    final SeerrSignInDisabled off => off,
    _ => null,
  };

  bool get localLogin => _off?.localLoginOff != true;

  bool get mediaServerLogin => _off?.mediaServerLoginOff != true;

  /// Whether Jellyfin's own Quick Connect is on.
  bool get quickConnectOn => _off?.quickConnectOff != true;

  /// The `/settings/public` of [release], as recorded.
  Map<String, dynamic> get recordedPublicSettings => _fixtures.putIfAbsent(
    release.publicSettingsFixture,
    () => jsonFixtureMap(release.publicSettingsFixture),
  );

  /// Overseerr has no `mediaServerType`, and is Plex.
  bool get sendsMediaServerType =>
      recordedPublicSettings.containsKey('mediaServerType');

  /// The media server Seerr is set up with.
  SeerrMediaServer get mediaServer {
    if (!sendsMediaServerType) return SeerrMediaServer.plex;
    if (!initialized) return state._setUpWith ?? SeerrMediaServer.notConfigured;
    return connection?.seerrMediaServer ??
        (_context.profile.has(ServiceKey.plex)
            ? SeerrMediaServer.plex
            : SeerrMediaServer.jellyfin);
  }

  /// Whether the release has Quick Connect: Seerr 3.4.0 and later.
  bool get hasQuickConnect {
    final match = RegExp(r'^(\d+)\.(\d+)').firstMatch(release.version);
    if (match == null) return false;
    final major = int.parse(match.group(1)!);
    final minor = int.parse(match.group(2)!);
    return major > 3 || (major == 3 && minor >= 4);
  }

  /// Every user the server has: the household, with this connection's
  /// account in its place (or after them), or nobody while the server is in
  /// its first setup. Plus whoever a first-setup sign-in created.
  List<WorldSeerrUser> get users {
    final account = connection?.seerrAccount;
    return [
      if (initialized) ...[
        for (final user in WorldSeerrUsers.household)
          if (account != null && account.id == user.id) account else user,
        if (account != null &&
            !WorldSeerrUsers.household.any((u) => u.id == account.id))
          account,
      ],
      ...state._created,
    ];
  }

  WorldSeerrUser? userById(int id) =>
      users.where((u) => u.id == id).firstOrNull;

  /// `/api/v1/settings/public`: the recorded answer of [release], with this
  /// server's own facts laid over it.
  Map<String, dynamic> get publicSettings {
    final json = {...recordedPublicSettings};
    bool fourK(ServiceKey service) => _context.profile.seerrKnows.any(
      (s) => s.service == service && s.is4k && s.isDefault,
    );
    json['initialized'] = initialized;
    if (sendsMediaServerType) {
      json['mediaServerType'] = switch (mediaServer) {
        SeerrMediaServer.plex => 1,
        SeerrMediaServer.jellyfin => 2,
        SeerrMediaServer.emby => 3,
        SeerrMediaServer.notConfigured => 4,
      };
    }
    // `fullPublicSettings`: a default 4K server of each kind.
    json['movie4kEnabled'] = fourK(ServiceKey.radarr);
    json['series4kEnabled'] = fourK(ServiceKey.sonarr);
    if (!localLogin) json['localLogin'] = false;
    if (!mediaServerLogin && json.containsKey('mediaServerLogin')) {
      json['mediaServerLogin'] = false;
    }
    return json;
  }

  static final Map<String, Map<String, dynamic>> _fixtures = {};
}

/// One Seerr server's state between requests.
class SeerrServerState {
  SeerrServerState._(this._network, this.serverId);

  final ProfileNetwork _network;
  final String serverId;

  final Map<String, SeerrSession> _sessions = {};
  final Map<String, SeerrQuickConnectCode> _quickConnect = {};
  final List<WorldSeerrUser> _created = [];
  SeerrMediaServer? _setUpWith;
  int _minted = 0;

  /// The session the connection's account starts with, as the app would
  /// have saved it: the `connect.sid` cookie value. Null without an account.
  String? savedSession;

  /// What `PUT /api/v1/request/{id}` wrote, by request id: the server,
  /// profile and folder the request carries from then on, so a read after
  /// the edit, and the approval, see it.
  final Map<int, ({Object? serverId, Object? profileId, Object? rootFolder})>
  requestEdits = {};

  /// Requests somebody decided on in Seerr itself since the app read them:
  /// an edit of one is refused as Seerr refuses an edit of a request that no
  /// longer waits.
  final Set<int> decidedElsewhere = {};

  /// Every session this server has handed out, live or not.
  Iterable<SeerrSession> get sessions => _sessions.values;

  /// Every Quick Connect code it has handed out.
  Iterable<SeerrQuickConnectCode> get quickConnectCodes => _quickConnect.values;

  /// The users a first-setup sign-in created: the admin, on a server that had
  /// nobody.
  List<WorldSeerrUser> get createdUsers => List.unmodifiable(_created);

  DateTime get _now => _network.currentTime;

  String _mint(String what) {
    _minted++;
    return base64Url
        .encode(sha256.convert(utf8.encode('$serverId/$what/$_minted')).bytes)
        .replaceAll('=', '');
  }

  String _sign(String id) => _signatureOf(serverId, id);

  /// The session the connection's account starts with, under the id
  /// [worldSeerrSessionOf] names: live, or already over when [expired].
  SeerrSession openSaved(int userId, {bool expired = false}) {
    final session = SeerrSession._(
      _savedSessionId(serverId),
      userId,
      expired ? _now : _now.add(seerrSessionLifetime),
    );
    _sessions[session.id] = session;
    return session;
  }

  /// A new session for [userId], or [userId] written into [over], which is
  /// what a sign-in over a live session does.
  SeerrSession open(int userId, {SeerrSession? over, bool expired = false}) {
    if (over != null && over.liveAt(_now)) {
      over
        ..userId = userId
        ..expiresAt = _now.add(seerrSessionLifetime);
      return over;
    }
    final session = SeerrSession._(
      _mint('session').substring(0, 32),
      userId,
      expired ? _now : _now.add(seerrSessionLifetime),
    );
    _sessions[session.id] = session;
    return session;
  }

  /// The `connect.sid` value for [session]: `s:<id>.<signature>`, URL
  /// encoded the way the cookie is written.
  String cookieValueOf(SeerrSession session) =>
      Uri.encodeComponent('s:${session.id}.${_sign(session.id)}');

  /// The live session [cookieValue] names, touched; null for a value this
  /// server did not sign, a session that expired or one that was closed.
  SeerrSession? resume(String? cookieValue) {
    if (cookieValue == null || cookieValue.isEmpty) return null;
    final String raw;
    try {
      raw = Uri.decodeComponent(cookieValue);
    } on ArgumentError {
      return null;
    }
    if (!raw.startsWith('s:')) return null;
    final dot = raw.lastIndexOf('.');
    if (dot < 2) return null;
    final id = raw.substring(2, dot);
    if (raw.substring(dot + 1) != _sign(id)) return null;
    final session = _sessions[id];
    if (session == null || !session.liveAt(_now)) return null;
    session.expiresAt = _now.add(seerrSessionLifetime);
    return session;
  }

  /// `Set-Cookie: connect.sid=…` for [session].
  String sessionCookie(SeerrSession session, {required SeerrSetup setup}) => [
    'connect.sid=${cookieValueOf(session)}',
    'Path=/',
    // The cookie's own expiry, from the sign-in: it does not roll.
    'Expires=${HttpDate.format(session.expiresAt)}',
    'HttpOnly',
    if (setup.overTls) 'Secure',
    'SameSite=${setup.csrfProtected ? 'Strict' : 'Lax'}',
  ].join('; ');

  /// csurf's secret, for a request that came without one.
  String mintCsrfSecret() => _mint('csrf').substring(0, 24);

  /// A token for [secret] in csurf's own form, `<salt>-<hash>`.
  String csrfTokenFor(String secret) {
    // Alphanumeric, as csurf's `rndm(8)` is: a base64url salt can hold the
    // `-` the token is split on, and then no token of it verifies.
    final salt = _mint(
      'salt',
    ).replaceAll(RegExp('[^A-Za-z0-9]'), '').substring(0, 8);
    return '$salt-${_csrfHash(salt, secret)}';
  }

  /// Whether [token] was made for [secret]: csurf checks the hash, not a
  /// list, so any token of the same secret passes.
  static bool csrfVerifies(String? secret, String? token) {
    if (secret == null || secret.isEmpty || token == null) return false;
    final dash = token.indexOf('-');
    if (dash <= 0) return false;
    return token.substring(dash + 1) ==
        _csrfHash(token.substring(0, dash), secret);
  }

  static String _csrfHash(String salt, String secret) => base64Url
      .encode(sha1.convert(utf8.encode('$salt-$secret')).bytes)
      .replaceAll('=', '');

  /// `POST /auth/jellyfin/quickconnect/initiate`: a new code.
  SeerrQuickConnectCode initiateQuickConnect() {
    final secret = sha256
        .convert(utf8.encode('$serverId/quick-connect/${++_minted}'))
        .toString();
    final code = (100000 + (_minted * 7919) % 900000).toString();
    final request = SeerrQuickConnectCode._(
      code,
      secret,
      _now.add(seerrQuickConnectLifetime),
    );
    _quickConnect[secret] = request;
    return request;
  }

  /// The code [secret] names, or null when it is unknown or has timed out.
  SeerrQuickConnectCode? quickConnect(String secret) {
    final request = _quickConnect[secret];
    if (request == null || !_now.isBefore(request.expiresAt)) return null;
    return request;
  }

  /// The code a person reads off the screen, or null.
  SeerrQuickConnectCode? quickConnectByCode(String code) => _quickConnect.values
      .where((q) => q.code == code && _now.isBefore(q.expiresAt))
      .firstOrNull;
}

final _states = Expando<Map<String, SeerrServerState>>('seerr state');

/// The Seerr state of [serverId] on [network].
SeerrServerState seerrStateOf(ProfileNetwork network, String serverId) =>
    (_states[network] ??= {}).putIfAbsent(
      serverId,
      () => SeerrServerState._(network, serverId),
    );

/// Opens the session each signed-in Seerr connection starts with. Called
/// once, when the network is built, so the session is as old as the test.
void openSavedSeerrSessions(ProfileNetwork network) {
  for (final connection in network.profile.connections) {
    final account = connection.seerrAccount;
    if (connection.service != ServiceKey.seerr || account == null) continue;
    final state = seerrStateOf(network, connection.id);
    final expired =
        network.profile.behaviourOf(connection.id) ==
        ConnectionBehaviour.sessionExpired;
    state.savedSession = state.cookieValueOf(
      state.openSaved(account.id, expired: expired),
    );
    assert(state.savedSession == worldSeerrSessionOf(connection.id));
  }
}

// === Per request ===========================================================

/// What the gate learnt about a request, for [SeerrFake.answer] and
/// [SeerrFake.finish] to read.
class _Visit {
  _Visit(this.caller, this.cookies);

  final SeerrCaller? caller;

  /// `Set-Cookie` lines the middleware adds to whatever answers.
  final List<String> cookies;
}

final _visits = Expando<_Visit>('seerr visit');

/// The cookies [request] carried, by name.
Map<String, String> requestCookies(NetworkRequest request) {
  final header = request.headers['cookie'];
  if (header == null || header.isEmpty) return const {};
  return {
    for (final part in header.split(RegExp(r'[;,]\s*')))
      if (part.contains('='))
        part.substring(0, part.indexOf('=')).trim(): part
            .substring(part.indexOf('=') + 1)
            .trim(),
  };
}

/// Who [request] reaches Seerr as, read the way `checkUser` reads it: the
/// API key if it is the server's, otherwise a live session, otherwise nobody.
SeerrCaller? _identify(NetworkRequest request, SeerrSetup setup) {
  final key = request.headers['x-api-key'];
  if (key != null &&
      key == setup.apiKey &&
      setup.behaviour != ConnectionBehaviour.refusesKey) {
    // The key acts as user 1, which a server in its first setup may not have,
    // or as the user `X-API-User` names: then nobody when there is no such
    // user, and the session is not asked.
    final named = request.headers['x-api-user'];
    final actsAs = setup.userById(named == null ? 1 : int.tryParse(named) ?? 0);
    return actsAs == null ? null : SeerrCaller(actsAs);
  }
  final session = setup.state.resume(requestCookies(request)['connect.sid']);
  if (session == null) return null;
  final user = setup.userById(session.userId);
  return user == null ? null : SeerrCaller(user, session: session);
}

/// Who [request] reached Seerr as, after [seerrGate] ran.
SeerrCaller? seerrCallerOf(NetworkRequest request, ServerContext context) =>
    _visits[request]?.caller ?? _identify(request, SeerrSetup.of(context));

/// What a route asks of its caller before it runs.
sealed class _Need {
  const _Need();
}

/// Anyone, no caller at all.
final class _Public extends _Need {
  const _Public();
}

/// `isAuthenticated()` with [permissions]: none means any caller.
final class _Caller extends _Need {
  const _Caller([this.permissions = const [], this.any = false]);

  final List<SeerrPermission> permissions;
  final bool any;

  bool admits(SeerrCaller caller) =>
      permissions.isEmpty ||
      (any ? caller.hasAny(permissions) : permissions.every(caller.has));
}

/// `isOwnProfile()` or, with [orManageUsers], `isOwnProfileOrAdmin()`
/// (`server/utils/profileMiddleware.ts`), behind the `/user` router's own
/// `isAuthenticated()`: user [userId] themselves, or anybody with
/// MANAGE_USERS.
final class _OwnProfile extends _Need {
  const _OwnProfile(this.userId, {required this.orManageUsers});

  final int userId;
  final bool orManageUsers;

  bool admits(SeerrCaller caller) =>
      caller.user.id == userId ||
      (orManageUsers && caller.has(SeerrPermission.manageUsers));
}

/// The routes of `server/routes/index.ts` and their own guards, as far as
/// the app reaches them. A route not named here is answered to any caller,
/// as the router's `isAuthenticated()` is. The routes that want nobody are
/// [isPublic]'s, the fake's own list.
_Need _needOf(
  NetworkRequest r, {
  required bool Function(NetworkRequest) isPublic,
}) {
  if (isPublic(r)) return const _Public();
  final route = r.path.substring('/api/v1/'.length);
  final get = r.method == 'GET';

  if (route.startsWith('settings/')) {
    if (get &&
        (route == 'settings/discover' ||
            route == 'settings/notifications/pushover/sounds')) {
      return const _Caller();
    }
    return const _Caller([SeerrPermission.admin]);
  }
  if (r.method == 'POST' &&
      RegExp(r'^request/\d+/(approve|decline|retry)$').hasMatch(route)) {
    return const _Caller([SeerrPermission.manageRequests]);
  }
  if (route.startsWith('media/')) {
    if (get && RegExp(r'^media/\d+/watch_data$').hasMatch(route)) {
      return const _Caller([SeerrPermission.admin]);
    }
    if (!get) return const _Caller([SeerrPermission.manageRequests]);
  }
  if (route == 'user' || route.startsWith('user/')) {
    return _userNeedOf(r.method, route.split('/').skip(1).toList());
  }
  if (route == 'issue' || route.startsWith('issue/')) {
    if (get && route != 'issue/count') {
      return const _Caller([
        SeerrPermission.manageIssues,
        SeerrPermission.viewIssues,
        SeerrPermission.createIssues,
      ], true);
    }
    if (!get) {
      return const _Caller([
        SeerrPermission.manageIssues,
        SeerrPermission.createIssues,
      ], true);
    }
  }
  return const _Caller();
}

/// The guards of `server/routes/user/index.ts` and `user/usersettings.ts`,
/// for the route segments after `user/`. Every one sits behind the router's
/// `isAuthenticated()`.
_Need _userNeedOf(String method, List<String> segments) {
  const manageUsers = _Caller([SeerrPermission.manageUsers]);
  final id = segments.isEmpty ? null : int.tryParse(segments.first);
  if (id == null) {
    if (method == 'GET') return const _Caller();
    // `POST /user`, `PUT /user`, `POST /user/import-from-plex` and
    // `-jellyfin`; `POST /user/registerPushSubscription` wants anybody.
    if (segments.isEmpty || segments.first.startsWith('import-from-')) {
      return manageUsers;
    }
    return const _Caller();
  }
  final rest = segments.skip(1).toList();
  // `GET /user/{id}` filters its answer; `PUT` and `DELETE` are the admin's.
  if (rest.isEmpty) return method == 'GET' ? const _Caller() : manageUsers;
  switch (rest.first) {
    case 'pushSubscriptions' || 'pushSubscription' || 'watch_data':
      return _OwnProfile(id, orManageUsers: true);
    case 'settings' when rest.length > 1:
      if (rest[1] == 'permissions') return manageUsers;
      // Linking a Plex or Jellyfin account is the user's own business only.
      if (method == 'POST' && rest[1] == 'linked-accounts') {
        return _OwnProfile(id, orManageUsers: false);
      }
      return _OwnProfile(id, orManageUsers: true);
  }
  // `quota`, `requests`, `watchlist`: the route checks for itself.
  return const _Caller();
}

/// Seerr's middleware ahead of every route: the CSRF guard when it is on,
/// then who the caller is and whether the route admits them. Null lets the
/// request through to the route. [isPublic] names the routes that want
/// nobody.
NetworkReply? seerrGate(
  NetworkRequest request,
  ServerContext context, {
  required bool Function(NetworkRequest) isPublic,
}) {
  final setup = SeerrSetup.of(context);
  final cookies = <String>[];

  // csurf, mounted ahead of the session and every route
  // (`server/index.ts:195-214`): the API key does not get past it either.
  if (setup.csrfProtected) {
    final sent = requestCookies(request);
    var secret = sent['_csrf'];
    if (secret == null || secret.isEmpty) {
      secret = setup.state.mintCsrfSecret();
      cookies.add('_csrf=$secret; Path=/; HttpOnly; Secure; SameSite=Strict');
    }
    final safe = const {'GET', 'HEAD', 'OPTIONS'}.contains(request.method);
    if (!safe &&
        !SeerrServerState.csrfVerifies(secret, _csrfTokenOf(request))) {
      _visits[request] = _Visit(null, cookies);
      return seerrError(403, 'invalid csrf token');
    }
    // The middleware after csurf, so only a request that got past it.
    cookies.add(
      'XSRF-TOKEN=${setup.state.csrfTokenFor(secret)}; Path=/; Secure; '
      'SameSite=Strict',
    );
  }

  // The OpenAPI request validator, after the session and ahead of every
  // route: a route the spec secures wants the key's header or the session's
  // cookie to be there at all, and answers a request with neither itself, in
  // its own 401, before `isAuthenticated` is asked. Its `errors[].path` is
  // the spec's route template; the request's own path stands in for it here.
  final need = _needOf(request, isPublic: isPublic);
  final noCredential =
      (request.headers['x-api-key'] ?? '').isEmpty &&
      (requestCookies(request)['connect.sid'] ?? '').isEmpty;
  if (noCredential && (need is! _Public || _isLogout(request))) {
    _visits[request] = _Visit(null, cookies);
    const message = "cookie 'connect.sid' required";
    return NetworkReply.json({
      'message': message,
      'errors': [
        {'path': request.path, 'message': message},
      ],
    }, status: 401);
  }

  final caller = _identify(request, setup);
  _visits[request] = _Visit(caller, cookies);

  if (need is _Public) return null;
  if (caller == null) return seerrEndpointRefused();
  switch (need) {
    case _Caller() when !need.admits(caller):
      return seerrEndpointRefused();
    case _OwnProfile() when !need.admits(caller):
      // Through the error handler, with the same sentence for a read and a
      // write.
      return seerrError(
        403,
        "You do not have permission to view this user's settings.",
      );
    case _Public() || _Caller() || _OwnProfile():
  }
  // Seerr has no read-only key; the profile behaviour reads it as a key
  // whose writes Seerr refuses as it refuses a missing permission.
  if (setup.behaviour == ConnectionBehaviour.readOnly &&
      caller.byKey &&
      request.method != 'GET') {
    return seerrEndpointRefused();
  }
  return null;
}

/// `POST /auth/logout`: no permission asked, but secured in the spec, so the
/// validator wants a session cookie or the key's header there too.
bool _isLogout(NetworkRequest request) =>
    request.method == 'POST' && request.path == '/api/v1/auth/logout';

/// Where csurf looks for the token: the body's or the query's `_csrf`, then
/// four headers (`build/cjs/index.js:52`).
String? _csrfTokenOf(NetworkRequest request) {
  final json = request.json;
  Object? fromBody;
  if (json is Map) {
    fromBody = json['_csrf'];
  } else {
    try {
      fromBody = request.form['_csrf'];
    } on FormatException {
      fromBody = null;
    }
  }
  if (fromBody is String && fromBody.isNotEmpty) return fromBody;
  final fromQuery = request.query['_csrf'];
  if (fromQuery != null && fromQuery.isNotEmpty) return fromQuery;
  for (final name in const [
    'csrf-token',
    'xsrf-token',
    'x-csrf-token',
    'x-xsrf-token',
  ]) {
    final value = request.headers[name];
    if (value != null && value.isNotEmpty) return value;
  }
  return null;
}

/// [reply] with the cookies the middleware set while [request] passed.
NetworkReply seerrFinish(NetworkRequest request, NetworkReply reply) {
  final cookies = _visits[request]?.cookies ?? const <String>[];
  return reply.withHeaders({if (cookies.isNotEmpty) 'set-cookie': cookies});
}

// === The users, as each route sends them ===================================

/// `user.toJSON()` with what `/auth/me` adds: everything but the secrets the
/// columns never select, and the email with it.
Map<String, Object?> seerrWhoAmI(WorldSeerrUser user, ServerContext context) =>
    {
      ..._userColumns(user, context),
      'email': user.email,
      if (user.kind == WorldSeerrUserType.plex) 'plexId': 9000 + user.id,
      'settings': {
        'locale': '',
        'discoverRegion': '',
        'streamingRegion': '',
        'originalLanguage': '',
        'notificationTypes': {'email': 0, 'webpush': 0},
        'watchlistSyncMovies': false,
        'watchlistSyncTv': false,
      },
    };

/// `user.filter()`: the columns, without the email, the Plex id and the
/// secrets. What the Plex, Jellyfin and Quick Connect sign-ins send.
Map<String, Object?> seerrFilteredUser(
  WorldSeerrUser user,
  ServerContext context,
) => _userColumns(user, context);

Map<String, Object?> _userColumns(WorldSeerrUser user, ServerContext context) {
  final viaJellyfin =
      user.kind == WorldSeerrUserType.jellyfin ||
      user.kind == WorldSeerrUserType.emby;
  return {
    'id': user.id,
    'displayName': user.displayName,
    'username': user.kind == WorldSeerrUserType.local
        ? user.displayName.toLowerCase()
        : null,
    'plexUsername': user.kind == WorldSeerrUserType.plex ? user.login : null,
    'jellyfinUsername': viaJellyfin ? user.login : null,
    'jellyfinUserId': viaJellyfin ? _jellyfinUserIdOf(user) : null,
    'userType': user.kind.wire,
    'permissions': user.permissions,
    'avatar': '/avatarproxy/${user.id}',
    'avatarETag': null,
    'avatarVersion': null,
    'recoveryLinkExpirationDate': null,
    'movieQuotaLimit': null,
    'movieQuotaDays': null,
    'tvQuotaLimit': null,
    'tvQuotaDays': null,
    'requestCount': user.id == 1 ? 0 : 20,
    'createdAt': context.ago(const Duration(days: 400)),
    'updatedAt': context.ago(const Duration(days: 1)),
    'warnings': const <String>[],
  };
}

/// The Jellyfin user a Seerr user came from: the world's Jellyfin knows the
/// household by these ids.
String _jellyfinUserIdOf(WorldSeerrUser user) => switch (user.id) {
  1 => JellyfinFake.operatorId,
  2 => JellyfinFake.annaId,
  3 => JellyfinFake.lucaId,
  _ => user.id.toRadixString(16).padLeft(32, '0'),
};

// === The routes under /auth ================================================

/// The answer to a route under `/api/v1/auth/`, or null for any other route.
NetworkReply? seerrAuthAnswer(NetworkRequest r, ServerContext c) {
  const prefix = '/api/v1/auth/';
  if (!r.path.startsWith(prefix)) return null;
  final route = r.path.substring(prefix.length);
  final setup = SeerrSetup.of(c);
  return switch ((r.method, route)) {
    ('GET', 'me') => switch (seerrCallerOf(r, c)) {
      // The gate already refused a request with nobody behind it.
      final caller? => NetworkReply.json(seerrWhoAmI(caller.user, c)),
      null => seerrEndpointRefused(),
    },
    ('POST', 'local') => _local(r, c, setup),
    ('POST', 'jellyfin') => _jellyfin(r, c, setup),
    ('POST', 'plex') => _plex(r, c, setup),
    ('POST', 'logout') => _logout(r, setup),
    ('POST', 'jellyfin/quickconnect/initiate') => _quickConnectInitiate(
      r,
      setup,
    ),
    ('GET', 'jellyfin/quickconnect/check') => _quickConnectCheck(r, setup),
    ('POST', 'jellyfin/quickconnect/authenticate') => _quickConnectAuthenticate(
      r,
      c,
      setup,
    ),
    _ => null,
  };
}

/// A route the release does not have. The OpenAPI validator in front of the
/// routes answers it; the body is not verified here.
NetworkReply _noSuchRoute(NetworkRequest r) => NetworkReply.json({
  'message': 'not found',
  'errors': [
    {'path': r.path, 'message': 'not found'},
  ],
}, status: 404);

/// A sign-in that worked: `req.session.userId` set, the cookie sent, and
/// [body] as the route sends it.
NetworkReply _signedIn(
  NetworkRequest r,
  SeerrSetup setup,
  WorldSeerrUser user,
  Map<String, Object?> body,
) {
  final over = setup.state.resume(requestCookies(r)['connect.sid']);
  final session = setup.state.open(user.id, over: over);
  return NetworkReply.json(body).withHeaders({
    'set-cookie': [setup.state.sessionCookie(session, setup: setup)],
  });
}

Map<String, dynamic> _body(NetworkRequest r) {
  final json = r.json;
  return json is Map<String, dynamic> ? json : const {};
}

/// `POST /auth/local` (`auth.ts:853-903`).
NetworkReply _local(NetworkRequest r, ServerContext c, SeerrSetup setup) {
  if (!setup.localLogin) {
    return seerrErrorField(500, 'Password sign-in is disabled.');
  }
  final body = _body(r);
  final email = body['email'];
  final password = body['password'];
  if (email is! String ||
      email.isEmpty ||
      password is! String ||
      password.isEmpty) {
    return seerrErrorField(
      500,
      'You must provide both an email address and a password.',
    );
  }
  final user = setup.users
      .where((u) => u.email == email.toLowerCase() && u.password == password)
      .firstOrNull;
  // No such user and a wrong password read the same, on purpose.
  if (user == null) return seerrError(403, 'Access denied.');
  // The route selects four columns (id, email, password, plexId) and filters
  // the email out, so the user it sends carries the entity's defaults:
  // `permissions: 0` whatever the account holds, no requests, and the email
  // as its name. `/auth/me` is where the account is read. Seerr 3.4.1, live.
  return _signedIn(r, setup, user, {
    'permissions': 0,
    'warnings': const <String>[],
    'id': user.id,
    'requestCount': 0,
    'displayName': user.email,
  });
}

/// `POST /auth/jellyfin` (`auth.ts:246-638`), Jellyfin and Emby alike.
NetworkReply _jellyfin(NetworkRequest r, ServerContext c, SeerrSetup setup) {
  if (!setup.sendsMediaServerType) return _noSuchRoute(r);
  final server = setup.mediaServer;
  final viaJellyfin =
      server == SeerrMediaServer.jellyfin || server == SeerrMediaServer.emby;
  if (server != SeerrMediaServer.notConfigured &&
      (!setup.mediaServerLogin || !viaJellyfin)) {
    return seerrErrorField(500, 'Jellyfin login is disabled');
  }
  final body = _body(r);
  final username = body['username'];
  if (username is! String || username.isEmpty) {
    return seerrErrorField(500, 'You must provide an username');
  }
  final hostname = body['hostname'];
  final sentHost = hostname is String && hostname.isNotEmpty;
  if (server != SeerrMediaServer.notConfigured && sentHost) {
    return seerrErrorField(500, 'Jellyfin hostname already configured');
  }
  if (server == SeerrMediaServer.notConfigured) {
    if (!sentHost) return seerrErrorField(500, 'No hostname provided.');
    // The first setup: whoever signs in becomes the admin and the server is
    // set up with their Jellyfin (`auth.ts:334-430`).
    return _firstAdmin(r, c, setup, username, SeerrMediaServer.jellyfin);
  }
  final user = setup.users
      .where((u) => u.login == username && u.password == body['password'])
      .firstOrNull;
  // Jellyfin's 401, relayed as `next({status: 401, message: errorCode})`.
  if (user == null) return seerrError(401, 'INVALID_CREDENTIALS');
  return _signedIn(r, setup, user, seerrFilteredUser(user, c));
}

/// `POST /auth/plex` (`auth.ts:69-244`).
NetworkReply _plex(NetworkRequest r, ServerContext c, SeerrSetup setup) {
  final token = _body(r)['authToken'];
  if (token is! String || token.isEmpty) {
    return seerrError(500, 'Authentication token required.');
  }
  final server = setup.mediaServer;
  if (server != SeerrMediaServer.notConfigured &&
      (!setup.mediaServerLogin || server != SeerrMediaServer.plex)) {
    return seerrErrorField(500, 'Plex login is disabled');
  }
  // Seerr asks plex.tv who the token is; a token plex.tv does not know
  // fails there, and the route's catch answers.
  if (!c.network.plexTv.knowsToken(token)) {
    return seerrError(500, 'Unable to authenticate.');
  }
  if (setup.users.isEmpty) {
    return _firstAdmin(r, c, setup, 'plex-admin', SeerrMediaServer.plex);
  }
  final user = setup.users.where((u) => u.plexToken == token).firstOrNull;
  // A Plex account the server's owner does not share with.
  if (user == null) return seerrError(403, 'Access denied.');
  return _signedIn(r, setup, user, seerrFilteredUser(user, c));
}

/// The first sign-in on a server nobody has signed in to: it creates the
/// admin. The trap the app's guard on `initialized` is for.
NetworkReply _firstAdmin(
  NetworkRequest r,
  ServerContext c,
  SeerrSetup setup,
  String login,
  SeerrMediaServer server,
) {
  final admin = WorldSeerrUser(
    id: 1,
    displayName: login,
    permissions: SeerrPermission.admin.value,
    kind: server == SeerrMediaServer.plex
        ? WorldSeerrUserType.plex
        : WorldSeerrUserType.jellyfin,
    login: login,
  );
  setup.state._created.add(admin);
  setup.state._setUpWith = server;
  return _signedIn(r, setup, admin, seerrFilteredUser(admin, c));
}

/// `POST /auth/logout` (`auth.ts:905-980`): the session's row goes, and the
/// answer is the same with no session at all.
NetworkReply _logout(NetworkRequest r, SeerrSetup setup) {
  setup.state.resume(requestCookies(r)['connect.sid'])?.destroyed = true;
  return NetworkReply.json({'status': 'ok'});
}

/// `POST /auth/jellyfin/quickconnect/initiate` (`auth.ts:640-673`).
NetworkReply _quickConnectInitiate(NetworkRequest r, SeerrSetup setup) {
  if (!setup.hasQuickConnect) return _noSuchRoute(r);
  // Only the media server type is checked, not `mediaServerLogin`.
  if (setup.mediaServer != SeerrMediaServer.jellyfin) {
    return seerrError(403, 'Quick Connect is only supported by Jellyfin.');
  }
  // Jellyfin refuses `/QuickConnect/Initiate` when its Quick Connect is off,
  // and the route's catch answers (Seerr 3.4.1 on Jellyfin 12.1, live).
  // `/settings/public` does not say Jellyfin turned it off.
  if (!setup.quickConnectOn) {
    return seerrError(500, 'Failed to initiate quick connect.');
  }
  final request = setup.state.initiateQuickConnect();
  return NetworkReply.json({'code': request.code, 'secret': request.secret});
}

final _quickConnectSecret = RegExp(r'^[A-Fa-f0-9]{8,128}$');

/// `GET /auth/jellyfin/quickconnect/check?secret=…` (`auth.ts:675-712`).
NetworkReply _quickConnectCheck(NetworkRequest r, SeerrSetup setup) {
  if (!setup.hasQuickConnect) return _noSuchRoute(r);
  if (setup.mediaServer != SeerrMediaServer.jellyfin) {
    return seerrError(403, 'Quick Connect is only supported by Jellyfin.');
  }
  final secret = r.query['secret'] ?? '';
  if (!_quickConnectSecret.hasMatch(secret)) {
    return seerrError(400, 'Invalid secret format');
  }
  // With its Quick Connect off, Jellyfin answers every check 401, and Seerr
  // relays the status (live, as below).
  if (!setup.quickConnectOn) {
    return seerrError(401, 'Failed to check Quick Connect status');
  }
  final request = setup.state.quickConnect(secret);
  // Jellyfin answers an unknown or timed-out secret with 404, relayed with
  // its status (Seerr 3.4.1 on Jellyfin 12.1, live: a code lives between nine
  // and ten minutes).
  if (request == null) {
    return seerrError(404, 'Failed to check Quick Connect status');
  }
  return NetworkReply.json({'authenticated': request.approvedBy != null});
}

/// `POST /auth/jellyfin/quickconnect/authenticate` (`auth.ts:714-851`).
NetworkReply _quickConnectAuthenticate(
  NetworkRequest r,
  ServerContext c,
  SeerrSetup setup,
) {
  if (!setup.hasQuickConnect) return _noSuchRoute(r);
  final secret = _body(r)['secret'];
  if (secret is! String || !_quickConnectSecret.hasMatch(secret)) {
    return seerrError(400, 'Secret required');
  }
  if (setup.mediaServer == SeerrMediaServer.notConfigured ||
      setup.users.isEmpty) {
    return seerrError(
      403,
      'Quick Connect is not available during initial setup.',
    );
  }
  if (setup.mediaServer != SeerrMediaServer.jellyfin) {
    return seerrError(403, 'Quick Connect is only supported by Jellyfin.');
  }
  final request = setup.state.quickConnect(secret);
  final approvedBy = request?.approvedBy;
  // Jellyfin refuses a secret nobody approved, and Seerr relays it with its
  // status as `INVALID_CREDENTIALS`: a 404 (Seerr 3.4.1 on Jellyfin 12.1,
  // live). An approved secret signs in again for as long as Jellyfin keeps
  // it, each time with a new session.
  if (request == null || approvedBy == null) {
    return seerrError(404, 'INVALID_CREDENTIALS');
  }
  request.spent = true;
  final user = setup.users.where((u) => u.id == approvedBy.id).firstOrNull;
  if (user == null) return seerrError(403, 'Access denied.');
  return _signedIn(r, setup, user, seerrFilteredUser(user, c));
}

// === The user's own settings ==============================================

/// `/api/v1/user/{id}/settings/{main,notifications,password,permissions}`
/// once the gate let the caller through (`server/routes/user/usersettings.ts`
/// v3.5.0): the checks each route makes on the user it is about. Null for
/// any other route.
NetworkReply? seerrUserSettingsAnswer(NetworkRequest r, ServerContext c) {
  final match = RegExp(
    r'^/api/v1/user/(\d+)/settings/(main|notifications|password|permissions)$',
  ).firstMatch(r.path);
  final caller = seerrCallerOf(r, c);
  if (match == null || caller == null) return null;
  final setup = SeerrSetup.of(c);
  final user = setup.userById(int.parse(match.group(1)!));
  if (user == null) return seerrError(404, 'User not found.');
  final body = _body(r);
  final write = r.method == 'POST';
  // "Owner" user settings cannot be modified by other users.
  final ownerByOther = user.id == 1 && caller.user.id != 1;

  switch (match.group(2)) {
    case 'main':
      if (!write) return NetworkReply.json(_generalSettings(user));
      if (ownerByOther) {
        return seerrError(
          403,
          "You do not have permission to modify this user's settings.",
        );
      }
      return NetworkReply.json({
        'username': body['username'],
        'locale': body['locale'],
        'discoverRegion': body['discoverRegion'],
        'streamingRegion': body['streamingRegion'],
        'originalLanguage': body['originalLanguage'],
        'watchlistSyncMovies': body['watchlistSyncMovies'],
        'watchlistSyncTv': body['watchlistSyncTv'],
        'email': user.kind == WorldSeerrUserType.plex
            ? user.email
            : (body['email'] as String?) ?? user.email,
      });
    case 'notifications':
      if (!write) {
        return NetworkReply.json({
          'emailEnabled': false,
          'discordEnabled': false,
          'discordEnabledTypes': 0,
          'discordIds': const <String>[],
          'telegramEnabled': false,
          'webPushEnabled': false,
          'notificationTypes': const <String, Object?>{},
        });
      }
      if (ownerByOther) {
        return seerrError(
          403,
          "You do not have permission to modify this user's settings.",
        );
      }
      return NetworkReply.json({
        'discordIds': [
          for (final id in (body['discordIds'] as List?) ?? const [])
            if (id != '') id,
        ],
        'notificationTypes': body['notificationTypes'] ?? const {},
      });
    case 'password':
      if (!write) return NetworkReply.json({'hasPassword': true});
      final next = body['newPassword'];
      if (next is! String) {
        // `req.body.newPassword.length` throws, and the catch answers.
        return seerrError(
          500,
          "Cannot read properties of undefined (reading 'length')",
        );
      }
      if (next.length < 8) {
        return seerrError(400, 'Password must be at least 8 characters.');
      }
      final admin = hasSeerrPermission(user.permissions, SeerrPermission.admin);
      if (ownerByOther ||
          (admin && user.id != caller.user.id && caller.user.id != 1)) {
        return seerrError(
          403,
          "You do not have permission to modify this user's password.",
        );
      }
      final overriding =
          caller.has(SeerrPermission.manageUsers) && caller.user.id != user.id;
      if (!overriding && body['currentPassword'] != user.password) {
        return seerrError(403, 'Current password is invalid.');
      }
      return const NetworkReply(204);
    case 'permissions':
      if (!write) return NetworkReply.json({'permissions': user.permissions});
      if (user.id == 1 || caller.user.id == user.id) {
        return seerrError(
          403,
          'You do not have permission to modify this user',
        );
      }
      final granted = body['permissions'];
      // `canMakePermissionsChange`: only user 1 hands out ADMIN.
      if (granted is int &&
          granted & SeerrPermission.admin.value != 0 &&
          caller.user.id != 1) {
        return seerrError(
          403,
          'You do not have permission to grant this level of access',
        );
      }
      return NetworkReply.json({'permissions': granted});
  }
  return null;
}

/// `GET /user/{id}/settings/main` for a user with no settings saved and no
/// quota of their own. The fields read from missing settings, and the
/// server's default quotas, which set none, are undefined and left out.
Map<String, Object?> _generalSettings(WorldSeerrUser user) => {
  'username': user.kind == WorldSeerrUserType.local
      ? user.displayName.toLowerCase()
      : null,
  'email': user.email,
  'movieQuotaLimit': null,
  'movieQuotaDays': null,
  'tvQuotaLimit': null,
  'tvQuotaDays': null,
};

// === Quota =================================================================

/// `GET /user/{id}/quota` for [user] (`User.ts` `getQuota`).
///
/// MANAGE_USERS has no limit (`limit: 0`). Otherwise the defaults set none,
/// so `limit`, `days` and `remaining` are left out, unless [full].
Map<String, Object?> seerrQuotaOf(WorldSeerrUser user, {required bool full}) {
  if (hasSeerrPermission(user.permissions, SeerrPermission.manageUsers)) {
    return {
      'movie': {'limit': 0, 'used': 0, 'restricted': false},
      'tv': {'limit': 0, 'used': 0, 'restricted': false},
    };
  }
  if (full) {
    return {
      'movie': {
        'days': 7,
        'limit': 5,
        'used': 5,
        'remaining': 0,
        'restricted': true,
      },
      'tv': {
        'days': 7,
        'limit': 3,
        'used': 3,
        'remaining': 0,
        'restricted': true,
      },
    };
  }
  return {
    'movie': {'used': 0, 'restricted': false},
    'tv': {'used': 0, 'restricted': false},
  };
}

/// Why `POST /request` refuses [caller] a request of [kind] (`movie` or
/// `tv`), or null when it would be made (`MediaRequest.ts:100-166`).
NetworkReply? seerrRequestRefusal(
  SeerrCaller caller, {
  required String? kind,
  required bool is4k,
  required bool ignoreQuota,
  required bool quotaReached,
}) {
  final movie = kind == 'movie';
  if (kind == 'movie' || kind == 'tv') {
    final allowed = caller.hasAny(
      is4k
          ? [
              SeerrPermission.request4k,
              movie
                  ? SeerrPermission.request4kMovie
                  : SeerrPermission.request4kTv,
            ]
          : [
              SeerrPermission.request,
              movie ? SeerrPermission.requestMovie : SeerrPermission.requestTv,
            ],
    );
    if (!allowed) {
      return seerrError(
        403,
        'You do not have permission to make ${is4k ? '4K ' : ''}'
        '${movie ? 'movie' : 'series'} requests.',
      );
    }
  }
  final canBypass = caller.has(SeerrPermission.manageRequests);
  if (ignoreQuota && !canBypass) {
    return seerrError(
      403,
      'You do not have permission to bypass user quota limits.',
    );
  }
  final limited = !caller.has(SeerrPermission.manageUsers);
  if (quotaReached && limited && !(ignoreQuota && canBypass)) {
    return seerrError(
      403,
      movie ? 'Movie Quota exceeded.' : 'Series Quota exceeded.',
    );
  }
  return null;
}

/// Whether a new request by [caller] skips the queue
/// (`MediaRequest.ts:310-340`).
bool seerrAutoApproves(
  SeerrCaller caller, {
  required bool movie,
  required bool is4k,
}) => caller.hasAny([
  SeerrPermission.manageRequests,
  if (is4k) ...[
    SeerrPermission.autoApprove4k,
    movie
        ? SeerrPermission.autoApprove4kMovie
        : SeerrPermission.autoApprove4kTv,
  ] else ...[
    SeerrPermission.autoApprove,
    movie ? SeerrPermission.autoApproveMovie : SeerrPermission.autoApproveTv,
  ],
]);
