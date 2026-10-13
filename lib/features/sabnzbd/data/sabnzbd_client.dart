import 'package:dio/dio.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/network/redirect_guard.dart';
import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/features/settings/domain/probe_identity.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import 'package:cupola/features/sabnzbd/domain/models/sabnzbd_models.dart';

/// Error thrown by [SabnzbdClient]. The message is always run through
/// [redactSabnzbdSecrets] so an API key (which SABnzbd carries in the request
/// URL query string) can never reach a log, snackbar or crash report. Carries
/// the [reason] so a caller verifying the connection can tell an unreachable
/// host from a rejected API key.
class SabnzbdException implements Exception, HasFailureReason, HasFailureCause {
  const SabnzbdException(
    this.message, {
    this.reason = ServiceFailureReason.unknown,
    this.cause,
  });
  final String message;
  @override
  final ServiceFailureReason reason;

  /// The failure this wraps, when it wraps one: what it knew (which gateway
  /// answered, for one) survives the wrapping.
  final Object? cause;

  @override
  Object? get failureCause => cause;
  @override
  String toString() => 'SabnzbdException: $message';
}

/// Strips secret query parameters (API key, credentials) from any string before
/// it can surface in an error message, log line or UI. Security standard
/// §10.2 #7: SABnzbd's key travels in the URL, so unredacted `DioException`
/// text would otherwise leak it.
String redactSabnzbdSecrets(String input) {
  return input.replaceAllMapped(
    RegExp(
      r'(apikey|apkey|ma_username|ma_password)=[^&\s]*',
      caseSensitive: false,
    ),
    (m) => '${m.group(1)}=***',
  );
}

/// Client for the SABnzbd HTTP API.
///
/// SABnzbd exposes a single `/api` endpoint driven by a `mode` query parameter
/// and authenticates with an `apikey` query parameter (not a header), so it
/// needs a dedicated client rather than the shared header-auth [ApiClient].
class SabnzbdClient {
  /// [certFingerprint], when non-empty, is a self-signed certificate the user
  /// explicitly trusted for this origin (trust-on-first-use, ADR-6). Ignored
  /// when [dio] is injected: a caller supplying its own transport owns its
  /// TLS behaviour too.
  SabnzbdClient({
    required String url,
    required String apiKey,
    Dio? dio,
    String? certFingerprint,
    Map<String, String> accessHeaders = const {},

    /// Away from home with no address away: every request is refused, and
    /// nothing is dialled (`OnlyAtHomeRefusal`).
    ServiceKey? onlyAtHome,
  }) : baseUrl = UrlUtils.normalizeBaseUrl(url),
       _apiKey = apiKey.trim() {
    // Redirects are followed by hand, and this client is the one that most
    // needs it: the API key travels in the **query string**, and a redirect is
    // resolved against `$request_uri`, which includes the query by definition.
    // `dart:io`'s only protection is a header filter; it cannot strip a
    // credential that is part of the URL, so a single
    // `return 301 https://elsewhere$request_uri;` in a reverse proxy delivers
    // the key to another host, where it lands in that server's access log in
    // plaintext.
    _dio = guardedDio(
      baseUrl: baseUrl,
      injected: dio,
      certFingerprint: certFingerprint,
      accessHeaders: accessHeaders,
      onlyAtHome: onlyAtHome,
    );
  }

  final String baseUrl;
  final String _apiKey;
  late final Dio _dio;

  Future<Map<String, dynamic>> _call(
    String mode, {
    Map<String, dynamic>? extra,
    bool withKey = true,
  }) async {
    try {
      final response = await _dio.get(
        '/api',
        queryParameters: {
          'mode': mode,
          'output': 'json',
          if (withKey && _apiKey.isNotEmpty) 'apikey': _apiKey,
          ...?extra,
        },
      );
      final data = response.data;
      if (data is Map<String, dynamic>) {
        // SABnzbd reports failures as {"status": false}: usually, but *not
        // always*, with an "error" string alongside. The bare form comes back
        // for a queue command against an unknown `nzo_id`, which is exactly
        // what a user hits by deleting a job that finished between the last
        // poll and the tap. Requiring the error string as well meant that
        // response fell through as a success and the UI cheerfully reported
        // "Job removed" for a call the server had refused.
        if (data['status'] == false) {
          final reported = data['error'];
          // SABnzbd answers 200 even for "API Key Incorrect", so the reason
          // has to come from the message.
          final message = reported == null
              ? 'SABnzbd rejected the request'
              : redactSabnzbdSecrets(reported.toString());
          throw SabnzbdException(
            message,
            reason: looksUnauthorizedMessage(message)
                ? ServiceFailureReason.unauthorized
                : ServiceFailureReason.unknown,
          );
        }
        return data;
      }
      if (data is String) {
        // A web page where the API should be (a proxy's page, an address
        // missing its base path): not SABnzbd, and never a read with nothing
        // in it. Any other text is kept for the caller to read.
        final page = UnexpectedAnswer(
          status: response.statusCode,
          headers: response.headers.map,
          body: data,
          host: ServiceKey.sabnzbd.extractHost(baseUrl),
          baseUrl: baseUrl,
        );
        if (page.isWebPage) {
          throw SabnzbdException(
            'A web page answered instead of SABnzbd',
            reason: page.reason,
            cause: page,
          );
        }
        return {'_raw': data};
      }
      return const {};
    } on DioException catch (e) {
      throw SabnzbdException(
        redactSabnzbdSecrets(e.message ?? 'SABnzbd request failed'),
        reason: classifyConnectionFailure(e),
        cause: e,
      );
    }
  }

  /// Server version. Does not require the API key, which is exactly why it
  /// cannot be the reachability probe on its own: see [checkKeyAndVersion].
  ///
  /// Also the probe's proof of who answered: `{"version": …}`. A web page at
  /// the address comes back as text, which is not SABnzbd
  /// ([WrongServiceAnswer]) rather than a version.
  Future<String> getVersion() async {
    final data = await _call('version', withKey: false);
    requireProbeIdentity(
      ServiceKey.sabnzbd,
      data.containsKey('_raw') ? data['_raw'] : data,
      url: baseUrl,
    );
    return (data['version'] ?? '').toString().trim();
  }

  /// The Dashboard's probe: proves the key, then names the version.
  ///
  /// `mode=version` answers without a key, so on its own it read a SABnzbd
  /// with a wrong key as answering while every screen behind it failed. A
  /// one-slot queue read is the cheapest call that checks the key; its
  /// refusal (`status: false`, "API Key Incorrect") throws unauthorized.
  Future<String> checkKeyAndVersion() async {
    await getQueue(limit: 1);
    return getVersion();
  }

  /// The `limit` that asks `mode=queue` for every job rather than a page.
  ///
  /// SABnzbd's `NzbQueue.queue_info` admits a job when
  /// `not limit or start <= n < start + limit`, so zero means "no page", not
  /// "no rows"; and an absent `limit` parses to the same zero.
  static const wholeQueue = 0;

  /// The active download queue: the first [limit] jobs, or all of them for
  /// [wholeQueue].
  ///
  /// An answer without SABnzbd's `queue` envelope is something that is not
  /// SABnzbd, and fails: read as an empty queue it was a confident "nothing
  /// downloading" about a server nobody reached.
  Future<SabnzbdQueue> getQueue({int limit = 50}) async {
    final data = await _call('queue', extra: {'start': 0, 'limit': limit});
    final queue = data['queue'];
    if (queue is! Map) throw _notSabnzbd();
    return SabnzbdQueue.fromJson(queue.cast<String, dynamic>());
  }

  /// Recent completed/failed downloads. Without SABnzbd's `history`
  /// envelope, a failure, as for [getQueue].
  Future<List<SabnzbdHistorySlot>> getHistory({int limit = 20}) async {
    final data = await _call('history', extra: {'start': 0, 'limit': limit});
    final history = data['history'];
    if (history is! Map) throw _notSabnzbd();
    final slots = (history['slots'] as List?) ?? const [];
    return slots
        .whereType<Map>()
        .map((e) => SabnzbdHistorySlot.fromJson(e.cast<String, dynamic>()))
        .toList(growable: false);
  }

  /// The failure of a read whose answer has no SABnzbd envelope: something
  /// answered at the address, and it is not SABnzbd.
  SabnzbdException _notSabnzbd() => SabnzbdException(
    'SABnzbd did not answer at this address',
    reason: ServiceFailureReason.notFound,
    cause: WrongServiceAnswer(
      ServiceKey.sabnzbd,
      ProbeIdentity.notThisService,
      url: baseUrl,
    ),
  );

  /// Aggregate transfer statistics (total / month / week / day bytes).
  Future<SabnzbdServerStats> getServerStats() async {
    final data = await _call('server_stats');
    return SabnzbdServerStats.fromJson(data);
  }

  /// Configured news servers. Passwords are deliberately not represented by
  /// the model even though SABnzbd masks them in this response.
  Future<List<SabnzbdServerConfig>> getServers() async {
    final data = await _call('get_config', extra: {'section': 'servers'});
    final config = data['config'];
    final root = config is Map ? config : data;
    final rawServers = root['servers'];
    if (rawServers is! List) return const [];
    return rawServers
        .whereType<Map>()
        .map(
          (server) =>
              SabnzbdServerConfig.fromJson(server.cast<String, dynamic>()),
        )
        .toList(growable: false);
  }

  /// The configured categories, always including the `*` default first.
  Future<List<String>> getCategories() async {
    final data = await _call('get_cats');
    final cats = (data['categories'] as List?) ?? const [];
    return cats.map((e) => e.toString()).toList(growable: false);
  }

  /// Verifies the configured URL + key by fetching the queue (which requires
  /// authentication), then that SABnzbd is what answered. Returns true on
  /// success.
  Future<bool> testConnection() async {
    // The Dashboard's probe, so the connection test checks who answered the
    // same way and says the same thing.
    await checkKeyAndVersion();
    return true;
  }

  /// Pauses the whole queue.
  Future<void> pause() async {
    await _call('pause');
  }

  /// Resumes the whole queue.
  Future<void> resume() async {
    await _call('resume');
  }

  /// Adds an NZB by URL. [category] defaults to SABnzbd's `*` and [priority]
  /// runs -2..2. The URL is passed via Dio's [queryParameters] so it is encoded
  /// automatically; never concatenated (security §10.2 #8).
  Future<void> addUrl(
    String nzbUrl, {
    String? category,
    int priority = 0,
  }) async {
    await _call(
      'addurl',
      extra: {
        'name': nzbUrl,
        if (category != null && category.isNotEmpty) 'cat': category,
        'priority': priority,
      },
    );
  }

  /// Pauses a single queued job by its NZO id.
  Future<void> pauseJob(String nzoId) async {
    await _call('queue', extra: {'name': 'pause', 'value': nzoId});
  }

  /// Resumes a single queued job by its NZO id.
  Future<void> resumeJob(String nzoId) async {
    await _call('queue', extra: {'name': 'resume', 'value': nzoId});
  }

  /// Deletes a queued job by its NZO id.
  ///
  /// SABnzbd keeps what it already downloaded for the job unless it is told
  /// otherwise: `del_files=1` removes those files too. Off by default, the
  /// server's own default, so the only way to lose the files is to ask.
  Future<void> deleteJob(String nzoId, {bool deleteFiles = false}) async {
    await _call(
      'queue',
      extra: {
        'name': 'delete',
        'value': nzoId,
        if (deleteFiles) 'del_files': 1,
      },
    );
  }

  void close({bool force = false}) => _dio.close(force: force);
}
