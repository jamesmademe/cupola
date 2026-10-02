import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/movies/domain/radarr_status.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';

import '../../../test_helpers/profiles/profiles.dart';

/// A queue refresh that fails used to replace the reading with a failed
/// snapshot: every badge went `Unknown` and the download a page showed a
/// minute ago disappeared. The last answer stays now, stale, and a first read
/// that fails is still the failed snapshot it always was.
void main() {
  group('Radarr', () {
    test('a refresh that fails keeps the film that was downloading', () async {
      final (:container, :refuse) = await _start(
        WorldIds.radarr,
        '/api/v3/queue',
      );
      final family = radarrQueueSnapshotForProvider(WorldIds.radarr);

      final first = await container.read(family.future);
      // Sprite Fright, at 62%.
      expect(first.entryFor(1)?.pipeline, MediaPipeline.downloading);
      expect(first.entryFor(1)?.progress, isNotNull);

      refuse();
      container.invalidate(family);
      final second = await container.read(family.future);

      expect(second.isStale, isTrue);
      expect(second.error, isNotNull);
      expect(second.sampledAt, first.sampledAt);
      expect(second.entryFor(1)?.pipeline, MediaPipeline.downloading);
      expect(second.entryFor(1)?.progress, isNull);
      expect(_movieBadge(second), 'Downloading');
    });

    test('a first read that fails stays unknown', () async {
      final (:container, :refuse) = await _start(
        WorldIds.radarr,
        '/api/v3/queue',
      );
      refuse();

      final snapshot = await container.read(
        radarrQueueSnapshotForProvider(WorldIds.radarr).future,
      );

      expect(snapshot.isStale, isFalse);
      expect(snapshot.isEmpty, isTrue);
      expect(_movieBadge(snapshot), 'Unknown');
    });

    test('a refresh that answers again replaces the stale reading', () async {
      var failing = false;
      final harness = await ProfileHarness.start(Profiles.p1);
      harness.network.on(
        WorldIds.radarr,
        'GET',
        '/api/v3/queue',
        (_) => failing
            ? NetworkReply.json({'message': 'boom'}, status: 500)
            : null,
      );
      final container = harness.container(retry: (_, _) => null);
      final family = radarrQueueSnapshotForProvider(WorldIds.radarr);
      await container.read(family.future);

      failing = true;
      container.invalidate(family);
      expect((await container.read(family.future)).isStale, isTrue);

      failing = false;
      container.invalidate(family);
      final fresh = await container.read(family.future);

      expect(fresh.isStale, isFalse);
      expect(fresh.isWhole, isTrue);
      expect(fresh.entryFor(1)?.progress, isNotNull);
    });
  });

  test('Sonarr keeps its three indexes of the last answer', () async {
    final (:container, :refuse) = await _start(
      WorldIds.sonarr,
      '/api/v3/queue',
    );
    final family = sonarrQueueSnapshotsForProvider(WorldIds.sonarr);
    final first = await container.read(family.future);
    // Cosmos Laundromat, series 1: S02E04 and S02E05 downloading.
    expect(first.bySeries.entryFor(1), isNotNull);
    expect(first.seasonEntry(1, 2), isNotNull);
    final episodes = first.byEpisode.entriesById.keys.toSet();
    expect(episodes, isNotEmpty);

    refuse();
    container.invalidate(family);
    final second = await container.read(family.future);

    expect(second.bySeries.isStale, isTrue);
    expect(second.isWhole, isFalse);
    expect(second.error, isNotNull);
    expect(second.bySeries.entryFor(1), isNotNull);
    expect(second.seasonEntry(1, 2), isNotNull);
    expect(second.byEpisode.entriesById.keys.toSet(), episodes);
  });

  test('Lidarr keeps the artist and the album of the last answer', () async {
    final (:container, :refuse) = await _start(
      WorldIds.lidarr,
      '/api/v1/queue',
      answer: (_) => NetworkReply.json({
        'page': 1,
        'pageSize': 200,
        'totalRecords': 1,
        'records': const [
          {
            'id': 1,
            'artistId': 1,
            'albumId': 4,
            'title': 'Sintel (Anniversary Edition)',
            'status': 'downloading',
            'trackedDownloadState': 'downloading',
            'size': 300000000,
            'sizeleft': 120000000,
          },
        ],
      }),
    );
    final family = lidarrQueueSnapshotsForProvider(WorldIds.lidarr);
    final first = await container.read(family.future);
    expect(first.byAlbum.entryFor(4)?.pipeline, MediaPipeline.downloading);

    refuse();
    container.invalidate(family);
    final second = await container.read(family.future);

    expect(second.byArtist.isStale, isTrue);
    expect(second.byAlbum.isStale, isTrue);
    expect(second.byArtist.entryFor(1)?.pipeline, MediaPipeline.downloading);
    expect(second.byAlbum.entryFor(4)?.pipeline, MediaPipeline.downloading);
  });
}

/// P1 with [path] on [serverId] answered by the world, or by [answer], until
/// `refuse()` makes it answer 500.
Future<({ProviderContainer container, void Function() refuse})> _start(
  String serverId,
  String path, {
  NetworkReply? Function(NetworkRequest request)? answer,
}) async {
  var failing = false;
  final harness = await ProfileHarness.start(Profiles.p1);
  harness.network.on(
    serverId,
    'GET',
    path,
    (request) => failing
        ? NetworkReply.json({'message': 'boom'}, status: 500)
        : answer?.call(request),
  );
  return (
    container: harness.container(retry: (_, _) => null),
    refuse: () => failing = true,
  );
}

/// What the badge of a film with nothing on disk reads over [queue].
String? _movieBadge(ArrQueueSnapshot queue) => badgeOverQueue(
  radarrMovieStatus(
    RadarrMovie.fromJson(const {
      'id': 1,
      'title': 'Sprite Fright',
      'hasFile': false,
      'monitored': true,
      'isAvailable': true,
      'status': 'released',
    }),
    queueEntry: queue.entryFor(1),
    queueUnknown: !queue.isWhole,
  ),
  queue,
)?.label;
