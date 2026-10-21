import 'package:http/http.dart' as http;

/// A [http.Client] that follows a redirect only where doing so cannot replay a
/// credential to another origin.
///
/// `dart:io` follows redirects by default, and its strip list covers only
/// `authorization`, `www-authenticate` and the cookie headers. A custom header
/// such as `X-Api-Key`, `X-Plex-Token`, `X-Emby-Token`, a Cloudflare service
/// token or a proxy password travels to whatever host the `Location` names.
/// `guardedDio` refuses that on every API transport; the image cache is the one
/// HTTP stack outside it, and it is exactly the stack that carries those
/// headers, so it gets the same rule here.
///
/// The rule is narrow on purpose:
/// * same-origin redirects are followed with their headers, because a path
///   normalisation or a proxy's own redirect is routine;
/// * a cross-origin redirect is followed only when the request carries no
///   credential (a public poster CDN may redirect, and there is nothing to
///   protect);
/// * `https` -> `http` is always refused, even for a public image.
///
/// The status codes are the ones [http.BaseRequest] itself treats as
/// redirects. A response without `Location`, or past [maxRedirects], ends the
/// chain as a refusal rather than looping.
class SameOriginHttpClient extends http.BaseClient {
  SameOriginHttpClient(this._inner, {this.maxRedirects = 5});

  final http.Client _inner;

  /// How many redirects one request may follow before the chain is refused.
  final int maxRedirects;

  /// Headers that say what the client wants or accepts, never who it is.
  ///
  /// A request carrying anything else is treated as credentialed: failing
  /// closed on an unknown header is the point, because the next header added
  /// to an image request must not silently become replayable.
  static const _credentialFreeHeaders = {
    'accept',
    'accept-encoding',
    'accept-language',
    'cache-control',
    'connection',
    'content-length',
    'content-type',
    'host',
    'if-modified-since',
    'if-none-match',
    'pragma',
    'range',
    'user-agent',
  };

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    var current = request;
    var url = request.url;

    for (var followed = 0; ; followed++) {
      // `dart:io` follows a redirect inside `send`; the guard has to see the
      // 3xx itself or it never gets the chance to refuse it.
      current
        ..followRedirects = false
        ..maxRedirects = 0;
      final response = await _inner.send(current);
      final location = _locationOf(response.headers);
      if (!_isRedirect(response.statusCode) || location == null) {
        return response;
      }

      final target = url.resolve(location);
      if (followed >= maxRedirects ||
          !_mayFollow(current, from: url, to: target)) {
        await response.stream.drain<void>();
        throw http.ClientException(
          'Refused a redirect from $url to $target',
          url,
        );
      }

      await response.stream.drain<void>();
      current = _nextRequest(current, target, response.statusCode);
      url = target;
    }
  }

  /// Whether [request] may be sent to [to].
  ///
  /// Cross-origin is allowed only when the scheme is not downgraded and the
  /// request carries no header outside [_credentialFreeHeaders]. The check
  /// runs on the request that produced the redirect, which is the one whose
  /// headers would be copied.
  static bool _mayFollow(
    http.BaseRequest request, {
    required Uri from,
    required Uri to,
  }) {
    if (from.scheme == 'https' && to.scheme != 'https') return false;
    if (_sameOrigin(from, to)) return true;
    return !request.headers.keys.any(
      (name) => !_credentialFreeHeaders.contains(name.toLowerCase()),
    );
  }

  static bool _sameOrigin(Uri a, Uri b) =>
      a.scheme == b.scheme && a.host == b.host && a.port == b.port;

  static bool _isRedirect(int status) =>
      status == 301 ||
      status == 302 ||
      status == 303 ||
      status == 307 ||
      status == 308;

  static String? _locationOf(Map<String, String> headers) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == 'location') return entry.value;
    }
    return null;
  }

  /// The request to send to [target], with the headers the caller set.
  ///
  /// Only [http.Request] is copied: that is what `flutter_cache_manager`'s
  /// `HttpFileService` sends, and a redirect of any other request type is
  /// refused rather than sent without its body.
  static http.BaseRequest _nextRequest(
    http.BaseRequest request,
    Uri target,
    int status,
  ) {
    if (request is! http.Request) {
      throw http.ClientException(
        'Refused to follow a redirect for ${request.runtimeType}',
        request.url,
      );
    }
    final switchToGet =
        status == 303 ||
        ((status == 301 || status == 302) && request.method == 'POST');
    final method = switchToGet ? 'GET' : request.method;
    final next = http.Request(method, target)
      ..followRedirects = false
      ..maxRedirects = 0
      ..persistentConnection = request.persistentConnection
      ..headers.addAll(request.headers);
    if (switchToGet) {
      next.headers.remove('content-length');
      next.headers.remove('content-type');
    } else if (request.bodyBytes.isNotEmpty) {
      next.bodyBytes = request.bodyBytes;
    }
    return next;
  }

  @override
  void close() => _inner.close();
}
