import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/media/domain/media_copies.dart';
import 'package:cupola/features/media/domain/media_reading.dart';
import 'package:cupola/features/media/domain/media_rows.dart';
import 'package:cupola/features/media/domain/media_series.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/domain/stream_external_match.dart';

/// The one action that leads a Media page, decided from its rows.
///
/// One decision for every page and both audiences: it replaces the two that
/// a title had before, `resolveMediaAction` for the arr pages and an `if` in
/// the Seerr page's buttons. A copy that needs something still names its own
/// action through `resolveMediaAction` ([MediaLeadCopy]); this decides which
/// copy, or whether something else leads.
sealed class MediaLead {
  const MediaLead();
}

/// A source that could outrank whatever would lead now has not answered: the
/// slot keeps its place, so the lead never flips from Trailer to Play.
final class MediaLeadWaiting extends MediaLead {
  const MediaLeadWaiting();
}

/// Play, or resume, on the media server that holds a verified copy.
final class MediaLeadPlay extends MediaLead {
  const MediaLeadPlay(this.server, this.item, {this.episode});

  final ServiceInstance server;
  final StreamItem item;

  /// For a series, the episode Play opens (`mediaNextEpisode`): null for a
  /// movie, and when every episode is watched or none could be read.
  final StreamItem? episode;

  /// The viewer is partway in: `Resume`.
  bool get resume => (episode ?? item).isInProgress;
}

/// The operator's arr is set up and none of its connections holds the title:
/// add it.
final class MediaLeadAdd extends MediaLead {
  const MediaLeadAdd(this.arr);

  /// Radarr for a film, Sonarr for a series.
  final ServiceKey arr;
}

/// Ask for the title through [seerr]: the requester always, and an operator
/// whose arr is not set up in Cupola while Seerr is (F-person-add).
final class MediaLeadRequest extends MediaLead {
  const MediaLeadRequest(this.seerr);

  final ServiceInstance seerr;
}

/// A copy that needs something leads with its own action
/// (`resolveMediaAction` on [status]): the one the page was opened on, or the
/// first that is not on disk.
final class MediaLeadCopy extends MediaLead {
  const MediaLeadCopy(this.connection, this.status);

  final ServiceInstance connection;
  final MediaStatusInfo status;
}

/// Nothing to play and nothing to do: Seerr's trailer leads.
final class MediaLeadTrailer extends MediaLead {
  const MediaLeadTrailer();
}

/// Nothing leads: the rows carry the page.
final class MediaLeadNone extends MediaLead {
  const MediaLeadNone();
}

/// The lead of a page with [rows], for [audience].
///
/// In order: a verified copy on a media server plays (rule 7: an unverified
/// one never does); the requester asks for anything else; the operator adds a
/// title nobody holds, requests it through Seerr when no arr is set up, or
/// follows the movie copy that needs something, [focus] first (the
/// connection the page was opened from); then the trailer; then nothing. A connection that
/// did not answer is never read as one that holds nothing: no Add while an arr
/// is silent.
MediaLead resolveMediaLead(
  List<MediaRow> rows, {
  required Audience audience,
  String? focus,
}) {
  final streams = rows.whereType<MediaConnectionRow<MediaStreamCopy>>();
  if (streams.any((row) => row.reading is MediaReadingWaiting)) {
    return const MediaLeadWaiting();
  }
  final found = [
    for (final row in streams)
      if (row.reading case MediaReadingAnswered(
        :final answer,
      ) when answer.value.outcome == StreamLookupOutcome.found)
        MediaLeadPlay(
          row.connection,
          answer.value.item!,
          episode: switch (answer.value.episodes) {
            final episodes? => mediaNextEpisode(episodes),
            null => null,
          },
        ),
  ];
  if (found.isNotEmpty) {
    return found.where((play) => play.resume).firstOrNull ?? found.first;
  }

  final seerrs = rows.whereType<MediaConnectionRow<MediaSeerrRecord>>();
  if (audience == Audience.requester) {
    final seerr = seerrs.firstOrNull;
    return seerr == null
        ? const MediaLeadNone()
        : MediaLeadRequest(seerr.connection);
  }

  final copies = [
    for (final row in rows)
      if (row
          case MediaConnectionRow<MediaRadarrCopy>() ||
              MediaConnectionRow<MediaSonarrCopy>())
        row as MediaConnectionRow,
  ];
  if (copies.any((row) => row.reading is MediaReadingWaiting)) {
    return const MediaLeadWaiting();
  }
  final tracked = [
    for (final row in copies)
      if (_statusOf(row) case final status?) (row: row, status: status),
  ];
  if (tracked.isEmpty) {
    final allAnswered = copies.every(
      (row) => row.reading is MediaReadingAnswered,
    );
    if (copies.isNotEmpty && allAnswered) {
      return MediaLeadAdd(copies.first.service);
    }
    if (copies.isEmpty && seerrs.isNotEmpty) {
      return MediaLeadRequest(seerrs.first.connection);
    }
  } else {
    // A series' copy never leads: its rows say what is downloading and
    // missing, and its searches are its episodes'.
    final needing = tracked.where(
      (copy) =>
          copy.row.service == ServiceKey.radarr &&
          copy.status.availability != MediaAvailability.available,
    );
    final lead =
        needing.where((copy) => copy.row.connection.id == focus).firstOrNull ??
        needing.firstOrNull;
    if (lead != null) return MediaLeadCopy(lead.row.connection, lead.status);
  }

  if (seerrs.any((row) => row.reading is MediaReadingWaiting)) {
    return const MediaLeadWaiting();
  }
  final trailer = seerrs.any(
    (row) => switch (row.reading) {
      MediaReadingAnswered(:final answer) => answer.value.hasTrailer,
      _ => false,
    },
  );
  return trailer ? const MediaLeadTrailer() : const MediaLeadNone();
}

/// The status of the copy [row] answered with, null while it is not tracked
/// or did not answer.
MediaStatusInfo? _statusOf(MediaConnectionRow row) => switch (row.reading) {
  MediaReadingAnswered(:final answer) => switch (answer.value) {
    final MediaRadarrCopy copy => copy.status,
    final MediaSonarrCopy copy => copy.status,
    _ => null,
  },
  _ => null,
};
