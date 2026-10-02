import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:cupola/core/network/redirect_guard.dart';
import 'package:cupola/features/plex/data/plex_client.dart'
    show kPlexProduct, kPlexProductVersion;

/// plex.tv, for the one thing Cupola asks of it: a PIN a person approves on
/// app.plex.tv, so their Plex token can be handed to Seerr.
///
/// The only third party the app talks to, and the sign-in provider the person
/// chose: only while they sign in with Plex, never in the background. No
/// connection stands behind it, so it carries no pinned certificate (plex.tv
/// has a public one), no gateway access and no Seerr cookie; and nothing sent
/// to Seerr carries anything of plex.tv's but the token, once.
///
/// The traditional PIN flow of Plex's own documentation (*Authenticating with
/// Plex*), the one Seerr's web client uses: the JWT flow's tokens expire every
/// 7 days, and Seerr keeps the token it is given and cannot renew one.
class PlexTvClient {
  PlexTvClient({required String clientIdentifier, Dio? dio})
    : _dio = guardedDio(
        baseUrl: 'https://plex.tv',
        injected: dio,
        headers: {
          'Accept': 'application/json',
          'X-Plex-Product': kPlexProduct,
          'X-Plex-Version': kPlexProductVersion,
          'X-Plex-Client-Identifier': clientIdentifier,
          'X-Plex-Platform': _platform(),
          'X-Plex-Device': _platform(),
          'X-Plex-Device-Name': '$kPlexProduct (${_platform()})',
        },
      ),
      _clientIdentifier = clientIdentifier;

  final Dio _dio;
  final String _clientIdentifier;

  /// A new strong PIN: a long code with a long life, for a person who never
  /// types it.
  Future<PlexTvPin> createPin() async {
    final response = await _dio.post<dynamic>(
      '/api/v2/pins',
      queryParameters: {'strong': 'true'},
    );
    final pin = PlexTvPin.fromJson(response.data);
    if (pin == null) {
      throw const FormatException('plex.tv answered without a PIN');
    }
    return pin;
  }

  /// The token [pin] carries once the person approved it, or null while it
  /// waits. Throws [PlexTvPinExpired] when plex.tv no longer knows it.
  Future<String?> authTokenOf(PlexTvPin pin) async {
    try {
      final response = await _dio.get<dynamic>('/api/v2/pins/${pin.id}');
      final data = response.data;
      final token = data is Map ? data['authToken'] : null;
      return token is String && token.isNotEmpty ? token : null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) throw const PlexTvPinExpired();
      rethrow;
    }
  }

  /// The page where the person approves [pin], with its parameters in the
  /// fragment as Plex's documentation writes them. No `forwardUrl`: a native
  /// app polls instead of being sent back.
  Uri authUrl(PlexTvPin pin) => Uri.parse(
    'https://app.plex.tv/auth#?clientID=${Uri.encodeQueryComponent(_clientIdentifier)}'
    '&code=${Uri.encodeQueryComponent(pin.code)}'
    '&context%5Bdevice%5D%5Bproduct%5D=${Uri.encodeQueryComponent(kPlexProduct)}',
  );

  void close() => _dio.close(force: true);

  static String _platform() => switch (defaultTargetPlatform) {
    TargetPlatform.iOS => 'iOS',
    TargetPlatform.android => 'Android',
    TargetPlatform.macOS => 'macOS',
    TargetPlatform.windows => 'Windows',
    TargetPlatform.linux => 'Linux',
    TargetPlatform.fuchsia => 'Fuchsia',
  };
}

/// One PIN on plex.tv. Its [code] is not a secret worth a log either: never
/// printed.
@immutable
class PlexTvPin {
  const PlexTvPin({required this.id, required this.code, this.expiresAt});

  /// The PIN in plex.tv's answer, or null when the answer has none.
  static PlexTvPin? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final code = json['code'];
    if (id is! int || code is! String || code.isEmpty) return null;
    final expiresAt = json['expiresAt'];
    return PlexTvPin(
      id: id,
      code: code,
      expiresAt: expiresAt is String ? DateTime.tryParse(expiresAt) : null,
    );
  }

  final int id;
  final String code;

  /// When plex.tv lets it go, when it said.
  final DateTime? expiresAt;

  @override
  String toString() => 'PlexTvPin($id)';
}

/// plex.tv no longer knows the PIN: it expired before anyone approved it.
class PlexTvPinExpired implements Exception {
  const PlexTvPinExpired();

  @override
  String toString() => 'PlexTvPinExpired';
}
