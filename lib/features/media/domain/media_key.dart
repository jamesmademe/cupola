import 'package:flutter/foundation.dart';

import 'package:cupola/features/stream/domain/models/stream_item.dart';

/// The two kinds of title a canonical Media page is about.
enum MediaKind { movie, tv }

/// Which title a canonical Media page is about: the same title is the same
/// page, from every entry point.
///
/// TMDB's id is the key because it is the one id Seerr, Radarr and the media
/// servers' provider ids all carry. A series that Sonarr v3 tracks, with no
/// Seerr to name its TMDB id, is keyed by TVDB's instead ([MediaKey.tvdb]):
/// that page lives without TMDB's identity layer, from Sonarr's own record.
///
/// One id, never both: the key is a provider family's key, and two keys for
/// one title would read it twice. The other ids are resolved by the page, not
/// carried here.
@immutable
class MediaKey {
  const MediaKey.movie(int this.tmdbId) : kind = MediaKind.movie, tvdbId = null;

  const MediaKey.tv(int this.tmdbId) : kind = MediaKind.tv, tvdbId = null;

  const MediaKey.tvdb(int this.tvdbId) : kind = MediaKind.tv, tmdbId = null;

  final MediaKind kind;

  /// TMDB's id, null only for [MediaKey.tvdb].
  final int? tmdbId;

  /// TVDB's id, set only for [MediaKey.tvdb].
  final int? tvdbId;

  bool get isMovie => kind == MediaKind.movie;

  /// The canonical location: `/media/movie/133701`, `/media/tv/358332`, or
  /// `/media/tv/tvdb/300001`.
  String get location => switch (this) {
    MediaKey(tmdbId: final tmdb?) => '/media/${kind.name}/$tmdb',
    MediaKey(tvdbId: final tvdb) => '/media/tv/tvdb/$tvdb',
  };

  /// The key a canonical location names, or null when [kind] or [id] is not
  /// one: `kind` is `movie` or `tv`, `id` a positive number, and
  /// [byTvdb] marks the `/media/tv/tvdb/:id` form.
  static MediaKey? parse(String kind, String id, {bool byTvdb = false}) {
    final value = int.tryParse(id);
    if (value == null || value <= 0) return null;
    return switch (kind) {
      'movie' when !byTvdb => MediaKey.movie(value),
      'tv' when byTvdb => MediaKey.tvdb(value),
      'tv' => MediaKey.tv(value),
      _ => null,
    };
  }

  /// The page a series has by the ids a source carries: TMDB's when it has
  /// one, else TVDB's (a Sonarr v3 record, a server that knows only TVDB's).
  /// Null with neither.
  static MediaKey? ofSeries({int? tmdbId, int? tvdbId}) =>
      switch ((tmdbId, tvdbId)) {
        (final tmdb?, _) when tmdb > 0 => MediaKey.tv(tmdb),
        (_, final tvdb?) when tvdb > 0 => MediaKey.tvdb(tvdb),
        _ => null,
      };

  /// The page a media server's item has: a movie the server knows by its
  /// TMDB id, a series by its TMDB or TVDB id. Null for anything else (an
  /// episode, a season, a home video with no id), which keeps the server's
  /// own page.
  static MediaKey? ofStreamItem(StreamItem item) {
    final ids = item.externalIds;
    final tmdb = int.tryParse(ids.tmdb ?? '');
    return switch (item.kind) {
      StreamItemKind.movie =>
        tmdb == null || tmdb <= 0 ? null : MediaKey.movie(tmdb),
      StreamItemKind.series => ofSeries(
        tmdbId: tmdb,
        tvdbId: int.tryParse(ids.tvdb ?? ''),
      ),
      _ => null,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is MediaKey &&
      other.kind == kind &&
      other.tmdbId == tmdbId &&
      other.tvdbId == tvdbId;

  @override
  int get hashCode => Object.hash(kind, tmdbId, tvdbId);

  @override
  String toString() => 'MediaKey($location)';
}
