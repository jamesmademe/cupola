/// A media server's item as a last drawing keeps it: everything a row draws
/// and an opening reads, nothing that is a way in.
///
/// The artwork is kept as the **paths** the server gave (`posterPath`,
/// `backdropPath`), which its connection's client turns into an address when
/// the picture is drawn (`imageFor`): a Jellyfin behind a gateway puts its
/// key in the address it builds, and that address is never kept. A path that
/// itself carries a credential in its query is dropped, and the row draws its
/// glyph.
///
/// The synopsis and the picture's frame (`overview`, `video`) are not kept:
/// no row of the Home draws them and no opening reads them (the item's page
/// reads its own). What the Media page opens a movie or a series by, the
/// external ids, is kept.
library;

import 'package:cupola/core/last_known/stored_image.dart';
import 'package:cupola/features/home/data/last_known/stored_fields.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';

Map<String, Object?> streamItemToJson(StreamItem item) => {
  'id': item.id,
  'title': item.title,
  'subtitle': ?item.subtitle,
  'kind': item.kind.name,
  'posterPath': ?_keptPath(item.posterPath),
  'backdropPath': ?_keptPath(item.backdropPath),
  'year': ?item.year,
  'runtimeMs': ?item.runtimeMs,
  'isPlayed': item.isPlayed,
  'resumeOffsetMs': ?item.resumeOffsetMs,
  'unplayedChildCount': ?item.unplayedChildCount,
  if (!item.externalIds.isEmpty)
    'externalIds': {
      'tmdb': ?item.externalIds.tmdb,
      'tvdb': ?item.externalIds.tvdb,
      'imdb': ?item.externalIds.imdb,
    },
  'seasonNumber': ?item.seasonNumber,
  'episodeNumber': ?item.episodeNumber,
};

/// [json] read back; null for an item this version cannot read whole.
StreamItem? streamItemFromJson(Object? json) {
  final fields = StoredFields(json);
  final id = fields.text('id', required: true);
  final title = fields.text('title');
  final kind = fields.named(StreamItemKind.values, 'kind', required: true);
  final isPlayed = fields.flag('isPlayed', required: true);
  final ids = fields.record('externalIds');
  final item = StreamItem(
    id: id ?? '',
    title: title ?? '',
    subtitle: fields.text('subtitle'),
    kind: kind ?? StreamItemKind.other,
    posterPath: fields.text('posterPath'),
    backdropPath: fields.text('backdropPath'),
    year: fields.whole('year'),
    runtimeMs: fields.whole('runtimeMs'),
    isPlayed: isPlayed ?? false,
    resumeOffsetMs: fields.whole('resumeOffsetMs'),
    unplayedChildCount: fields.whole('unplayedChildCount'),
    externalIds: ids == null
        ? StreamExternalIds.none
        : StreamExternalIds(
            tmdb: ids.text('tmdb'),
            tvdb: ids.text('tvdb'),
            imdb: ids.text('imdb'),
          ),
    seasonNumber: fields.whole('seasonNumber'),
    episodeNumber: fields.whole('episodeNumber'),
  );
  if (title == null) return null;
  return fields.isBroken ? null : item;
}

String? _keptPath(String? path) {
  if (path == null || path.isEmpty) return null;
  return StoredImage.carriesCredential(path) ? null : path;
}
