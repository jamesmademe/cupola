import 'package:cupola/features/movies/domain/models/radarr_collection.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/domain/stream_server_client.dart';

/// The collections worth finishing, the nearest to whole first: Radarr holds
/// a movie of each and misses another. Ties go to the one that holds more,
/// then by name, so the atrium does not change its mind between two reads.
List<RadarrCollection> collectionsToComplete(
  Iterable<RadarrCollection> collections,
) {
  final open = [
    for (final collection in collections)
      if (collection.tmdbId > 0 &&
          collection.held > 0 &&
          collection.missing > 0)
        collection,
  ];
  int total(RadarrCollection c) => c.held + c.missing;
  open.sort((a, b) {
    final nearer = (b.held * total(a)).compareTo(a.held * total(b));
    if (nearer != 0) return nearer;
    final more = b.held.compareTo(a.held);
    if (more != 0) return more;
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  });
  return open;
}

/// What TMDB can recommend from: the title the household finished last,
/// across every media server, among those that carry a TMDB id.
///
/// [StreamWatched.item] is a movie or a series; anything else (a music video,
/// a home movie) has no recommendations to ask for.
({StreamItem item, int tmdbId, String mediaType})? latestRecommendable(
  Iterable<List<StreamWatched>> servers,
) {
  final watched = [for (final server in servers) ...server]
    ..sort((a, b) => b.playedAt.compareTo(a.playedAt));
  for (final (:item, playedAt: _) in watched) {
    final tmdbId = int.tryParse(item.externalIds.tmdb ?? '');
    if (tmdbId == null || tmdbId <= 0) continue;
    final mediaType = switch (item.kind) {
      StreamItemKind.movie => 'movie',
      StreamItemKind.series => 'tv',
      _ => null,
    };
    if (mediaType != null) {
      return (item: item, tmdbId: tmdbId, mediaType: mediaType);
    }
  }
  return null;
}
