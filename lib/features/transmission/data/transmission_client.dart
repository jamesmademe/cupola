import 'dart:convert';

import 'package:dio/dio.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/network/redirect_guard.dart';
import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/features/transmission/domain/models/transmission_models.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Error thrown by [TransmissionClient]. Carries the [reason] so a caller
/// verifying the connection can tell an unreachable host from rejected
/// credentials from a host this device is not allowed to talk to.
///
/// [message] is always either a static sentence written here or a string
/// Transmission itself returned in the RPC `result` field, never an
/// interpolated `DioException`, request URI or credential. That is the contract
/// that keeps a password out of `AppErrorState`, which renders `toString()`
/// verbatim.
class TransmissionException
    implements Exception, HasFailureReason, HasFailureCause {
  const TransmissionException(
    this.message, {
    this.reason = ServiceFailureReason.unknown,
    this.rejectedByDaemon = false,
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

  /// The daemon read the request and answered it with a `result` other than
  /// `"success"`: "invalid or corrupt torrent file", "http error 404". The
  /// request arrived and was refused, which is a different fact from one that
  /// never arrived or whose answer never came back, and [message] is the
  /// daemon's own words.
  final bool rejectedByDaemon;

  @override
  String toString() => 'TransmissionException: $message';
}

/// Client for the Transmission RPC API.
///
/// Three properties of this API drive the whole shape of this class, and each
/// one breaks a client written to the usual REST assumptions.
///
/// **1. Every response is HTTP 200; success lives in the JSON.** The spec says
/// `result` "MUST be `success` on success, or an error string on failure", so a
/// client that checks only the status code reports "torrent not found",
/// "invalid argument" and "method name not recognized" as successes. [_call] is
/// the single place that test happens.
///
/// This client speaks Transmission's **legacy** protocol deliberately.
/// Transmission 4.1 (January 2026) added a JSON-RPC 2.0 dialect with snake_case
/// method names, where `result` carries the arguments object and failures come
/// back as an `error` object instead. It is the future, but it exists only on
/// 4.1+, while the legacy protocol is understood by every release from 2.x
/// through 4.1.x (deprecated there, but answered). One dialect that works
/// against every daemon a user might have beats two code paths chosen by a
/// version probe, and switching later is a change to [_unwrap] and the method
/// names, not to anything above them.
///
/// **2. The CSRF handshake, and its hard hourly cutover.** Transmission answers
/// an unknown or stale `X-Transmission-Session-Id` with **409**, carrying the
/// correct id in the response headers. The id lives one hour
/// (`SessionIdDurationSec`) and is regenerated on daemon restart. This is
/// the part that is easy to get wrong: **there is no grace window**.
/// `tr_session_id` keeps a `previous_value_`, but `test_session_id()` compares
/// against the current id only; the old value exists purely to hold the
/// previous lockfile open for same-machine detection. The rotation is performed
/// lazily *by the very request that trips it*, so a long-lived client is
/// guaranteed one 409 per hour, forever. The retry therefore lives on **every**
/// request rather than on first contact, and runs **exactly once**,
/// non-recursively: replaying without actually updating the stored id 409s
/// forever, which is the classic way clients hang against this API.
///
/// The server's check order is `403` brute-force → `401` auth → `421` hostname
/// → `409` session-id → dispatch, so a wrong password surfaces as 401 and never
/// reaches the handshake at all. Treating 409 as the only interesting failure
/// misdiagnoses every auth problem.
///
/// **3. A 401 is terminal and must not be retried.** With
/// `anti-brute-force-enabled`, exceeding `anti-brute-force-threshold` (default
/// 100) failed logins flips the daemon to 403 *until it is restarted*. A client
/// that re-sends a wrong password on a polling timer locks the user out of their
/// own Transmission. [_credentialsRejected] makes the first 401 stick, so every
/// later call fails immediately and locally.
///
/// Basic credentials are base64, i.e. cleartext-equivalent, and are re-sent on
/// **every** request, so a scheme-less URL defaults to HTTPS
/// ([UrlUtils.normalizeBaseUrl]) and redirects are followed by hand
/// ([SameOriginRedirectInterceptor]). The latter is not optional here:
/// `dart:io` copies `Authorization` on a redirect from a subdomain to its parent
/// domain, which is exactly the `transmission.homelab.net` → `homelab.net`
/// topology this app is used on.
class TransmissionClient {
  /// [certFingerprint], when non-empty, is a self-signed certificate the user
  /// explicitly trusted for this origin (trust-on-first-use, ADR-6). Ignored
  /// when [dio] is injected: a caller supplying its own transport owns its TLS
  /// behaviour too.
  TransmissionClient({
    required String url,
    this.username,
    this.password,
    Dio? dio,
    String? certFingerprint,
    Map<String, String> accessHeaders = const {},

    /// Away from home with no address away: every request is refused, and
    /// nothing is dialled (`OnlyAtHomeRefusal`).
    ServiceKey? onlyAtHome,
  }) : baseUrl = UrlUtils.normalizeBaseUrl(url),
       rpcPath = resolveRpcPath(url),
       rpcUrl = resolveRpcUrl(url) {
    // Redirects are followed by hand so the Basic credential is never replayed
    // to a host the user did not configure: `dart:io` copies `Authorization`
    // from a subdomain to its parent domain, and so a 303 cannot downgrade
    // this POST to a GET, which Transmission answers with 405.
    //
    // The transport is rooted at the **origin**, never at [baseUrl]: the path
    // the user typed is already inside [rpcPath], and Dio joins a relative
    // request path onto `baseUrl` by plain concatenation, so a base carrying
    // `/tr` turned every call into `/tr/tr/rpc`.
    _dio = guardedDio(
      baseUrl: _originOf(baseUrl),
      injected: dio,
      certFingerprint: certFingerprint,
      accessHeaders: accessHeaders,
      onlyAtHome: onlyAtHome,
      // It signs in with Basic itself: a Basic 401 is its own refusal.
      nativeBasicAuth: true,
    );
  }

  /// Header Transmission uses for its CSRF token, in both directions.
  static const sessionIdHeader = 'X-Transmission-Session-Id';

  /// Where the RPC endpoint sits on the configured host, as a path from the
  /// origin.
  ///
  /// **Not a constant, because the server moves it.** Transmission's `rpc-url`
  /// setting (default `/transmission/`) relocates the endpoint wholesale, and a
  /// reverse proxy in front of it moves it again. Hardcoding
  /// `/transmission/rpc` is the single most common reason a working daemon
  /// looks unreachable, so the address field accepts any of the three forms
  /// people actually have:
  ///
  /// * `https://nas.local:9091`: no path, so the default is appended.
  /// * `https://nas.local/tr`: a relocated `rpc-url`, so `/rpc` is appended.
  /// * `https://nas.local/tr/rpc`: the endpoint itself, used verbatim.
  ///
  /// Plus the one people paste most often without meaning to: the address bar
  /// of the Web UI, `https://nas.local:9091/transmission/web/`. Transmission
  /// always serves that page at `<rpc-url>web/`, so a trailing `web` segment is
  /// the Web UI and its sibling `rpc` is the endpoint. A bare `/web` is left
  /// alone (→ `/web/rpc`): at the root it is as likely to be a reverse-proxy
  /// mount as the Web UI of a daemon whose `rpc-url` is `/`.
  ///
  /// The result is an **absolute path** from the origin, and exactly one:
  /// [rpcUrl] is what actually goes on the wire. Static and pure so it can be
  /// tested without building a client.
  static String resolveRpcPath(String rawUrl) {
    final normalized = UrlUtils.normalizeBaseUrl(rawUrl);
    if (normalized.isEmpty) return '/transmission/rpc';

    // The raw (still percent-encoded) path, split by hand: `pathSegments`
    // would decode `%20` and friends, and rejoining those would put characters
    // on the wire the user never typed.
    final segments = (Uri.tryParse(normalized)?.path ?? '')
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList();
    if (segments.isEmpty) return '/transmission/rpc';
    final last = segments.last.toLowerCase();
    if (last == 'rpc') return '/${segments.join('/')}';
    if (last == 'web' && segments.length > 1) {
      segments[segments.length - 1] = 'rpc';
      return '/${segments.join('/')}';
    }
    return '/${[...segments, 'rpc'].join('/')}';
  }

  /// The full RPC endpoint for [rawUrl]: its origin plus [resolveRpcPath].
  ///
  /// Posted as an absolute URL so the endpoint is independent of whatever
  /// `baseUrl` the transport carries. Dio ignores `baseUrl` for a path that
  /// starts with a scheme. That is what makes the path appear exactly once
  /// whether the client built its own Dio or was handed one.
  static String resolveRpcUrl(String rawUrl) {
    final normalized = UrlUtils.normalizeBaseUrl(rawUrl);
    return '${_originOf(normalized)}${resolveRpcPath(rawUrl)}';
  }

  /// `scheme://host[:port]` of an already-normalized address, with no path.
  /// Empty in, empty out, so an unconfigured client still constructs.
  static String _originOf(String normalized) {
    if (normalized.isEmpty) return '';
    final uri = Uri.tryParse(normalized);
    if (uri == null || uri.host.isEmpty) return normalized;
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
    ).toString();
  }

  /// The configured address, normalized ([UrlUtils.normalizeBaseUrl]), the
  /// identity of this connection, path included. It is **not** the transport's
  /// base: see the constructor.
  final String baseUrl;

  /// The resolved RPC endpoint path; see [resolveRpcPath].
  final String rpcPath;

  /// The absolute RPC endpoint every call is posted to; see [resolveRpcUrl].
  final String rpcUrl;

  final String? username;
  final String? password;
  late final Dio _dio;

  /// The transport, for tests that assert the pinned adapter and redirect guard
  /// are actually installed. `ApiClient` exposes the same accessor for the same
  /// reason: without it, a client can accept `certFingerprint`, store it, drop
  /// it on the floor, and every existing test still passes green.
  Dio get dio => _dio;

  /// The current CSRF token. Null until the first 409 teaches it to us.
  String? _sessionId;

  /// Sticky once Transmission has rejected these credentials.
  ///
  /// Guards the anti-brute-force lockout described in the class doc: the
  /// provider holding this client polls, and without this every tick would
  /// spend another of the daemon's 100 allowed failures.
  bool _credentialsRejected = false;

  int _tag = 0;

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    sessionIdHeader: ?_sessionId,
    if ((username?.trim() ?? '').isNotEmpty)
      'Authorization': 'Basic ${base64Credentials(username!, password ?? '')}',
  };

  /// Base64 of `username:password`, as HTTP Basic requires.
  ///
  /// Split out and named so the assembled header is testable without reaching
  /// into a live client, and so there is exactly one place the credential is
  /// encoded.
  static String base64Credentials(String username, String password) {
    return base64Encode(utf8.encode('${username.trim()}:$password'));
  }

  /// Performs one RPC call and returns its `arguments` object.
  ///
  /// The only path to the server. Everything that makes this API unusual
  /// (the 409 handshake, the 200-means-nothing rule, the terminal 401) is
  /// handled here exactly once, so no method below can forget any of it.
  Future<Map<String, dynamic>> _call(
    String method, [
    Map<String, dynamic> arguments = const {},
  ]) async {
    if (_credentialsRejected) {
      throw const TransmissionException(
        'Transmission rejected these credentials.',
        reason: ServiceFailureReason.unauthorized,
      );
    }

    // `retried` rather than recursion: exactly one extra attempt exists, and it
    // is visible in one place. A recursive retry is how this API produces an
    // infinite 409 loop.
    var retried = false;
    while (true) {
      final Response<dynamic> response;
      try {
        response = await _dio.post<dynamic>(
          rpcUrl,
          data: {'method': method, 'arguments': arguments, 'tag': ++_tag},
          options: Options(headers: _headers),
        );
      } on DioException catch (e) {
        final status = e.response?.statusCode;

        if (status == 409 && !retried) {
          final refreshed = _sessionIdFrom(e.response);
          // Only worth replaying if the server actually told us something new;
          // otherwise this is a 409 we cannot satisfy and looping on it is the
          // bug.
          if (refreshed != null && refreshed.isNotEmpty) {
            _sessionId = refreshed;
            retried = true;
            continue;
          }
          throw const TransmissionException(
            'Transmission asked for a session id but did not supply one. If it '
            'is behind a reverse proxy, make sure the proxy forwards the '
            'X-Transmission-Session-Id header in both directions.',
            reason: ServiceFailureReason.notFound,
          );
        }

        throw _describe(e, status);
      }

      return _unwrap(response.data);
    }
  }

  /// Maps a transport failure onto a sentence naming the thing the user can
  /// change. Each status Transmission uses means something specific, and
  /// collapsing them into "could not connect" sends people to re-type a
  /// password that was never the problem.
  TransmissionException _describe(DioException e, int? status) {
    // Something in front of the daemon answered, whatever its status: the
    // daemon never saw the request, so none of its own sentences applies.
    if (e.error is AccessGatewayAnswer) {
      return TransmissionException(
        e.message ?? 'Transmission request failed',
        reason: ServiceFailureReason.accessGateway,
        cause: e,
      );
    }
    switch (status) {
      case 401:
        // Terminal, and it must stay terminal; see [_credentialsRejected].
        _credentialsRejected = true;
        return const TransmissionException(
          'Transmission rejected the username or password.',
          reason: ServiceFailureReason.unauthorized,
        );
      case 403:
        return const TransmissionException(
          'Transmission refused this device. Add its address to '
          '`rpc-whitelist`, or turn `rpc-whitelist-enabled` off. (This is also '
          'what Transmission returns once its anti-brute-force lockout has '
          'tripped, which clears only when the daemon restarts.)',
          reason: ServiceFailureReason.unauthorized,
        );
      case 421:
        // Only reachable on a daemon with RPC authentication turned off:
        // `isHostnameAllowed()` short-circuits to true as soon as a password is
        // set. So the fix worth offering first is the one that also fixes the
        // bigger problem.
        return const TransmissionException(
          'Transmission did not recognize the hostname in the request. Add it '
          'to `rpc-host-whitelist`, or make the reverse proxy rewrite the Host '
          'header. (This check is skipped entirely once Transmission has a '
          'username and password set, which is worth doing anyway.)',
          reason: ServiceFailureReason.notFound,
        );
      case 405:
        return const TransmissionException(
          'The RPC endpoint is not at this address. Check for a missing or '
          'wrong base path.',
          reason: ServiceFailureReason.notFound,
        );
      default:
        // A body that could not be decoded means the address is answering with
        // something that is not this API: the Web UI itself, or a reverse
        // proxy's landing page served with a JSON content type. [_unwrap]
        // catches the same case when Dio hands the body over as a string, but
        // when the content type claims JSON, Dio throws while decoding and
        // never gets that far. Both roads have to arrive at the same sentence,
        // or the user is told "unknown error" for a wrong base path.
        if (e.error is FormatException) {
          return const TransmissionException(
            'The Transmission RPC API did not answer at this address. Check '
            'the URL, port and base path.',
            reason: ServiceFailureReason.notFound,
          );
        }
        // `e.message` is one of Dio's own static sentences and never carries
        // the request URI; the credential lives in a header, which no Dio
        // `toString()` includes. Nothing here can carry the password.
        return TransmissionException(
          e.message ?? 'Transmission request failed',
          reason: classifyConnectionFailure(e),
          cause: e,
        );
    }
  }

  static String? _sessionIdFrom(Response<dynamic>? response) {
    final values = response?.headers.map[sessionIdHeader.toLowerCase()];
    if (values == null || values.isEmpty) return null;
    return values.first.trim();
  }

  /// Reads the RPC envelope, enforcing the rule that HTTP 200 proves nothing.
  Map<String, dynamic> _unwrap(dynamic data) {
    if (data is! Map) {
      // A 200 carrying HTML means the address points at something that is not
      // the RPC endpoint: a proxy landing page, or the Web UI itself.
      throw const TransmissionException(
        'The Transmission RPC API did not answer at this address. Check the '
        'URL, port and base path.',
        reason: ServiceFailureReason.notFound,
      );
    }

    final map = data.cast<String, dynamic>();
    final result = map['result']?.toString() ?? '';
    if (result != 'success') {
      throw TransmissionException(
        result.isEmpty ? 'Transmission rejected the request.' : result,
        rejectedByDaemon: true,
      );
    }

    final arguments = map['arguments'];
    return arguments is Map
        ? arguments.cast<String, dynamic>()
        : const <String, dynamic>{};
  }

  // ── Reads ─────────────────────────────────────────────────────────────────

  /// Session settings and, usefully, the version triple.
  ///
  /// The cheapest call that proves everything at once: it forces the session-id
  /// handshake, validates the Basic credentials (401), proves the whitelists
  /// admit this device (403/421), and returns `version` and `rpc-version` so
  /// the caller can tell 3.x from 4.x in the same round trip.
  Future<TransmissionSession> session() async {
    return TransmissionSession.fromJson(await _call('session-get'));
  }

  /// Aggregate counters (speeds and torrent counts) without listing anything.
  Future<TransmissionStats> stats() async {
    return TransmissionStats.fromJson(await _call('session-stats'));
  }

  /// The daemon's version string. Doubles as a reachability probe.
  Future<String> version() async => (await session()).version;

  /// Verifies the configured URL and credentials.
  Future<bool> testConnection() async {
    await session();
    return true;
  }

  /// The torrent list.
  ///
  /// [_listFields] deliberately excludes `pieces` and `availability`: the first
  /// is a base64 bitfield sized to the torrent and the second a per-piece array,
  /// so including either in a polling call moves serious bandwidth and CPU for
  /// data only a detail view can show.
  Future<List<TransmissionTorrent>> torrents({List<String>? ids}) async {
    final arguments = <String, dynamic>{'fields': _listFields};
    // Never send an *absent* `ids` for an empty selection: the spec says all
    // torrents are used when `ids` is omitted, which is harmless here but
    // catastrophic in [removeTorrents]. Keeping the two shaped the same way is
    // what stops the dangerous one being written differently by accident.
    if (ids != null) arguments['ids'] = ids;

    final result = await _call('torrent-get', arguments);
    final torrents = result['torrents'];
    if (torrents is! List) return const [];
    return torrents
        .whereType<Map>()
        .map((e) => TransmissionTorrent.fromJson(e.cast<String, dynamic>()))
        .toList(growable: false);
  }

  static const List<String> _listFields = [
    'id',
    'hashString',
    'name',
    'status',
    'percentDone',
    'totalSize',
    'sizeWhenDone',
    'leftUntilDone',
    'rateDownload',
    'rateUpload',
    'eta',
    'uploadRatio',
    'uploadedEver',
    'downloadedEver',
    'downloadDir',
    'error',
    'errorString',
    'addedDate',
    'doneDate',
    'activityDate',
    'peersConnected',
    'peersSendingToUs',
    'peersGettingFromUs',
    'queuePosition',
    'isFinished',
    'isStalled',
    'labels',
    'recheckProgress',
  ];

  /// Free space at [path] on the **daemon's** filesystem, or null when the
  /// daemon did not report a usable figure.
  ///
  /// Worth stating because it is a common source of confusion: every path in
  /// this API belongs to the server's namespace, and in Docker the daemon's
  /// `/downloads` is not the user's.
  ///
  /// **Nullable, and zero is kept.** Collapsing an absent or non-numeric
  /// `size-bytes` to `0` made "the daemon did not answer" and "the disk is
  /// full" the same int, and the only way to recover the first was for the
  /// caller to discard the second, which threw away precisely the reading a
  /// user needs before starting a grab. A negative value is silence too:
  /// `size-bytes` is documented as a count of free bytes, so a daemon that
  /// answers below zero is saying it could not measure, not that the volume
  /// owes space.
  Future<int?> freeSpace(String path) async {
    final result = await _call('free-space', {'path': path});
    final bytes = result['size-bytes'];
    if (bytes is! num) return null;
    final value = bytes.toInt();
    return value < 0 ? null : value;
  }

  // ── Writes ────────────────────────────────────────────────────────────────

  /// Ids for a write, refusing an empty selection.
  ///
  /// The dangerous shape in this API is an **absent** `ids` key: the spec says
  /// all torrents are used when it is omitted, so a write assembled with
  /// `if (ids.isNotEmpty) 'ids': ids` silently escalates an empty selection into
  /// "every torrent you own", and with [removeTorrents]' `deleteLocalData` that
  /// erases the library and its files.
  ///
  /// An empty *array* is in fact safe (the server's loop runs zero times and
  /// selects nothing), so this throw is not what stands between the user and
  /// that bug. What stands between them is that every write goes through here
  /// and therefore always emits the key. The throw is the second line: it turns
  /// a selection bug in the UI into a visible error instead of a silent no-op.
  static Map<String, dynamic> _idsArgument(List<String> ids) {
    if (ids.isEmpty) {
      throw const TransmissionException(
        'No torrents selected.',
        reason: ServiceFailureReason.unknown,
      );
    }
    return {'ids': ids};
  }

  Future<void> start(List<String> ids) async {
    await _call('torrent-start', _idsArgument(ids));
  }

  Future<void> stop(List<String> ids) async {
    await _call('torrent-stop', _idsArgument(ids));
  }

  /// Re-checks local data. Returns as soon as the daemon accepts the request:
  /// the verify itself runs for minutes to hours, so progress must be read from
  /// `recheckProgress` rather than inferred from this completing.
  Future<void> verify(List<String> ids) async {
    await _call('torrent-verify', _idsArgument(ids));
  }

  Future<void> reannounce(List<String> ids) async {
    await _call('torrent-reannounce', _idsArgument(ids));
  }

  /// Removes torrents, optionally deleting their downloaded files.
  ///
  /// [deleteLocalData] is the only genuinely destructive call in this client and
  /// it is irreversible: Transmission unlinks the files, nothing goes to a
  /// trash. The UI must confirm it explicitly and separately from removal.
  Future<void> removeTorrents(
    List<String> ids, {
    bool deleteLocalData = false,
  }) async {
    await _call('torrent-remove', {
      ..._idsArgument(ids),
      'delete-local-data': deleteLocalData,
    });
  }

  /// Adds a torrent from a magnet link or a `.torrent` URL.
  ///
  /// Returns `(torrent, isDuplicate)`. The duplicate case is the trap:
  /// Transmission answers `result: "success"` with a `torrent-duplicate` key
  /// instead of `torrent-added`, so a client that checks only `result` cheerfully
  /// reports adding a torrent it did not add.
  Future<({TransmissionTorrent? torrent, bool isDuplicate})> addTorrent(
    String filenameOrMagnet, {
    String? downloadDir,
    bool paused = false,
    List<String>? labels,
  }) async {
    final result = await _call('torrent-add', {
      'filename': filenameOrMagnet.trim(),
      'paused': paused,
      if (downloadDir != null && downloadDir.trim().isNotEmpty)
        'download-dir': downloadDir.trim(),
      if (labels != null && labels.isNotEmpty) 'labels': labels,
    });

    final duplicate = result['torrent-duplicate'];
    final added = result['torrent-added'];
    final payload = duplicate ?? added;
    return (
      torrent: payload is Map
          ? TransmissionTorrent.fromJson(payload.cast<String, dynamic>())
          : null,
      isDuplicate: duplicate != null,
    );
  }

  /// Per-torrent speed limits, in **kilobytes** per second.
  ///
  /// The unit asymmetry is Transmission's, not this client's: every *rate* it
  /// reports is bytes/s while every *limit* it accepts is KB/s, and no key name
  /// says so. Null leaves a limit untouched; passing 0 with the matching
  /// `*Limited` flag set is how "no limit" is expressed.
  Future<void> setSpeedLimits(
    List<String> ids, {
    int? downloadKbPerSec,
    int? uploadKbPerSec,
  }) async {
    await _call('torrent-set', {
      ..._idsArgument(ids),
      if (downloadKbPerSec != null) ...{
        'downloadLimit': downloadKbPerSec,
        'downloadLimited': downloadKbPerSec > 0,
      },
      if (uploadKbPerSec != null) ...{
        'uploadLimit': uploadKbPerSec,
        'uploadLimited': uploadKbPerSec > 0,
      },
    });
  }

  /// Replaces the labels on the selected torrents.
  ///
  /// `labels` arrived in Transmission 3.00 (**rpc-version 16**) and arrived
  /// on both halves of the protocol at once: the revision that puts `labels`
  /// on `torrent-get` is the one that accepts it on `torrent-set`. So a daemon
  /// whose torrents report labels can assign them, and there is no version
  /// window where the read works and the write does not. Older daemons omit
  /// the field on reads and reject this write; the Session surface exposes
  /// `rpcVersion` so callers can withhold the editor instead of shipping a
  /// control that fails.
  Future<void> setLabels(List<String> ids, List<String> labels) async {
    await _call('torrent-set', {
      ..._idsArgument(ids),
      'labels': labels
          .map((label) => label.trim())
          .where((label) => label.isNotEmpty)
          .toList(growable: false),
    });
  }

  /// Writes the subset of `session-set` exposed by Cupola's Session tab.
  /// Null means leave the daemon setting untouched.
  Future<void> setSessionPreferences({
    int? peerPort,
    bool? peerPortRandomOnStart,
    bool? portForwardingEnabled,
    String? encryption,
    int? peerLimitGlobal,
    int? peerLimitPerTorrent,
    double? seedRatioLimit,
    bool? seedRatioLimited,
    int? idleSeedingLimitMinutes,
    bool? idleSeedingLimitEnabled,
    bool? blocklistEnabled,
    bool? downloadQueueEnabled,
    int? downloadQueueSize,
    bool? seedQueueEnabled,
    int? seedQueueSize,
    bool? startAddedTorrents,
    bool? renamePartialFiles,
    int? cacheSizeMb,
  }) async {
    final values = <String, dynamic>{
      'peer-port': ?peerPort,
      'peer-port-random-on-start': ?peerPortRandomOnStart,
      'port-forwarding-enabled': ?portForwardingEnabled,
      'encryption': ?encryption,
      'peer-limit-global': ?peerLimitGlobal,
      'peer-limit-per-torrent': ?peerLimitPerTorrent,
      'seedRatioLimit': ?seedRatioLimit,
      'seedRatioLimited': ?seedRatioLimited,
      'idle-seeding-limit': ?idleSeedingLimitMinutes,
      'idle-seeding-limit-enabled': ?idleSeedingLimitEnabled,
      'blocklist-enabled': ?blocklistEnabled,
      'download-queue-enabled': ?downloadQueueEnabled,
      'download-queue-size': ?downloadQueueSize,
      'seed-queue-enabled': ?seedQueueEnabled,
      'seed-queue-size': ?seedQueueSize,
      'start-added-torrents': ?startAddedTorrents,
      'rename-partial-files': ?renamePartialFiles,
      'cache-size-mb': ?cacheSizeMb,
    };
    if (values.isEmpty) return;
    await _call('session-set', values);
  }

  /// Moves torrents within the queue.
  Future<void> queueMove(List<String> ids, TransmissionQueueMove move) async {
    await _call(move.method, _idsArgument(ids));
  }

  /// Turns the alternative ("turtle") speed limits on or off; Transmission's
  /// nearest equivalent to a global pause that does not stop every torrent.
  Future<void> setAltSpeedEnabled(bool enabled) async {
    await _call('session-set', {'alt-speed-enabled': enabled});
  }

  void close({bool force = false}) => _dio.close(force: force);
}
