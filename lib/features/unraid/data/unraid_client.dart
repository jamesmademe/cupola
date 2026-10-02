import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:cupola/core/capability/permission_refusal.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/network/redirect_guard.dart';
import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/features/unraid/domain/models/unraid_models.dart';

/// Error thrown by [UnraidClient]. Carries the [reason] so a caller verifying
/// the connection can tell an unreachable host from a rejected API key.
class UnraidException
    implements
        Exception,
        HasFailureReason,
        HasPermissionRefusal,
        HasFailureCause {
  const UnraidException(
    this.message, {
    this.reason = ServiceFailureReason.unknown,
    this.forbidden = false,
    this.cause,
  });

  /// The failure this wraps, when it wraps one: what it knew (which gateway
  /// answered, for one) survives the wrapping.
  final Object? cause;

  @override
  Object? get failureCause => cause;

  final String message;
  @override
  final ServiceFailureReason reason;

  /// Unraid answered `FORBIDDEN`: the key is valid and may not do this.
  ///
  /// Its own flag because the message is "Forbidden resource", which the
  /// generic message heuristic folds into *unauthorized* — and a key that
  /// works but may not write is not a key that does not work.
  final bool forbidden;

  @override
  bool get isPermissionRefusal => forbidden;

  @override
  String toString() => 'UnraidException: $message';
}

/// The exception one GraphQL error entry stands for.
///
/// Unraid answers **200** with a GraphQL error for both a bad key and a
/// refused permission, so the status says nothing. The error's
/// `extensions.code` does: `FORBIDDEN` (Nest's `ForbiddenException`, message
/// "Forbidden resource") is a valid key that may not do this, and
/// `UNAUTHENTICATED` is a key that does not work. Anything else — an older
/// server with no code — falls back to reading the message.
@visibleForTesting
UnraidException unraidGraphQlError(Object? error) {
  final message = error is Map
      ? (error['message'] ?? error).toString()
      : error.toString();
  final extensions = error is Map ? error['extensions'] : null;
  final code = extensions is Map
      ? extensions['code']?.toString().toUpperCase()
      : null;
  return switch (code) {
    'FORBIDDEN' => UnraidException(message, forbidden: true),
    'UNAUTHENTICATED' => UnraidException(
      message,
      reason: ServiceFailureReason.unauthorized,
    ),
    _ => UnraidException(
      message,
      reason: looksUnauthorizedMessage(message)
          ? ServiceFailureReason.unauthorized
          : ServiceFailureReason.unknown,
    ),
  };
}

/// Client for the Unraid GraphQL API.
///
/// Authenticates with the `x-api-key` header (security §10.2 #10). Every
/// dynamic *value* is passed through the GraphQL `variables` map — never
/// string-interpolated into the query (§10.2 #11).
///
/// The one document that is not a compile-time constant is [runVmAction]'s,
/// because the thing that varies there is a **field name** and GraphQL has no
/// variable for that. It is built from `UnraidVmAction.graphQl`, a closed enum
/// whose six values are spelled in this file, so nothing a server or a user
/// says can reach the document. That is the whole of the exception; a field
/// name that came from outside the enum would be an injection.
///
/// The Unraid API must be enabled server-side (Settings → Management Access →
/// Developer Options → GraphQL Sandbox) and an API key created before this can
/// connect. Field names below follow the documented schema but may differ by
/// Unraid release; confirm against the instance's SDL.
class UnraidClient {
  /// [certFingerprint], when non-empty, is a self-signed certificate the user
  /// explicitly trusted for this origin (trust-on-first-use, ADR-6). Ignored
  /// when [dio] is injected — a caller supplying its own transport owns its
  /// TLS behaviour too.
  UnraidClient({
    required String url,
    required String apiKey,
    Dio? dio,
    String? certFingerprint,
    Map<String, String> accessHeaders = const {},
  }) : baseUrl = UrlUtils.normalizeBaseUrl(url),
       _apiKey = apiKey.trim() {
    // Redirects are followed manually so `x-api-key` is never replayed to an
    // unconfigured host (a 303 would also downgrade this POST to GET).
    _dio = guardedDio(
      baseUrl: baseUrl,
      injected: dio,
      certFingerprint: certFingerprint,
      accessHeaders: accessHeaders,
    );
  }

  final String baseUrl;
  final String _apiKey;
  late final Dio _dio;

  /// Decodes a GraphQL response body, or throws an [UnraidException] the caller
  /// can classify.
  ///
  /// A 200 carrying HTML — the URL points at some other web app, or at a reverse
  /// proxy's landing page — used to throw a raw `TypeError`/`FormatException`
  /// that was neither an `UnraidException` nor classifiable, so the UI fell back
  /// to a generic failure. `notFound` says the useful thing: the API is not here.
  static Map<String, dynamic> _decodeGraphQl(dynamic raw) {
    const notGraphQl =
        'The Unraid GraphQL API did not answer at this address. '
        'Check the URL and that the API is enabled.';
    try {
      final decoded = raw is String ? jsonDecode(raw) : raw;
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } on FormatException {
      throw const UnraidException(
        notGraphQl,
        reason: ServiceFailureReason.notFound,
      );
    }
    throw const UnraidException(
      notGraphQl,
      reason: ServiceFailureReason.notFound,
    );
  }

  Future<Map<String, dynamic>> _query(
    String document, {
    Map<String, dynamic>? variables,
  }) async {
    try {
      final response = await _dio.post(
        '/graphql',
        data: {'query': document, 'variables': ?variables},
        options: Options(
          headers: {'x-api-key': _apiKey, 'Content-Type': 'application/json'},
        ),
      );
      final map = _decodeGraphQl(response.data);
      final errors = map['errors'];
      if (errors is List && errors.isNotEmpty) {
        throw unraidGraphQlError(errors.first);
      }
      return (map['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    } on DioException catch (e) {
      throw UnraidException(
        e.message ?? 'Unraid request failed',
        reason: classifyConnectionFailure(e),
        cause: e,
      );
    }
  }

  static const _infoQuery = 'query { info { os { distro release uptime } } }';
  // Parity and cache slots are their own lists in Unraid's schema, beside
  // `disks`, which holds the data drives only. Asked for disks alone, a
  // disabled parity drive, the fault Unraid users fear most, was invisible.
  static const _arrayQuery =
      'query { array { state capacity { kilobytes { free used total } } '
      'parities { name status temp } disks { name status temp } '
      'caches { name status temp } } }';
  static const _dockerQuery =
      'query { dockerContainers { id names state status autoStart } }';
  static const _capabilitiesQuery =
      'query { me { roles permissions { resource actions } } }';
  static const _vmsQuery = 'query { vms { domains { id name state } } }';
  static const _notificationsQuery =
      r'query Notifications($filter: NotificationFilter!) { '
      r'notifications { overview { unread { info warning alert total } '
      r'archive { info warning alert total } } list(filter: $filter) { '
      'id title subject description importance link type timestamp '
      'formattedTimestamp } } }';
  // Only the fields the committed SDL declares AND `UnraidShare` reads. A
  // GraphQL server does not null out an unknown field, it rejects the whole
  // document: one speculative field here takes the Shares tab down entirely,
  // which is how `allocator`, `splitLevel`, `floor`, `cow` and `color` — none
  // of them in the SDL, none of them parsed — got removed again.
  static const _sharesQuery =
      'query { shares { id name used size cache comment luksStatus } }';

  /// The document [runVmAction] sends for [action].
  ///
  /// Public because the field name is the thing that varies and GraphQL has no
  /// variable for a field name, so the contract test has to be able to ask for
  /// every spelling this client can emit rather than trusting that six enum
  /// values match six mutations.
  @visibleForTesting
  static String vmActionDocument(UnraidVmAction action) =>
      r'mutation VmAction($id: PrefixedID!) { vm { '
      '${action.graphQl}(id: \$id) } }';

  static const _archiveNotificationMutation =
      r'mutation ArchiveNotification($id: PrefixedID!) { '
      r'archiveNotification(id: $id) { id title subject description '
      'importance link type timestamp formattedTimestamp } }';

  /// Every document this client can send, keyed by the call that sends it.
  ///
  /// The contract test walks these and asserts each selected field against the
  /// committed SDL. A hand-maintained list of needles cannot do that — it only
  /// proves the fields somebody remembered to list are still there, which is
  /// how a `shares` selection of five fields nobody had written down shipped
  /// past a green test and would have taken the whole tab down on the first
  /// real instance.
  @visibleForTesting
  static Map<String, String> get graphQlDocuments => {
    'getInfo': _infoQuery,
    'getArray': _arrayQuery,
    'getDockerContainers': _dockerQuery,
    'getCapabilities': _capabilitiesQuery,
    'getVms': _vmsQuery,
    'getNotifications': _notificationsQuery,
    'getShares': _sharesQuery,
    'archiveNotification': _archiveNotificationMutation,
    for (final action in UnraidVmAction.values)
      'runVmAction(${action.name})': vmActionDocument(action),
  };

  Future<UnraidInfo> getInfo() async {
    final data = await _query(_infoQuery);
    return UnraidInfo.fromJson(
      (data['info'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }

  Future<UnraidArray> getArray() async {
    final data = await _query(_arrayQuery);
    return UnraidArray.fromJson(
      (data['array'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }

  Future<List<UnraidDockerContainer>> getDockerContainers() async {
    final data = await _query(_dockerQuery);
    final list = (data['dockerContainers'] as List?) ?? const [];
    return list
        .whereType<Map>()
        .map((e) => UnraidDockerContainer.fromJson(e.cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<UnraidCapabilities> getCapabilities() async {
    final data = await _query(_capabilitiesQuery);
    return UnraidCapabilities.fromJson(
      (data['me'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }

  Future<List<UnraidVm>> getVms() async {
    final data = await _query(_vmsQuery);
    final vms = (data['vms'] as Map?)?.cast<String, dynamic>();
    final list = (vms?['domains'] as List?) ?? const [];
    return list
        .whereType<Map>()
        .map((e) => UnraidVm.fromJson(e.cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<UnraidNotifications> getNotifications({
    UnraidNotificationType type = UnraidNotificationType.unread,
    int offset = 0,
    int limit = 100,
  }) async {
    final data = await _query(
      _notificationsQuery,
      variables: {
        'filter': {'type': type.graphQl, 'offset': offset, 'limit': limit},
      },
    );
    return UnraidNotifications.fromJson(
      (data['notifications'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }

  Future<List<UnraidShare>> getShares() async {
    final data = await _query(_sharesQuery);
    final list = (data['shares'] as List?) ?? const [];
    return list
        .whereType<Map>()
        .map((e) => UnraidShare.fromJson(e.cast<String, dynamic>()))
        .toList(growable: false);
  }

  /// Runs [action] on one VM. **False means the daemon ran the mutation and
  /// refused it** — already stopping, libvirt busy, a privilege the coarse
  /// capability check cannot see. Callers must report that; it never throws.
  Future<bool> runVmAction(String id, UnraidVmAction action) async {
    final data = await _query(vmActionDocument(action), variables: {'id': id});
    final vm = (data['vm'] as Map?)?.cast<String, dynamic>();
    return vm?[action.graphQl] == true;
  }

  Future<UnraidNotification> archiveNotification(String id) async {
    final data = await _query(
      _archiveNotificationMutation,
      variables: {'id': id},
    );
    return UnraidNotification.fromJson(
      (data['archiveNotification'] as Map?)?.cast<String, dynamic>() ??
          const {},
    );
  }

  /// Unraid release string.
  Future<String> version() async => (await getInfo()).version;

  /// Verifies the URL + key by fetching system info. Returns true on success.
  Future<bool> testConnection() async {
    await getInfo();
    return true;
  }

  void close({bool force = false}) => _dio.close(force: force);
}
