import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/features/series/domain/models/sonarr_episode.dart';
import 'package:cupola/features/series/domain/models/sonarr_season.dart';
import 'package:cupola/features/series/domain/models/sonarr_series.dart';

/// Resolves the badge status for a Sonarr series.
///
/// [queueUnknown] as in `radarrMovieStatus`: `!snapshot.isWhole`, so a series
/// whose queue could not be read never reads `Missing` for want of an entry.
MediaStatusInfo sonarrSeriesStatus(
  SonarrSeries series, {
  ArrQueueEntry? queueEntry,
  bool queueUnknown = false,
}) {
  return mediaStatusFromQueue(
    availability: sonarrSeriesAvailability(series),
    monitored: series.monitored,
    queueEntry: queueEntry,
    queueUnknown: queueUnknown,
  );
}

MediaAvailability sonarrSeriesAvailability(SonarrSeries series) {
  if (series.status.toLowerCase() == 'deleted') {
    return MediaAvailability.deleted;
  }

  // Both figures or neither: a missing `episodeCount` read as `0` made a series
  // with no files "Not released", a claim about the schedule from no data.
  final files = series.episodeFileCount;
  final aired = series.episodeCount;
  if (series.statistics == null || files == null || aired == null) {
    return MediaAvailability.unknown;
  }

  // `episodeCount` counts aired, monitored episodes, so a continuing series
  // that holds everything broadcast so far is `available` rather than being
  // stuck at `partial` forever.
  if (aired <= 0) {
    return files > 0
        ? MediaAvailability.available
        : MediaAvailability.unavailable;
  }

  return availabilityFromCounts(fileCount: files, totalCount: aired);
}

/// Resolves the status of one season.
///
/// The season header used to signal monitoring with a green bookmark while the
/// rows beneath it signalled `hasFile` with an indigo dot: two vocabularies for
/// related facts, neither of them written down anywhere on the page. Both now
/// come from here, so the header badge and the row badge cannot disagree.
///
/// [queueEntry] is the season's own slice of the queue
/// (`SonarrQueueSnapshots.seasonEntry`): a season with an episode downloading
/// reads downloading, not `Missing`. [queueUnknown] as in
/// [sonarrSeriesStatus]: a season whose queue could not be read whole never
/// reads `Missing` for want of an entry.
MediaStatusInfo sonarrSeasonStatus(
  SonarrSeason season, {
  ArrQueueEntry? queueEntry,
  bool queueUnknown = false,
}) {
  return mediaStatusFromQueue(
    availability: sonarrSeasonAvailability(season),
    monitored: season.monitored,
    queueEntry: queueEntry,
    queueUnknown: queueUnknown,
  );
}

MediaAvailability sonarrSeasonAvailability(SonarrSeason season) {
  // Both figures or neither, as at series level: a count Sonarr did not send
  // read as `0` made a season "Missing" from no data.
  final aired = season.episodeCount;
  final files = season.episodeFileCount;
  if (aired == null || files == null) return MediaAvailability.unknown;

  // Nothing has aired yet: an announced season is not a missing one.
  if (aired <= 0) {
    return files > 0
        ? MediaAvailability.available
        : MediaAvailability.unavailable;
  }

  return availabilityFromCounts(fileCount: files, totalCount: aired);
}

/// The season's manifest gap in words: `8 of 10 episodes`.
///
/// The gap is the only reason this region exists: Sonarr models expected
/// episodes (`episodeCount`) separately from present ones
/// (`episodeFileCount`), so it is stated rather than left to a bar. When more
/// episodes are still to air the total is named too, because `8 of 8 episodes`
/// on a season that will end up with twelve is true and misleading at once.
///
/// A count Sonarr did not send is left out, never written as `0`: with the
/// files unknown the line says how many episodes there are (`10 episodes`)
/// and states no gap, and with the aired count unknown it can say neither
/// what is missing nor what is still to come.
String? sonarrSeasonSummary(SonarrSeason season) {
  final expected = season.episodeCount;
  final total = season.totalEpisodeCount;
  if (expected == null) {
    return total != null && total > 0 ? '$total episodes' : null;
  }

  if (expected <= 0) {
    return total != null && total > 0 ? '$total episodes announced' : null;
  }

  final onDisk = season.episodeFileCount;
  final aired = onDisk == null ? '$expected' : '$onDisk of $expected';
  if (season.hasUnairedEpisodes) {
    return '$aired aired\u00A0· $total total';
  }

  return '$aired episodes';
}

/// Resolves the status of one episode.
///
/// [queueEntry] is the episode's record in the queue
/// (`SonarrQueueSnapshots.byEpisode`): an episode being downloaded reads
/// downloading, never `Missing`. [queueUnknown] as in [sonarrSeriesStatus]:
/// with the queue unread, an aired episode with no file may be on its way,
/// and reads unknown rather than `Missing`.
///
/// [now] is injectable so the unaired case is testable without freezing the
/// clock; it defaults to the wall clock.
MediaStatusInfo sonarrEpisodeStatus(
  SonarrEpisode episode, {
  DateTime? now,
  ArrQueueEntry? queueEntry,
  bool queueUnknown = false,
}) {
  return mediaStatusFromQueue(
    availability: sonarrEpisodeAvailability(episode, now: now),
    monitored: episode.monitored,
    queueEntry: queueEntry,
    queueUnknown: queueUnknown,
  );
}

MediaAvailability sonarrEpisodeAvailability(
  SonarrEpisode episode, {
  DateTime? now,
}) {
  if (episode.hasFile) return MediaAvailability.available;
  // Not yet broadcast: nothing is wrong and nothing is expected, so this is
  // "Not released" rather than the red "Missing" every future episode of a
  // continuing series used to draw.
  if (episode.isUnairedAt(now ?? DateTime.now())) {
    return MediaAvailability.unavailable;
  }

  return MediaAvailability.missing;
}
