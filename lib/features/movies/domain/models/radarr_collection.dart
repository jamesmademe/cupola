import 'package:cupola/core/utils/dynamic_map_utils.dart';

/// A TMDB collection as Radarr keeps it (`GET /api/v3/collection`): which of
/// its movies the library holds.
///
/// Radarr lists a collection once a movie of it is in the library, and keeps
/// the parts it does not hold beside the ones it does.
class RadarrCollection {
  const RadarrCollection({
    required this.tmdbId,
    required this.title,
    this.movies = const [],
  });

  final int tmdbId;
  final String title;
  final List<RadarrCollectionMovie> movies;

  /// The movies anyone could still add: the excluded ones are a choice.
  Iterable<RadarrCollectionMovie> get parts =>
      movies.where((movie) => !movie.isExcluded);

  int get held => parts.where((movie) => movie.isExisting).length;

  int get missing => parts.where((movie) => !movie.isExisting).length;

  factory RadarrCollection.fromJson(Map<String, dynamic> json) =>
      RadarrCollection(
        tmdbId: intOrNull(json['tmdbId']) ?? 0,
        title: '${json['title'] ?? ''}',
        movies: [
          if (json['movies'] case final List movies)
            for (final movie in movies.whereType<Map>())
              RadarrCollectionMovie.fromJson(movie.cast<String, dynamic>()),
        ],
      );
}

class RadarrCollectionMovie {
  const RadarrCollectionMovie({
    required this.tmdbId,
    required this.title,
    this.isExisting = false,
    this.isExcluded = false,
  });

  final int tmdbId;
  final String title;

  /// In the library, with a file or not.
  final bool isExisting;

  /// On Radarr's list of movies not to add.
  final bool isExcluded;

  factory RadarrCollectionMovie.fromJson(Map<String, dynamic> json) =>
      RadarrCollectionMovie(
        tmdbId: intOrNull(json['tmdbId']) ?? 0,
        title: '${json['title'] ?? ''}',
        isExisting: json['isExisting'] == true,
        isExcluded: json['isExcluded'] == true,
      );
}
