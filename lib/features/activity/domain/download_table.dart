/// The desktop's table of downloads: its columns, how each sorts, and what
/// each cell says.
library;

import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/status/media_status.dart' show StatusTone;
import 'package:cupola/core/utils/byte_format.dart';
import 'package:cupola/core/utils/duration_format.dart';
import 'package:cupola/core/utils/percent_format.dart';
import 'package:cupola/features/activity/domain/activity_download.dart';
import 'package:cupola/features/activity/domain/download_page.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/home/domain/downloads.dart'
    show isDownloadFault, stuckValue;
import 'package:cupola/features/requests/domain/my_requests.dart'
    show aroundWords;
import 'package:cupola/features/services/presentation/services_provider.dart'
    show ServiceQueueItem;

/// A column of the table.
enum DownloadColumn {
  title('Title'),
  progress('Progress'),
  speed('Speed'),
  left('Left');

  const DownloadColumn(this.label);

  /// Its name in the header.
  final String label;

  /// Which way it sorts first: the furthest along and the fastest first,
  /// the soonest done first, A to Z.
  bool get descendingFirst =>
      this == DownloadColumn.progress || this == DownloadColumn.speed;
}

/// The table's order: a column and which way.
typedef DownloadSort = ({DownloadColumn column, bool descending});

/// The order after a click on [column]'s header, from [current]: its first
/// way, then the other, then back to the queue's own order (null).
DownloadSort? nextDownloadSort(DownloadSort? current, DownloadColumn column) {
  if (current == null || current.column != column) {
    return (column: column, descending: column.descendingFirst);
  }
  if (current.descending == column.descendingFirst) {
    return (column: column, descending: !current.descending);
  }
  return null;
}

/// [items] in [sort]'s order, or as given (the queue's own, the stuck ones
/// last) when null. What a column cannot say (no speed, no time left) goes
/// last either way. Stable: equal rows keep their order.
List<ServiceQueueItem> sortDownloads(
  List<ServiceQueueItem> items,
  DownloadSort? sort,
) {
  if (sort == null) return items;
  final indexed = items.indexed.toList();
  int compare((int, ServiceQueueItem) a, (int, ServiceQueueItem) b) {
    final order = switch (sort.column) {
      DownloadColumn.title => _known(
        a.$2.title.toLowerCase(),
        b.$2.title.toLowerCase(),
        sort.descending,
      ),
      DownloadColumn.progress => _known(
        a.$2.progress,
        b.$2.progress,
        sort.descending,
      ),
      DownloadColumn.speed => _known(
        _movingRate(a.$2),
        _movingRate(b.$2),
        sort.descending,
      ),
      DownloadColumn.left => _known(
        _etaOf(a.$2),
        _etaOf(b.$2),
        sort.descending,
      ),
    };
    return order != 0 ? order : a.$1.compareTo(b.$1);
  }

  indexed.sort(compare);
  return [for (final (_, item) in indexed) item];
}

/// [a] against [b] in the order asked, an unknown one last whichever way.
int _known<T extends Comparable<Object>>(T? a, T? b, bool descending) {
  if (a == null || b == null) {
    if (a == null && b == null) return 0;
    return a == null ? 1 : -1;
  }
  return descending ? b.compareTo(a) : a.compareTo(b);
}

int? _movingRate(ServiceQueueItem item) =>
    item.isMoving ? item.rateBytesPerSecond : null;

int? _etaOf(ServiceQueueItem item) {
  final eta = item.etaSeconds;
  return item.isMoving && eta != null && eta > 0 ? eta : null;
}

/// The Progress cell and its tone: `62%` in blue while it moves, `Stopped at
/// 62%` in the neutral once stopped, `Stuck at 47%` or `Failed` in amber,
/// `Queued · starts in about 6 min` in blue.
({String text, StatusTone tone}) downloadProgressCell(ServiceQueueItem item) {
  final percent = item.progress == null
      ? null
      : wholePercent(item.progress! * 100);
  final stand = downloadStandOf(item);
  final tone = downloadStandTone(stand);
  final text = switch (stand) {
    DownloadStand.stuck ||
    DownloadStand.failed ||
    DownloadStand.needsImport => stuckValue(item.fault!, percent: percent),
    DownloadStand.queued => queuedWords(item.startsInSeconds),
    DownloadStand.stopped =>
      percent == null
          ? StateWord.stopped.label
          : '${StateWord.stopped.label} at ${formatPercent(percent)}',
    DownloadStand.downloading =>
      percent == null ? Lexicon.noFigure : formatPercent(percent),
  };
  return (text: text, tone: tone);
}

/// The Speed cell: `4.2 MB/s` while it moves and its client measures it, the
/// dash otherwise.
String downloadSpeedCell(ServiceQueueItem item) => switch (_movingRate(item)) {
  final rate? => formatBytesPerSecond(rate),
  null => Lexicon.noFigure,
};

/// The Left cell: `11 min`, and under it when it should be done, `around
/// 21:10`; the dash when its client gave no estimate or it does not move.
({String left, String? around}) downloadLeftCell(
  ServiceQueueItem item, {
  required DateTime now,
}) {
  final eta = _etaOf(item);
  if (eta == null) return (left: Lexicon.noFigure, around: null);
  return (
    left: formatTimeSpan(Duration(seconds: eta)),
    around: 'around ${aroundWords(now.add(Duration(seconds: eta)), now: now)}',
  );
}

/// The line under the release: which way its bytes travel, and who asked or
/// since when nothing arrived: `Radarr → qBittorrent · Anna asked`, `Radarr →
/// qBittorrent · nothing for 3 h`. In a narrow table ([withFigures]) the
/// speed and the time left join it, since their columns are not drawn:
/// `Radarr → qBittorrent · 4.2 MB/s · 11 min left`.
String downloadRouteLine(
  ServiceQueueItem item, {
  SeerrRequest? request,
  required DateTime now,
  bool withFigures = false,
}) {
  final who = request?.requestedBy?.displayName.trim();
  final eta = _etaOf(item);
  final rate = _movingRate(item);
  return [
    downloadRoute(item),
    if (withFigures && rate != null) formatBytesPerSecond(rate),
    if (withFigures && eta != null)
      '${formatTimeSpan(Duration(seconds: eta))} left',
    if (isDownloadFault(item.fault))
      ?nothingForWords(item.stalledSince, now: now)
    else if (who != null && who.isNotEmpty)
      '$who asked',
  ].join(' · ');
}
