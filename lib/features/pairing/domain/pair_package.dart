import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/features/discover/domain/seerr_sign_in.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/connection_address.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

/// The kind of device a package comes from, as the receiving screen names it:
/// "From your iPhone".
///
/// A kind and not the device's own name: iOS hands an app the name its owner
/// gave the phone only with an entitlement Cupola has no reason to ask for,
/// and "your iPhone" is what the person holding both devices calls it anyway.
enum PairDevice {
  iphone('your iPhone'),
  ipad('your iPad'),
  mac('your Mac'),
  androidPhone('your Android phone'),
  androidTablet('your Android tablet'),
  windows('your PC'),
  linux('your computer');

  const PairDevice(this.phrase);

  /// `your iPhone`.
  final String phrase;

  /// This device, on [platform], [tablet] when its shorter side is a
  /// tablet's.
  static PairDevice of(TargetPlatform platform, {required bool tablet}) =>
      switch (platform) {
        TargetPlatform.iOS => tablet ? ipad : iphone,
        TargetPlatform.android => tablet ? androidTablet : androidPhone,
        TargetPlatform.macOS => mac,
        TargetPlatform.windows => windows,
        _ => linux,
      };
}

/// What one device hands another when the other copies everything: every
/// connection with its secrets, and the certificate each of their origins is
/// trusted with.
///
/// **What does not travel**, and why:
/// * a Seerr account's session. A session is one device's: the new device
///   signs in again with the same account, which keeps its kind, login and
///   name (`SeerrAccountSignIn.signedOut`).
/// * Cupola's Plex identity (`SettingsModel.plexClientId`). It names the
///   install, and two installs that share one read as one device to Plex.
/// * a secret the sending device could not read from its own secure storage.
///   The connection travels without it, marked ([ServiceInstance.unreadSecret]),
///   so the receiving screen can say so.
/// * how the app looks and what the Home shows: those are the device's.
///
/// Sealed before it leaves (`PairCipher`), so the JSON here is only ever read
/// by the device that holds the link.
@immutable
final class PairPackage {
  const PairPackage({
    required this.from,
    required this.connections,
    this.certificates = const {},
    this.unknown = 0,
  });

  /// Everything [settings] holds that another device can use: each
  /// connection with an address, in order, and the pin of every origin they
  /// are reached at.
  factory PairPackage.everything(
    SettingsModel settings, {
    required PairDevice from,
  }) {
    final carried = [
      for (final instance in settings.instances)
        if (instance.url.isNotEmpty) _travelling(instance),
    ];
    return PairPackage(
      from: from,
      connections: carried,
      certificates: {
        for (final instance in carried)
          for (final address in instance.addresses)
            ?UrlUtils.certOrigin(address): ?settings.pinForUrl(address),
      },
    );
  }

  /// The version of the JSON this build writes and reads.
  static const version = 1;

  /// How much a package may hold once unpacked: far more than any household's
  /// connections, far less than a device should be made to hold in memory.
  static const maxBytes = 2 * 1024 * 1024;

  /// The device it comes from.
  final PairDevice from;

  /// The connections, as the sending device has them: its labels, secrets
  /// included, a Seerr account signed out. Their ids are placeholders: the
  /// receiving device mints its own (`PairPlan`).
  final List<ServiceInstance> connections;

  /// The pins of their origins, as `SettingsModel.trustedCertificates` keeps
  /// them: origin to lowercase SHA-256.
  final Map<String, String> certificates;

  /// Connections of a service this build does not know, left out on reading:
  /// a newer Cupola on the sending device.
  final int unknown;

  static ServiceInstance _travelling(ServiceInstance instance) {
    final account = instance.account;
    return account == null || !account.isSignedIn
        ? instance
        : instance.copyWith(account: account.signedOut);
  }

  Map<String, Object?> toJson() => {
    'v': version,
    'from': from.name,
    'connections': [for (final c in connections) _connectionToJson(c)],
    'certificates': certificates,
  };

  /// The JSON, gzipped: what is sealed.
  Uint8List encode() =>
      Uint8List.fromList(gzip.encode(utf8.encode(jsonEncode(toJson()))));

  /// The package [bytes] hold, as [encode] wrote them. Throws a
  /// [FormatException] for anything that is not one, and a
  /// [PairPackageNewer] for one a later version wrote.
  static PairPackage decode(List<int> bytes) {
    final List<int> clear;
    try {
      clear = _gunzipCapped(bytes);
    } on FormatException {
      rethrow;
    } on Object {
      throw const FormatException('not a gzip stream');
    }
    return fromJson(jsonDecode(utf8.decode(clear)));
  }

  /// The package [json] describes. Strict: a field of the wrong type, an
  /// address that is not one, a pin that is not a fingerprint, is a
  /// [FormatException]; the device that sealed it wrote none of those.
  static PairPackage fromJson(Object? json) {
    if (json is! Map<String, Object?>) throw const FormatException('package');
    final v = json['v'];
    if (v is! int) throw const FormatException('version');
    if (v > version) throw PairPackageNewer(v);
    if (v != version) throw const FormatException('version');

    final from = PairDevice.values.asNameMap()[json['from']];
    if (from == null) throw const FormatException('from');

    final rawConnections = json['connections'];
    if (rawConnections is! List || rawConnections.length > 256) {
      throw const FormatException('connections');
    }
    final services = ServiceKey.values.asNameMap();
    final connections = <ServiceInstance>[];
    var unknown = 0;
    for (final raw in rawConnections) {
      if (raw is! Map<String, Object?>) {
        throw const FormatException('connection');
      }
      final service = services[raw['service']];
      if (service == null) {
        unknown++;
        continue;
      }
      connections.add(_connectionFromJson(raw, service, connections.length));
    }

    final rawCertificates = json['certificates'] ?? const <String, Object?>{};
    if (rawCertificates is! Map<String, Object?>) {
      throw const FormatException('certificates');
    }
    final certificates = <String, String>{};
    for (final MapEntry(:key, :value) in rawCertificates.entries) {
      if (UrlUtils.certOrigin(key) != key ||
          value is! String ||
          !_fingerprint.hasMatch(value)) {
        throw const FormatException('certificate');
      }
      certificates[key] = value;
    }

    return PairPackage(
      from: from,
      connections: connections,
      certificates: certificates,
      unknown: unknown,
    );
  }

  static final _fingerprint = RegExp(r'^[0-9a-f]{64}$');

  /// A connection without its id: the receiving device mints its own, since
  /// the sending device's may already name another connection there.
  static Map<String, Object?> _connectionToJson(ServiceInstance c) => {
    'service': c.service.name,
    if (c.label.isNotEmpty) 'label': c.label,
    'url': c.url,
    if (c.credential.isNotEmpty) 'credential': c.credential,
    if (c.username.isNotEmpty) 'username': c.username,
    if (c.viewerId.isNotEmpty) 'viewerId': c.viewerId,
    'access': ?_accessToJson(c.access),
    if (c.away case final away?)
      'away': {'url': away.url, 'access': ?_accessToJson(away.access)},
    if (c.account case final account?)
      'account': {
        'kind': account.kind.name,
        if (account.login.isNotEmpty) 'login': account.login,
        'userId': account.userId,
        if (account.displayName.isNotEmpty) 'displayName': account.displayName,
        'permissions': account.permissions,
      },
    if (c.unreadSecret case final unread?) 'unread': unread.name,
  };

  static ServiceInstance _connectionFromJson(
    Map<String, Object?> raw,
    ServiceKey service,
    int index,
  ) {
    final url = _address(raw['url']);
    final away = switch (raw['away']) {
      null => null,
      final Map<String, Object?> a => ConnectionAddress(
        url: _address(a['url']),
        access: _accessFromJson(a['access']),
      ),
      _ => throw const FormatException('away'),
    };
    final account = switch (raw['account']) {
      null => null,
      final Map<String, Object?> a when service == ServiceKey.seerr =>
        SeerrAccountSignIn(
          kind:
              SeerrAccountKind.byName(_text(a['kind'])) ??
              (throw const FormatException('account kind')),
          login: _text(a['login']),
          userId: _int(a['userId']),
          displayName: _text(a['displayName']),
          permissions: _int(a['permissions']),
        ),
      _ => throw const FormatException('account'),
    };
    final credential = _text(raw['credential']);
    if (account != null && credential.isNotEmpty) {
      throw const FormatException('a key and an account');
    }
    final unread = switch (raw['unread']) {
      null => null,
      final String name =>
        UnreadSecret.values.asNameMap()[name] ??
            (throw const FormatException('unread')),
      _ => throw const FormatException('unread'),
    };
    final instance = ServiceInstance(
      id: '${service.routeParam}-paired-$index',
      service: service,
      label: _text(raw['label']),
      url: url,
      credential: credential,
      username: _text(raw['username']),
      viewerId: _text(raw['viewerId']),
      access: _accessFromJson(raw['access']),
      account: account,
      away: away,
    );
    return unread == null ? instance : instance.withUnreadSecret(unread);
  }

  static Map<String, Object?>? _accessToJson(ConnectionAccess access) =>
      switch (access) {
        NoAccess() => null,
        CloudflareServiceToken(:final clientId, :final clientSecret) => {
          'kind': AccessKind.cloudflare.name,
          'clientId': clientId,
          'clientSecret': clientSecret,
        },
        ProxyPassword(:final username, :final password) => {
          'kind': AccessKind.password.name,
          'username': username,
          'password': password,
        },
        CustomHeaders(:final entries) => {
          'kind': AccessKind.custom.name,
          'headers': [
            for (final e in entries) {'name': e.name, 'value': e.value},
          ],
        },
      };

  static ConnectionAccess _accessFromJson(Object? raw) {
    if (raw == null) return const NoAccess();
    if (raw is! Map<String, Object?>) throw const FormatException('access');
    return switch (AccessKind.byName(_text(raw['kind']))) {
      AccessKind.cloudflare => CloudflareServiceToken(
        clientId: _text(raw['clientId']),
        clientSecret: _text(raw['clientSecret']),
      ),
      AccessKind.password => ProxyPassword(
        username: _text(raw['username']),
        password: _text(raw['password']),
      ),
      AccessKind.custom => CustomHeaders([
        for (final header in _list(raw['headers']))
          if (header is Map<String, Object?>)
            (name: _text(header['name']), value: _text(header['value']))
          else
            throw const FormatException('header'),
      ]),
      AccessKind.none => const NoAccess(),
      null => throw const FormatException('access kind'),
    };
  }

  /// An `http` or `https` address with a host: what the sending device saved.
  static String _address(Object? raw) {
    final text = _text(raw);
    final uri = Uri.tryParse(text);
    if (uri == null ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        uri.host.isEmpty) {
      throw const FormatException('address');
    }
    return text;
  }

  static String _text(Object? raw) => switch (raw) {
    null => '',
    final String s when s.length <= 8192 => s,
    _ => throw const FormatException('text'),
  };

  static int _int(Object? raw) => switch (raw) {
    null => 0,
    final int i => i,
    _ => throw const FormatException('number'),
  };

  static List<Object?> _list(Object? raw) => switch (raw) {
    null => const [],
    final List<Object?> l when l.length <= 32 => l,
    _ => throw const FormatException('list'),
  };

  /// [bytes] unzipped, refused past [maxBytes] rather than unpacked whole: the
  /// cap holds while the stream is read, not after.
  static List<int> _gunzipCapped(List<int> bytes) {
    final out = BytesBuilder(copy: false);
    final sink = ByteConversionSink.withCallback((chunk) {
      out.add(chunk);
    });
    final input = gzip.decoder.startChunkedConversion(
      _CappedSink(sink, maxBytes),
    );
    input
      ..add(bytes)
      ..close();
    return out.takeBytes();
  }

  /// Counts only, never a value.
  @override
  String toString() =>
      'PairPackage(from ${from.name}, ${connections.length} connections, '
      '${certificates.length} certificates'
      '${unknown == 0 ? '' : ', $unknown unknown'})';
}

/// A package written by a later Cupola: its [version] says more than this
/// build can read.
final class PairPackageNewer implements Exception {
  const PairPackageNewer(this.version);

  final int version;

  @override
  String toString() => 'PairPackageNewer($version)';
}

final class _CappedSink implements Sink<List<int>> {
  _CappedSink(this._inner, this._cap);

  final ByteConversionSink _inner;
  final int _cap;
  var _seen = 0;

  @override
  void add(List<int> data) {
    _seen += data.length;
    if (_seen > _cap) throw const FormatException('too large');
    _inner.add(data);
  }

  @override
  void close() => _inner.close();
}
