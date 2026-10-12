import 'package:flutter/foundation.dart';

import 'package:cupola/core/utils/image_utils.dart';
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
///  * [StoredArrImage]: an address on an arr's own server, drawn with that
///    connection's key and access headers, and only at that connection's own
///    address;
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
      'arr' => switch ((service(), text('connection'), text('url'))) {
        (final service?, final connection?, final url?) => StoredArrImage(
          service: service,
          connectionId: connection,
          url: url,
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

  /// An [ImageSource] as it can be kept: a public address as it is, an
  /// address on [service]'s own server by [connectionId] (headers dropped,
  /// put back when drawn). Null when it cannot be kept: an empty address, a
  /// credential in the address itself (SABnzbd's and Jellyfin's query keys),
  /// or headers with no connection to put them back from.
  static StoredImage? ofSource(
    ImageSource source, {
    ServiceKey? service,
    String? connectionId,
  }) {
    final url = source.url;
    if (url.isEmpty || carriesCredential(url)) return null;
    if (source.headers == null || source.headers!.isEmpty) {
      return StoredUrl(url);
    }
    if (service == null || connectionId == null || connectionId.isEmpty) {
      return null;
    }
    return StoredArrImage(
      service: service,
      connectionId: connectionId,
      url: url,
    );
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
    required this.url,
  });

  final ServiceKey service;
  final String connectionId;
  final String url;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'arr',
    'service': service.name,
    'connection': connectionId,
    'url': url,
  };

  @override
  bool operator ==(Object other) =>
      other is StoredArrImage &&
      other.service == service &&
      other.connectionId == connectionId &&
      other.url == url;

  @override
  int get hashCode => Object.hash(service, connectionId, url);
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

/// The picture with nothing to draw.
const ImageSource noImage = (url: '', headers: null);
