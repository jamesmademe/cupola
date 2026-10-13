import 'package:dio/dio.dart';

import 'package:cupola/core/network/answer_guard.dart';
import 'package:cupola/core/network/cert_trust.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/network/unreached_origins.dart';

/// A service's own interceptors, built over the [Dio] they are installed on:
/// see `guardedDio`.
typedef DioInterceptors = List<Interceptor> Function(Dio dio);

/// Status codes that carry a `Location` header we are expected to follow.
const _redirectStatuses = {301, 302, 303, 307, 308};

/// Shared by every client [guardedDio] builds, so a black-holed host fails in
/// seconds instead of hanging on the socket defaults.
const _connectTimeout = Duration(seconds: 10);
const _receiveTimeout = Duration(seconds: 15);

/// Headers that describe a request body. A redirect that downgrades to GET
/// leaves the body behind, so these stop describing anything.
const _entityHeaders = {Headers.contentLengthHeader, Headers.contentTypeHeader};

/// Accepts exactly the 3xx codes [SameOriginRedirectInterceptor] knows how to
/// follow, so Dio hands them to the interceptor instead of rejecting them
/// before the chain runs.
///
/// Deliberately *not* "any status below 400": the other 3xx codes (300 Multiple
/// Choices, 304 Not Modified, 305, 306) are not followed by anything here, so
/// accepting them would deliver an empty or HTML body to a caller that goes on
/// to read `response.data['results']` and either throws a type error or
/// silently yields nothing. Rejecting them makes them ordinary Dio failures
/// that [classifyConnectionFailure] can report.
bool allowRedirectStatus(int? status) =>
    status != null && (status < 300 || _redirectStatuses.contains(status));

/// A redirect [SameOriginRedirectInterceptor] refused to follow.
///
/// Carries both the verdict and the sentence explaining it, because the enum
/// alone cannot say *which* host a reverse proxy bounced the request to, and
/// that sentence is the only thing that tells the user their proxy, not their
/// address, is the problem.
///
/// [reason] is [ServiceFailureReason.redirected], which is its own cause rather
/// than a borrowed one. It was `notFound` for a while: close, since both mean
/// "the server answered but the API is not here", but the fixes differ: a
/// missing base path is corrected in the address field, whereas a refused
/// redirect is corrected on the proxy sitting in front of the service, and the
/// address the user typed may be perfectly right. Either way it tells
/// `certProbeWorthwhile` the handshake already succeeded, so no TLS probe is
/// worth running.
///
/// All three refusals (cross-origin target, missing `Location`), redirect loop
/// share the reason and differ only in [failureDetail], which is the sentence
/// the UI actually shows.
class RedirectRefused implements Exception, HasFailureReason, HasFailureDetail {
  const RedirectRefused(this.message);

  final String message;

  @override
  String get failureDetail => message;

  @override
  ServiceFailureReason get reason => ServiceFailureReason.redirected;

  @override
  String toString() => message;
}

/// Follows redirects by hand so a credential header is never replayed to a host
/// the user did not configure.
///
/// `dart:io` strips only `authorization`, `www-authenticate`, `cookie` and
/// `cookie2` when a redirect crosses origins; custom headers such as
/// `X-Api-Key` are copied to *any* target. A compromised instance, a
/// misconfigured reverse proxy, or an on-path attacker on a cleartext base URL
/// could therefore harvest the key with a single 302.
///
/// Same-origin redirects (trailing slashes, base-path normalisation) are the
/// legitimate case and keep working; cross-origin ones fail with an explanatory
/// error rather than leaking the credential.
///
/// A redirect an access gateway sent (Cloudflare Access's login, a sign-in
/// page on another host) is refused the same way and named for what it is,
/// [AccessGatewayAnswer], rather than as a redirect: Cloudflare Access is
/// named even when it redirects to a path on the service's own host, because
/// following it only reaches its login page.
///
/// Requires the owning [Dio] to be configured with `followRedirects: false` and
/// [allowRedirectStatus] as its `validateStatus`.
class SameOriginRedirectInterceptor extends Interceptor {
  SameOriginRedirectInterceptor(
    this._dio, {
    this.maxRedirects = 5,
    this.nativeBasicAuth = false,
  });

  final Dio _dio;
  final int maxRedirects;

  /// See [AnswerGuardInterceptor.nativeBasicAuth].
  final bool nativeBasicAuth;

  /// Redirect depth so far, threaded through `RequestOptions.extra`.
  static const _depthKey = 'cupola.redirectDepth';

  @override
  Future<void> onResponse(
    Response response,
    ResponseInterceptorHandler handler,
  ) async {
    final status = response.statusCode;
    if (status == null || !_redirectStatuses.contains(status)) {
      handler.next(response);
      return;
    }

    final request = response.requestOptions;
    final location = response.headers.value('location');
    if (location == null || location.isEmpty) {
      handler.reject(
        DioException(
          requestOptions: request,
          response: response,
          type: DioExceptionType.badResponse,
          error: RedirectRefused(
            'The server answered $status without a Location header. '
            'Check the service URL.',
          ),
        ),
      );
      return;
    }

    final target = request.uri.resolve(location);
    final gateway = gatewayRedirectOf(
      request,
      target,
      nativeBasicAuth: nativeBasicAuth,
    );
    if (gateway != null) {
      handler.reject(
        DioException(
          requestOptions: request,
          response: response,
          type: DioExceptionType.badResponse,
          error: gateway,
          message: 'Something in front of the service answered.',
        ),
      );
      return;
    }
    if (!_isSameOrigin(request.uri, target)) {
      handler.reject(
        DioException(
          requestOptions: request,
          response: response,
          type: DioExceptionType.badResponse,
          error: RedirectRefused(
            'The server redirected to ${target.origin}, a different host '
            'than the one configured. The request was not resent so the '
            'API key is not exposed. Point Cupola directly at the '
            'service, or fix the redirect on the server.',
          ),
        ),
      );
      return;
    }

    final depth = (request.extra[_depthKey] as int?) ?? 0;
    if (depth >= maxRedirects) {
      handler.reject(
        DioException(
          requestOptions: request,
          response: response,
          type: DioExceptionType.badResponse,
          error: RedirectRefused(
            'The server redirected more than $maxRedirects times.',
          ),
        ),
      );
      return;
    }

    // 303, and 301/302 in practice, downgrade the method to GET and drop the body.
    final becomesGet =
        status == 303 ||
        ((status == 301 || status == 302) &&
            request.method.toUpperCase() != 'HEAD');

    // Dio stamps `content-length` onto the *original* `RequestOptions` while
    // encoding the body, so replaying `request.headers` verbatim after dropping
    // that body sends a GET whose headers still promise N bytes. `dart:io` then
    // throws `HttpException: Content size below specified contentLength` at
    // `request.close()`: the legitimate same-origin redirect this interceptor
    // exists to follow would fail with an opaque transport error (a Radarr
    // `POST /api/v3/command` behind a proxy that normalises a trailing slash).
    // 307/308 keep the body, so they keep the headers that describe it.
    final headers = Map<String, dynamic>.from(request.headers);
    if (becomesGet) {
      headers.removeWhere(
        (key, _) => _entityHeaders.contains(key.toLowerCase()),
      );
    }

    try {
      final followed = await _dio.request(
        target.toString(),
        data: becomesGet ? null : request.data,
        queryParameters: const {}, // already baked into `target`
        cancelToken: request.cancelToken,
        onReceiveProgress: request.onReceiveProgress,
        onSendProgress: request.onSendProgress,
        options: Options(
          method: becomesGet ? 'GET' : request.method,
          headers: headers,
          responseType: request.responseType,
          contentType: becomesGet ? null : request.contentType,
          sendTimeout: request.sendTimeout,
          receiveTimeout: request.receiveTimeout,
          followRedirects: false,
          validateStatus: request.validateStatus,
          extra: {...request.extra, _depthKey: depth + 1},
        ),
      );
      handler.resolve(followed);
    } on DioException catch (e) {
      handler.reject(e);
    }
  }

  static bool _isSameOrigin(Uri a, Uri b) =>
      a.scheme == b.scheme && a.host == b.host && a.port == b.port;
}

/// The [Dio] every client in this app is built on: redirects followed by hand,
/// plus the ADR-6 pinned adapter when the user has trusted a certificate for
/// [baseUrl]'s origin.
///
/// The three redirect settings are one decision rather than three.
/// `followRedirects: false` is what hands a 3xx to
/// [SameOriginRedirectInterceptor] instead of letting `dart:io` replay the
/// request, and its credential, at a host the user never configured; the
/// interceptor is what actually refuses the cross-origin case; and
/// [allowRedirectStatus] is what stops Dio rejecting those statuses as failures
/// before the interceptor ever runs. Set any two without the third and the
/// result is either a leaked credential or a legitimate same-origin redirect
/// (trailing slash, base-path normalisation) turned into an error. Minting them
/// together here is what keeps seven call sites from drifting apart; the reason
/// *each* service cannot afford the leak is documented at its own call site.
///
/// After the redirect guard comes [AnswerGuardInterceptor], so the final answer
/// to a request that asked for JSON is JSON, or a classified failure: a web
/// page answering with a 200 is not the service answering.
///
/// [nativeBasicAuth] is for the two services that sign in with
/// `Authorization: Basic` themselves (NZBGet, Transmission), so their own
/// refusal is never read as a proxy's password prompt.
///
/// [injected] is returned untouched. A caller supplying its own transport: a
/// test stub, in practice, owns redirect handling and TLS along with it, and
/// installing a pinned adapter over it would replace the very thing it was
/// injected to replace.
///
/// [certFingerprint], when non-empty, is a self-signed certificate the user
/// explicitly trusted for this origin (trust-on-first-use, ADR-6). Null or empty
/// leaves the connection on the platform trust store, which is what keeps every
/// unpinned service byte-identical to its pre-ADR-6 behaviour. A followed
/// same-origin redirect goes back out over this same Dio, so it inherits the pin
/// with no extra wiring.
///
/// [accessHeaders] is what the connection presents to a gateway in front of
/// the service (a Cloudflare Access service token, a proxy's password, custom
/// headers), sent on **every** request this Dio makes: they sit in the base
/// options, so a client that sets its own headers per request keeps them too.
/// The service's own headers win a clash ([headers], and whatever a request
/// sets), so an access header can never take the service's credential away.
/// Their names travel as the request extra [kAccessHeaderNamesExtra], which is
/// how a gateway's answer tells whether it was sent anything. A redirect is
/// followed only on the same origin, so they never leave the configured host.
/// This is the sixth obligation of a client, beside ADR-6's five: every
/// construction passes the connection's access
/// (`test/core/network/access_headers_guard_test.dart`).
///
/// A request that opens no connection, or none in time, is told to
/// [UnreachedOrigins] ([reportUnreached]), so the route probe can move a
/// connection to its other address; the route probe's own knocks say false.
///
/// [interceptors] are a service's own, built over this Dio (so one can send a
/// request again through it) and installed **ahead** of the two guards: they
/// see every answer first, a redirect's and a refusal's included, and a
/// request they send again passes both guards like any other. Seerr's session
/// and CSRF interceptors are the ones (`seerr_session.dart`).
Dio guardedDio({
  required String baseUrl,
  Dio? injected,
  String? certFingerprint,
  Duration? sendTimeout,
  Map<String, dynamic>? headers,
  Map<String, String> accessHeaders = const {},
  bool nativeBasicAuth = false,
  DioInterceptors? interceptors,
  bool reportUnreached = true,
}) {
  if (injected != null) return injected;

  final serviceNames = {
    for (final name in headers?.keys ?? const <String>[]) name.toLowerCase(),
  };
  final access = {
    for (final MapEntry(:key, :value) in accessHeaders.entries)
      if (!serviceNames.contains(key.toLowerCase())) key: value,
  };
  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: _connectTimeout,
      receiveTimeout: _receiveTimeout,
      sendTimeout: sendTimeout,
      followRedirects: false,
      validateStatus: allowRedirectStatus,
      headers: {...access, ...?headers},
      extra: access.isEmpty
          ? null
          : {kAccessHeaderNamesExtra: access.keys.toList(growable: false)},
    ),
  );
  dio.interceptors
    ..addAll(interceptors?.call(dio) ?? const [])
    ..add(SameOriginRedirectInterceptor(dio, nativeBasicAuth: nativeBasicAuth))
    ..add(AnswerGuardInterceptor(nativeBasicAuth: nativeBasicAuth));
  if (reportUnreached) dio.interceptors.add(const UnreachedReporter());
  final adapter = pinnedHttpClientAdapterFor(
    baseUrl,
    pinnedFingerprint: certFingerprint,
  );
  if (adapter != null) dio.httpClientAdapter = adapter;
  return dio;
}

/// Tells [UnreachedOrigins] of a request that opened no connection, or none
/// in time, and passes the failure on unchanged.
///
/// Off for the route probe's own knocks ([guardedDio]'s `reportUnreached`):
/// an address that does not answer a knock is the probe's answer already,
/// and reporting it would ask the probe again.
class UnreachedReporter extends Interceptor {
  const UnreachedReporter();

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.connectionError) {
      UnreachedOrigins.report(err.requestOptions.uri);
    }
    handler.next(err);
  }
}
