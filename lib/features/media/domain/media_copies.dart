import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/features/bazarr/domain/models/bazarr_models.dart';
import 'package:cupola/features/discover/domain/models/discover_detail_model.dart';
import 'package:cupola/features/discover/domain/seerr_arr_server.dart';
import 'package:cupola/features/discover/domain/seerr_media_copy.dart';
import 'package:cupola/features/movies/domain/radarr_status.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/series/domain/models/sonarr_series.dart';
import 'package:cupola/features/series/domain/sonarr_status.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/domain/stream_external_match.dart';

/// What one Radarr holds of a film: its record, or nothing, and what its
/// queue says about it.
class MediaRadarrCopy {
  const MediaRadarrCopy({required this.movie, required this.queue});

  /// Null when Radarr answered and does not track the film: `Not added yet`.
  final RadarrMovie? movie;

  /// This Radarr's queue, read whole, cut short, stale or failed: the badge
  /// waits for it ([MediaStatusInfo] through `radarrMovieStatus`).
  final ArrQueueSnapshot queue;

  bool get isTracked => movie != null;

  /// The copy's status, null while Radarr does not track the film.
  MediaStatusInfo? get status {
    final movie = this.movie;
    if (movie == null) return null;
    return radarrMovieStatus(
      movie,
      queueEntry: queue.entryFor(movie.id),
      queueUnknown: !queue.isWhole,
    );
  }
}

/// What one Sonarr holds of a series: its record, or nothing, and what its
/// queue says about it.
class MediaSonarrCopy {
  const MediaSonarrCopy({required this.series, required this.queue});

  /// Null when Sonarr answered and does not track the series.
  final SonarrSeries? series;

  /// This Sonarr's queue, indexed by series.
  final ArrQueueSnapshot queue;

  bool get isTracked => series != null;

  /// The copy's status, null while Sonarr does not track the series.
  MediaStatusInfo? get status {
    final series = this.series;
    if (series == null) return null;
    return sonarrSeriesStatus(
      series,
      queueEntry: queue.entryFor(series.id),
      queueUnknown: !queue.isWhole,
    );
  }
}

/// What one media server answered about a title, looked up by its ids.
///
/// [StreamLookupOutcome.notVerified] is case f: something with that title
/// whose ids do not match. It is no match, and draws nothing (rule 7).
class MediaStreamCopy {
  const MediaStreamCopy.found(StreamItem this.item)
    : outcome = StreamLookupOutcome.found;

  const MediaStreamCopy.notInLibrary()
    : outcome = StreamLookupOutcome.notInLibrary,
      item = null;

  const MediaStreamCopy.notVerified()
    : outcome = StreamLookupOutcome.notVerified,
      item = null;

  final StreamLookupOutcome outcome;

  /// The verified item, only for [StreamLookupOutcome.found].
  final StreamItem? item;
}

/// What Bazarr holds for one arr copy of a title.
///
/// Bazarr follows one Radarr and one Sonarr, and its ids are theirs: a title
/// is matched to a copy by the copy's id and checked against the copy's path,
/// or its title and year, so the 4K Radarr's film 12 is never read as the
/// other Radarr's film 12.
class MediaBazarrCopy {
  const MediaBazarrCopy({
    required this.arrConnectionId,
    this.movie,
    this.series,
  });

  /// The Radarr or Sonarr connection whose copy Bazarr covers.
  final String arrConnectionId;

  /// The film Bazarr follows, for a film.
  final BazarrMovie? movie;

  /// The series Bazarr follows, for a series.
  final BazarrSeries? series;
}

/// What one Seerr knows of a title: its record, and the arr servers it
/// would place it on.
class MediaSeerrRecord {
  const MediaSeerrRecord({required this.details, this.arrServers});

  /// `/movie/:id` or `/tv/:id`, as Seerr answered: identity, ratings, cast and
  /// the `mediaInfo` the rows read.
  final Map<String, dynamic> details;

  /// Seerr's servers of the arr that holds this kind of title, Radarr's for a
  /// film and Sonarr's for a series; null when they could not be read (an
  /// account without ADMIN, or a failed read): then a copy cannot be bound to
  /// one.
  final List<SeerrArrServer>? arrServers;

  /// Seerr's media row for the title, null when it has no record.
  Map<String, dynamic>? get mediaInfo => mapOrNull(details['mediaInfo']);

  /// TVDB's id for a series, as TMDB's record names it: what Sonarr is asked
  /// by.
  int? get tvdbId {
    final id = intOrNull(mapOrNull(details['externalIds'])?['tvdbId']);
    return id == null || id <= 0 ? null : id;
  }

  /// Whether TMDB's record has a video a viewer can open: the trailer the
  /// page offers ([RelatedVideo.url], as the Seerr page reads it).
  bool get hasTrailer => switch (details['relatedVideos']) {
    final List<dynamic> videos => videos.whereType<Map>().any(
      (video) =>
          RelatedVideo.fromJson(video.cast<String, dynamic>()).url.isNotEmpty,
    ),
    _ => false,
  };

  /// The copies Seerr says an arr holds, the standard one first.
  List<SeerrMediaCopy> get copies => SeerrMediaCopy.fromMediaInfo(mediaInfo);
}
