/// Naming a download no arr's queue claims: ask the arrs.
///
/// A torrent added by hand, or a finished one an arr imported long ago, has
/// only its machine name. The arrs read such names for a living
/// (`/api/v3/parse` on Radarr and Sonarr, `/api/v1/parse` on Lidarr), with the
/// logic they file downloads by, and when the name is a title they hold they
/// say which one. Their reading is the title; when none of them can read the
/// name, the raw name is the title and nothing stands beside it. There is no
/// home-made reading in between: dots to spaces and a cut at the year make
/// wrong titles that look right.
///
/// Pure and top-level, so each reading is testable without a network.
library;

import 'package:cupola/core/status/media_names.dart';
import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/core/utils/episode_code.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The arrs a name can be put to, in the order they are asked when nothing
/// says which.
const List<ServiceKey> parsingArrs = [
  ServiceKey.radarr,
  ServiceKey.sonarr,
  ServiceKey.lidarr,
];

/// The arr a download client's category points at, or null when it points
/// at none.
///
/// The arrs file what they send under a category of their own (`radarr`,
/// `tv-sonarr`, `lidarr` are their defaults; `movies`, `tv` and `music` are
/// the usual hand-set ones), so the category says which arr can read the
/// name, and the others need not be asked.
ServiceKey? arrForClientCategory(String? category) {
  final value = category?.trim().toLowerCase() ?? '';
  if (value.isEmpty) return null;
  if (value.contains('radarr') || value.contains('movie')) {
    return ServiceKey.radarr;
  }
  if (value.contains('sonarr') ||
      value.contains('tv') ||
      value.contains('series') ||
      value.contains('show')) {
    return ServiceKey.sonarr;
  }
  if (value.contains('lidarr') || value.contains('music')) {
    return ServiceKey.lidarr;
  }
  return null;
}

/// What one arr's `/parse` answer says [name] is, or null when it could not
/// read it.
///
/// A library item the answer names wins ([MediaTitleSource.library]): the
/// movie, the series with the parsed episode, the artist with the album.
/// Without one, the parser's own reading stands ([MediaTitleSource.parser]):
/// `parsedMovieInfo.movieTitles`, `parsedEpisodeInfo.seriesTitle`,
/// `parsedAlbumInfo.albumTitle`. [name] is the machine name beside it,
/// exactly as the client reported it.
MediaNames? namesFromParse(
  ServiceKey arr,
  String name,
  Map<String, dynamic> answer,
) {
  final (title, source) = switch (arr) {
    ServiceKey.radarr => _radarrTitle(answer),
    ServiceKey.sonarr => _sonarrTitle(answer),
    ServiceKey.lidarr => _lidarrTitle(answer),
    _ => (null, MediaTitleSource.raw),
  };
  final clean = title?.trim();
  if (clean == null || clean.isEmpty) return null;
  final machine = name.trim();
  if (machine.isEmpty || machine == clean) return MediaNames.raw(clean);
  return MediaNames(
    title: clean,
    machineName: machine,
    machineKind: MachineNameKind.release,
    source: source,
  );
}

(String?, MediaTitleSource) _radarrTitle(Map<String, dynamic> answer) {
  final movie = stringOrNull(mapOrNull(answer['movie'])?['title']);
  if (movie != null) return (movie, MediaTitleSource.library);
  final parsed = mapOrNull(answer['parsedMovieInfo']);
  final titles = parsed?['movieTitles'];
  final first = titles is List && titles.isNotEmpty
      ? stringOrNull(titles.first)
      : null;
  return (
    first ?? stringOrNull(parsed?['primaryMovieTitle']),
    MediaTitleSource.parser,
  );
}

(String?, MediaTitleSource) _sonarrTitle(Map<String, dynamic> answer) {
  final parsed = mapOrNull(answer['parsedEpisodeInfo']);
  final numbers = parsed?['episodeNumbers'];
  final code = formatArrEpisodeCode(
    intOrNull(parsed?['seasonNumber']),
    numbers is List && numbers.isNotEmpty ? intOrNull(numbers.first) : null,
  );
  final series = stringOrNull(mapOrNull(answer['series'])?['title']);
  if (series != null) {
    return (joinDisplayParts([series, code]), MediaTitleSource.library);
  }
  final parsedSeries = stringOrNull(parsed?['seriesTitle']);
  return (
    parsedSeries == null ? null : joinDisplayParts([parsedSeries, code]),
    MediaTitleSource.parser,
  );
}

(String?, MediaTitleSource) _lidarrTitle(Map<String, dynamic> answer) {
  final artist = stringOrNull(mapOrNull(answer['artist'])?['artistName']);
  final albums = answer['albums'];
  final album = albums is List && albums.isNotEmpty
      ? stringOrNull(mapOrNull(albums.first)?['title'])
      : null;
  if (artist != null || album != null) {
    return (joinDisplayParts([album, artist]), MediaTitleSource.library);
  }
  final parsed = mapOrNull(answer['parsedAlbumInfo']);
  final parsedAlbum = stringOrNull(parsed?['albumTitle']);
  final parsedArtist = stringOrNull(parsed?['artistName']);
  return (
    parsedAlbum == null && parsedArtist == null
        ? null
        : joinDisplayParts([parsedAlbum, parsedArtist]),
    MediaTitleSource.parser,
  );
}
