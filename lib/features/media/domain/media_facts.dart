import 'package:cupola/features/discover/domain/models/discover_detail_model.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/presentation/discover_detail_view_model.dart';
import 'package:cupola/features/media/domain/media_copies.dart';
import 'package:cupola/features/media/domain/media_reading.dart';
import 'package:cupola/features/media/domain/media_rows.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';

/// When a movie came out, or comes out: in cinemas, digitally, on disc.
/// Dates as the source wrote them (ISO); each null when it has none.
///
/// [region] names the country the dates are for, as TMDB keeps them through
/// Seerr; null for an arr's own dates, which TMDB keeps for no one country.
typedef MediaReleases = ({
  String? region,
  String? cinemas,
  String? digital,
  String? physical,
});

/// The movie's releases: TMDB's for [region] through the first Seerr that
/// answered, else the first Radarr copy's own dates, else null. Null too
/// when the source has no date at all: no section that reports its own
/// absence.
MediaReleases? mediaReleasesOf(List<MediaRow> rows, String region) {
  for (final value in _answered(rows)) {
    if (value is MediaSeerrRecord) {
      final releases = DiscoverDetailViewModel.fromResponse(
        value.details,
      ).releasesForRegion(region);
      String? dated(int type) {
        for (final release in releases) {
          if (release.type == type && release.releaseDate.isNotEmpty) {
            return release.releaseDate;
          }
        }
        return null;
      }

      final found = (
        region: region,
        // TMDB's types: 3 theatrical, 4 digital, 5 physical.
        cinemas: dated(3),
        digital: dated(4),
        physical: dated(5),
      );
      if (_dated(found)) return found;
      break;
    }
  }
  for (final value in _answered(rows)) {
    if (value case MediaRadarrCopy(:final movie?)) {
      final found = (
        region: null,
        cinemas: _date(movie.inCinemas),
        digital: _date(movie.digitalRelease),
        physical: _date(movie.physicalRelease),
      );
      return _dated(found) ? found : null;
    }
  }
  return null;
}

/// Where the title streams, or can be bought or rented, in [region]: TMDB's
/// list through the first Seerr that answered. Null without a Seerr, or when
/// the region names nowhere.
WatchProviderRegion? mediaWatchProvidersOf(List<MediaRow> rows, String region) {
  for (final value in _answered(rows)) {
    if (value is MediaSeerrRecord) {
      final providers = DiscoverDetailViewModel.fromResponse(
        value.details,
      ).watchProvidersForRegion(region);
      return providers != null && providers.hasAny ? providers : null;
    }
  }
  return null;
}

/// A request waiting for someone to approve it, and the Seerr it waits on:
/// a request id is that Seerr's own.
typedef MediaPendingRequest = ({ServiceInstance seerr, SeerrRequest request});

/// Every request for the title that waits for approval, Seerr by Seerr, the
/// oldest first: the one waiting longest is answered first.
List<MediaPendingRequest> mediaPendingRequests(List<MediaRow> rows) {
  final pending = <MediaPendingRequest>[];
  for (final row in rows) {
    if (row case MediaConnectionRow(
      :final connection,
      reading: MediaReadingAnswered(:final answer),
    )) {
      if (answer.value case final MediaSeerrRecord record) {
        final requests = [
          for (final json in switch (record.mediaInfo?['requests']) {
            final List<dynamic> list => list.whereType<Map<String, dynamic>>(),
            _ => const <Map<String, dynamic>>[],
          })
            SeerrRequest.fromJson(json),
        ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        for (final request in requests) {
          if (request.status == RequestStatus.pendingApproval) {
            pending.add((seerr: connection, request: request));
          }
        }
      }
    }
  }
  return pending;
}

Iterable<Object?> _answered(List<MediaRow> rows) sync* {
  for (final row in rows) {
    if (row case MediaConnectionRow(
      reading: MediaReadingAnswered(:final answer),
    )) {
      yield answer.value;
    }
  }
}

bool _dated(MediaReleases releases) =>
    releases.cinemas != null ||
    releases.digital != null ||
    releases.physical != null;

String? _date(String? value) =>
    value == null || value.trim().isEmpty ? null : value.trim();
