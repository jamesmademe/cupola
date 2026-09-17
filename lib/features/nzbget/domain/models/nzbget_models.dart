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
  });

  /// Current download rate in bytes per second.
  final int downloadRateBytes;

  /// Megabytes remaining across the queue.
  final int remainingSizeMb;

  final bool paused;

  String get rateLabel => formatBytesPerSecond(downloadRateBytes);
  String get remainingLabel => formatMegabytes(remainingSizeMb);

  factory NzbgetStatus.fromJson(Map<String, dynamic> json) {
    // Prefer the direct MB field; fall back to Hi/Lo bytes if absent.
    final remainingMb = json.containsKey('RemainingSizeMB')
        ? intOrNull(json['RemainingSizeMB']) ?? 0
        : combineHiLo(json['RemainingSizeHi'], json['RemainingSizeLo']) ~/
              (1024 * 1024);
    return NzbgetStatus(
      downloadRateBytes: intOrNull(json['DownloadRate']) ?? 0,
      remainingSizeMb: remainingMb,
      paused: boolOrFalse(json['DownloadPaused']),
    );
  }
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
  });

  final int nzbId;
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
    return value == null ? null : (value * 100).round();
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
    );
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
