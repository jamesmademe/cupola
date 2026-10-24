import 'dart:io';

/// The [HttpClient] a WebSocket upgrade sees when the upgrade must not follow a
/// redirect.
///
/// `dart:io` follows a redirect on the upgrade GET like on any other request,
/// carrying the WebSocket headers along, and whatever answers `101` at the end
/// of the chain gets the socket and the first frame after it. For TrueNAS that
/// frame is `auth.login_with_api_key`; for Dockge it is `login` with the
/// username and password. A `Location: http://…` would put either on a
/// cleartext socket after the scheme check had passed, and a `Location` on
/// another host would hand that host the credential outright.
///
/// The API transports refuse the same thing through
/// `SameOriginRedirectInterceptor`; this is the guard for the upgrade
/// transports `Dio` does not carry.
///
/// Only [openUrl] is implemented because it is the only member
/// `WebSocket.connect` calls on its `customClient`. The loopback tests in
/// `truenas_ws_client_test.dart` and `dockge_client_test.dart` dial through
/// this wrapper, so an SDK that starts calling another member fails there,
/// loudly, and not in the field.
class NoRedirectUpgradeClient implements HttpClient {
  NoRedirectUpgradeClient(this._inner);

  final HttpClient _inner;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      (await _inner.openUrl(method, url))..followRedirects = false;

  @override
  void close({bool force = false}) => _inner.close(force: force);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
