import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';

/// Sonarr's queue indexed three ways from one read: by series, by episode and
/// by season.
///
/// A queue record names one episode of one series. The library grid and the
/// series page badge the series; the episode rows and the season headers
/// badge what they draw. They used to read nothing at all, so an episode
/// that was downloading read `Missing`, and so did its season. One fetch,
/// three indexes, so the three cannot disagree about what is downloading.
///
/// The three share one answer: [isWhole], [isPending] and [error] are the
/// read's, whichever index a row consults.
class SonarrQueueSnapshots {
  /// Indexed by series id.
  final ArrQueueSnapshot bySeries;

  /// Indexed by episode id. A season pack is one record per episode, so
  /// each of its episodes has its own entry.
  final ArrQueueSnapshot byEpisode;

  /// Indexed by [_seasonKey]: reach it through [seasonEntry].
  final ArrQueueSnapshot _bySeason;

  const SonarrQueueSnapshots._({
    required this.bySeries,
    required this.byEpisode,
    required ArrQueueSnapshot bySeason,
  }) : _bySeason = bySeason;

  /// A queue that answered with nothing in it.
  static const SonarrQueueSnapshots empty = SonarrQueueSnapshots._(
    bySeries: ArrQueueSnapshot.empty,
    byEpisode: ArrQueueSnapshot.empty,
    bySeason: ArrQueueSnapshot.empty,
  );

  /// A queue nobody has read yet: see [ArrQueueSnapshot.unknown].
  static const SonarrQueueSnapshots unknown = SonarrQueueSnapshots._(
    bySeries: ArrQueueSnapshot.unknown,
    byEpisode: ArrQueueSnapshot.unknown,
    bySeason: ArrQueueSnapshot.unknown,
  );

  /// A queue read that failed with [error], every way.
  factory SonarrQueueSnapshots.failed(Object? error) => SonarrQueueSnapshots._(
    bySeries: ArrQueueSnapshot.failed(error),
    byEpisode: ArrQueueSnapshot.failed(error),
    bySeason: ArrQueueSnapshot.failed(error),
  );

  /// Builds the three indexes from raw `/queue` records. [cutShort] is the
  /// walk's own word that [records] are not the whole queue.
  factory SonarrQueueSnapshots.fromQueueItems(
    Iterable<dynamic> records, {
    bool cutShort = false,
    DateTime? sampledAt,
  }) {
    final at = sampledAt ?? DateTime.now();
    ArrQueueSnapshot index(Iterable<int?> Function(Map<String, dynamic>) ids) =>
        ArrQueueSnapshot.fromQueueItems(
          records,
          idsFor: (item) => ids(item).whereType<int>(),
          cutShort: cutShort,
          sampledAt: at,
        );
    return SonarrQueueSnapshots._(
      bySeries: index((item) => [_seriesId(item)]),
      byEpisode: index(
        (item) => [
          intOrNull(item['episodeId']) ??
              intOrNull(mapOrNull(item['episode'])?['id']),
        ],
      ),
      bySeason: index((item) {
        final series = _seriesId(item);
        final season =
            intOrNull(item['seasonNumber']) ??
            intOrNull(mapOrNull(item['episode'])?['seasonNumber']);
        return [
          if (series != null && season != null && season >= 0)
            _seasonKey(series, season),
        ];
      }),
    );
  }

  /// The queue answered and every record of it was read.
  bool get isWhole => byEpisode.isWhole;

  /// Nothing has come back yet.
  bool get isPending => byEpisode.isPending;

  /// Why the read failed, when it did.
  Object? get error => byEpisode.error;

  /// The queue's state for one season of one series: its episodes' records
  /// folded into one entry, the worst headline winning.
  ArrQueueEntry? seasonEntry(int seriesId, int seasonNumber) =>
      _bySeason.entryFor(_seasonKey(seriesId, seasonNumber));

  /// Every index is keyed on one int. A season is a series and a number, and
  /// Sonarr numbers some seasons by year, so the series id is shifted past
  /// any season number a show can carry.
  static int _seasonKey(int seriesId, int seasonNumber) =>
      seriesId * 100000 + seasonNumber + 1;

  static int? _seriesId(Map<String, dynamic> item) =>
      intOrNull(mapOrNull(item['series'])?['id'] ?? item['seriesId']);
}
