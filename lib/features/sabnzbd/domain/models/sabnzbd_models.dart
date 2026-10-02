/// Typed models for the SABnzbd HTTP API. SABnzbd returns most numeric fields
/// as strings, so parsing is deliberately tolerant.
///
/// Every size and rate label here goes through `core/utils/byte_format.dart`.
/// This file used to carry two private formatters of its own — one for
/// megabytes, one for bytes — which disagreed with each other on precision and
/// with NZBGet's pair on unit thresholds, so the same quantity read differently
/// depending on which dashboard you were looking at.
library;

import 'package:cupola/core/utils/byte_format.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/core/utils/percent_format.dart';

/// SABnzbd reports decimals with the server's locale separator, so a comma has
/// to become a dot before parsing — which is why this is not `doubleOrNull`.
///
/// Null when the field was absent, blank or unreadable. Kept separate from
/// [_asDouble] because the two answers are different facts: a size the server
/// reported as zero is zero, and a size it never reported is not a size at all
/// — and the second one has to reach the UI as an absence so the row can drop
/// the clause instead of printing a fabricated `0 B`.
double? _asDoubleOrNull(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  final text = '$value'.trim();
  if (text.isEmpty) return null;
  return double.tryParse(text.replaceAll(',', '.'));
}

double _asDouble(dynamic value) => _asDoubleOrNull(value) ?? 0;

/// A size that is only a size when it is above zero.
///
/// SABnzbd answers `mb: 0` for a job whose full size it does not yet know — a
/// fetched-but-unparsed NZB, a job still being grabbed — and zero beside a
/// gigabyte still to fetch is a contradiction, not a measurement. Folded into
/// the same absence as a missing field so exactly one branch downstream has to
/// handle "no total".
double? _asPositiveDouble(dynamic value) {
  final parsed = _asDoubleOrNull(value);
  if (parsed == null || parsed <= 0 || !parsed.isFinite) return null;
  return parsed;
}

/// The download queue (`mode=queue`).
class SabnzbdQueue {
  const SabnzbdQueue({
    required this.paused,
    required this.status,
    required this.kbPerSec,
    required this.mbLeft,
    required this.mb,
    required this.timeLeft,
    required this.slots,
    this.reportedSlots,
    this.pauseInterval = '0',
    this.downloadDiskFreeGb,
  });

  /// `paused`: the downloader is stopped. SABnzbd sets it for a user's pause
  /// and for its own: a full disk stops the queue through the same
  /// `Downloader.pause()` (`assembler.py`), so the flag alone cannot say
  /// which.
  final bool paused;
  final String status;

  /// `pause_int`: the time left on a timed pause, `"0"` when there is none.
  /// A timed pause is always somebody's decision.
  final String pauseInterval;

  /// `diskspace1`: free space in the download (incomplete) folder, in GB, or
  /// null when the payload did not carry it.
  final double? downloadDiskFreeGb;

  /// A timed pause is running.
  bool get isTimedPause {
    final left = pauseInterval.trim();
    return left.isNotEmpty && left != '0';
  }

  /// Current download speed in kilobytes per second.
  final double kbPerSec;

  /// Megabytes remaining across the queue.
  final double mbLeft;

  /// Total megabytes queued.
  final double mb;

  final String timeLeft;

  /// The slots this page was handed, never more than the `limit` the request
  /// asked for.
  final List<SabnzbdQueueSlot> slots;

  /// The queue's true depth as `mode=queue` states it (`noofslots_total`), or
  /// null when the server did not say.
  ///
  /// [slots] is one page of a queue that can be deeper, so a count taken from
  /// its length is the size of the request rather than the size of the queue.
  /// Read [jobCount], never `slots.length`, wherever the number is shown to
  /// someone.
  final int? reportedSlots;

  /// How many jobs are queued: the server's own figure where it gave one, and
  /// the page length where it did not.
  ///
  /// Never below the number of slots in hand — a `noofslots_total` smaller than
  /// the page it came with describes a different queue than the one being
  /// drawn, and the rows on screen are the floor of what can honestly be
  /// counted.
  int get jobCount {
    final reported = reportedSlots;
    if (reported == null || reported < slots.length) return slots.length;
    return reported;
  }

  String get speedLabel => formatKilobytesPerSecond(kbPerSec);

  String get sizeLeftLabel => formatMegabytes(mbLeft);

  factory SabnzbdQueue.fromJson(Map<String, dynamic> json) {
    final slots = (json['slots'] as List?) ?? const [];
    return SabnzbdQueue(
      paused: boolOrFalse(json['paused']),
      status: (json['status'] ?? '').toString(),
      kbPerSec: _asDouble(json['kbpersec']),
      mbLeft: _asDouble(json['mbleft']),
      mb: _asDouble(json['mb']),
      timeLeft: (json['timeleft'] ?? '0:00:00').toString(),
      slots: slots
          .whereType<Map>()
          .map((e) => SabnzbdQueueSlot.fromJson(e.cast<String, dynamic>()))
          .toList(growable: false),
      // `noofslots_total` is the whole queue; `noofslots` is what the current
      // view holds after the limit and any filter. The total first, the view as
      // a fallback, and null when the payload carries neither — a depth nobody
      // reported is not a depth to invent.
      reportedSlots:
          intOrNull(json['noofslots_total']) ?? intOrNull(json['noofslots']),
      pauseInterval: (json['pause_int'] ?? '0').toString(),
      downloadDiskFreeGb: _asDoubleOrNull(json['diskspace1']),
    );
  }
}

/// A single active download in the queue.
class SabnzbdQueueSlot {
  const SabnzbdQueueSlot({
    required this.nzoId,
    required this.filename,
    required this.status,
    required this.percentage,
    required this.category,
    required this.timeLeft,
    required this.mbLeft,
    this.mb,
    this.labels = const [],
  });

  final String nzoId;
  final String filename;
  final String status;
  final int percentage;
  final String category;
  final String timeLeft;

  /// Megabytes still to fetch for this job (`mbleft`).
  final double mbLeft;

  /// The job's full size in megabytes (`mb`), or null when the slot carried
  /// no usable one.
  ///
  /// Nullable on purpose. `mbleft` alone answers "how much is still coming"
  /// and says nothing about how big the job is, so `1.2 GB left` reads the
  /// same on a download a third of the way in as on one that is nearly done.
  /// `mode=queue` returns `mb` on every slot beside `mbleft`, so the figure is
  /// a parse away — but a server that omits it must leave the clause off the
  /// row rather than have a total invented for it.
  final double? mb;

  /// `labels`: SABnzbd's own marks on the job, in its own words and
  /// language (`DUPLICATE`, `ENCRYPTED`, `TOO LARGE`, `PROPAGATING 5 min`).
  final List<String> labels;

  double get progress => (percentage / 100).clamp(0, 1).toDouble();
  String get sizeLeftLabel => formatMegabytes(mbLeft);

  /// The job's full size, or null when SABnzbd did not report one.
  String? get sizeLabel {
    final total = mb;
    return total == null ? null : formatMegabytes(total);
  }

  /// What a queue row says about size: `1.2 GB left of 3.4 GB`.
  ///
  /// Falls back to `1.2 GB left` — the clause dropped, never `1.2 GB left of
  /// 0 B` and never an em dash wedged mid-sentence — when [mb] is absent. A
  /// dash inside a dotted detail line reads as a figure that failed to load,
  /// where the truth is that this server never claimed one.
  ///
  /// The scale is deliberately *not* re-derived into a percentage here:
  /// SABnzbd reports `percentage` itself, and computing one from a total that
  /// may be missing is the guess this getter exists to refuse.
  String get sizeProgressLabel {
    final total = sizeLabel;
    return total == null
        ? '$sizeLeftLabel left'
        : '$sizeLeftLabel left of $total';
  }

  factory SabnzbdQueueSlot.fromJson(Map<String, dynamic> json) {
    return SabnzbdQueueSlot(
      nzoId: (json['nzo_id'] ?? '').toString(),
      filename: (json['filename'] ?? json['name'] ?? 'Unknown').toString(),
      status: (json['status'] ?? '').toString(),
      percentage: wholePercent(_asDouble(json['percentage'])),
      category: (json['cat'] ?? '').toString(),
      timeLeft: (json['timeleft'] ?? '').toString(),
      mbLeft: _asDouble(json['mbleft']),
      // The one field on this slot that is allowed to be absent, and the
      // reason `_asPositiveDouble` exists: every other figure here has a
      // defensible zero, a total does not.
      mb: _asPositiveDouble(json['mb']),
      labels: [
        for (final label in (json['labels'] as List?) ?? const [])
          if ('$label'.trim().isNotEmpty) '$label'.trim(),
      ],
    );
  }
}

/// Aggregate transfer statistics (`mode=server_stats`).
///
/// SABnzbd reports totals in bytes, and the response also carries `month`,
/// `week` and `day` roll-ups plus a per-server breakdown. None of them are
/// modelled: the dashboard shows the all-time total and nothing else, and a
/// field that is parsed but never read is one more thing to keep in step with
/// the API for no one's benefit.
class SabnzbdServerStats {
  const SabnzbdServerStats({
    required this.total,
    required this.month,
    required this.week,
    required this.day,
    required this.servers,
  });

  /// Total bytes downloaded over all time.
  final int total;
  final int month;
  final int week;
  final int day;
  final List<SabnzbdServerUsage> servers;

  String get totalLabel => formatBytes(total);
  String get monthLabel => formatBytes(month);
  String get weekLabel => formatBytes(week);
  String get dayLabel => formatBytes(day);

  factory SabnzbdServerStats.fromJson(Map<String, dynamic> json) {
    final rawServers = json['servers'];
    return SabnzbdServerStats(
      total: _asDouble(json['total']).round(),
      month: _asDouble(json['month']).round(),
      week: _asDouble(json['week']).round(),
      day: _asDouble(json['day']).round(),
      servers: rawServers is Map
          ? [
              for (final entry in rawServers.entries)
                if (entry.value is Map)
                  SabnzbdServerUsage.fromJson(
                    entry.key.toString(),
                    (entry.value as Map).cast<String, dynamic>(),
                  ),
            ]
          : const [],
    );
  }
}

class SabnzbdServerUsage {
  const SabnzbdServerUsage({
    required this.name,
    required this.totalBytes,
    required this.articlesTried,
    required this.articlesSucceeded,
  });

  final String name;
  final int totalBytes;
  final int articlesTried;
  final int articlesSucceeded;

  int get articlesFailed =>
      (articlesTried - articlesSucceeded).clamp(0, articlesTried);
  String get totalLabel => formatBytes(totalBytes);

  factory SabnzbdServerUsage.fromJson(String name, Map<String, dynamic> json) =>
      SabnzbdServerUsage(
        name: name,
        totalBytes: _asDouble(json['total']).round(),
        articlesTried: _asDouble(json['articles_tried']).round(),
        articlesSucceeded: _asDouble(json['articles_success']).round(),
      );
}

/// One configured news server from `mode=get_config&section=servers`.
class SabnzbdServerConfig {
  const SabnzbdServerConfig({
    required this.name,
    required this.host,
    required this.port,
    required this.connections,
    required this.enabled,
    required this.ssl,
    required this.optional,
    required this.priority,
  });

  final String name;
  final String host;
  final int port;
  final int connections;
  final bool enabled;
  final bool ssl;
  final bool optional;
  final int priority;

  factory SabnzbdServerConfig.fromJson(Map<String, dynamic> json) {
    return SabnzbdServerConfig(
      name: (json['displayname'] ?? json['name'] ?? '').toString(),
      host: (json['host'] ?? '').toString(),
      port: intOrNull(json['port']) ?? 0,
      connections: intOrNull(json['connections']) ?? 0,
      enabled: boolOrFalse(json['enable']),
      ssl: boolOrFalse(json['ssl']),
      optional: boolOrFalse(json['optional']),
      priority: intOrNull(json['priority']) ?? 0,
    );
  }
}

/// A completed/failed download from history (`mode=history`).
class SabnzbdHistorySlot {
  const SabnzbdHistorySlot({
    required this.nzoId,
    required this.name,
    required this.status,
    required this.category,
    required this.bytes,
    required this.completed,
    this.failMessage,
  });

  final String nzoId;
  final String name;
  final String status;
  final String category;
  final int bytes;
  final DateTime? completed;
  final String? failMessage;

  bool get failed => status.toLowerCase() == 'failed';

  factory SabnzbdHistorySlot.fromJson(Map<String, dynamic> json) {
    final completedRaw = json['completed'];
    DateTime? completed;
    if (completedRaw is num) {
      completed = DateTime.fromMillisecondsSinceEpoch(
        completedRaw.toInt() * 1000,
      );
    } else if (completedRaw != null) {
      final asInt = int.tryParse('$completedRaw');
      if (asInt != null) {
        completed = DateTime.fromMillisecondsSinceEpoch(asInt * 1000);
      }
    }
    final fail = (json['fail_message'] ?? '').toString();
    return SabnzbdHistorySlot(
      nzoId: (json['nzo_id'] ?? '').toString(),
      name: (json['name'] ?? 'Unknown').toString(),
      status: (json['status'] ?? '').toString(),
      category: (json['category'] ?? '').toString(),
      bytes: _asDouble(json['bytes']).round(),
      completed: completed,
      failMessage: fail.isEmpty ? null : fail,
    );
  }
}
