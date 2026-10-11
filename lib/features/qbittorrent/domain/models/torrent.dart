import 'parse_utils.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/utils/duration_format.dart';
import 'package:cupola/core/utils/percent_format.dart';

enum TorrentState {
  downloading,
  metaDownloading,
  seeding,
  stalled,
  checking,
  paused,
  queuedUp,
  queuedDl,
  error,
  unknown;

  String get label {
    switch (this) {
      case TorrentState.downloading:
        return 'Downloading';
      case TorrentState.metaDownloading:
        return 'Fetching metadata';
      case TorrentState.seeding:
        return 'Seeding';
      case TorrentState.stalled:
        return StateWord.stuck.label;
      case TorrentState.checking:
        return 'Checking';
      case TorrentState.paused:
        return StateWord.stopped.label;
      case TorrentState.queuedUp:
      case TorrentState.queuedDl:
        return 'Queued';
      case TorrentState.error:
        return 'Error';
      case TorrentState.unknown:
        return '—';
    }
  }

  bool get isActive =>
      this == TorrentState.downloading ||
      this == TorrentState.metaDownloading ||
      this == TorrentState.seeding;

  bool get isPaused => this == TorrentState.paused;

  bool get isQueued =>
      this == TorrentState.queuedUp || this == TorrentState.queuedDl;

  static TorrentState fromString(String? state) {
    return switch (state) {
      'downloading' || 'forcedDL' => TorrentState.downloading,
      'metaDL' || 'forcedMetaDL' => TorrentState.metaDownloading,
      'uploading' || 'forcedUP' => TorrentState.seeding,
      'stalledUP' => TorrentState.seeding,
      'stalledDL' => TorrentState.stalled,
      'checkingUP' || 'checkingDL' => TorrentState.checking,
      'pausedUP' || 'pausedDL' => TorrentState.paused,
      'stoppedUP' || 'stoppedDL' || 'stopped' => TorrentState.paused,
      'queuedUP' => TorrentState.queuedUp,
      'queuedDL' => TorrentState.queuedDl,
      'moving' || 'allocating' => TorrentState.downloading,
      'error' || 'missingFiles' => TorrentState.error,
      _ => TorrentState.unknown,
    };
  }
}

class Torrent {
  final String hash;
  final String name;
  final int size;
  final double progress;
  final String state;
  final TorrentState parsedState;
  final int dlSpeed;
  final int upSpeed;
  final int eta;
  final String category;
  final String tracker;
  final List<String> tags;
  final double ratio;
  final int addedOn;
  final int completed;
  final int leechers;
  final int seeders;

  /// Peers with the whole file that the trackers know of (`num_complete`),
  /// connected or not; -1 when the client did not say.
  final int swarmSeeds;

  // Optional fields from `/torrents/info` (mirrors the qB WebUI General tab).
  // All defaulted so existing tests/fixtures that only set the original 16
  // fields keep passing unchanged. -1 sentinels follow qB's "no limit"
  // convention; UI rendering decisions live in the property model.
  final String contentPath;
  final int dlLimit;
  final int upLimit;
  final int lastActivity;
  final int seedingTime;
  final int timeActive;
  final int downloaded;
  final int uploaded;
  final double availability;
  final bool isPrivate;
  final bool forceStart;
  final bool superSeeding;
  final String magnetUri;
  final double maxRatio;
  final double ratioLimit;
  final int maxSeedingTime;

  const Torrent({
    required this.hash,
    required this.name,
    required this.size,
    required this.progress,
    required this.state,
    required this.parsedState,
    required this.dlSpeed,
    required this.upSpeed,
    required this.eta,
    required this.category,
    required this.tracker,
    required this.tags,
    required this.ratio,
    required this.addedOn,
    required this.completed,
    required this.leechers,
    required this.seeders,
    this.swarmSeeds = -1,
    this.contentPath = '',
    this.dlLimit = -1,
    this.upLimit = -1,
    this.lastActivity = 0,
    this.seedingTime = 0,
    this.timeActive = 0,
    this.downloaded = 0,
    this.uploaded = 0,
    this.availability = 1.0,
    this.isPrivate = false,
    this.forceStart = false,
    this.superSeeding = false,
    this.magnetUri = '',
    this.maxRatio = -1,
    this.ratioLimit = -1,
    this.maxSeedingTime = -1,
  });

  factory Torrent.fromJson(Map<String, dynamic> json) {
    return Torrent(
      hash: json['hash'] as String? ?? '',
      name: json['name'] as String? ?? '',
      size: parseInt(json['size']),
      progress: parseDouble(json['progress']),
      state: json['state'] as String? ?? '',
      parsedState: TorrentState.fromString(json['state'] as String?),
      dlSpeed: parseInt(json['dlspeed']),
      upSpeed: parseInt(json['upspeed']),
      eta: parseInt(json['eta']),
      category: json['category'] as String? ?? '',
      tracker: json['tracker'] as String? ?? '',
      tags: _parseTags(json['tags']),
      ratio: parseDouble(json['ratio']),
      addedOn: parseInt(json['added_on']),
      completed: parseInt(json['completed']),
      leechers: parseInt(json['num_leechs']),
      seeders: parseInt(json['num_seeds']),
      swarmSeeds: json['num_complete'] is num
          ? (json['num_complete'] as num).toInt()
          : -1,
      contentPath: json['content_path'] as String? ?? '',
      dlLimit: parseInt(json['dl_limit']),
      upLimit: parseInt(json['up_limit']),
      lastActivity: parseInt(json['last_activity']),
      seedingTime: parseInt(json['seeding_time']),
      timeActive: parseInt(json['time_active']),
      downloaded: parseInt(json['downloaded']),
      uploaded: parseInt(json['uploaded']),
      availability: parseDouble(json['availability']),
      isPrivate: parseBool(json['is_private']),
      forceStart: parseBool(json['force_start']),
      superSeeding: parseBool(json['super_seeding']),
      magnetUri: json['magnet_uri'] as String? ?? '',
      maxRatio: parseDouble(json['max_ratio']),
      ratioLimit: parseDouble(json['ratio_limit']),
      maxSeedingTime: parseInt(json['max_seeding_time']),
    );
  }

  static List<String> _parseTags(dynamic value) {
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    final str = value?.toString() ?? '';
    if (str.isEmpty) return [];
    return str
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
  }

  String get sizeFormatted => formatSize(size);

  String get dlSpeedFormatted {
    if (dlSpeed <= 0) return '0';
    return formatSpeed(dlSpeed);
  }

  String get upSpeedFormatted {
    if (upSpeed <= 0) return '0';
    return formatSpeed(upSpeed);
  }

  String get etaFormatted {
    if (eta < 0 ||
        state == 'pausedDL' ||
        state == 'pausedUP' ||
        state == 'stoppedDL' ||
        state == 'stoppedUP' ||
        state == 'stopped') {
      return '';
    }
    if (eta >= 8640000) return '∞';
    return formatTimeSpan(Duration(seconds: eta));
  }

  String get progressFormatted => formatPercent(progress * 100, decimals: 1);

  String get trackerDomain {
    if (tracker.isEmpty) return '';
    try {
      final uri = Uri.parse(tracker);
      final host = uri.host;
      return host.startsWith('www.') ? host.substring(4) : host;
    } catch (_) {
      return '';
    }
  }
}
