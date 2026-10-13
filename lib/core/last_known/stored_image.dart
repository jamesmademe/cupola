import 'package:flutter/foundation.dart';

import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// A picture as a last drawing keeps it: where it is, never how to get in.
///
/// An [ImageSource] carries the credential its server wants (an arr's
/// `X-Api-Key`, Jellyfin's `Authorization`, Plex's token, a gateway's headers),
/// and none of it may reach the file `LastKnownStore` writes. So a picture is
/// kept as one of three plain shapes, and its headers are put back when it is
/// drawn, from the connection as it is then (`resolveStoredImage`):
///
///  * [StoredUrl]: a public address (TMDB's), drawn as it is;
///  * [StoredArrImage]: a path on an arr's own server, kept by its
///    connection and never by an address: it is drawn at the address that
///    connection is reached at when it is drawn, with that connection's key
///    and that address's access headers, so a drawing kept at home draws
///    away from home too;
///  * [StoredStreamImage]: a path on a media server, which that connection's
///    client turns into an address (`imageFor`) the way it does live, so the
///    address, and the cached picture under it, are the same.
@immutable
sealed class StoredImage {
  const StoredImage();

  /// The JSON a last drawing keeps.
  Map<String, Object?> toJson();

  /// [json] read back, or null for anything this version cannot draw.
  static StoredImage? fromJson(Object? json) {
    if (json is! Map) return null;
    String? text(String key) => switch (json[key]) {
      final String value when value.isNotEmpty => value,
      _ => null,
    };
    ServiceKey? service() =>
        ServiceKey.values.asNameMap()[json['service'] as Object? ?? ''];
    return switch (json['kind']) {
      'url' => switch (text('url')) {
        final url? => StoredUrl(url),
        null => null,
      },
      // A path, never an address: an `arr` picture kept as an address (the
      // shape before the address away) reads as nothing rather than as a
      // picture bound to an origin.
      'arr' => switch ((service(), text('connection'), text('path'))) {
        (final service?, final connection?, final path?) => StoredArrImage(
          service: service,
          connectionId: connection,
          path: path,
        ),
        _ => null,
      },
      'stream' => switch ((service(), text('connection'), text('path'))) {
        (final service?, final connection?, final path?) => StoredStreamImage(
          service: service,
          connectionId: connection,
          path: path,
          width: switch (json['width']) {
            final int width => width,
            _ => null,
          },
        ),
        _ => null,
      },
      _ => null,
    };
  }

  /// An [ImageSource] as it can be kept: a public address as it is, a
  /// picture on [service]'s own server by [connectionId] and its path under
  /// whichever of [addresses] (that connection's, at home and away) it was
  /// built on (headers dropped, put back when drawn). Null when it cannot be
  /// kept: an empty address, a credential in the address itself (SABnzbd's
  /// and Jellyfin's query keys), or headers with no connection, or no address
  /// of it, to put them back from.
  static StoredImage? ofSource(
    ImageSource source, {
    ServiceKey? service,
    String? connectionId,
    Iterable<String> addresses = const [],
  }) {
    final url = source.url;
    if (url.isEmpty || carriesCredential(url)) return null;
    if (source.headers == null || source.headers!.isEmpty) {
      return StoredUrl(url);
    }
    if (service == null || connectionId == null || connectionId.isEmpty) {
      return null;
    }
    final path = _pathUnder(url, addresses);
    if (path == null) return null;
    return StoredArrImage(
      service: service,
      connectionId: connectionId,
      path: path,
    );
  }

  /// What follows the longest of [addresses] that [url] starts with, or null
  /// when it starts with none: the path a picture was asked at, under the
  /// address it was built on (`UrlUtils.buildUrl`), whose own path, if any,
  /// stays with the address.
  static String? _pathUnder(String url, Iterable<String> addresses) {
    String? best;
    var bestLength = -1;
    for (final address in addresses) {
      for (final base in {
        _trimmed(address),
        UrlUtils.normalizeBaseUrl(address),
      }) {
        if (base.isEmpty || base.length <= bestLength) continue;
        if (!url.startsWith(base)) continue;
        final rest = url.substring(base.length);
        if (rest.isNotEmpty && !rest.startsWith('/') && !rest.startsWith('?')) {
          continue;
        }
        best = rest;
        bestLength = base.length;
      }
    }
    return best == null || best.isEmpty ? null : best;
  }

  static String _trimmed(String address) {
    var trimmed = address.trim();
    while (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  /// Whether [url] carries a key in its query, as SABnzbd's `apikey`, a
  /// Jellyfin behind a gateway's `ApiKey` and a Plex `X-Plex-Token` would.
  static bool carriesCredential(String url) {
    final query = Uri.tryParse(url)?.queryParameters.keys ?? const <String>[];
    return query.any((key) => _credentialKeys.contains(key.toLowerCase()));
  }

  static const _credentialKeys = {
    'apikey',
    'api_key',
    'x-plex-token',
    'token',
    'access_token',
  };
}

final class StoredUrl extends StoredImage {
  const StoredUrl(this.url);

  final String url;

  @override
  Map<String, Object?> toJson() => {'kind': 'url', 'url': url};

  @override
  bool operator ==(Object other) => other is StoredUrl && other.url == url;

  @override
  int get hashCode => url.hashCode;
}

final class StoredArrImage extends StoredImage {
  const StoredArrImage({
    required this.service,
    required this.connectionId,
    required this.path,
  });

  final ServiceKey service;
  final String connectionId;

  /// Where the picture is under the connection's address, `/MediaCover/…`
  /// with its query: put after whichever address the connection is reached
  /// at when it is drawn.
  final String path;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'arr',
    'service': service.name,
    'connection': connectionId,
    'path': path,
  };

  @override
  bool operator ==(Object other) =>
      other is StoredArrImage &&
      other.service == service &&
      other.connectionId == connectionId &&
      other.path == path;

  @override
  int get hashCode => Object.hash(service, connectionId, path);
}

final class StoredStreamImage extends StoredImage {
  const StoredStreamImage({
    required this.service,
    required this.connectionId,
    required this.path,
    this.width,
  });

  final ServiceKey service;
  final String connectionId;
  final String path;
  final int? width;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'stream',
    'service': service.name,
    'connection': connectionId,
    'path': path,
    'width': ?width,
  };

  @override
  bool operator ==(Object other) =>
      other is StoredStreamImage &&
      other.service == service &&
      other.connectionId == connectionId &&
      other.path == path &&
      other.width == width;

  @override
  int get hashCode => Object.hash(service, connectionId, path, width);
}

/// Turns a kept picture back into one that can be drawn, with the headers its
/// connection sends today. What a last drawing's codec receives, so a codec
/// never reaches for a client itself.
typedef StoredImageResolver = ImageSource Function(StoredImage image);

/// Turns a picture as drawn into one that can be kept ([StoredImage.ofSource]),
/// against the connections as they are when it is kept: what a last
/// drawing's codec is handed to keep a picture, so a codec never reaches for
/// the settings itself. Null for a picture that cannot be kept.
typedef StoredImageKeeper =
    StoredImage? Function(
      ImageSource source, {
      ServiceKey? service,
      String? connectionId,
    });

/// The picture with nothing to draw.
const ImageSource noImage = (url: '', headers: null);
