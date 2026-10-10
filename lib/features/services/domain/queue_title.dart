/// What an \*arr's queue record says about the title a download is for,
/// beyond its name: the facts a download's own page states.
library;

import 'package:cupola/core/utils/arr_activity_display.dart'
    show arrEpisodeCode;
import 'package:cupola/core/utils/dynamic_map_utils.dart';

/// The movie, or the series and its episode, a queue record embeds
/// (Radarr's `movie`, Sonarr's `series` and `episode`), read once with the
/// queue: no second request to say what year it is or where it will go.
class QueueTitle {
  const QueueTitle({
    this.name,
    this.year,
    this.episode,
    this.qualityProfileId,
    this.folder,
    this.inCinemas,
    this.digitalRelease,
    this.physicalRelease,
  });

  /// [record]'s title, or null when it embeds neither a movie nor a series.
  /// A pack of several records ([single] false) names its series and no
  /// episode.
  static QueueTitle? ofRecord(
    Map<String, dynamic> record, {
    bool single = true,
  }) {
    final movie = mapOrNull(record['movie']);
    final media = movie ?? mapOrNull(record['series']);
    if (media == null) return null;
    final year = intOrNull(media['year']);
    final code = single && movie == null ? arrEpisodeCode(record) : null;
    final episodeTitle = switch (stringOrNull(
      mapOrNull(record['episode'])?['title'],
    )?.trim()) {
      final title? when title.isNotEmpty => title,
      _ => null,
    };
    final profile = intOrNull(media['qualityProfileId']);
    return QueueTitle(
      name: stringOrNull(media['title'])?.trim(),
      year: year == null || year <= 0 ? null : year,
      episode: code == null ? null : [code, ?episodeTitle].join(' · '),
      qualityProfileId: profile == null || profile <= 0 ? null : profile,
      folder: libraryFolderOf(media),
      inCinemas: _date(media['inCinemas']),
      digitalRelease: _date(media['digitalRelease']),
      physicalRelease: _date(media['physicalRelease']),
    );
  }

  /// The movie or the series alone: `Sprite Fright`, `Cosmos Laundromat`.
  final String? name;

  final int? year;

  /// The episode a Sonarr record is for: `S2 E4 · The Second Cycle`.
  final String? episode;

  /// The profile it was grabbed under, by the arr's id for it.
  final int? qualityProfileId;

  /// The library folder it will be filed under: `/mnt/tank/media/movies`.
  final String? folder;

  final DateTime? inCinemas;
  final DateTime? digitalRelease;
  final DateTime? physicalRelease;
}

/// The root folder [media] is filed under: its `rootFolderPath`, else the
/// folder its own `path` sits in. Null when it names neither.
String? libraryFolderOf(Map<String, dynamic> media) {
  final root = stringOrNull(media['rootFolderPath'])?.trim();
  if (root != null && root.isNotEmpty) return _trimSlash(root);
  final path = stringOrNull(media['path'])?.trim();
  if (path == null || path.isEmpty) return null;
  final trimmed = _trimSlash(path);
  final cut = trimmed.lastIndexOf(RegExp(r'[/\\]'));
  return cut <= 0 ? null : trimmed.substring(0, cut);
}

String _trimSlash(String path) =>
    path.length > 1 && (path.endsWith('/') || path.endsWith(r'\'))
    ? path.substring(0, path.length - 1)
    : path;

DateTime? _date(Object? value) => switch (value) {
  final String text => DateTime.tryParse(text)?.toLocal(),
  _ => null,
};
