import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/features/bazarr/domain/models/bazarr_models.dart';
import 'package:cupola/features/discover/domain/seerr_arr_server.dart';
import 'package:cupola/features/discover/domain/seerr_media_copy.dart';
import 'package:cupola/features/movies/domain/radarr_status.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
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

/// What Bazarr holds for one Radarr copy of a film.
///
/// Bazarr follows one Radarr, and its ids are that Radarr's: a film is matched
/// to a copy by the copy's movie id and checked against the copy's path, or
/// its title and year, so the 4K Radarr's film 12 is never read as the other
/// Radarr's film 12.
class MediaBazarrCopy {
  const MediaBazarrCopy({required this.radarrConnectionId, this.movie});

  /// The Radarr connection whose copy Bazarr covers.
  final String radarrConnectionId;

  /// Null when Bazarr answered and does not follow that copy.
  final BazarrMovie? movie;
}

/// What one Seerr knows of a title: its record, and the arr servers it
/// would place it on.
class MediaSeerrRecord {
  const MediaSeerrRecord({required this.details, this.radarrServers});

  /// `/movie/:id` or `/tv/:id`, as Seerr answered: identity, ratings, cast and
  /// the `mediaInfo` the rows read.
  final Map<String, dynamic> details;

  /// Seerr's Radarr servers, null when they could not be read (an account
  /// without ADMIN, or a failed read): then a copy cannot be bound to one.
  final List<SeerrArrServer>? radarrServers;

  /// Seerr's media row for the title, null when it has no record.
  Map<String, dynamic>? get mediaInfo => mapOrNull(details['mediaInfo']);

  /// The copies Seerr says an arr holds, the standard one first.
  List<SeerrMediaCopy> get copies => SeerrMediaCopy.fromMediaInfo(mediaInfo);
}
