/// Which arr item a download belongs to: the one join between an \*arr's
/// queue and the download clients moving its bytes.
///
/// Home and Activity both read it. Activity had none: a torrent qBittorrent
/// called stalled read "Downloading" there because its arr still said so,
/// while Home had already made it a decision. One function, so the two
/// surfaces cannot disagree about which download is which.
library;

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/services/domain/in_flight.dart';

/// The key a download goes by on both sides, case-folded.
///
/// An \*arr queue record names the client's own id for the transfer it tracks
/// in `downloadId`: the torrent hash (upper case; qBittorrent and
/// Transmission report it in lower), the SABnzbd `nzo_id`, the NZBGet job's
/// `drone` parameter (its NZBID only when it has none). So the two rows for
/// one grab are the same key in two spellings.
String downloadJoinKey(String? id) => id?.trim().toLowerCase() ?? '';

/// One arr row and the client row moving the same bytes, when one is.
typedef JoinedDownload<A, C> = ({A arr, C? client});

/// The arr rows, each with its client row, in the arr's order, and the client
/// rows no arr claims: a torrent added by hand.
class DownloadJoin<A, C> {
  const DownloadJoin({required this.joined, required this.unclaimed});

  final List<JoinedDownload<A, C>> joined;

  /// In the clients' order.
  final List<C> unclaimed;
}

/// Matches every arr row to the client row with the same download id.
///
/// Several arr rows may meet one client row: Sonarr files a season pack as
/// one record per episode, all carrying the torrent's id, and each of them
/// is that torrent. The first client row with an id wins when two clients
/// report the same one. A row with no id joins nothing: nothing says which
/// download it is.
///
/// Pure and generic, so Home's rows and Activity's records go through the same
/// rule and it is testable without a container.
DownloadJoin<A, C> joinDownloads<A, C>({
  required Iterable<A> arr,
  required Iterable<C> clients,
  required String? Function(A row) arrDownloadId,
  required String? Function(C row) clientDownloadId,
}) {
  final clientRows = clients.toList(growable: false);
  final byId = <String, int>{};
  for (var index = 0; index < clientRows.length; index++) {
    final id = downloadJoinKey(clientDownloadId(clientRows[index]));
    if (id.isNotEmpty) byId.putIfAbsent(id, () => index);
  }

  final claimed = <int>{};
  final joined = <JoinedDownload<A, C>>[];
  for (final row in arr) {
    final id = downloadJoinKey(arrDownloadId(row));
    final index = id.isEmpty ? null : byId[id];
    if (index != null) claimed.add(index);
    joined.add((arr: row, client: index == null ? null : clientRows[index]));
  }

  return DownloadJoin(
    joined: joined,
    unclaimed: [
      for (var index = 0; index < clientRows.length; index++)
        if (!claimed.contains(index)) clientRows[index],
    ],
  );
}

/// An arr queue record's status once the client moving its bytes has been
/// read: the rule Home's joined row follows, for a surface that draws the
/// record's own status.
///
/// The arr's fault first ([arrFault]): an import it refuses is the more
/// specific truth. The client's second: the arr polls its client on a
/// minute's delay and can still be calling a stalled or broken transfer
/// "downloading". Either way a fault is amber. Otherwise the record keeps its
/// own status, with the client's [clientProgress], which is fresher.
MediaStatusInfo queueStatusWithClient(
  MediaStatusInfo arr, {
  required InFlightFault? arrFault,
  required InFlightFault? clientFault,
  String? clientReason,
  double? clientProgress,
}) {
  if (arrFault == null && clientFault != null) {
    return MediaStatusInfo(
      availability: arr.availability,
      pipeline: clientFault == InFlightFault.failed
          ? MediaPipeline.failed
          : MediaPipeline.stalled,
      progress: clientProgress ?? arr.progress,
      unmonitored: arr.unmonitored,
      hasWarning: true,
      detail: clientReason ?? arr.detail,
      toneOverride: StatusTone.warning,
    );
  }
  if (clientProgress == null || clientProgress == arr.progress) return arr;
  return MediaStatusInfo(
    availability: arr.availability,
    pipeline: arr.pipeline,
    progress: clientProgress,
    unmonitored: arr.unmonitored,
    hasWarning: arr.hasWarning,
    detail: arr.detail,
    labelOverride: arr.labelOverride,
    toneOverride: arr.toneOverride,
    glyph: arr.glyph,
  );
}
