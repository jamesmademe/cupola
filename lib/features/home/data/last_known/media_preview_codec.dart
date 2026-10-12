/// A catalogue title as a last drawing keeps it: what its poster draws.
///
/// `MediaPreview.fromJson` reads Seerr's own answer, and that answer is not
/// what a file should hold: its `mediaInfo` is Seerr's whole record of the
/// title (the requests made for it, who made them, the downloads it follows).
/// What a poster draws of it is two codes, the standard copy's state and the
/// 4K copy's, and those two are all that is kept. The download Seerr follows
/// is what runs (the ring of a title downloading), and a drawing does not run:
/// the poster of a title on its way reads `On its way`, as the requester's
/// words have it.
///
/// The overview is not kept: no poster draws it.
library;

import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';

Map<String, Object?> mediaPreviewToJson(MediaPreview item) {
  final status = intOrNull(item.mediaInfo?['status']);
  final status4k = intOrNull(item.mediaInfo?['status4k']);
  return {
    'id': item.id,
    'title': item.title,
    'mediaType': item.mediaType,
    'posterPath': ?item.posterPath,
    'releaseDate': ?item.releaseDate,
    'voteAverage': ?item.voteAverage,
    'voteCount': ?item.voteCount,
    if (status != null || status4k != null)
      'mediaInfo': {'status': ?status, 'status4k': ?status4k},
  };
}

/// [json] read back; null for a title this version cannot read whole.
MediaPreview? mediaPreviewFromJson(Object? json) {
  if (json is! Map) return null;
  final id = json['id'];
  final title = json['title'];
  final mediaType = json['mediaType'];
  if (id is! int || title is! String || mediaType is! String) return null;
  String? text(String key) => switch (json[key]) {
    final String value when value.isNotEmpty => value,
    _ => null,
  };
  final info = json['mediaInfo'];
  return MediaPreview(
    id: id,
    title: title,
    mediaType: mediaType,
    posterPath: text('posterPath'),
    releaseDate: text('releaseDate'),
    voteAverage: switch (json['voteAverage']) {
      final num value => value.toDouble(),
      _ => null,
    },
    voteCount: switch (json['voteCount']) {
      final int value => value,
      _ => null,
    },
    mediaInfo: info is Map
        ? {
            for (final key in const ['status', 'status4k'])
              if (info[key] case final int code) key: code,
          }
        : null,
  );
}
