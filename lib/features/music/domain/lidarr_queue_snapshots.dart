import 'package:cupola/core/status/arr_queue_snapshot.dart';

/// Lidarr's queue indexed two ways.
///
/// A queue record names an album, while the library screen and artist detail
/// page badge artists — so the same fetch is indexed by both, and the expensive
/// album → artist resolution happens once.
class LidarrQueueSnapshots {
  final ArrQueueSnapshot byArtist;
  final ArrQueueSnapshot byAlbum;

  const LidarrQueueSnapshots({required this.byArtist, required this.byAlbum});

  /// A queue that answered with nothing in it.
  static const LidarrQueueSnapshots empty = LidarrQueueSnapshots(
    byArtist: ArrQueueSnapshot.empty,
    byAlbum: ArrQueueSnapshot.empty,
  );

  /// A queue nobody could read, both ways: see [ArrQueueSnapshot.unknown].
  static const LidarrQueueSnapshots unknown = LidarrQueueSnapshots(
    byArtist: ArrQueueSnapshot.unknown,
    byAlbum: ArrQueueSnapshot.unknown,
  );

  /// A queue read that failed with [error], both ways.
  factory LidarrQueueSnapshots.failed(Object? error) => LidarrQueueSnapshots(
    byArtist: ArrQueueSnapshot.failed(error),
    byAlbum: ArrQueueSnapshot.failed(error),
  );
}
