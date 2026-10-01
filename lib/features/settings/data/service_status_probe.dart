import 'dart:async';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/features/settings/domain/probe_identity.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Reads [service]'s status route ([ServiceKey.statusEndpoint]) over
/// [client] and checks who answered, returning the version it named.
///
/// The one reading the Dashboard's probe and the connection test share, so
/// the Dashboard and Settings say the same thing about the same address: a
/// Sonarr answering on Radarr's port is [WrongServiceAnswer] in both, and so
/// is a web page answering for Radarr ([probeFailureOf]). [url] is the
/// configured address the words name.
///
/// Throws whatever the read threw otherwise, classified as before.
Future<String?> readServiceStatus(
  ApiClient client,
  ServiceKey service, {
  required String url,
  Duration timeout = const Duration(seconds: 5),
}) async {
  final Object? data;
  try {
    data = (await client.get(service.statusEndpoint).timeout(timeout)).data;
  } catch (error, stack) {
    Error.throwWithStackTrace(probeFailureOf(service, error, url: url), stack);
  }
  requireProbeIdentity(service, data, url: url);
  return statusVersionOf(service, data);
}

/// The version a status route names: Bazarr nests it under `data`, the rest
/// say `version` (or `appVersion`), and a body without one names none.
String? statusVersionOf(ServiceKey service, Object? data) {
  if (data is! Map) return null;
  if (service == ServiceKey.bazarr) {
    return stringOrNull(mapOrNull(data['data'])?['bazarr_version']);
  }
  return (data['version'] ?? data['appVersion'])?.toString();
}
