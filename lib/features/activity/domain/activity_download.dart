/// The words of a download on Activity: which way its bytes travel, how long
/// nothing has arrived, when a waiting one starts.
library;

import 'package:cupola/core/utils/duration_format.dart';
import 'package:cupola/core/utils/unit_space.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/requests/domain/my_requests.dart'
    show aroundWords;
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart'
    show serviceWithConnection;
import 'package:cupola/features/services/presentation/services_provider.dart'
    show ServiceQueueItem;

/// Who asked and who moves the bytes: `Radarr → qBittorrent`, `Radarr 4K →
/// SABnzbd`; the client alone on a transfer no arr asked for.
String downloadRoute(ServiceQueueItem item) {
  final client = item.clientService;
  if (client == null || client == item.service) {
    return item.clientLabel.isEmpty ? item.service.title : item.clientLabel;
  }
  final arr = serviceWithConnection(
    item.service,
    item.connectionName,
    joiner: ' ',
  );
  return '$arr → ${item.clientLabel}';
}

/// How long nothing has arrived, as the stuck row's proof says it: `nothing
/// for 3 h`, `nothing for 40 min`, `nothing for 2 days`. Null when the
/// client did not date it.
String? nothingForWords(DateTime? since, {required DateTime now}) {
  if (since == null) return null;
  final idle = now.difference(since);
  if (idle.isNegative) return null;
  final words = switch (idle) {
    _ when idle.inDays >= 2 => '${idle.inDays} days',
    _ when idle.inHours >= 1 => withUnit(idle.inHours, 'h'),
    _ => withUnit(idle.inMinutes, 'min'),
  };
  return 'nothing for $words';
}

/// What a download waiting its turn says: `Queued · starts in about 6 min`
/// where its client estimates it (SABnzbd), `Queued` elsewhere.
String queuedWords(int? startsInSeconds) {
  if (startsInSeconds == null || startsInSeconds <= 0) return 'Queued';
  return 'Queued · starts in about '
      '${formatTimeSpan(Duration(seconds: startsInSeconds))}';
}

/// The household request that asked for [item], among [requests]: the same
/// movie by TMDB, or the same series by TVDB or TMDB, asked for and not
/// declined. Null for a download nobody asked for through Seerr, and for a
/// row that names no title.
SeerrRequest? requestFor(
  ServiceQueueItem item,
  Iterable<SeerrRequest> requests,
) {
  final movie = item.service == ServiceKey.radarr;
  final series = item.service == ServiceKey.sonarr;
  if (!movie && !series) return null;
  for (final request in requests) {
    if (request.status == RequestStatus.declined ||
        request.status == RequestStatus.failed) {
      continue;
    }
    final media = request.media;
    if (media == null) continue;
    final same = movie
        ? request.type == 'movie' &&
              item.tmdbId != null &&
              media.tmdbId == item.tmdbId
        : request.type == 'tv' &&
              ((item.tvdbId != null && media.tvdbId == item.tvdbId) ||
                  (item.tmdbId != null && media.tmdbId == item.tmdbId));
    if (same) return request;
  }
  return null;
}

/// Who asked for a download and when it should be ready: `Anna's request ·
/// ready around 21:10`, `Anna's request` with no estimate. Null when the
/// request names nobody.
String? requestLine(
  ServiceQueueItem item,
  SeerrRequest request, {
  required DateTime now,
}) {
  final who = request.requestedBy?.displayName.trim();
  if (who == null || who.isEmpty) return null;
  final eta = item.etaSeconds;
  final ready = eta == null || eta <= 0 || item.queued
      ? null
      : aroundWords(now.add(Duration(seconds: eta)), now: now);
  return ready == null
      ? "$who's request"
      : "$who's request · ready around $ready";
}
