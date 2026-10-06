import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/music/domain/models/lidarr_album.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';
import 'package:cupola/features/music/domain/models/lidarr_track.dart';

/// One record on one named connection: the connection is part of the key,
/// so an artist opened from a second Lidarr reads that Lidarr.
typedef LidarrRecordRef = ({String instanceId, int id});

/// The artist an artist's page shows. A failure reaches the page, which says
/// why; Retry and a pull read it again, nothing retries on its own.
final lidarrArtistProvider = FutureProvider.autoDispose
    .family<LidarrArtist, LidarrRecordRef>(
      (ref, item) => _lidarr(ref, item.instanceId).getArtistOrThrow(item.id),
      retry: noProviderRetry,
    );

/// The artist's albums, every one Lidarr knows of.
final lidarrArtistAlbumsProvider = FutureProvider.autoDispose
    .family<List<LidarrAlbum>, LidarrRecordRef>(
      (ref, item) => _lidarr(ref, item.instanceId).getAlbums(item.id),
      retry: noProviderRetry,
    );

/// One album's tracks, read when its row opens: by disc, then by number.
final lidarrAlbumTracksProvider = FutureProvider.autoDispose
    .family<List<LidarrTrack>, LidarrRecordRef>((ref, album) async {
      final tracks = await _lidarr(ref, album.instanceId).getTracks(album.id);
      return [...tracks]..sort((a, b) {
        final disc = (a.mediumNumber ?? 0).compareTo(b.mediumNumber ?? 0);
        return disc != 0
            ? disc
            : a.sortableTrackNumber.compareTo(b.sortableTrackNumber);
      });
    }, retry: noProviderRetry);

LidarrService _lidarr(Ref ref, String instanceId) => instanceId.isEmpty
    ? ref.watch(lidarrServiceProvider)
    : ref.watch(lidarrServiceForProvider(instanceId));
