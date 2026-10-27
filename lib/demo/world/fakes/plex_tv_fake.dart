/// plex.tv on the fake network: the PIN sign-in a native app goes through
/// to hand Seerr a Plex token.
///
/// From Plex's developer documentation (*Authenticating with Plex*, the
/// traditional flow): `POST https://plex.tv/api/v2/pins?strong=true` with
/// `X-Plex-Product` and `X-Plex-Client-Identifier` answers JSON with `id` and
/// `code`; `GET /api/v2/pins/<id>` with the same identifier carries
/// `authToken: null` until the PIN is claimed; `GET /api/v2/user` with
/// `X-Plex-Token` answers 200 for a valid token and 401 for an invalid one.
/// Seerr's own web client also reads `expiresAt` (`src/utils/plex.ts`).
///
/// Not in the documentation, and so not verified here: the 201 of the
/// create, `expiresIn` (1800 seconds for a strong PIN, 900 for a short one),
/// the 404 body of an unknown or expired PIN, the 400 of a missing client
/// identifier and the 401 body of `/api/v2/user`. They follow what plex.tv is
/// commonly seen to answer.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:cupola/demo/world/config_profile.dart';
import 'package:cupola/demo/world/profile_network.dart';

/// The host this fake answers for.
const plexTvHost = 'plex.tv';

/// One PIN, from its creation to its claim.
class PlexPin {
  PlexPin._({
    required this.id,
    required this.code,
    required this.clientIdentifier,
    required this.product,
    required this.createdAt,
    required this.expiresAt,
  });

  final int id;
  final String code;

  /// Whoever asked for it: only that identifier may read it back.
  final String clientIdentifier;
  final String product;
  final DateTime createdAt;
  final DateTime expiresAt;

  /// The user's token once the PIN is claimed in the browser.
  String? authToken;
}

/// plex.tv's side of the PIN flow, and the accounts it knows.
class PlexTvFake {
  PlexTvFake(this._network);

  final ProfileNetwork _network;
  final Map<int, PlexPin> _pins = {};
  final Set<String> _claimedTokens = {};

  /// Every PIN created, in order.
  Iterable<PlexPin> get pins => _pins.values;

  DateTime get _now => _network.currentTime;

  /// Every token of a Plex account plex.tv knows: the world's Seerr users,
  /// each connection's Seerr account, and whatever a test claimed a PIN with.
  bool knowsToken(String token) =>
      _claimedTokens.contains(token) ||
      WorldSeerrUsers.household.any((u) => u.plexToken == token) ||
      _network.profile.connections.any(
        (c) => c.seerrAccount?.plexToken == token,
      ) ||
      _network.profile.seerrRequester?.plexToken == token;

  /// The token a PIN is claimed with when a test names none: the profile's
  /// Seerr account that signs in through Plex, else its requester, else
  /// Anna.
  String get _defaultToken {
    final accounts = [
      for (final c in _network.profile.connections) ?c.seerrAccount,
    ];
    final plex = accounts
        .where((a) => a.kind == WorldSeerrUserType.plex)
        .firstOrNull;
    return (plex ??
            accounts.firstOrNull ??
            _network.profile.seerrRequester ??
            WorldSeerrUsers.anna)
        .plexToken;
  }

  /// The person signs in on app.plex.tv and approves the PIN: from now on
  /// polling it answers [authToken].
  PlexPin claim(int id, {String? authToken}) {
    final pin = _pins[id];
    if (pin == null) throw StateError('plex.tv has no PIN $id');
    if (!_now.isBefore(pin.expiresAt)) {
      throw StateError('PIN $id expired at ${pin.expiresAt}');
    }
    final token = authToken ?? _defaultToken;
    _claimedTokens.add(token);
    return pin..authToken = token;
  }

  /// The answer to [r] on plex.tv, or null for a route it does not have.
  NetworkReply? answer(NetworkRequest r) {
    if (r.method == 'POST' && r.path == '/api/v2/pins') return _create(r);
    final poll = RegExp(r'^/api/v2/pins/(\d+)$').firstMatch(r.path);
    if (r.method == 'GET' && poll != null) {
      return _poll(r, int.parse(poll.group(1)!));
    }
    if (r.method == 'GET' && r.path == '/api/v2/user') return _user(r);
    return null;
  }

  static NetworkReply _errors(int status, int code, String message) =>
      NetworkReply.json({
        'errors': [
          {'code': code, 'message': message, 'status': status},
        ],
      }, status: status);

  NetworkReply _create(NetworkRequest r) {
    final client = r.headers['x-plex-client-identifier'];
    if (client == null || client.isEmpty) {
      return _errors(400, 1000, 'X-Plex-Client-Identifier is missing');
    }
    final strong = r.query['strong'] == 'true';
    final id = 564964751 + _pins.length;
    final digest = sha256.convert(utf8.encode('pin/$id')).toString();
    final pin = PlexPin._(
      id: id,
      code: strong
          ? digest.substring(0, 25)
          : digest.substring(0, 4).toUpperCase(),
      clientIdentifier: client,
      product: r.headers['x-plex-product'] ?? '',
      createdAt: _now,
      expiresAt: _now.add(Duration(seconds: strong ? 1800 : 900)),
    );
    _pins[id] = pin;
    return NetworkReply.json(_pinJson(pin), status: 201);
  }

  NetworkReply _poll(NetworkRequest r, int id) {
    final pin = _pins[id];
    if (pin == null ||
        pin.clientIdentifier != r.headers['x-plex-client-identifier'] ||
        !_now.isBefore(pin.expiresAt)) {
      return _errors(404, 1020, 'Code not found or expired');
    }
    return NetworkReply.json(_pinJson(pin));
  }

  NetworkReply _user(NetworkRequest r) {
    final token = r.headers['x-plex-token'];
    if (token == null || !knowsToken(token)) {
      return _errors(401, 1001, 'User could not be authenticated');
    }
    final digest = sha256.convert(utf8.encode('user/$token')).toString();
    return NetworkReply.json({
      'id': 10000 + int.parse(digest.substring(0, 4), radix: 16),
      'uuid': digest.substring(0, 16),
      'username': 'plex-${digest.substring(0, 6)}',
      'authToken': token,
    });
  }

  Map<String, Object?> _pinJson(PlexPin pin) => {
    'id': pin.id,
    'code': pin.code,
    'product': pin.product,
    'trusted': false,
    'qr': 'https://plex.tv/api/v2/pins/qr/${pin.code}',
    'clientIdentifier': pin.clientIdentifier,
    'expiresIn': pin.expiresAt.difference(_now).inSeconds,
    'createdAt': pin.createdAt.toUtc().toIso8601String(),
    'expiresAt': pin.expiresAt.toUtc().toIso8601String(),
    'authToken': pin.authToken,
    'newRegistration': null,
  };
}
