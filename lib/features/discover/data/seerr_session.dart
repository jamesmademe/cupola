/// How a client reaches Seerr: the one place a Seerr client is built
/// ([seerrClientFor]), and the CSRF token Seerr may ask of every write.
///
/// The operator's API key travels as `X-Api-Key`, as it always has, and meets
/// Seerr's CSRF protection when the operator turned it on: a guard mounted
/// ahead of every route, which refuses a write without the token whatever
/// credential it carries.
///
/// Read from Seerr v3.5.0: the CSRF guard (`server/index.ts:195-214`,
/// `@dr.pogodin/csurf` 1.16.9).
library;


import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/capability/permission_refusal.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/features/discover/domain/seerr_refusal.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// csurf's secret, an httpOnly cookie.
const _csrfSecretCookie = '_csrf';

/// The token for that secret, which the server sets on every answer and the
/// client sends back in [_csrfTokenHeader].
const _csrfTokenCookie = 'XSRF-TOKEN';

/// One of the four headers csurf reads (`build/cjs/index.js:52`), the one
/// Seerr's own web client sends.
const _csrfTokenHeader = 'X-XSRF-TOKEN';

const _writeMethods = {'POST', 'PUT', 'PATCH', 'DELETE'};

/// The Seerr client of [instance]: the one constructor, so every Seerr
/// request carries what the connection needs.
///
/// The API key as `X-Api-Key`, plus [SeerrCsrfInterceptor]; the certificate
/// pinned for the origin ([pinnedCertFingerprint], ADR-6) and the
/// connection's access to a gateway in front ([ServiceInstance.access]).
///
/// `test/features/discover/data/seerr_client_guard_test.dart` holds that no
/// Seerr client is born anywhere else.
ApiClient seerrClientFor(
  ServiceInstance instance, {
  String? pinnedCertFingerprint,
}) {
  assert(instance.service == ServiceKey.seerr, 'not a Seerr connection');
  return ApiClient(
    baseUrl: instance.url,
    apiKey: instance.credential.trim(),
    pinnedCertFingerprint: pinnedCertFingerprint,
    accessHeaders: instance.access.headers(),
    interceptors: (dio) => [SeerrCsrfInterceptor(dio)],
  );
}

/// [seerrClientFor] as a value a test can replace: the Dashboard probe builds
/// its throwaway Seerr client through this.
typedef SeerrClientFactory =
    ApiClient Function(
      ServiceInstance instance, {
      String? pinnedCertFingerprint,
    });

final seerrClientFactoryProvider = Provider<SeerrClientFactory>(
  (ref) => seerrClientFor,
);

/// The Seerr client of the connection [instanceId] names, or of the lens when
/// it names none, rebuilt when its address, key, pinned certificate or access
/// changes, and closed when the provider goes.
///
/// Throws `Exception('Seerr not configured')`, which `AsyncValueWidget`
/// turns into its placeholder, as `watchApiClient` does for the other
/// services.
ApiClient watchSeerrClient(Ref ref, {String? instanceId}) {
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
  );
  ref.onDispose(client.close);
  return client;
}

// === CSRF ==================================================================

/// Answers Seerr's CSRF protection.
///
/// Off by default in Seerr, and then this does nothing: no token ever
/// arrives. On, csurf guards every POST, PUT, PATCH and DELETE ahead of every
/// route, the key's included, and refuses one without the token with
/// `403 invalid csrf token`, which read as the key refused until this
/// answered it:
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
      // it costs nothing to ask.
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

/// What Seerr meant by refusing the request [error] stands for, or null when
/// it was not one of Seerr's own refusals.
///
/// Reads what the transport already decided ([SeerrCsrfRefused]) before the
/// answer itself.
SeerrRefusal? seerrRefusalOf(Object? error) {
  final cause = unwrapFailure(error);
  if (cause is! DioException) return null;
  return switch (cause.error) {
    SeerrCsrfRefused() => SeerrRefusal.csrfToken,
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
