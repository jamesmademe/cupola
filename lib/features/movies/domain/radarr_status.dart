import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';

/// Resolves the badge status for a Radarr movie.
///
/// Pass the movie's [queueEntry] from the shared queue snapshot: without it a
/// movie being grabbed reads `Missing`, which is the bug this layer exists to
/// fix. Pass [queueUnknown] as `!snapshot.isWhole`, and as true while there is
/// no snapshot yet: a queue that could not be read cannot say the film is not
/// in it, so a film with no file reads unknown rather than `Missing`.
MediaStatusInfo radarrMovieStatus(
  RadarrMovie movie, {
  ArrQueueEntry? queueEntry,
  bool queueUnknown = false,
}) {
  return mediaStatusFromQueue(
    availability: radarrMovieAvailability(movie),
    monitored: movie.monitored,
    queueEntry: queueEntry,
    queueUnknown: queueUnknown,
  );
}

MediaAvailability radarrMovieAvailability(RadarrMovie movie) {
  if (movie.status.toLowerCase() == 'deleted') {
    return MediaAvailability.deleted;
  }
  if (movie.hasFile) return MediaAvailability.available;

  // A movie that has not reached its minimum availability yet is not "missing":
  // nothing has gone wrong and there is nothing to grab.
  return movie.isExpectedOnDisk
      ? MediaAvailability.missing
      : MediaAvailability.unavailable;
}
