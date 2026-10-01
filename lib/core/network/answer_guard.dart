import 'dart:convert';

import 'package:dio/dio.dart';

import 'package:cupola/core/network/connection_failure.dart';

/// Turns an answer that cannot be the one asked for into a failure, so a 2xx
/// stops meaning "the service answered" whatever came back.
///
/// Installed by `guardedDio` after `SameOriginRedirectInterceptor`, so it sees
/// the final answer of every client built on it.
///
/// ## A JSON request that gets something other than JSON
///
/// A request **asks for JSON** when it sends `Accept: application/json` and
/// leaves Dio's response type on JSON ([asksForJson]). The `Accept` header is
/// the test, not the response type alone, because the response type is JSON
/// on every request by default: the clients whose answers are text by design
/// never set it otherwise, and could not be told apart by it. `ApiClient`
/// sends the header, so the check covers the arrs, Seerr, Bazarr, Jellyfin and
/// Plex. The clients that send no such header read their own envelopes and
/// already name a page that is not one (qBittorrent's text answers,
/// SABnzbd's `output=json`, NZBGet's and Transmission's JSON-RPC, Unraid's
/// GraphQL, Nginx Proxy Manager's `/api/`).
///
/// Such a request fails with [UnexpectedAnswer] when the answer is a 2xx that
/// is a web page (`text/html`), or, for a read, a body that does not decode as
/// JSON. Never for an empty body: a write that answers `200` or `204` with
/// nothing has answered, and so has one that confirms itself in a word. Never
/// for a body that decodes, whatever its label, because a service that labels
/// JSON `text/plain` still sent JSON.
///
/// ## Something in front of the service
///
/// On every request, whatever it asked for, an answer that shows an access
/// gateway fails with [AccessGatewayAnswer] instead: a `200` page with a
/// password field ([signInPageOf]), or a `401`/`403` that Cloudflare Access or
/// a proxy's password prompt sent ([gatewayRefusalOf]). The redirect guard
/// names the gateways that answer with a redirect ([gatewayRedirectOf]).
///
/// [nativeBasicAuth] is for the two services that sign in with
/// `Authorization: Basic` themselves (NZBGet, Transmission): for them a Basic
/// `401` is their own refusal, never a proxy's prompt.
class AnswerGuardInterceptor extends Interceptor {
  AnswerGuardInterceptor({this.nativeBasicAuth = false});

  final bool nativeBasicAuth;

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final Object? failure =
        signInPageOf(response, nativeBasicAuth: nativeBasicAuth) ??
        unexpectedAnswerOf(response);
    if (failure == null) {
      handler.next(response);
      return;
    }
    handler.reject(
      DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        error: failure,
        message: failure is AccessGatewayAnswer
            ? 'Something in front of the service answered.'
            : 'The answer was not the JSON that was asked for.',
      ),
      true,
    );
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final response = err.response;
    // A status Dio refused, and nothing has a verdict on it yet.
    if (err.type == DioExceptionType.badResponse &&
        err.error == null &&
        response != null) {
      final gateway = gatewayRefusalOf(
        response,
        nativeBasicAuth: nativeBasicAuth,
      );
      if (gateway != null) {
        handler.next(
          DioException(
            requestOptions: err.requestOptions,
            response: response,
            type: DioExceptionType.badResponse,
            error: gateway,
            stackTrace: err.stackTrace,
            message: 'Something in front of the service answered.',
          ),
        );
        return;
      }
    }
    // Dio decodes a body labelled JSON before any interceptor sees it, and a
    // body that does not parse arrives here as a bare `FormatException` with
    // no response at all.
    if (err.error is FormatException && asksForJson(err.requestOptions)) {
      handler.next(
        DioException(
          requestOptions: err.requestOptions,
          response: err.response,
          type: err.type,
          error: UnexpectedAnswer(
            status: err.response?.statusCode,
            host: answeringHost(err.requestOptions.uri),
            baseUrl: err.requestOptions.baseUrl,
          ),
          stackTrace: err.stackTrace,
          message: 'The answer was not the JSON that was asked for.',
        ),
      );
      return;
    }
    handler.next(err);
  }
}

/// The [UnexpectedAnswer] [response] is, or null when it is an answer the
/// request can read. See [AnswerGuardInterceptor].
UnexpectedAnswer? unexpectedAnswerOf(Response response) {
  final status = response.statusCode ?? 0;
  if (status < 200 || status >= 300) return null;
  final request = response.requestOptions;
  if (!asksForJson(request)) return null;
  final data = response.data;
  if (data is! String || data.trim().isEmpty) return null;
  final contentType = response.headers[Headers.contentTypeHeader]?.firstOrNull;
  if (!_isWebPage(contentType)) {
    // A write may confirm itself in a word (`OK`), which is an answer; a read
    // that asked for JSON and got text has nothing it can read.
    if (!_isRead(request.method) || _decodes(data)) return null;
  }
  return UnexpectedAnswer(
    status: status,
    headers: response.headers.map,
    body: data,
    host: answeringHost(request.uri),
    baseUrl: request.baseUrl,
  );
}

/// Whether [options] asks for JSON: an `Accept` that names it, on Dio's JSON
/// response type. See [AnswerGuardInterceptor].
bool asksForJson(RequestOptions options) {
  if (options.responseType != ResponseType.json) return false;
  for (final MapEntry(:key, :value) in options.headers.entries) {
    if (key.toLowerCase() != 'accept') continue;
    final accept = '$value'.toLowerCase();
    return accept.contains('application/json') || accept.contains('+json');
  }
  return false;
}

/// The address that answered, as the UI prints one: the host, and the port
/// only when the address names one (`nas.home.arpa:7878`).
String answeringHost(Uri uri) =>
    uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;

bool _isRead(String method) {
  final verb = method.toUpperCase();
  return verb == 'GET' || verb == 'HEAD';
}

bool _isWebPage(String? contentType) {
  final type = contentType?.toLowerCase() ?? '';
  return type.contains('text/html') || type.contains('xhtml');
}

bool _decodes(String body) {
  try {
    jsonDecode(body);
    return true;
  } on FormatException {
    return false;
  }
}

/// The request extra under which a connection's access layer names the
/// headers it added for a gateway, so a gateway's answer can say whether it
/// was sent anything beyond the two headers it is known by
/// (`CF-Access-Client-Id`, `Authorization: Basic`).
const kAccessHeaderNamesExtra = 'cupola.accessHeaderNames';

/// A sign-in page answering where the service should: a `200` web page with a
/// password field. Null for anything else.
AccessGatewayAnswer? signInPageOf(
  Response response, {
  bool nativeBasicAuth = false,
}) {
  final status = response.statusCode ?? 0;
  if (status < 200 || status >= 300) return null;
  final data = response.data;
  if (data is! String || !_passwordField.hasMatch(data)) return null;
  final contentType = response.headers[Headers.contentTypeHeader]?.firstOrNull;
  if (!_isWebPage(contentType) && !_looksLikePage(data)) return null;
  final request = response.requestOptions;
  return AccessGatewayAnswer(
    kind: AccessGatewayKind.signInPage,
    credentialsSent: accessCredentialsSent(
      request,
      AccessGatewayKind.signInPage,
      nativeBasicAuth: nativeBasicAuth,
    ),
    gatewayHost: request.uri.host,
    serviceHost: answeringHost(request.uri),
  );
}

/// A `401` or `403` that something in front of the service sent, or null for
/// one the service sent itself:
///
///  * Cloudflare Access: a `WWW-Authenticate` naming `cloudflareaccess.com`,
///    or Cloudflare's own page (`Server: cloudflare` with a `CF-Ray`, and a
///    web page rather than the service's answer);
///  * a proxy's password prompt: a `401` with `WWW-Authenticate: Basic` in
///    front of a service that does not sign in that way itself
///    ([nativeBasicAuth]), whose realm does not name the service.
AccessGatewayAnswer? gatewayRefusalOf(
  Response response, {
  bool nativeBasicAuth = false,
}) {
  final status = response.statusCode;
  if (status != 401 && status != 403) return null;
  final request = response.requestOptions;
  final challenges = <String>[
    for (final value
        in response.headers['www-authenticate'] ?? const <String>[])
      value.toLowerCase(),
  ];
  final named = challenges.any((c) => c.contains('cloudflareaccess.com'));
  final server = response.headers['server']?.firstOrNull?.toLowerCase() ?? '';
  final viaCloudflare =
      server.contains('cloudflare') && response.headers['cf-ray'] != null;
  final data = response.data;
  final contentType = response.headers[Headers.contentTypeHeader]?.firstOrNull;
  final page =
      _isWebPage(contentType) || (data is String && _looksLikePage(data));
  if (named || (viaCloudflare && page)) {
    return AccessGatewayAnswer(
      kind: AccessGatewayKind.cloudflareAccess,
      credentialsSent: accessCredentialsSent(
        request,
        AccessGatewayKind.cloudflareAccess,
        nativeBasicAuth: nativeBasicAuth,
      ),
      gatewayHost:
          challenges.map(_cloudflareAccessHost).nonNulls.firstOrNull ??
          request.uri.host,
      serviceHost: answeringHost(request.uri),
    );
  }
  if (status == 401 && !nativeBasicAuth) {
    final basic = challenges.where((c) => c.trimLeft().startsWith('basic'));
    if (basic.isNotEmpty && !basic.any(_namesAnAppOwnSignIn)) {
      return AccessGatewayAnswer(
        kind: AccessGatewayKind.passwordPrompt,
        credentialsSent: accessCredentialsSent(
          request,
          AccessGatewayKind.passwordPrompt,
          nativeBasicAuth: nativeBasicAuth,
        ),
        gatewayHost: request.uri.host,
        serviceHost: answeringHost(request.uri),
      );
    }
  }
  return null;
}

/// A redirect to [target] that an access gateway sent, or null:
///
///  * Cloudflare Access: a host under `cloudflareaccess.com`, or a path under
///    `/cdn-cgi/access/` on any host, the service's own included;
///  * a sign-in page: another host whose path reads as a sign-in (`login`,
///    `auth`, `sso`, …), or a host that is one (`auth.`, Authelia,
///    Authentik).
AccessGatewayAnswer? gatewayRedirectOf(
  RequestOptions request,
  Uri target, {
  bool nativeBasicAuth = false,
}) {
  final host = target.host.toLowerCase();
  final path = target.path.toLowerCase();
  AccessGatewayAnswer answer(AccessGatewayKind kind) => AccessGatewayAnswer(
    kind: kind,
    credentialsSent: accessCredentialsSent(
      request,
      kind,
      nativeBasicAuth: nativeBasicAuth,
    ),
    gatewayHost: target.host,
    serviceHost: answeringHost(request.uri),
  );
  if (host == 'cloudflareaccess.com' ||
      host.endsWith('.cloudflareaccess.com') ||
      path.contains('/cdn-cgi/access/')) {
    return answer(AccessGatewayKind.cloudflareAccess);
  }
  final origin = request.uri;
  final crossOrigin =
      target.scheme != origin.scheme ||
      target.host != origin.host ||
      target.port != origin.port;
  if (!crossOrigin) return null;
  final signInPath = _signInPathWords.any(path.contains);
  final signInHost =
      _signInHostPrefixes.any(host.startsWith) ||
      _signInHostWords.any(host.contains);
  return signInPath || signInHost ? answer(AccessGatewayKind.signInPage) : null;
}

/// Whether [request] carried the credential a [kind] gateway asks for: read
/// from the request's own headers, so it starts saying yes the day a
/// connection sends them.
bool accessCredentialsSent(
  RequestOptions request,
  AccessGatewayKind kind, {
  bool nativeBasicAuth = false,
}) {
  String? header(String name) {
    for (final MapEntry(:key, :value) in request.headers.entries) {
      if (key.toLowerCase() == name) return '$value';
    }
    return null;
  }

  final cloudflareToken = header('cf-access-client-id')?.trim() ?? '';
  final authorization = header('authorization')?.trimLeft().toLowerCase();
  final proxyPassword =
      !nativeBasicAuth && (authorization?.startsWith('basic ') ?? false);
  final named = request.extra[kAccessHeaderNamesExtra];
  final namedSent =
      named is Iterable &&
      named.any((name) => header('$name'.toLowerCase()) != null);
  return switch (kind) {
    AccessGatewayKind.cloudflareAccess => cloudflareToken.isNotEmpty,
    AccessGatewayKind.passwordPrompt => proxyPassword,
    AccessGatewayKind.signInPage =>
      cloudflareToken.isNotEmpty || proxyPassword || namedSent,
  };
}

/// A password field, however the page quotes its type.
final _passwordField = RegExp(
  '<input[^>]*type\\s*=\\s*["\']?password',
  caseSensitive: false,
);

const _signInPathWords = [
  'login',
  'signin',
  'sign-in',
  'sign_in',
  'auth',
  'sso',
  'saml',
  'openid',
];
const _signInHostPrefixes = ['auth.', 'login.', 'sso.', 'id.'];
const _signInHostWords = ['authelia', 'authentik', 'keycloak'];

/// The services of the stack that can sign in with Basic themselves, for
/// their own web interface. A Basic realm that names one is that service's
/// own prompt, never a proxy's.
const _appsWithOwnBasicSignIn = [
  'radarr',
  'sonarr',
  'lidarr',
  'readarr',
  'prowlarr',
  'bazarr',
];

bool _namesAnAppOwnSignIn(String challenge) =>
    _appsWithOwnBasicSignIn.any(challenge.contains);

/// The `*.cloudflareaccess.com` host a challenge points at, if it names one.
String? _cloudflareAccessHost(String challenge) => RegExp(
  r'([a-z0-9-]+\.cloudflareaccess\.com)',
).firstMatch(challenge)?.group(1);

bool _looksLikePage(String body) {
  final start = body.trimLeft().toLowerCase();
  return start.startsWith('<!doctype html') || start.startsWith('<html');
}
