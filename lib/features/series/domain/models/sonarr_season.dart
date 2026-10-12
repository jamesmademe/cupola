import 'package:cupola/core/utils/episode_code.dart';

/// One season of a Sonarr series.
///
/// Sonarr returns seasons nested inside the series payload, so they arrived,
/// and were rendered as raw `dynamic` maps: the season pill read
/// `season['seasonNumber']` while the panel beside it read
/// `season['statistics']['episodeFileCount']`, with nothing to stop the two
/// halves of one control disagreeing about the shape they were handed. This is
/// that shape, written down once.
class SonarrSeason {
  final int seasonNumber;
  final bool monitored;

  /// Episodes Sonarr expects to hold: aired and monitored ones only.
  ///
  /// Deliberately not [totalEpisodeCount], which counts unaired episodes and
  /// would leave any currently-airing season permanently `partial`: the same
  /// distinction `SonarrSeries.episodeCount` documents at series level.
  ///
  /// The three counts are null when Sonarr did not send them, never 0. Each
  /// used to fall back to `0`, so a season whose statistics were missing read
  /// "0 of 10 episodes" and painted as missing: the worst gap a season can
  /// have, from no data. `SeriesDetailViewModel.diskCounts` keeps the same
  /// rule for the whole series.
  final int? episodeCount;

  /// Every known episode of the season, including unaired ones.
  final int? totalEpisodeCount;

  final int? episodeFileCount;

  const SonarrSeason({
    required this.seasonNumber,
    required this.monitored,
    required this.episodeCount,
    required this.totalEpisodeCount,
    required this.episodeFileCount,
  });

  bool get isSpecials => seasonNumber == 0;

  /// Full name, for a summary line or a picker row.
  String get label => isSpecials ? 'Specials' : 'Season $seasonNumber';

  /// One-line pill label. Kept to three characters so a 40-season rail stays
  /// scannable.
  String get shortLabel => isSpecials ? 'Sp' : formatSeasonCode(seasonNumber);

  /// Share of the expected episodes that are on disk, or null when nothing is
  /// expected yet (an announced season that has not started airing) or when
  /// Sonarr did not send both counts.
  double? get completionPercent {
    final expected = episodeCount;
    final onDisk = episodeFileCount;
    if (expected == null || onDisk == null || expected <= 0) return null;
    return (onDisk / expected).clamp(0.0, 1.0);
  }

  /// True while more episodes of this season are still expected to air, and
  /// false when Sonarr did not say.
  bool get hasUnairedEpisodes {
    final total = totalEpisodeCount;
    final aired = episodeCount;
    return total != null && aired != null && total > aired;
  }

  factory SonarrSeason.fromJson(Map<String, dynamic> json) {
    final rawStatistics = json['statistics'];
    final statistics = rawStatistics is Map<String, dynamic>
        ? rawStatistics
        : const <String, dynamic>{};
    final aired = (statistics['episodeCount'] as num?)?.toInt();

    return SonarrSeason(
      seasonNumber: (json['seasonNumber'] as num?)?.toInt() ?? 0,
      monitored: json['monitored'] as bool? ?? false,
      episodeCount: aired,
      // No total means no unaired episode Sonarr told us about, so the aired
      // count stands in; neither stands in for a count that never came.
      totalEpisodeCount:
          (statistics['totalEpisodeCount'] as num?)?.toInt() ?? aired,
      episodeFileCount: (statistics['episodeFileCount'] as num?)?.toInt(),
    );
  }

  /// Maps `SonarrSeries.seasons`' raw entries, dropping anything that is not a
  /// JSON object, and returns them in display order.
  static List<SonarrSeason> listFrom(List<dynamic> raw) {
    final seasons = <SonarrSeason>[];
    for (final entry in raw) {
      if (entry is Map<String, dynamic>) {
        seasons.add(SonarrSeason.fromJson(entry));
      }
    }

    seasons.sort(compare);
    return List<SonarrSeason>.unmodifiable(seasons);
  }

  /// Ascending by season number, with specials last: they are an appendix, not
  /// season zero.
  static int compare(SonarrSeason left, SonarrSeason right) {
    if (left.isSpecials != right.isSpecials) return left.isSpecials ? 1 : -1;
    return left.seasonNumber.compareTo(right.seasonNumber);
  }
}
