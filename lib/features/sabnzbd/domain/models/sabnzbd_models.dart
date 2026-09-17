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

/// SABnzbd reports decimals with the server's locale separator, so a comma has
/// to become a dot before parsing — which is why this is not `doubleOrNull`.
double _asDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value'.replaceAll(',', '.')) ?? 0;
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
  });

  final bool paused;
  final String status;

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
  });

  final String nzoId;
  final String filename;
  final String status;
  final int percentage;
  final String category;
  final String timeLeft;
  final double mbLeft;

  double get progress => (percentage / 100).clamp(0, 1).toDouble();
  String get sizeLeftLabel => formatMegabytes(mbLeft);

  factory SabnzbdQueueSlot.fromJson(Map<String, dynamic> json) {
    return SabnzbdQueueSlot(
      nzoId: (json['nzo_id'] ?? '').toString(),
      filename: (json['filename'] ?? json['name'] ?? 'Unknown').toString(),
      status: (json['status'] ?? '').toString(),
      percentage: _asDouble(json['percentage']).round(),
      category: (json['cat'] ?? '').toString(),
      timeLeft: (json['timeleft'] ?? '').toString(),
      mbLeft: _asDouble(json['mbleft']),
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
  const SabnzbdServerStats({required this.total});

  /// Total bytes downloaded over all time.
  final int total;

  String get totalLabel => formatBytes(total);

  factory SabnzbdServerStats.fromJson(Map<String, dynamic> json) {
    return SabnzbdServerStats(total: _asDouble(json['total']).round());
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
