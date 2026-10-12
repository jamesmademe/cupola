import 'parse_utils.dart';
import 'package:cupola/core/utils/unit_space.dart';

/// Per-torrent detail payload from `/api/v2/torrents/properties`.
///
/// Mirrors the qBittorrent WebUI General tab. Sentinel integers (-1) and
/// string-or-empty values are preserved here and only rendered into display
/// form by the formatted getters below. All fields are required at
/// construction time: the family provider guarantees a non-null payload.
class TorrentProperties {
  final String savePath;
  final int creationDate;
  final int pieceSize;
  final String comment;
  final int totalWasted;
  final int totalUploaded;
  final int totalUploadedSession;
  final int totalDownloaded;
  final int totalDownloadedSession;
  final int upLimit;
  final int dlLimit;
  final int timeElapsed;
  final int seedingTime;
  final int nbConnections;
  final int nbConnectionsLimit;
  final double shareRatio;
  final int additionDate;
  final int completionDate;
  final String createdBy;
  final int dlSpeedAvg;
  final int dlSpeed;
  final int eta;
  final int lastSeen;
  final int peers;
  final int peersTotal;
  final int piecesHave;
  final int piecesNum;
  final int reannounceSeconds;
  final int seeds;
  final int seedsTotal;
  final int totalSize;
  final int upSpeedAvg;
  final int upSpeed;
  final bool isPrivate;

  const TorrentProperties({
    required this.savePath,
    required this.creationDate,
    required this.pieceSize,
    required this.comment,
    required this.totalWasted,
    required this.totalUploaded,
    required this.totalUploadedSession,
    required this.totalDownloaded,
    required this.totalDownloadedSession,
    required this.upLimit,
    required this.dlLimit,
    required this.timeElapsed,
    required this.seedingTime,
    required this.nbConnections,
    required this.nbConnectionsLimit,
    required this.shareRatio,
    required this.additionDate,
    required this.completionDate,
    required this.createdBy,
    required this.dlSpeedAvg,
    required this.dlSpeed,
    required this.eta,
    required this.lastSeen,
    required this.peers,
    required this.peersTotal,
    required this.piecesHave,
    required this.piecesNum,
    required this.reannounceSeconds,
    required this.seeds,
    required this.seedsTotal,
    required this.totalSize,
    required this.upSpeedAvg,
    required this.upSpeed,
    required this.isPrivate,
  });

  factory TorrentProperties.fromJson(Map<String, dynamic> json) {
    return TorrentProperties(
      savePath: json['save_path'] as String? ?? '',
      creationDate: parseInt(json['creation_date']),
      pieceSize: parseInt(json['piece_size']),
      comment: json['comment'] as String? ?? '',
      totalWasted: parseInt(json['total_wasted']),
      totalUploaded: parseInt(json['total_uploaded']),
      totalUploadedSession: parseInt(json['total_uploaded_session']),
      totalDownloaded: parseInt(json['total_downloaded']),
      totalDownloadedSession: parseInt(json['total_downloaded_session']),
      upLimit: parseInt(json['up_limit']),
      dlLimit: parseInt(json['dl_limit']),
      timeElapsed: parseInt(json['time_elapsed']),
      seedingTime: parseInt(json['seeding_time']),
      nbConnections: parseInt(json['nb_connections']),
      nbConnectionsLimit: parseInt(json['nb_connections_limit']),
      shareRatio: parseDouble(json['share_ratio']),
      additionDate: parseInt(json['addition_date']),
      completionDate: parseInt(json['completion_date']),
      createdBy: json['created_by'] as String? ?? '',
      dlSpeedAvg: parseInt(json['dl_speed_avg']),
      dlSpeed: parseInt(json['dl_speed']),
      eta: parseInt(json['eta']),
      lastSeen: parseInt(json['last_seen']),
      peers: parseInt(json['peers']),
      peersTotal: parseInt(json['peers_total']),
      piecesHave: parseInt(json['pieces_have']),
      piecesNum: parseInt(json['pieces_num']),
      reannounceSeconds: parseInt(json['reannounce']),
      seeds: parseInt(json['seeds']),
      seedsTotal: parseInt(json['seeds_total']),
      totalSize: parseInt(json['total_size']),
      upSpeedAvg: parseInt(json['up_speed_avg']),
      upSpeed: parseInt(json['up_speed']),
      isPrivate: parseBool(json['is_private']),
    );
  }

  String get savePathFormatted => savePath.isEmpty ? '—' : savePath;
  String get createdByFormatted => createdBy.isEmpty ? '—' : createdBy;
  String get commentFormatted => comment.isEmpty ? '—' : comment;
  String get timeActiveFormatted => formatDuration(timeElapsed);
  String get seededForFormatted => formatDuration(seedingTime);
  String get lastSeenFormatted => formatEpochDate(lastSeen);
  String get additionDateFormatted => formatEpochDate(additionDate);
  String get completionDateFormatted => formatEpochDate(completionDate);
  String get creationDateFormatted => formatEpochDate(creationDate);
  String get shareRatioFormatted => shareRatio.toStringAsFixed(2);
  String get dlLimitFormatted => formatLimit(dlLimit);
  String get upLimitFormatted => formatLimit(upLimit);
  String get dlSpeedAvgFormatted => formatSpeed(dlSpeedAvg);
  String get upSpeedAvgFormatted => formatSpeed(upSpeedAvg);
  String get piecesFormatted => '$piecesHave / $piecesNum';
  String get peersFormatted => '$peers / $peersTotal';
  String get seedsFormatted => '$seeds / $seedsTotal';
  String get pieceSizeFormatted => formatSize(pieceSize);

  /// qB uses `0` to mean "no connection limit": suppress the denominator in
  /// that case to avoid a misleading `5 / 0` row.
  String get connectionsFormatted => nbConnectionsLimit > 0
      ? '$nbConnections / $nbConnectionsLimit'
      : '$nbConnections';

  /// Reannounce countdown. `0` (and negative) render as the placeholder of a
  /// figure there is none of, `—`, to match the WebUI's discrete "never" state;
  /// otherwise `'<N> s'`.
  String get reannounceFormatted =>
      reannounceSeconds <= 0 ? '—' : withUnit(reannounceSeconds, 's');
}
