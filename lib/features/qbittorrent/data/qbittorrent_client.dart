import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/network/redirect_guard.dart';
import 'package:cupola/core/utils/url_utils.dart';

/// Error thrown by [QbittorrentClient], carrying the [reason] so a caller
/// verifying the connection can tell rejected credentials from an unreachable
/// host — matching the contract the other service clients use.
class QbittorrentException implements Exception, HasFailureReason {
  const QbittorrentException(
    this.message, {
    this.reason = ServiceFailureReason.unknown,
  });
  final String message;
  @override
  final ServiceFailureReason reason;
  @override
  String toString() => 'QbittorrentException: $message';
}

/// Why the WebUI refused to sign this client in, once it has said so in a way
/// no retry can change. See [QbittorrentClient]'s `_refusal`.
enum _LoginRefusal {
  /// `200 Fails.` (qB ≤ 5.0) or `401` (5.1+): wrong username or password.
  credentials,

  /// `403` on the login route, with qBittorrent's "banned" body: the WebUI has
  /// banned this address after too many failed sign-ins.
  banned,

  /// `403` on the login route with some other body — qBittorrent's ban message
  /// in another WebUI locale, or a reverse proxy refusing the request.
  forbidden,
}

/// qBittorrent WebUI client.
///
/// ## A refused sign-in is final for this client
///
/// qBittorrent counts every failed login per client address and, at
/// `WebUIMaxAuthFailCount` (default **5**), bans that address for
/// `WebUIBanDuration` (default **3600 s**). Behind a reverse proxy the address
/// it bans is the proxy's, which is everybody. A client that re-sends a wrong
/// password on a three-second poll — with Riverpod's default retry on top —
/// spends the five attempts in seconds.
///
/// So once the WebUI has refused a sign-in unambiguously ([_LoginRefusal]),
/// this client never sends the login again on its own: every later call fails
/// locally with the same sentence. Only two things lift it — new credentials,
/// which build a new client (the providers watch the transport), and
/// [clearLoginRefusal], which a *user's* Retry calls. A poll tick never does.
class QbittorrentClient {
  final String baseUrl;
  final String? username;
  final String? password;
  late final Dio _dio;
  final CookieJar _cookieJar;
  bool _authenticated = false;
  Future<bool>? _authInFlight;

  /// Sticky once the WebUI has refused a sign-in unambiguously — see the class
  /// doc. Deliberately **not** reset by an attempt to sign in: it used to be,
  /// at the top of every login, which is what made it stop nothing.
  _LoginRefusal? _refusal;

  /// [certFingerprint], when non-empty, is a self-signed certificate the user
  /// explicitly trusted for this origin (trust-on-first-use, ADR-6). Ignored
  /// when [dio] is injected — a caller supplying its own transport owns its
  /// TLS behaviour too, the same rule the other per-service clients follow.
  QbittorrentClient({
    required String url,
    this.username,
    this.password,
    Dio? dio,
    CookieJar? cookieJar,
    String? certFingerprint,
  }) : baseUrl = UrlUtils.normalizeBaseUrl(url),
       _cookieJar = cookieJar ?? CookieJar() {
    // Redirects are followed by hand so the SID cookie — which is full account
    // access to the torrent client — is never replayed to a host the user did
    // not configure. `dart:io` exempts a redirect to a *parent* domain from its
    // own cookie stripping, so `qbit.homelab.net` → `homelab.net` hands the
    // session over.
    _dio = guardedDio(
      baseUrl: baseUrl,
      injected: dio,
      certFingerprint: certFingerprint,
      sendTimeout: const Duration(seconds: 10),
    );

    // Added after the redirect guard, and unconditionally: the guard has to see
    // a 3xx first, and these two apply to an injected transport as well.
    _dio.interceptors.add(CookieManager(_cookieJar));
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          options.headers['Referer'] = baseUrl;
          options.headers['Origin'] = baseUrl;
          handler.next(options);
        },
        onError: (error, handler) async {
          final isAuthFailure = error.response?.statusCode == 403;
          final alreadyRetried =
              error.requestOptions.extra['skipAuthRetry'] == true;
          if (!isAuthFailure || !hasCredentials || alreadyRetried) {
            handler.next(error);
            return;
          }
          final ok = await authenticate();
          if (!ok) {
            handler.next(error);
            return;
          }
          error.requestOptions.extra['skipAuthRetry'] = true;
          try {
            final response = await _dio.fetch(error.requestOptions);
            handler.resolve(response);
          } catch (_) {
            handler.next(error);
          }
        },
      ),
    );
  }

  bool get hasCredentials =>
      username != null &&
      username!.isNotEmpty &&
      password != null &&
      password!.isNotEmpty;

  /// Whether a sign-in has been refused and is being held — see the class doc.
  bool get loginRefused => _refusal != null;

  /// Lets the next call sign in again after a refusal.
  ///
  /// For a **user's** explicit Retry only: the person has fixed the password
  /// on the server, or waited out the ban, and asks once. Never from a timer —
  /// a poll that cleared this would be exactly the loop it exists to stop.
  void clearLoginRefusal() => _refusal = null;

  Future<bool> authenticate() {
    if (!hasCredentials) return Future.value(true);
    // A refused sign-in is never re-sent on the client's own initiative: this
    // is also the path the 403 interceptor takes, so without the check an
    // expired session plus a changed password would log in on every request.
    if (_refusal != null) return Future.value(false);
    final inflight = _authInFlight;
    if (inflight != null) return inflight;
    final future = _doAuthenticate();
    _authInFlight = future;
    future.whenComplete(() => _authInFlight = null);
    return future;
  }

  Future<bool> _doAuthenticate() async {
    try {
      final response = await _dio.post(
        '/api/v2/auth/login',
        data: {'username': username, 'password': password},
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          extra: {'skipAuthRetry': true},
        ),
      );
      _authenticated = _isLoginSuccess(response);
      _refusal = _refusalFrom(response.statusCode, response.data);
    } on DioException catch (e) {
      _authenticated = false;
      // A 401 or 403 arrives as an error rather than a response, so read it
      // here too. A transport failure (no response at all) is not a refusal:
      // the WebUI never saw the attempt, so it counted nothing.
      _refusal = _refusalFrom(e.response?.statusCode, e.response?.data);
    } catch (_) {
      _authenticated = false;
    }
    return _authenticated;
  }

  /// qBittorrent <= 5.0 answers `200 Ok.` on success and `200 Fails.` on bad
  /// credentials; 5.1+ answers `204` with an empty body on success and `401`
  /// on bad credentials. Accept any 2xx that is not an explicit failure.
  static bool _isLoginSuccess(Response response) {
    final status = response.statusCode ?? 0;
    if (status < 200 || status >= 300) return false;
    final body = response.data?.toString().trim().toLowerCase() ?? '';
    return body != 'fails.';
  }

  /// Which refusal, if any, a login answer states unambiguously.
  ///
  /// * `401`, and `200 Fails.`: wrong credentials (qB 5.1+ and ≤ 5.0).
  /// * `403`: qBittorrent's login route answers 403 for one reason only — the
  ///   address is banned (`isBanned()` runs before the credentials are even
  ///   read). The body is its translated "Your IP address has been banned…"
  ///   sentence, so an English `banned` names the ban and any other 403 is
  ///   held as [_LoginRefusal.forbidden]: a ban in another locale or a proxy
  ///   refusing the route, neither of which a retry changes.
  ///
  /// Anything else — a 2xx, a 5xx, no response at all — is not a refusal.
  static _LoginRefusal? _refusalFrom(int? status, dynamic body) {
    final text = body?.toString().trim().toLowerCase() ?? '';
    if (status == 401) return _LoginRefusal.credentials;
    if (status == 200 && text == 'fails.') return _LoginRefusal.credentials;
    if (status == 403) {
      return text.contains('banned')
          ? _LoginRefusal.banned
          : _LoginRefusal.forbidden;
    }
    return null;
  }

  /// The sentence a held refusal reads as. Static text only — never the body
  /// or the request — so nothing here can carry the password.
  static QbittorrentException _refusalException(_LoginRefusal refusal) {
    return switch (refusal) {
      _LoginRefusal.credentials => const QbittorrentException(
        'qBittorrent rejected the username or password',
        reason: ServiceFailureReason.unauthorized,
      ),
      _LoginRefusal.banned => const QbittorrentException(
        'qBittorrent has blocked this address after too many failed sign-ins. '
        'The block lifts on its own (after an hour by default) or when '
        'qBittorrent restarts.',
        reason: ServiceFailureReason.unauthorized,
      ),
      _LoginRefusal.forbidden => const QbittorrentException(
        'qBittorrent refused to sign in from this address (403). It does this '
        'after too many failed sign-ins; a proxy in front of it can too.',
        reason: ServiceFailureReason.unauthorized,
      ),
    };
  }

  /// Authenticates when credentials are configured, failing fast on a refusal.
  ///
  /// Without this the client pressed on to the data call, took a 403, let the
  /// interceptor re-authenticate, and only then surfaced the failure — three
  /// round trips to learn the password was wrong, which on a slow link ran past
  /// the verify timeout and reported "check the address" instead. A refusal
  /// already held fails before anything reaches the network.
  Future<void> _ensureAuthenticated() async {
    if (!hasCredentials) return;
    final held = _refusal;
    if (held != null) throw _refusalException(held);
    if (_authenticated) return;
    await authenticate();
    final refusal = _refusal;
    if (!_authenticated && refusal != null) throw _refusalException(refusal);
  }

  Future<String> getVersion() async {
    await _ensureAuthenticated();
    final response = await _dio.get('/api/v2/app/version');
    return response.data?.toString().trim() ?? '';
  }

  Future<Response> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
  }) async {
    await _ensureAuthenticated();
    return _dio.get(
      path,
      queryParameters: queryParameters,
      cancelToken: cancelToken,
    );
  }

  Future<Response> post(
    String path, {
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? data,
    FormData? formData,
  }) async {
    await _ensureAuthenticated();
    return _dio.post(
      path,
      queryParameters: queryParameters,
      data: formData ?? data,
      options: Options(
        contentType: formData != null
            ? Headers.multipartFormDataContentType
            : Headers.formUrlEncodedContentType,
      ),
    );
  }

  void close({bool force = false}) {
    _dio.close(force: force);
  }
}
