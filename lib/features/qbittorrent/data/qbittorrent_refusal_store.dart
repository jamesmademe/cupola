import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:cupola/features/settings/data/settings_service.dart';

/// A refused qBittorrent sign-in, as kept for one connection beyond the life
/// of the client that met it.
///
/// [kind] is the client's own name for the refusal. [credentials] is the
/// [qbittorrentCredentialMark] of what was refused: a later client of the same
/// connection holds the refusal only while it would send the very same thing,
/// so new credentials lift it on their own.
typedef QbittorrentStoredRefusal = ({String kind, String credentials});

/// Where each connection's refused qBittorrent sign-in is kept.
///
/// qBittorrent bans an address after five failed sign-ins, for an hour by
/// default. A refusal held only by a client object is forgotten by every new
/// client: the app's next launch, or a check run in the background, which
/// builds clients of its own each time. Kept here, **per connection**, a
/// refused sign-in stays refused for every client of that connection until its
/// credentials change or a person asks again, and a refusal on one connection
/// holds nothing on another.
abstract interface class QbittorrentRefusalStore {
  /// The refusal held for [connectionId], or null. Never throws: a store that
  /// cannot be read holds nothing.
  Future<QbittorrentStoredRefusal?> read(String connectionId);

  /// Holds [refusal] for [connectionId]. Never throws.
  Future<void> write(String connectionId, QbittorrentStoredRefusal refusal);

  /// Forgets what is held for [connectionId]. Never throws.
  Future<void> clear(String connectionId);
}

/// What a client of one connection presents at the login, reduced to a
/// SHA-256 mark: the address, the username, the password and the access
/// headers sent in front of it. A mark, never the values, so the store holds
/// no second copy of a secret; it is compared, never shown or logged.
String qbittorrentCredentialMark({
  required String baseUrl,
  required String? username,
  required String? password,
  Map<String, String> accessHeaders = const {},
}) {
  final headers =
      accessHeaders.entries
          .map((e) => '${e.key.toLowerCase()}:${e.value}')
          .toList()
        ..sort();
  final material = [baseUrl, username ?? '', password ?? '', ...headers];
  return sha256.convert(utf8.encode(material.join('\u0000'))).toString();
}

/// Held in memory, for the life of the app: the default, and enough for every
/// client of a connection inside one run to agree.
class MemoryQbittorrentRefusalStore implements QbittorrentRefusalStore {
  final Map<String, QbittorrentStoredRefusal> _held = {};

  @override
  Future<QbittorrentStoredRefusal?> read(String connectionId) async =>
      _held[connectionId];

  @override
  Future<void> write(
    String connectionId,
    QbittorrentStoredRefusal refusal,
  ) async => _held[connectionId] = refusal;

  @override
  Future<void> clear(String connectionId) async => _held.remove(connectionId);
}

/// Held in the platform's secure storage, beside the password it was refused
/// for, so it survives a relaunch and is there for a check that runs in the
/// background. The mark is derived from the password, which is why it lives
/// there rather than in the plain preferences, and why removing the connection
/// removes it ([SettingsService.qbittorrentRefusalKey]).
class SecureQbittorrentRefusalStore implements QbittorrentRefusalStore {
  const SecureQbittorrentRefusalStore(this._storage);

  final SecureSettingsStore _storage;

  static String _key(String connectionId) =>
      SettingsService.qbittorrentRefusalKey(connectionId);

  @override
  Future<QbittorrentStoredRefusal?> read(String connectionId) async {
    try {
      final raw = await _storage.read(key: _key(connectionId));
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final kind = decoded['kind'];
      final credentials = decoded['credentials'];
      if (kind is! String || credentials is! String) return null;
      return (kind: kind, credentials: credentials);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(
    String connectionId,
    QbittorrentStoredRefusal refusal,
  ) async {
    try {
      await _storage.write(
        key: _key(connectionId),
        value: jsonEncode({
          'kind': refusal.kind,
          'credentials': refusal.credentials,
        }),
      );
    } catch (_) {
      // Held in the client still; only the next launch would not know.
    }
  }

  @override
  Future<void> clear(String connectionId) async {
    try {
      await _storage.delete(key: _key(connectionId));
    } catch (_) {
      // Nothing to do: a mark that no longer matches lifts itself.
    }
  }
}
