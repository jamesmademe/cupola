import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/api/base_arr_service.dart';
import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/features/readarr/presentation/readarr_provider.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/music/domain/lidarr_queue_snapshots.dart';
import 'package:cupola/features/music/domain/models/lidarr_album.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/series/domain/sonarr_queue_snapshots.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The Radarr queue of one named connection, indexed by movie id.
///
/// A queue is a property of a server, and the ids in it are that server's. Read
/// through the lens while the page it badges belongs to a different connection,
/// every badge is answering about a different film that happens to share an id.
/// Empty id means the lens, which is what [radarrQueueSnapshotProvider] passes.
final radarrQueueSnapshotForProvider =
    FutureProvider.family<ArrQueueSnapshot, String>((ref, instanceId) async {
      final service = instanceId.isEmpty
          ? ref.watch(radarrServiceProvider)
          : ref.watch(radarrServiceForProvider(instanceId));
      return _loadArrQueueSnapshot(
        service,
        service.getQueuePage,
        (item) => [
          intOrNull(mapOrNull(item['movie'])?['id'] ?? item['movieId']),
        ],
      );
    });

/// The Readarr queue of one named connection, indexed by book id: an
/// author's page badges its books with it, so a book being downloaded never
/// reads `Wanted`. Empty id means the lens.
final readarrQueueSnapshotForProvider =
    FutureProvider.family<ArrQueueSnapshot, String>((ref, instanceId) async {
      final service = instanceId.isEmpty
          ? ref.watch(readarrServiceProvider)
          : ref.watch(readarrServiceForProvider(instanceId));
      return _loadArrQueueSnapshot(
        service,
        service.getQueuePage,
        (item) => [intOrNull(mapOrNull(item['book'])?['id'] ?? item['bookId'])],
      );
    });

/// The Radarr queue indexed by movie id.
///
/// Every surface that badges a movie (grid, poster rail, detail page) reads
/// this one snapshot, so they cannot disagree about what is downloading. A
/// queue that did not answer is a failed snapshot, never an empty one, and a
/// badge reads it through `queueUnknown: !snapshot.isWhole`
/// (`radarrMovieStatus`), so a film being downloaded never reads `Missing`
/// because its queue could not be asked.
/// Delegates to the connection the lens points at, so the surfaces that never
/// name one keep the shape they always had.
final radarrQueueSnapshotProvider = FutureProvider<ArrQueueSnapshot>((
  ref,
) async {
  final lens = ref.watch(activeInstanceProvider(ServiceKey.radarr))?.id ?? '';
  return ref.watch(radarrQueueSnapshotForProvider(lens).future);
});

/// A queue snapshot as a screen reads it off its provider: the snapshot last
/// read, the failure when the read itself threw, and
/// [ArrQueueSnapshot.unknown] while nothing has been read yet.
///
/// Never [ArrQueueSnapshot.empty] for a queue nobody read: a badge passes
/// `queueUnknown: !snapshot.isWhole`, so a title with nothing on disk reads
/// unknown until the queue answers, and `Missing` only once it answered whole
/// without it.
ArrQueueSnapshot queueSnapshotOf(AsyncValue<ArrQueueSnapshot> queue) =>
    switch (queue) {
      AsyncValue(:final value?) => value,
      AsyncValue(:final error?) => ArrQueueSnapshot.failed(error),
      _ => ArrQueueSnapshot.unknown,
    };

/// [queueSnapshotOf] for Lidarr's two indexes of one queue.
LidarrQueueSnapshots lidarrQueueSnapshotsOf(
  AsyncValue<LidarrQueueSnapshots> queue,
) => switch (queue) {
  AsyncValue(:final value?) => value,
  AsyncValue(:final error?) => LidarrQueueSnapshots.failed(error),
  _ => LidarrQueueSnapshots.unknown,
};

/// The Sonarr queue of one named connection, indexed by series, episode and
/// season from one read. Empty id means the lens.
///
/// Degrades to a **failed** snapshot, never an empty one, or to the last
/// answer kept as stale: see [_loadArrQueueSnapshot]. Invalidate this family,
/// not the series index derived from it, to read the queue again.
final sonarrQueueSnapshotsForProvider =
    FutureProvider.family<SonarrQueueSnapshots, String>((
      ref,
      instanceId,
    ) async {
      final service = instanceId.isEmpty
          ? ref.watch(sonarrServiceProvider)
          : ref.watch(sonarrServiceForProvider(instanceId));
      try {
        final page = await service.getQueuePage();
        return _lastSonarrQueue[service] = SonarrQueueSnapshots.fromQueueItems(
          page.records,
          cutShort: page.cutShort,
        );
      } catch (error) {
        // The last answer, stale, over a refresh that failed: see
        // [_lastArrQueue].
        return _lastSonarrQueue[service]?.staleAfter(error) ??
            SonarrQueueSnapshots.failed(error);
      }
    });

/// The Sonarr queue of one named connection, indexed by series id. See
/// [radarrQueueSnapshotForProvider]. A view of
/// [sonarrQueueSnapshotsForProvider], so the series grid and the episode rows
/// read one queue.
final sonarrQueueSnapshotForProvider =
    FutureProvider.family<ArrQueueSnapshot, String>((ref, instanceId) async {
      return (await ref.watch(
        sonarrQueueSnapshotsForProvider(instanceId).future,
      )).bySeries;
    });

/// The Sonarr queue indexed by series id.
final sonarrQueueSnapshotProvider = FutureProvider<ArrQueueSnapshot>((
  ref,
) async {
  final lens = ref.watch(activeInstanceProvider(ServiceKey.sonarr))?.id ?? '';
  return ref.watch(sonarrQueueSnapshotForProvider(lens).future);
});

/// How many artists the album → artist fallback may probe, and how many of
/// those requests may be in flight at once.
///
/// The fallback exists for Lidarr queue records that name an album but not its
/// artist, and there is no endpoint that maps one to the other: the only route
/// is `/album?artistId=` per artist. Unbounded, that walks the entire artist
/// library one request at a time, so a four-thousand-artist library could fire
/// four thousand sequential requests to badge one queue row. The guard above
/// makes it rare; this makes it bounded when it does happen. An unresolved
/// album simply badges nothing, which is the same outcome as the request
/// failing.
const int _lidarrAlbumLookupCap = 40;
const int _lidarrAlbumLookupConcurrency = 4;

/// The Lidarr queue indexed by artist *and* album id.
///
/// Delegates to the connection the lens points at, so the surfaces that never
/// name one keep the shape they always had. See
/// [lidarrQueueSnapshotsForProvider].
final lidarrQueueSnapshotsProvider = FutureProvider<LidarrQueueSnapshots>((
  ref,
) async {
  final lens = ref.watch(activeInstanceProvider(ServiceKey.lidarr))?.id ?? '';
  return ref.watch(lidarrQueueSnapshotsForProvider(lens).future);
});

/// The Lidarr queue of one named connection, indexed by artist and album id.
///
/// A queue is a property of a server, and the ids in it are that server's: an
/// artist page opened on the second Lidarr that read the lens's queue badged
/// its albums with the other server's downloads. Empty id means the lens,
/// which is what [lidarrQueueSnapshotsProvider] passes. The Radarr and Sonarr
/// pages read theirs the same way ([radarrQueueSnapshotForProvider]).
final lidarrQueueSnapshotsForProvider =
    FutureProvider.family<LidarrQueueSnapshots, String>((
      ref,
      instanceId,
    ) async {
      final service = instanceId.isEmpty
          ? ref.watch(lidarrServiceProvider)
          : ref.watch(lidarrServiceForProvider(instanceId));
      return _loadLidarrQueueSnapshots(service);
    });

Future<LidarrQueueSnapshots> _loadLidarrQueueSnapshots(
  LidarrService service,
) async {
  try {
    return _lastLidarrQueue[service] = await _readLidarrQueueSnapshots(service);
  } catch (error) {
    // Failed, not empty, and the last answer kept as stale when there was
    // one: see [_loadArrQueueSnapshot].
    return _lastLidarrQueue[service]?.staleAfter(error) ??
        LidarrQueueSnapshots.failed(error);
  }
}

Future<LidarrQueueSnapshots> _readLidarrQueueSnapshots(
  LidarrService service,
) async {
  int? directArtistId(Map<String, dynamic> item) => intOrNull(
    mapOrNull(item['artist'])?['id'] ??
        mapOrNull(item['album'])?['artistId'] ??
        item['artistId'],
  );
  int? albumIdOf(Map<String, dynamic> item) =>
      intOrNull(mapOrNull(item['album'])?['id'] ?? item['albumId']);

  final page = await service.getQueuePage();
  final queueItems = page.records
      .whereType<Map>()
      .map(stringKeyMap)
      .toList(growable: false);
  if (queueItems.isEmpty && !page.cutShort) {
    return LidarrQueueSnapshots.empty;
  }

  // Only records that do not already name their artist are worth the album
  // lookup below, which costs one request per artist.
  final unresolvedAlbumIds = <int>{};
  for (final item in queueItems) {
    final artistId = directArtistId(item);
    if (artistId != null && artistId > 0) continue;

    final albumId = albumIdOf(item);
    if (albumId != null && albumId > 0) {
      unresolvedAlbumIds.add(albumId);
    }
  }

  final albumToArtist = <int, int>{};
  if (unresolvedAlbumIds.isNotEmpty) {
    final pending = {...unresolvedAlbumIds};
    final candidates = (await service.getArtists())
        .where((artist) => artist.albumCount > 0)
        .take(_lidarrAlbumLookupCap)
        .toList(growable: false);

    for (
      var start = 0;
      start < candidates.length && pending.isNotEmpty;
      start += _lidarrAlbumLookupConcurrency
    ) {
      final batch = candidates.skip(start).take(_lidarrAlbumLookupConcurrency);
      final fetched = await Future.wait(
        batch.map((artist) async {
          try {
            return (
              artist: artist.id,
              albums: await service.getAlbums(artist.id),
            );
          } catch (_) {
            // One artist that will not answer must not abandon the rest of
            // the batch.
            return (artist: artist.id, albums: const <LidarrAlbum>[]);
          }
        }),
      );

      for (final result in fetched) {
        for (final album in result.albums) {
          if (pending.remove(album.id)) {
            albumToArtist[album.id] = result.artist;
          }
        }
      }
    }
  }

  return LidarrQueueSnapshots(
    byArtist: ArrQueueSnapshot.fromQueueItems(
      queueItems,
      cutShort: page.cutShort,
      idsFor: (item) {
        final direct = directArtistId(item);
        if (direct != null && direct > 0) return [direct];

        final albumId = albumIdOf(item);
        final resolved = albumId == null ? null : albumToArtist[albumId];
        return resolved == null ? const <int>[] : [resolved];
      },
    ),
    byAlbum: ArrQueueSnapshot.fromQueueItems(
      queueItems,
      cutShort: page.cutShort,
      idsFor: (item) {
        final albumId = albumIdOf(item);
        return albumId == null ? const <int>[] : [albumId];
      },
    ),
  );
}

/// Walks a `/queue` and indexes it, degrading on failure so a badge never
/// blocks on an unreachable service.
///
/// Degrading to a **failed** snapshot, not to [ArrQueueSnapshot.empty]. The
/// empty one is an answer, a queue with nothing in it, and every detail page
/// read it as one: with the queue endpoint down, each film that was
/// downloading read `Missing`. A walk that stopped short says so too
/// ([ArrQueueSnapshot.cutShort]), for the same reason: an id missing from the
/// rows it read may be in the rows it did not.
///
/// A refresh that fails after [client] has answered once degrades to that
/// answer instead, kept as stale ([ArrQueueSnapshot.staleAfter]): see
/// [_lastArrQueue]. Only a first read that fails is the failed snapshot.
Future<ArrQueueSnapshot> _loadArrQueueSnapshot(
  Object client,
  Future<ArrRecordPage> Function() loadPage,
  Iterable<int?> Function(Map<String, dynamic> item) idsFor,
) async {
  try {
    final page = await loadPage();
    return _lastArrQueue[client] = ArrQueueSnapshot.fromQueueItems(
      page.records,
      idsFor: (item) => idsFor(item).whereType<int>(),
      cutShort: page.cutShort,
    );
  } catch (error) {
    return _lastArrQueue[client]?.staleAfter(error) ??
        ArrQueueSnapshot.failed(error);
  }
}

/// The last queue each client answered with, so a refresh that fails keeps
/// it rather than throwing it away.
///
/// A queue refresh that failed used to replace the reading with a failed
/// snapshot: every badge went `Unknown` and the download a page was showing
/// a minute ago disappeared from it. The reading stays now, stale, and the
/// page says how old it is.
///
/// Keyed on the client, and weakly. A connection whose address or key
/// changes gets a new client and starts with nothing kept, which is the
/// point: the ids in the old answer may be another server's. A client that
/// goes away takes its answer with it.
final Expando<ArrQueueSnapshot> _lastArrQueue = Expando('last queue answer');

/// [_lastArrQueue] for Sonarr's three indexes of one queue.
final Expando<SonarrQueueSnapshots> _lastSonarrQueue = Expando(
  'last Sonarr queue answer',
);

/// [_lastArrQueue] for Lidarr's two indexes of one queue.
final Expando<LidarrQueueSnapshots> _lastLidarrQueue = Expando(
  'last Lidarr queue answer',
);
