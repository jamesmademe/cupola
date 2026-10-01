import 'dart:async';

import 'package:dio/dio.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/network/redirect_guard.dart';

/// What answered in place of the service when a WebSocket upgrade to
/// [endpoint] was refused, or null when nothing in front of it did.
///
/// TrueNAS and Dockge speak over a WebSocket, and a refused upgrade says only
/// the status it got (a 302, a 401): not where it pointed, nor whose page it
/// was. So one plain HTTP request goes to the same address through
/// [guardedDio], with the same [accessHeaders], and the answer guard and the
/// redirect guard read it the way they read every other service's: Cloudflare
/// Access's login, a sign-in page, a proxy's password prompt. Those two
/// services then name a gateway with the same words as the others.
///
/// [endpoint] is the upgrade's own URL (`wss://`); the request goes to its
/// `https://` twin (`ws://` to `http://`). Asked only after an upgrade was
/// answered with something other than `101`, so a box that is switched off
/// costs nothing more. Its own failure is never the verdict: anything but a
/// gateway leaves the upgrade's failure as it was.
Future<AccessGatewayAnswer?> gatewayAtUpgrade(
  Uri endpoint, {
  String? certFingerprint,
  Map<String, String> accessHeaders = const {},
  Duration timeout = const Duration(seconds: 5),
}) async {
  final secure = endpoint.scheme == 'wss' || endpoint.scheme == 'https';
  final origin = Uri(
    scheme: secure ? 'https' : 'http',
    host: endpoint.host,
    port: endpoint.port,
  );
  final dio = guardedDio(
    baseUrl: origin.toString(),
    certFingerprint: certFingerprint,
    accessHeaders: accessHeaders,
  );
  try {
    await dio
        .get<String>(
          endpoint.path.isEmpty ? '/' : endpoint.path,
          options: Options(responseType: ResponseType.plain),
        )
        .timeout(timeout);
    return null;
  } catch (error) {
    return accessGatewayOf(error);
  } finally {
    dio.close(force: true);
  }
}
