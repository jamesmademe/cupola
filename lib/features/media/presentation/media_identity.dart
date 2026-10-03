import 'package:cupola/core/models/rating_source.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/features/discover/domain/models/discover_detail_model.dart';
import 'package:cupola/features/discover/presentation/discover_detail_view_model.dart';
import 'package:cupola/features/media/domain/media_copies.dart';
import 'package:cupola/features/media/domain/media_reading.dart';
import 'package:cupola/features/media/domain/media_rows.dart';
import 'package:cupola/features/media/domain/quality_words.dart';

/// Who the title is: the identity layer of the page.
///
/// TMDB's record through the first Seerr that answered, else the first arr
/// copy's own record: a household without Seerr still sees its film, its
/// studio in place of the credits.
class MediaIdentity {
  const MediaIdentity({
    required this.title,
    this.year,
    this.runtime,
    this.genres = const [],
    this.overview = '',
    this.posterUrl,
    this.backdropUrl,
    this.directors = const [],
    this.writers = const [],
    this.studios = const [],
    this.cast = const [],
    this.collection,
    this.videos = const [],
    this.tmdbScore,
  });

  /// TMDB's record, as Seerr answered it.
  factory MediaIdentity.fromSeerr(MediaSeerrRecord record) {
    final model = DiscoverDetailViewModel.fromResponse(record.details);
    return MediaIdentity(
      title: model.title,
      year: model.year.isEmpty ? null : model.year,
      runtime: model.runtimeStr,
      genres: model.genresList,
      overview: model.overview,
      posterUrl: model.posterUrl.isEmpty ? null : model.posterUrl,
      backdropUrl: model.backdropUrl,
      directors: model.directors,
      writers: model.writers,
      studios: model.studios,
      cast: model.cast,
      collection: model.collection,
      videos: model.playableVideos,
      tmdbScore: model.voteAverage,
    );
  }

  final String title;
  final String? year;
  final String? runtime;
  final List<String> genres;
  final String overview;
  final String? posterUrl;
  final String? backdropUrl;
  final List<String> directors;
  final List<String> writers;
  final List<String> studios;
  final List<DiscoverCastMember> cast;
  final CollectionInfo? collection;
  final List<RelatedVideo> videos;

  /// TMDB's score, when Seerr gave one.
  final double? tmdbScore;

  /// The line under the title: who made it, when, how long, what it is.
  /// `Ian Hubert · 2012 · 12 min · Science fiction`.
  String get metaLine => [
    if (directors.isNotEmpty) directors.first,
    ?year,
    if ((runtime ?? '').isNotEmpty) runtime!,
    if (genres.isNotEmpty) genres.first,
  ].join(' · ');

  /// The credits under the overview: `Directed by …` · `written by …` ·
  /// the studios.
  String get creditsLine => [
    if (directors.isNotEmpty) 'Directed by ${directors.join(', ')}',
    if (writers.isNotEmpty) 'written by ${writers.join(', ')}',
    ...studios,
  ].join(' · ');

  /// The identity [rows] carry: the first Seerr's that answered, else the
  /// first arr copy's own record, else null while nothing has answered.
  static MediaIdentity? of(List<MediaRow> rows) {
    for (final row in rows) {
      if (row case MediaConnectionRow(
        reading: MediaReadingAnswered(:final answer),
      ) when answer.value is MediaSeerrRecord) {
        return MediaIdentity.fromSeerr(answer.value as MediaSeerrRecord);
      }
    }
    for (final row in rows) {
      if (row case MediaConnectionRow(
        reading: MediaReadingAnswered(:final answer),
      )) {
        switch (answer.value) {
          case MediaRadarrCopy(:final movie?):
            return MediaIdentity(
              title: movie.title,
              year: movie.year > 0 ? '${movie.year}' : null,
              runtime: formatRuntimeMinutes(movie.runtime),
              genres: movie.genres,
              overview: movie.overview ?? '',
              posterUrl: _remoteImage(movie.images, 'poster'),
              backdropUrl: _remoteImage(movie.images, 'fanart'),
              studios: [?movie.studio],
            );
          case MediaSonarrCopy(:final series?):
            return MediaIdentity(
              title: series.title,
              year: series.year > 0 ? '${series.year}' : null,
              genres: series.genres,
              overview: series.overview ?? '',
              posterUrl: _remoteImage(series.images, 'poster'),
              backdropUrl: _remoteImage(series.images, 'fanart'),
              studios: [?series.network],
            );
        }
      }
    }
    return null;
  }
}

/// The public artwork an arr's record links for [coverType]: TMDB's or
/// TVDB's own address, which needs no key, unlike the arr's local copy.
String? _remoteImage(List<dynamic> images, String coverType) {
  for (final image in images.whereType<Map>()) {
    if (image['coverType'] == coverType) {
      final url = '${image['remoteUrl'] ?? ''}';
      if (url.startsWith('http')) return url;
    }
  }
  return null;
}

/// The four scores of the page, each with its source, `null` for one that
/// has no figure: it reads `—`, never 0. Never one aggregate.
typedef MediaScores = ({
  double? tmdb,
  double? imdb,
  int? rottenTomatoes,
  int? metacritic,
});

/// The scores [rows] carry: an arr's record carries all four for a title it
/// holds; otherwise TMDB's through Seerr.
MediaScores mediaScoresOf(List<MediaRow> rows, MediaIdentity? identity) {
  List<RatingSource>? arr;
  for (final row in rows) {
    if (row case MediaConnectionRow(
      reading: MediaReadingAnswered(:final answer),
    )) {
      arr ??= switch (answer.value) {
        MediaRadarrCopy(:final movie?) => movie.ratings,
        MediaSonarrCopy(:final series?) => series.ratings,
        _ => null,
      };
    }
  }
  double? score(String name) {
    for (final rating in arr ?? const <RatingSource>[]) {
      if (rating.name.toLowerCase() == name.toLowerCase() && rating.value > 0) {
        return rating.value;
      }
    }
    return null;
  }

  return (
    tmdb: score('tmdb') ?? identity?.tmdbScore,
    imdb: score('imdb'),
    rottenTomatoes: score('rottenTomatoes')?.round(),
    metacritic: score('metacritic')?.round(),
  );
}

/// The format marks beside the meta line: `4K` when a copy is 2160p, and the
/// dynamic range a media server reports (`HDR10`, `Dolby Vision`).
List<String> mediaFormatMarks(List<MediaRow> rows) {
  var uhd = false;
  String? range;
  for (final row in rows) {
    if (row case MediaConnectionRow(
      reading: MediaReadingAnswered(:final answer),
    )) {
      switch (answer.value) {
        case MediaRadarrCopy(:final movie?)
            when isUhdQuality(movie.movieFile?.qualityName):
          uhd = true;
        case MediaStreamCopy(:final item?):
          if (item.video?.resolution == '2160p') uhd = true;
          range ??= item.video?.range;
      }
    }
  }
  return [if (uhd) '4K', ?range];
}
