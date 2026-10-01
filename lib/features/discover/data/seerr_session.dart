/// How a client reaches Seerr: the one place a Seerr client is built
/// ([seerrClientFor]), the session an account signs in with, and the CSRF
/// token Seerr may ask of every write.
///
/// Two ways in. The operator's API key travels as `X-Api-Key`, as it always
/// has. A household member's account travels as the session cookie Seerr
/// handed back when they signed in, and nothing else: no password, no Plex
/// token, ever. Both ways meet Seerr's CSRF protection when the operator turned
/// it on, the key included.
///
/// Read from Seerr v3.5.0: the session (`server/index.ts:216-235`, the default
/// `express-session` cookie, 30 days, never rolled), the CSRF guard
/// (`server/index.ts:195-214`, `@dr.pogodin/csurf` 1.16.9) and the permission
/// check (`server/middleware/auth.ts`).
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/capability/permission_refusal.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/features/discover/domain/seerr_refusal.dart';
import 'package:cupola/features/discover/domain/seerr_sign_in.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The session cookie: `express-session`'s default name, which Seerr keeps.
const _sessionCookie = 'connect.sid';

/// csurf's secret, an httpOnly cookie.
const _csrfSecretCookie = '_csrf';

/// The token for that secret, which the server sets on every answer and the
/// client sends back in [_csrfTokenHeader].
const _csrfTokenCookie = 'XSRF-TOKEN';

/// One of the four headers csurf reads (`build/cjs/index.js:52`), the one
/// Seerr's own web client sends.
const _csrfTokenHeader = 'X-XSRF-TOKEN';

/// The routes that sign in. A session is never sent to them: each starts a
/// new one, and Seerr writes the new user into whatever session arrives
/// rather than starting afresh.
final _signInRoute = RegExp(r'/api/v1/auth/(local|jellyfin|plex)(/|$)');

const _writeMethods = {'POST', 'PUT', 'PATCH', 'DELETE'};

/// What a client tells the app about the session beyond one request.
///
/// Every callback is optional, and none carries a secret except [onSession],
/// whose caller keeps the value in secure storage and nowhere else.
@immutable
class SeerrSessionEvents {
  const SeerrSessionEvents({
    this.onSession,
    this.onSessionEnded,
    this.onWhoAmI,
  });

  /// A new session arrived: Seerr answered a sign-in with its cookie.
  final void Function(String session)? onSession;

  /// The server no longer knows the session: a request was refused and so
  /// was `/auth/me`. Once per session.
  final void Function()? onSessionEnded;

  /// `/auth/me` answered, while a refusal was being told apart from an ended
  /// session: the account's current permissions, for the gate. The body
  /// carries the email; read what is needed and keep nothing else.
  final void Function(Map<String, dynamic> whoAmI)? onWhoAmI;
}

/// The Seerr client of [instance]: the one constructor, so every Seerr
/// request carries what the connection needs.
///
/// - The API key ([SeerrApiKeySignIn]) as `X-Api-Key`, plus
///   [SeerrCsrfInterceptor].
/// - An account ([SeerrAccountSignIn]) as its session cookie
///   ([SeerrSessionInterceptor]), plus [SeerrCsrfInterceptor]. An account
///   with no session yet is a client to sign in with: it sends no cookie and
///   keeps the one the sign-in answers with ([SeerrSessionEvents.onSession]).
///
/// Both carry the certificate pinned for the origin
/// ([pinnedCertFingerprint], ADR-6) and the connection's access to a gateway
/// in front ([ServiceInstance.access]). Redirects stay on the configured
/// origin, so the cookie never leaves the host.
///
/// [signIn] overrides the instance's own way in: the sign-in sequences pass
/// the account being signed in. Without it the instance's credential is the
/// API key.
///
/// `test/features/discover/data/seerr_client_guard_test.dart` holds that no
/// Seerr client is born anywhere else.
ApiClient seerrClientFor(
  ServiceInstance instance, {
  String? pinnedCertFingerprint,
  SeerrSignIn? signIn,
  SeerrSessionEvents events = const SeerrSessionEvents(),
}) {
  assert(instance.service == ServiceKey.seerr, 'not a Seerr connection');
  final way = signIn ?? SeerrApiKeySignIn(instance.credential);
  final accessHeaders = instance.access.headers();
  return switch (way) {
    SeerrApiKeySignIn(:final key) => ApiClient(
      baseUrl: instance.url,
      apiKey: key.trim(),
      pinnedCertFingerprint: pinnedCertFingerprint,
      accessHeaders: accessHeaders,
      interceptors: (dio) => [SeerrCsrfInterceptor(dio)],
    ),
    SeerrAccountSignIn(:final session) => ApiClient.authenticatedBy(
      baseUrl: instance.url,
      headers: const {},
      pinnedCertFingerprint: pinnedCertFingerprint,
      accessHeaders: accessHeaders,
      interceptors: (dio) => [
        SeerrSessionInterceptor(dio, session: session, events: events),
        SeerrCsrfInterceptor(dio),
      ],
    ),
  };
}

/// [seerrClientFor] as a value a test can replace: the Dashboard probe builds
/// its throwaway Seerr client through this.
typedef SeerrClientFactory =
    ApiClient Function(
      ServiceInstance instance, {
      String? pinnedCertFingerprint,
      SeerrSessionEvents events,
    });

final seerrClientFactoryProvider = Provider<SeerrClientFactory>(
  (ref) => seerrClientFor,
);

/// The Seerr client of the connection [instanceId] names, or of the lens when
/// it names none, rebuilt when its address, credential, pinned certificate or
/// access changes, and closed when the provider goes.
///
/// Throws `Exception('Seerr not configured')`, which `AsyncValueWidget`
/// turns into its placeholder, as `watchApiClient` does for the other
/// services.
ApiClient watchSeerrClient(
  Ref ref, {
  String? instanceId,
  SeerrSessionEvents events = const SeerrSessionEvents(),
}) {
  final transport = watchTransport(
    ref,
    ServiceKey.seerr,
    instanceId: instanceId,
  );
  if (!transport.configured) {
    throw Exception('${ServiceKey.seerr.title} not configured');
  }
  final client = seerrClientFor(
    ServiceInstance(
      id: transport.instanceId,
      service: ServiceKey.seerr,
      url: transport.url,
      credential: transport.apiKey,
      access: transport.access,
    ),
    pinnedCertFingerprint: transport.pin,
    events: events,
  );
  ref.onDispose(client.close);
  return client;
}

// === The session ===========================================================

/// Sends an account's session, keeps the one a sign-in hands back, and tells
/// an ended session apart from a permission the account lacks.
///
/// - On every request but a sign-in, `Cookie: connect.sid=<session>`. A
///   sign-in gets no session at all, so it always starts a new one.
/// - On every answer, the `connect.sid` of a `Set-Cookie`, which Seerr sends
///   only to a sign-in. Its `Expires`, `Domain`, `Path` and `Secure` are left
///   unread: the client talks to one origin, and the server is the authority
///   on when the session is over (it moves the expiry 30 days past every use,
///   the cookie's own does not move). That is also why no `CookieJar` is
///   used: a persistent one writes to a file rather than the keychain, and an
///   in-memory one drops a `Secure` cookie over `http://`.
/// - On a refusal that `classifySeerrRefusal` reads as "no permission", one
///   `GET /auth/me`: refused too, the session is over
///   ([SeerrSessionEnded], [SeerrSessionEvents.onSessionEnded]); answered,
///   the account lacks the permission ([SeerrRefused],
///   [SeerrSessionEvents.onWhoAmI] with its current permissions).
///
/// The CSRF cookie is [SeerrCsrfInterceptor]'s, in both ways in.
class SeerrSessionInterceptor extends Interceptor {
  SeerrSessionInterceptor(
    this._dio, {
    required String session,
    this.events = const SeerrSessionEvents(),
  }) : _session = session;

  final Dio _dio;
  final SeerrSessionEvents events;
  String _session;

  /// Set on the `/auth/me` this interceptor sends itself, so its own refusal
  /// is not resolved by asking `/auth/me` again.
  static const _whoAmIExtra = 'cupola.seerrWhoAmI';

  Future<int?>? _whoAmI;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final signIn = _signInRoute.hasMatch(options.uri.path);
    _putCookie(options, _sessionCookie, signIn ? null : _session);
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    _keepSession(response);
    handler.next(response);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final response = err.response;
    _keepSession(response);
    final options = err.requestOptions;
    if (response == null ||
        options.extra[_whoAmIExtra] == true ||
        _signInRoute.hasMatch(options.uri.path)) {
      handler.next(err);
      return;
    }
    final refusal = classifySeerrRefusal(
      status: response.statusCode,
      method: options.method,
      path: options.uri.path,
      body: response.data,
    );
    if (refusal == null) {
      handler.next(err);
      return;
    }
    final verdict = refusal.asksWhoAmI
        ? refusal.afterWhoAmI(await (_whoAmI ??= _askWhoAmI()))
        : refusal;
    switch (verdict) {
      case SeerrRefusal.sessionEnded:
        _ended();
        handler.next(_withVerdict(err, const SeerrSessionEnded()));
      case SeerrRefusal.endpointRefused ||
          SeerrRefusal.permissionDenied ||
          SeerrRefusal.requestNotAllowed:
        handler.next(_withVerdict(err, SeerrRefused(verdict)));
      case _:
        // Every other verdict is the request's own (a quota, a duplicate, a
        // CSRF token), answered where the request was made.
        handler.next(err);
    }
  }

  /// `GET /auth/me`'s status, or null when it did not answer: a timeout
  /// settles nothing.
  Future<int?> _askWhoAmI() async {
    try {
      final me = await _dio.get<dynamic>(
        '/api/v1/auth/me',
        options: Options(extra: {_whoAmIExtra: true}),
      );
      final data = me.data;
      if (data is Map<String, dynamic>) events.onWhoAmI?.call(data);
      return me.statusCode;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final refused =
          classifySeerrRefusal(
            status: status,
            method: 'GET',
            path: '/api/v1/auth/me',
            body: e.response?.data,
          ) ==
          SeerrRefusal.sessionEnded;
      return refused ? status : null;
    } finally {
      _whoAmI = null;
    }
  }

  void _ended() {
    if (_session.isEmpty) return;
    _session = '';
    events.onSessionEnded?.call();
  }

  void _keepSession(Response? response) {
    final value = _setCookiesOf(response)[_sessionCookie];
    if (value == null || value.isEmpty || value == _session) return;
    _session = value;
    events.onSession?.call(value);
  }
}

// === CSRF ==================================================================

/// Answers Seerr's CSRF protection, for the API key and an account alike.
///
/// Off by default in Seerr, and then this does nothing: no token ever
/// arrives. On, csurf guards every POST, PUT, PATCH and DELETE ahead of every
/// route, the key's included, and refuses one without the token with
/// `403 invalid csrf token`:
///
/// - the secret cookie (`_csrf`) and the token (`XSRF-TOKEN`) are kept from
///   any answer, in memory and for this client only;
/// - the secret goes back on every request, and the token in
///   `X-XSRF-TOKEN` on every write;
/// - a write refused for its token fetches one (`GET /settings/public`, a
///   public route) and is sent **once** more. Refused again, it fails as
///   [SeerrCsrfRefused].
class SeerrCsrfInterceptor extends Interceptor {
  SeerrCsrfInterceptor(this._dio);

  final Dio _dio;
  String? _secret;
  String? _token;

  /// Set on a write sent the second time.
  static const _againExtra = 'cupola.seerrCsrfAgain';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _putCookie(options, _csrfSecretCookie, _secret);
    final token = _token;
    if (_isWrite(options) && token != null) {
      options.headers[_csrfTokenHeader] = token;
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    _keep(response);
    handler.next(response);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    _keep(err.response);
    final options = err.requestOptions;
    if (!_isWrite(options) || !_refusedForToken(err)) {
      handler.next(err);
      return;
    }
    if (options.extra[_againExtra] == true) {
      handler.next(_withVerdict(err, const SeerrCsrfRefused()));
      return;
    }
    try {
      // Any answer past the guard carries the token; this one is public, so
      // it costs neither a session nor the key.
      await _dio.get<dynamic>('/api/v1/settings/public');
    } on DioException {
      // Nothing to send the write with: the refusal stands.
    }
    if (_token == null) {
      handler.next(_withVerdict(err, const SeerrCsrfRefused()));
      return;
    }
    try {
      final again = await _dio.fetch<dynamic>(
        options.copyWith(extra: {...options.extra, _againExtra: true}),
      );
      handler.resolve(again);
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  void _keep(Response? response) {
    final cookies = _setCookiesOf(response);
    final secret = cookies[_csrfSecretCookie];
    if (secret != null && secret.isNotEmpty) _secret = secret;
    final token = cookies[_csrfTokenCookie];
    if (token != null && token.isNotEmpty) _token = token;
  }

  static bool _refusedForToken(DioException err) {
    final response = err.response;
    return response != null &&
        classifySeerrRefusal(
              status: response.statusCode,
              method: err.requestOptions.method,
              path: err.requestOptions.uri.path,
              body: response.data,
            ) ==
            SeerrRefusal.csrfToken;
  }
}

// === What a refusal turned out to be ======================================

/// The account's session is over. [ServiceFailureReason.sessionEnded]: blue,
/// and the remedy is signing in again.
class SeerrSessionEnded
    implements Exception, HasFailureReason, HasPermissionRefusal {
  const SeerrSessionEnded();

  @override
  ServiceFailureReason get reason => ServiceFailureReason.sessionEnded;

  /// Not the account lacking a permission: nothing about it is known.
  @override
  bool get isPermissionRefusal => false;

  @override
  String toString() => 'SeerrSessionEnded';
}

/// A write Seerr's CSRF protection refused twice, the second time with the
/// token it had just handed out. [ServiceFailureReason.csrfRefused].
class SeerrCsrfRefused
    implements Exception, HasFailureReason, HasPermissionRefusal {
  const SeerrCsrfRefused();

  @override
  ServiceFailureReason get reason => ServiceFailureReason.csrfRefused;

  /// The server's guard, never the credential's scope.
  @override
  bool get isPermissionRefusal => false;

  @override
  String toString() => 'SeerrCsrfRefused';
}

/// The account reached Seerr, and Seerr said it may not: [refusal] is
/// [SeerrRefusal.permissionDenied], [SeerrRefusal.requestNotAllowed], or
/// [SeerrRefusal.endpointRefused] when `/auth/me` could not be asked.
///
/// Classified as the refusal it was before accounts existed; what the
/// surface says about it is the gate's (`RoleGate`), which knows the account
/// and the audience.
class SeerrRefused implements Exception, HasPermissionRefusal {
  const SeerrRefused(this.refusal);

  final SeerrRefusal refusal;

  @override
  bool get isPermissionRefusal => true;

  @override
  String toString() => 'SeerrRefused(${refusal.name})';
}

/// What Seerr meant by refusing the request [error] stands for, or null when
/// it was not one of Seerr's own refusals.
///
/// Reads what the transport already decided ([SeerrSessionEnded],
/// [SeerrCsrfRefused], [SeerrRefused]) before the answer itself, so an ended
/// session is never read again as a missing permission.
SeerrRefusal? seerrRefusalOf(Object? error) {
  final cause = unwrapFailure(error);
  if (cause is! DioException) return null;
  return switch (cause.error) {
    SeerrSessionEnded() => SeerrRefusal.sessionEnded,
    SeerrCsrfRefused() => SeerrRefusal.csrfToken,
    SeerrRefused(:final refusal) => refusal,
    _ => classifySeerrRefusal(
      status: cause.response?.statusCode,
      method: cause.requestOptions.method,
      path: cause.requestOptions.uri.path,
      body: cause.response?.data,
    ),
  };
}

// === Cookies ===============================================================

bool _isWrite(RequestOptions options) =>
    _writeMethods.contains(options.method.toUpperCase());

/// [err] carrying the verdict the transport reached on it.
DioException _withVerdict(DioException err, Object verdict) => DioException(
  requestOptions: err.requestOptions,
  response: err.response,
  type: err.type,
  error: verdict,
  stackTrace: err.stackTrace,
  message: 'Seerr refused the request.',
);

/// Sets cookie [name] on [options] to [value], or takes it off when [value]
/// is null or empty, leaving every other cookie as it was. A followed
/// redirect replays the headers it was sent with, so setting rather than
/// adding is what keeps one cookie of each name.
void _putCookie(RequestOptions options, String name, String? value) {
  final key = options.headers.keys
      .where((header) => header.toLowerCase() == 'cookie')
      .firstOrNull;
  final current = key == null ? '' : '${options.headers[key] ?? ''}';
  final pairs = [
    for (final pair in current.split(';'))
      if (pair.trim().isNotEmpty && _cookieName(pair) != name) pair.trim(),
    if (value != null && value.isNotEmpty) '$name=$value',
  ];
  if (key != null) options.headers.remove(key);
  if (pairs.isNotEmpty) options.headers['Cookie'] = pairs.join('; ');
}

String _cookieName(String pair) {
  final at = pair.indexOf('=');
  return (at < 0 ? pair : pair.substring(0, at)).trim();
}

/// The `name=value` of every `Set-Cookie` of [response], by name, the
/// attributes left behind.
Map<String, String> _setCookiesOf(Response? response) {
  final lines = response?.headers['set-cookie'] ?? const <String>[];
  final cookies = <String, String>{};
  for (final line in lines) {
    final pair = line.split(';').first;
    final at = pair.indexOf('=');
    if (at <= 0) continue;
    cookies[pair.substring(0, at).trim()] = pair.substring(at + 1).trim();
  }
  return cookies;
}
