/// Typed models for the NZBGet JSON-RPC API.
///
/// NZBGet splits large 64-bit integers into `<field>Hi` / `<field>Lo` unsigned
/// 32-bit halves; [combineHiLo] recomposes them. Most sizes are also exposed
/// directly in MB, which the dashboard prefers.
///
/// Size and rate labels go through `core/utils/byte_format.dart`. This file
/// used to carry `formatNzbgetRate` and `formatNzbgetMb`, which disagreed with
/// SABnzbd's equivalents on both thresholds and precision — so an identical
/// quantity read differently depending on which download client reported it.
library;

import 'package:cupola/core/utils/byte_format.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/core/utils/percent_format.dart';

/// Recomposes an unsigned 64-bit value from NZBGet's Hi/Lo 32-bit halves.
int combineHiLo(dynamic hi, dynamic lo) {
  return (intOrNull(hi) ?? 0) * (1 << 32) + (intOrNull(lo) ?? 0);
}

/// Reads one of NZBGet's sizes — `<field>MB`, or the `<field>Hi`/`<field>Lo`
/// pair — in megabytes, and answers **null** when the record carried neither.
///
/// Null and not zero. NZBGet's own responses carry all three keys, so an
/// absent one means a truncated reply, a version that does not report the
/// field, or a record this app guessed the shape of — none of which is the
/// same statement as "zero megabytes", and each of which used to be rendered
/// as one.
int? megabytesOrNull(Map<String, dynamic> json, String field) {
  final direct = intOrNull(json['${field}MB']);
  if (direct != null) return direct;
  final hi = json['${field}Hi'];
  final lo = json['${field}Lo'];
  if (intOrNull(hi) == null && intOrNull(lo) == null) return null;
  return combineHiLo(hi, lo) ~/ (1024 * 1024);
}

/// Global download status (`status`).
class NzbgetStatus {
  const NzbgetStatus({
    required this.downloadRateBytes,
    required this.remainingSizeMb,
    required this.paused,
    this.freeDiskSpaceMb,
    this.freeInterDiskSpaceMb,
    this.resumeTime,
    this.quotaReached = false,
  });

  /// Current download rate in bytes per second.
  final int downloadRateBytes;

  /// Megabytes remaining across the queue.
  final int remainingSizeMb;

  /// `DownloadPaused`: the download queue is paused. NZBGet sets the same
  /// register for a user's pause and for its own when disk space runs low.
  final bool paused;

  /// `FreeDiskSpaceMB` (or the Hi/Lo pair): free space on `DestDir`, or null
  /// when the reply carried neither.
  final int? freeDiskSpaceMb;

  /// `FreeInterDiskSpaceMB` (NZBGet 24.3 and later): free space on
  /// `InterDir`, where a download is written while it runs. Null on older
  /// daemons.
  final int? freeInterDiskSpaceMb;

  /// `ResumeTime`: when a pause set with `scheduleresume` ends, or null when
  /// none is set.
  final int? resumeTime;

  /// `QuotaReached`: the download quota the user configured is spent.
  final bool quotaReached;

  /// Free space where the queue is being written: `InterDir` when the daemon
  /// reports it, `DestDir` otherwise.
  int? get writingDiskFreeMb => freeInterDiskSpaceMb ?? freeDiskSpaceMb;

  /// A pause somebody set to end, or one the configured quota took: both are
  /// decisions, never a stop.
  bool get isDeliberateStop => (resumeTime ?? 0) > 0 || quotaReached;

  String get rateLabel => formatBytesPerSecond(downloadRateBytes);
  String get remainingLabel => formatMegabytes(remainingSizeMb);

  factory NzbgetStatus.fromJson(Map<String, dynamic> json) {
    // Prefer the direct MB field; fall back to Hi/Lo bytes if absent.
    final remainingMb = json.containsKey('RemainingSizeMB')
        ? intOrNull(json['RemainingSizeMB']) ?? 0
        : combineHiLo(json['RemainingSizeHi'], json['RemainingSizeLo']) ~/
              (1024 * 1024);
    return NzbgetStatus(
      downloadRateBytes: _downloadRate(json),
      remainingSizeMb: remainingMb,
      paused: boolOrFalse(json['DownloadPaused']),
      freeDiskSpaceMb: megabytesOrNull(json, 'FreeDiskSpace'),
      freeInterDiskSpaceMb: megabytesOrNull(json, 'FreeInterDiskSpace'),
      resumeTime: intOrNull(json['ResumeTime']),
      quotaReached: boolOrFalse(json['QuotaReached']),
    );
  }
}

/// The current download rate in bytes per second.
///
/// NZBGet 24.2 deprecated the 32-bit `DownloadRate` for the
/// `DownloadRateLo`/`DownloadRateHi` pair, because a 32-bit rate tops out at
/// 4 GiB/s — and a field NZBGet has deprecated is one it can stop sending. The
/// pair wins whenever either half is there; older daemons, which send only
/// `DownloadRate`, still read.
int _downloadRate(Map<String, dynamic> json) {
  final hi = json['DownloadRateHi'];
  final lo = json['DownloadRateLo'];
  if (intOrNull(hi) != null || intOrNull(lo) != null) {
    return combineHiLo(hi, lo);
  }
  return intOrNull(json['DownloadRate']) ?? 0;
}

/// A queued NZB (`listgroups`).
class NzbgetGroup {
  const NzbgetGroup({
    required this.nzbId,
    required this.name,
    required this.status,
    required this.category,
    required this.fileSizeMb,
    required this.remainingSizeMb,
    this.droneId,
    this.health,
    this.criticalHealth,
    this.parStatus,
    this.unpackStatus,
  });

  final int nzbId;

  /// The `drone` post-processing parameter, when the job carries one.
  ///
  /// Every \*arr that sends an NZB to NZBGet tags it with `drone=<guid>` and
  /// records **that** as the queue record's `downloadId` — the NZBID only when
  /// the job has no such parameter (Sonarr's `Nzbget.cs`, `GetQueue`: the id is
  /// the drone value, else `NzbId`). Radarr, Lidarr and Readarr share the code.
  final String? droneId;

  /// The id an \*arr knows this job by: [droneId] first, the NZBID otherwise.
  ///
  /// The dashboard used to join on the NZBID alone, which is the one spelling
  /// an \*arr never records for a job it sent — so an \*arr grab and the
  /// NZBGet job moving it never met, and one download read as two.
  String get downloadId => droneId ?? '$nzbId';
  final String name;
  final String status;
  final String category;

  /// The job's whole size in megabytes, or **null** when the record carried
  /// neither `FileSizeMB` nor the `FileSizeHi`/`FileSizeLo` pair.
  final int? fileSizeMb;

  /// What is left to fetch, or **null** on the same terms as [fileSizeMb].
  ///
  /// Nullable and not defaulted to zero, which is the whole point: with a `0`
  /// standing in for silence, [progress] computed `(size - 0) / size` == 1 and
  /// a job whose remaining size the server never reported drew a full bar and
  /// read `100%` — a percentage nobody computed, presented as finished. Zero
  /// stays available for what it actually means: a job with nothing left.
  final int? remainingSizeMb;

  /// `Health` and `CriticalHealth`, in permille. Below its critical health a
  /// download cannot be repaired. Null when the record carried none.
  final int? health;
  final int? criticalHealth;

  /// `ParStatus` and `UnpackStatus` of a group being post-processed (`NONE`,
  /// `SUCCESS`, `FAILURE`, and for unpacking `SPACE` and `PASSWORD`).
  final String? parStatus;
  final String? unpackStatus;

  /// 0..1, or **null** when either size is missing and there is therefore
  /// nothing to divide.
  double? get progress {
    final total = fileSizeMb;
    final left = remainingSizeMb;
    if (total == null || left == null || total <= 0) return null;
    return ((total - left) / total).clamp(0, 1).toDouble();
  }

  /// The same value as a whole number, or null on the same terms.
  int? get percentage {
    final value = progress;
    return value == null ? null : wholePercent(value * 100);
  }

  String get remainingLabel {
    final left = remainingSizeMb;
    return left == null ? '—' : formatMegabytes(left);
  }

  factory NzbgetGroup.fromJson(Map<String, dynamic> json) {
    return NzbgetGroup(
      nzbId: intOrNull(json['NZBID']) ?? 0,
      name: (json['NZBName'] ?? json['NZBNicename'] ?? 'Unknown').toString(),
      status: (json['Status'] ?? '').toString(),
      category: (json['Category'] ?? '').toString(),
      fileSizeMb: megabytesOrNull(json, 'FileSize'),
      remainingSizeMb: megabytesOrNull(json, 'RemainingSize'),
      droneId: _droneParameter(json['Parameters']),
      health: intOrNull(json['Health']),
      criticalHealth: intOrNull(json['CriticalHealth']),
      parStatus: stringOrNull(json['ParStatus'])?.toUpperCase(),
      unpackStatus: stringOrNull(json['UnpackStatus'])?.toUpperCase(),
    );
  }

  /// `Parameters` is a list of `{Name, Value}` pairs.
  static String? _droneParameter(Object? parameters) {
    if (parameters is! List) return null;
    for (final parameter in parameters) {
      if (parameter is! Map) continue;
      if (parameter['Name']?.toString().trim() != 'drone') continue;
      final value = parameter['Value']?.toString().trim() ?? '';
      return value.isEmpty ? null : value;
    }
    return null;
  }
}

/// A completed/failed NZB (`history`).
class NzbgetHistoryItem {
  const NzbgetHistoryItem({
    required this.id,
    required this.name,
    required this.status,
    required this.category,
    this.time,
  });

  final int id;
  final String name;
  final String status;
  final String category;
  final DateTime? time;

  /// NZBGet statuses look like `SUCCESS/ALL`, `FAILURE/UNPACK`, etc.
  bool get failed => status.toUpperCase().startsWith('FAILURE');
  bool get success => status.toUpperCase().startsWith('SUCCESS');

  factory NzbgetHistoryItem.fromJson(Map<String, dynamic> json) {
    final historyTime = intOrNull(json['HistoryTime']) ?? 0;
    return NzbgetHistoryItem(
      id: intOrNull(json['ID']) ?? 0,
      name: (json['Name'] ?? json['NZBName'] ?? 'Unknown').toString(),
      status: (json['Status'] ?? '').toString(),
      category: (json['Category'] ?? '').toString(),
      time: historyTime > 0
          ? DateTime.fromMillisecondsSinceEpoch(historyTime * 1000)
          : null,
    );
  }
}

/// One configured RSS feed, reconstructed from NZBGet's `config` option list.
///
/// NZBGet has no public `listfeeds` JSON-RPC method. Feeds are numbered config
/// groups (`Feed1.Name`, `Feed1.URL`, ...), so reading `config` is the protocol
/// supported way to enumerate them without pretending a private WebUI call is
/// an RPC endpoint.
class NzbgetFeed {
  const NzbgetFeed({
    required this.index,
    required this.name,
    required this.url,
    required this.intervalMinutes,
    required this.category,
    required this.priority,
    required this.backlog,
    required this.pauseNzb,
  });

  final int index;
  final String name;
  final String url;
  final int intervalMinutes;
  final String category;
  final int priority;
  final bool backlog;
  final bool pauseNzb;
}

/// One line from the screen log returned by `log`.
class NzbgetMessage {
  const NzbgetMessage({
    required this.id,
    required this.kind,
    required this.time,
    required this.text,
  });

  final int id;
  final String kind;
  final DateTime? time;
  final String text;

  bool get isFault {
    final normalized = kind.toUpperCase();
    return normalized == 'WARNING' || normalized == 'ERROR';
  }

  factory NzbgetMessage.fromJson(Map<String, dynamic> json) {
    final seconds = intOrNull(json['Time']) ?? 0;
    return NzbgetMessage(
      id: intOrNull(json['ID']) ?? 0,
      kind: json['Kind']?.toString() ?? '',
      time: seconds > 0
          ? DateTime.fromMillisecondsSinceEpoch(seconds * 1000)
          : null,
      text: json['Text']?.toString() ?? '',
    );
  }
}

/// Converts the `config` array (`{Name, Value}`) into numbered feed records.
List<NzbgetFeed> nzbgetFeedsFromConfig(Object? raw) {
  if (raw is! List) return const [];
  final grouped = <int, Map<String, String>>{};
  final pattern = RegExp(r'^Feed(\d+)\.(.+)$', caseSensitive: false);
  for (final option in raw.whereType<Map>()) {
    final name = option['Name']?.toString() ?? '';
    final match = pattern.firstMatch(name);
    if (match == null) continue;
    final index = int.tryParse(match.group(1) ?? '');
    final key = match.group(2);
    if (index == null || key == null) continue;
    grouped.putIfAbsent(index, () => <String, String>{})[key.toLowerCase()] =
        option['Value']?.toString() ?? '';
  }

  bool yes(String? value) => value?.trim().toLowerCase() == 'yes';

  final indexes = grouped.keys.toList()..sort();
  return List.unmodifiable([
    for (final index in indexes)
      if ((grouped[index]!['url'] ?? '').trim().isNotEmpty)
        NzbgetFeed(
          index: index,
          name: (grouped[index]!['name'] ?? '').trim(),
          url: grouped[index]!['url']!.trim(),
          intervalMinutes: int.tryParse(grouped[index]!['interval'] ?? '') ?? 0,
          category: (grouped[index]!['category'] ?? '').trim(),
          priority: int.tryParse(grouped[index]!['priority'] ?? '') ?? 0,
          backlog: yes(grouped[index]!['backlog']),
          pauseNzb: yes(grouped[index]!['pausenzb']),
        ),
  ]);
}
