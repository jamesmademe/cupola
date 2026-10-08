import 'package:cupola/core/models/rating_source.dart';

class MediaPreview {
  final int id;
  final String title;
  final String? posterPath;
  final String? overview;
  final String? releaseDate;
  final String mediaType; // 'movie' or 'tv'
  final double? voteAverage;

  /// How many people TMDB's [voteAverage] is the average of; null when the
  /// answer did not say.
  final int? voteCount;

  /// What Seerr holds of this title (`mediaInfo`: its status, its 4K status,
  /// the downloads it forwards), as Seerr sent it; null when Seerr holds
  /// nothing. Read through `seerrCatalogStatus`, never directly.
  final Map<String, dynamic>? mediaInfo;

  const MediaPreview({
    required this.id,
    required this.title,
    this.posterPath,
    this.overview,
    this.releaseDate,
    required this.mediaType,
    this.voteAverage,
    this.voteCount,
    this.mediaInfo,
  });

  /// TMDB's average as a list draws it: null when nobody rated the title or
  /// too few did (`ratingWorthShowing`).
  double? get tmdbScore => ratingWorthShowing(voteAverage, votes: voteCount);

  factory MediaPreview.fromJson(
    Map<String, dynamic> json, {
    String? forcedMediaType,
  }) {
    // Handle both 'title' (movies) and 'name' (tv)
    final title = json['title'] ?? json['name'] ?? 'Unknown';
    // Handle both 'release_date' and 'first_air_date' (TMDB/Seerr usually use snake_case or camelCase depending on endpoint,
    // but the previous code used camelCase accessors like json['releaseDate'] suggesting the API client might not be normalizing it,
    // OR the previous code was guessing.
    // Seerr API v1 usually returns mixed. Let's handle both camel and snake for safety.)
    final releaseDate =
        json['releaseDate'] ??
        json['release_date'] ??
        json['firstAirDate'] ??
        json['first_air_date'];
    final posterPath = json['posterPath'] ?? json['poster_path'];
    final overview = json['overview'];
    final voteAverage = (json['voteAverage'] ?? json['vote_average'])
        ?.toDouble();
    final voteCount = (json['voteCount'] ?? json['vote_count'])?.toInt();
    final mediaInfo = json['mediaInfo'];

    // Determine media type
    var mediaType = forcedMediaType ?? json['mediaType'] ?? json['media_type'];
    if (mediaType == null) {
      // Infere based on keys if missing
      if (json.containsKey('name') ||
          json.containsKey('firstAirDate') ||
          json.containsKey('first_air_date')) {
        mediaType = 'tv';
      } else {
        mediaType = 'movie'; // Default to movie
      }
    }

    return MediaPreview(
      id: json['id'],
      title: title,
      posterPath: posterPath,
      overview: overview,
      releaseDate: releaseDate,
      mediaType: mediaType,
      voteAverage: voteAverage,
      voteCount: voteCount,
      mediaInfo: mediaInfo is Map ? Map<String, dynamic>.from(mediaInfo) : null,
    );
  }

  String get year {
    if (releaseDate != null && releaseDate!.length >= 4) {
      return releaseDate!.substring(0, 4);
    }
    return '';
  }
}
