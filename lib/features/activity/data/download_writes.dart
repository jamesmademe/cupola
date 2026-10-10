/// What a download's page writes to the client moving its bytes.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/activity/domain/download_page.dart';
import 'package:cupola/features/nzbget/presentation/nzbget_provider.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_provider.dart';
import 'package:cupola/features/sabnzbd/presentation/sabnzbd_provider.dart';
import 'package:cupola/features/services/domain/download_join.dart'
    show downloadJoinKey;
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/transmission/presentation/transmission_provider.dart';

/// Stops [download] in its client, keeping what has arrived, or resumes it
/// ([stopped] false): qBittorrent's stop and start, Transmission's
/// `torrent-stop` and `torrent-start`, SABnzbd's and NZBGet's pause and
/// resume of one job.
///
/// NZBGet edits a job by its NZBID, which a row does not carry when an
/// \*arr named the job (its `drone` id): the client's groups are read to
/// find it.
Future<void> setDownloadStopped(
  WidgetRef ref,
  DownloadClientHandle download, {
  required bool stopped,
}) async {
  switch (download.client) {
    case ServiceKey.qbittorrent:
      final client = ref.read(
        qbittorrentServiceForProvider(download.instanceId),
      );
      stopped
          ? await client.pauseTorrents([download.id])
          : await client.resumeTorrents([download.id]);
    case ServiceKey.transmission:
      final client = ref.read(
        transmissionClientForProvider(download.instanceId),
      );
      stopped
          ? await client.stop([download.id])
          : await client.start([download.id]);
    case ServiceKey.sabnzbd:
      final client = ref.read(sabnzbdClientForProvider(download.instanceId));
      stopped
          ? await client.pauseJob(download.id)
          : await client.resumeJob(download.id);
    case ServiceKey.nzbget:
      final client = ref.read(nzbgetClientForProvider(download.instanceId));
      final wanted = downloadJoinKey(download.id);
      final group = (await client.listGroups())
          .where((group) => downloadJoinKey(group.downloadId) == wanted)
          .firstOrNull;
      if (group == null) throw StateError('NZBGet no longer lists this job');
      final done = stopped
          ? await client.pauseGroup(group.nzbId)
          : await client.resumeGroup(group.nzbId);
      if (!done) throw StateError('NZBGet did not change the job');
    default:
      throw ArgumentError.value(download.client, 'client', 'not a client');
  }
}
