import 'package:dio/dio.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/features/discover/data/seerr_session.dart';
import 'package:cupola/features/discover/domain/seerr_server_facts.dart';
import 'package:cupola/features/discover/domain/seerr_sign_in.dart';
import 'package:cupola/features/settings/data/service_status_probe.dart';
import 'package:cupola/features/settings/domain/connection_reach.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Signing in to Seerr with one's own account, and out again.
///
/// Every sequence runs on the connection's own client (its pinned
/// certificate, its gateway access, the redirect guard), as an account with
/// no session yet: the sign-in route is sent no cookie and answers with the
/// session, which `/auth/me` then proves.
///
///  1. [readServer]: `/status` (who answered: Seerr, or a stop) and
///     `/settings/public`, the ways in it offers ([SeerrServerFacts]).
///  2. One of the sign-ins, each of which refuses to call a route the server
///     did not offer ([SeerrSignInRefused]): **on a server still in its first
///     setup, a media-server sign-in creates its admin**.
///  3. `/auth/me`: the account as it stands, kept as a
///     [SeerrAccountSignIn] with its session.
///
/// The password and the Plex token go in one request body and are never
/// kept, printed or put in a failure.
class SeerrAuthService {
  SeerrAuthService._(this._url, this._reachedAt, this._client);

  /// The service for the connection [instance], reached at [reach] (the
  /// address its route is on, with that address's access and pin; null for
  /// its address at home with no pin). A key in the instance is not sent:
  /// signing in is the account's.
  factory SeerrAuthService.forConnection(
    ServiceInstance instance, {
    ConnectionReach? reach,
    DateTime Function()? now,
  }) {
    late final SeerrAuthService service;
    final client = seerrClientFor(
      instance,
      reach: reach,
      signIn: const SeerrAccountSignIn(kind: SeerrAccountKind.local),
      events: SeerrSessionEvents(
        onSession: (value) => service._session = value,
      ),
    );
    service = SeerrAuthService._(
      instance.url,
      reach?.url ?? instance.url,
      client,
    ).._now = now;
    return service;
  }

  final String _url;

  /// The address the requests go to, which names whatever answers there.
  final String _reachedAt;

  /// The address of the connection this service signs in to, the one it is
  /// saved by: the session it hands back belongs to it, whatever the form's
  /// field says by then, and whichever of the connection's addresses the
  /// sign-in went to.
  String get url => _url;
  final ApiClient _client;
  DateTime Function()? _now;
  String _session = '';

  /// Who answers at the address and how it may be signed in to. Throws what
  /// the reads threw: a transport failure, or `WrongServiceAnswer` when
  /// something that is not Seerr answered.
  Future<SeerrServerFacts> readServer() async {
    final version = await readServiceStatus(
      _client,
      ServiceKey.seerr,
      url: _reachedAt,
    );
    final response = await _client.get('/api/v1/settings/public');
    final json = mapOrNull(response.data);
    if (json == null) {
      throw const FormatException('Seerr answered without its settings');
    }
    return SeerrServerFacts.fromPublicSettings(
      json.cast<String, dynamic>(),
      version: version,
    );
  }

  /// The server's own email and password: `POST /auth/local`.
  Future<SeerrAccountSignIn> signInWithEmail(
    SeerrServerFacts facts, {
    required String email,
    required String password,
  }) async {
    _offered(facts, SeerrSignInMethod.local);
    await _client.post(
      '/api/v1/auth/local',
      data: {'email': email.trim(), 'password': password},
    );
    return _whoAmI(SeerrAccountKind.local, login: email.trim());
  }

  /// A Jellyfin or an Emby username and password: `POST /auth/jellyfin`,
  /// with nothing but the two. A `hostname` is what sets a new server up.
  Future<SeerrAccountSignIn> signInWithMediaServer(
    SeerrServerFacts facts, {
    required String username,
    required String password,
  }) async {
    final emby = facts.signIn.offers(SeerrSignInMethod.emby);
    _offered(facts, emby ? SeerrSignInMethod.emby : SeerrSignInMethod.jellyfin);
    await _client.post(
      '/api/v1/auth/jellyfin',
      data: {'username': username.trim(), 'password': password},
    );
    return _whoAmI(
      emby ? SeerrAccountKind.emby : SeerrAccountKind.jellyfin,
      login: username.trim(),
    );
  }

  /// The person's Plex token, from plex.tv: `POST /auth/plex`. The token is
  /// sent once and dropped.
  Future<SeerrAccountSignIn> signInWithPlex(
    SeerrServerFacts facts, {
    required String authToken,
  }) async {
    _offered(facts, SeerrSignInMethod.plex);
    await _client.post('/api/v1/auth/plex', data: {'authToken': authToken});
    return _whoAmI(SeerrAccountKind.plex, login: '');
  }

  /// A Quick Connect code to approve from a Jellyfin app.
  Future<SeerrQuickConnect> startQuickConnect(SeerrServerFacts facts) async {
    _offered(facts, SeerrSignInMethod.jellyfinQuickConnect);
    final response = await _client.post(
      '/api/v1/auth/jellyfin/quickconnect/initiate',
    );
    final json = mapOrNull(response.data);
    final code = json?['code'];
    final secret = json?['secret'];
    if (code is! String || secret is! String) {
      throw const FormatException('Seerr answered without a code');
    }
    return SeerrQuickConnect._(code: code, secret: secret);
  }

  /// Whether the code was approved yet. Throws [SeerrQuickConnectExpired]
  /// once the server no longer knows it.
  Future<bool> quickConnectApproved(SeerrQuickConnect code) async {
    try {
      final response = await _client.get(
        '/api/v1/auth/jellyfin/quickconnect/check',
        queryParameters: {'secret': code._secret},
      );
      return mapOrNull(response.data)?['authenticated'] == true;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) throw const SeerrQuickConnectExpired();
      rethrow;
    }
  }

  /// Signs in with an approved code.
  Future<SeerrAccountSignIn> finishQuickConnect(
    SeerrServerFacts facts,
    SeerrQuickConnect code,
  ) async {
    _offered(facts, SeerrSignInMethod.jellyfinQuickConnect);
    await _client.post(
      '/api/v1/auth/jellyfin/quickconnect/authenticate',
      data: {'secret': code._secret},
    );
    return _whoAmI(SeerrAccountKind.jellyfin);
  }

  /// `/auth/me` on the session the sign-in answered with, as the account
  /// the connection keeps.
  Future<SeerrAccountSignIn> _whoAmI(
    SeerrAccountKind kind, {
    String? login,
  }) async {
    if (_session.isEmpty) {
      throw const FormatException('Seerr signed in without a session');
    }
    final me = mapOrNull((await _client.get('/api/v1/auth/me')).data);
    final id = intOrNull(me?['id']);
    if (me == null || id == null) {
      throw const FormatException('Seerr answered without the account');
    }
    String? text(Object? value) =>
        value is String && value.trim().isNotEmpty ? value.trim() : null;
    return SeerrAccountSignIn(
      kind: kind,
      login:
          login ?? text(me['jellyfinUsername']) ?? text(me['username']) ?? '',
      userId: id,
      displayName:
          text(me['displayName']) ??
          text(me['username']) ??
          text(me['jellyfinUsername']) ??
          text(me['plexUsername']) ??
          '',
      session: _session,
      permissions: intOrNull(me['permissions']) ?? 0,
      checkedAt: (_now ?? DateTime.now)(),
    );
  }

  void close() => _client.close();

  /// Never a route the server did not offer: on one still in its first
  /// setup, the first media-server sign-in creates the admin.
  static void _offered(SeerrServerFacts facts, SeerrSignInMethod method) {
    if (!facts.signIn.offers(method)) throw SeerrSignInRefused(method);
  }
}

/// Signs the account of [instance] out of the server, then forgets nothing
/// itself: the caller empties the saved session whatever the server said.
///
/// Bounded at five seconds: a server that does not answer lets the session
/// go by itself, 30 days after it was last used.
///
/// [reach] is where the connection is reached now (`connectionReachProvider`):
/// the server is asked at the address that answers.
Future<void> signOutOfSeerr(
  ServiceInstance instance, {
  ConnectionReach? reach,
}) async {
  if (instance.account?.isSignedIn != true) return;
  final client = seerrClientFor(instance, reach: reach);
  try {
    await client
        .post('/api/v1/auth/logout')
        .timeout(const Duration(seconds: 5));
  } catch (_) {
    // The session is emptied here either way.
  } finally {
    client.close();
  }
}

/// A Quick Connect code waiting for approval. [code] is the six digits a
/// person types into Jellyfin; the secret it is checked with stays here.
class SeerrQuickConnect {
  const SeerrQuickConnect._({required this.code, required String secret})
    : _secret = secret;

  final String code;
  final String _secret;

  @override
  String toString() => 'SeerrQuickConnect';
}

/// The server no longer knows the Quick Connect code: nobody approved it in
/// time.
class SeerrQuickConnectExpired implements Exception {
  const SeerrQuickConnectExpired();

  @override
  String toString() => 'SeerrQuickConnectExpired';
}

/// A sign-in the server did not offer, refused before anything was sent.
class SeerrSignInRefused implements Exception {
  const SeerrSignInRefused(this.method);

  final SeerrSignInMethod method;

  @override
  String toString() => 'SeerrSignInRefused(${method.name})';
}
