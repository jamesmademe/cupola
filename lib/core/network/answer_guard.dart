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
class AnswerGuardInterceptor extends Interceptor {
  AnswerGuardInterceptor();

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final unexpected = unexpectedAnswerOf(response);
    if (unexpected == null) {
      handler.next(response);
      return;
    }
    handler.reject(
      DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        error: unexpected,
        message: 'The answer was not the JSON that was asked for.',
      ),
      true,
    );
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
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
