import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/features/series/domain/models/sonarr_episode.dart';
import 'package:cupola/features/series/domain/sonarr_queue_snapshots.dart';
import 'package:cupola/features/series/domain/sonarr_status.dart';

/// One record of a season pack: Sonarr files one per episode, every one
/// carrying the pack's download id.
Map<String, Object?> _packRecord(int episodeId, int episodeNumber) => {
  'id': episodeId,
  'seriesId': 1,
  'episodeId': episodeId,
  'seasonNumber': 2,
  'episode': {
    'id': episodeId,
    'seasonNumber': 2,
    'episodeNumber': episodeNumber,
  },
  'downloadId': 'PACK',
  'status': 'downloading',
  'trackedDownloadState': 'downloading',
  'size': 1000,
  'sizeleft': 250,
};

const _episode = SonarrEpisode(
  id: 22,
  seasonNumber: 2,
  episodeNumber: 2,
  title: 'On Its Way',
  hasFile: false,
  monitored: true,
  airDateUtc: '2024-01-08T00:00:00Z',
);

void main() {
  test('one read indexes the queue by series, by episode and by season', () {
    final queues = SonarrQueueSnapshots.fromQueueItems([
      _packRecord(21, 1),
      _packRecord(22, 2),
      // Another series' season 2, which must not leak into series 1's.
      {..._packRecord(31, 1), 'seriesId': 2, 'episode': null},
    ]);

    expect(queues.isWhole, isTrue);
    expect(queues.bySeries.entryFor(1)?.pipeline, MediaPipeline.downloading);
    expect(queues.byEpisode.entryFor(22)?.progress, 0.75);
    expect(queues.byEpisode.entryFor(23), isNull);
    expect(queues.seasonEntry(1, 2)?.pipeline, MediaPipeline.downloading);
    expect(queues.seasonEntry(1, 3), isNull);
    expect(queues.seasonEntry(2, 2), isNotNull);
  });

  test('a failed read is failed every way, and a walk cut short is not '
      'whole', () {
    final failed = SonarrQueueSnapshots.failed(Exception('refused'));
    expect(failed.isWhole, isFalse);
    expect(failed.isPending, isFalse);
    expect(failed.error, isNotNull);
    expect(SonarrQueueSnapshots.unknown.isPending, isTrue);
    expect(
      SonarrQueueSnapshots.fromQueueItems(const [], cutShort: true).isWhole,
      isFalse,
    );
  });

  test('an episode in the queue reads downloading, never Missing', () {
    final queues = SonarrQueueSnapshots.fromQueueItems([_packRecord(22, 2)]);
    final now = DateTime.utc(2025);

    final status = sonarrEpisodeStatus(
      _episode,
      now: now,
      queueEntry: queues.byEpisode.entryFor(22),
      queueUnknown: !queues.isWhole,
    );
    expect(status.pipeline, MediaPipeline.downloading);
    // The file is still missing on disk; what the row says is the pipeline.
    expect(status.label, 'Downloading');
  });

  test('with the queue unread, an aired episode with no file and its '
      'season read unknown, not Missing', () {
    final now = DateTime.utc(2025);
    expect(
      sonarrEpisodeStatus(_episode, now: now, queueUnknown: true).availability,
      MediaAvailability.unknown,
    );
    expect(
      sonarrEpisodeStatus(_episode, now: now).availability,
      MediaAvailability.missing,
    );
  });
}
