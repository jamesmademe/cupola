import 'package:flutter/foundation.dart';

import 'package:cupola/core/utils/dynamic_map_utils.dart';

/// Where a download Seerr follows stands, from the arr's queue `status`.
enum SeerrDownloadState {
  /// Moving.
  downloading,

  /// Waiting its turn, or held back on purpose (`queued`, `delay`).
  queued,

  /// Paused by whoever runs the client.
  paused,

  /// Transferred, being moved into the library (`completed`).
  done,

  /// Not moving for a reason the arr flags (`warning`, `failed`, the client
  /// gone): the operator's fault to see to.
  stuck,

  /// A status this app does not know.
  other;

  static SeerrDownloadState of(String? status) => switch (status) {
    'downloading' => SeerrDownloadState.downloading,
    'queued' || 'delay' => SeerrDownloadState.queued,
    'paused' => SeerrDownloadState.paused,
    'completed' => SeerrDownloadState.done,
    'warning' ||
    'failed' ||
    'downloadClientUnavailable' => SeerrDownloadState.stuck,
    _ => SeerrDownloadState.other,
  };
}

/// One download Seerr follows for a title: a row of its media's
/// `downloadStatus`, which Seerr fills from the first rows of each arr's
/// queue once a minute.
///
/// The release's name travels with it and is never read: the requester
/// reads how far it got and when it should end, nothing that names a file.
@immutable
class SeerrDownload {
  const SeerrDownload({
    required this.size,
    required this.sizeLeft,
    required this.state,
    this.finishesAt,
  });

  /// Bytes in all, and still to come.
  final int size;
  final int sizeLeft;

  final SeerrDownloadState state;

  /// When the client expects the transfer to end (`estimatedCompletionTime`),
  /// on this device's clock; null when it does not say.
  final DateTime? finishesAt;

  /// How far it got, 0 to 1, or null when the size is not known.
  double? get progress =>
      size > 0 ? ((size - sizeLeft) / size).clamp(0, 1).toDouble() : null;

  static SeerrDownload? fromJson(Object? json) {
    if (json is! Map) return null;
    return SeerrDownload(
      size: intOrNull(json['size']) ?? 0,
      sizeLeft: intOrNull(json['sizeLeft']) ?? 0,
      state: SeerrDownloadState.of(json['status']?.toString()),
      finishesAt: DateTime.tryParse(
        json['estimatedCompletionTime']?.toString() ?? '',
      )?.toLocal(),
    );
  }

  /// The rows of a `downloadStatus` list; anything that is not one is
  /// dropped.
  static List<SeerrDownload> listOf(Object? json) =>
      json is List ? [for (final row in json) ?fromJson(row)] : const [];
}

/// The downloads of one request, read together: a series' episodes are one
/// transfer to the person who asked for it.
extension SeerrDownloadsX on List<SeerrDownload> {
  /// Whether every row is moving and its size is known: the only reading
  /// that earns a percentage. A row held, stuck or of no size, and the
  /// request is simply on its way.
  bool get moving =>
      isNotEmpty &&
      every(
        (download) =>
            download.state == SeerrDownloadState.downloading &&
            download.size > 0,
      );

  /// How far the rows got together, by bytes; null unless [moving].
  double? get progress {
    if (!moving) return null;
    final size = fold<int>(0, (sum, download) => sum + download.size);
    final left = fold<int>(0, (sum, download) => sum + download.sizeLeft);
    return ((size - left) / size).clamp(0, 1).toDouble();
  }

  /// When the last of them should end; null unless [moving] and every row
  /// says.
  DateTime? get finishesAt {
    if (!moving) return null;
    DateTime? last;
    for (final download in this) {
      final at = download.finishesAt;
      if (at == null) return null;
      if (last == null || at.isAfter(last)) last = at;
    }
    return last;
  }
}
