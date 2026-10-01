import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/movies/presentation/movie_detail_provider.dart'
    show ArrItemRef;
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/music/domain/models/lidarr_album.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';

/// One artist, from one named connection. See [movieDetailForProvider] for why
/// the connection is part of the key rather than something resolved inside.
final musicDetailForProvider = FutureProvider.autoDispose
    .family<LidarrArtist?, ArrItemRef>((ref, item) async {
      if (item.id <= 0) return null;
      return _lidarr(ref, item.instanceId).getArtistById(item.id);
    });

final musicAlbumsForProvider = FutureProvider.autoDispose
    .family<List<LidarrAlbum>, ArrItemRef>((ref, item) async {
      if (item.id <= 0) return const [];
      return _lidarr(ref, item.instanceId).getAlbums(item.id);
    });

LidarrService _lidarr(Ref ref, String instanceId) => instanceId.isEmpty
    ? ref.watch(lidarrServiceProvider)
    : ref.watch(lidarrServiceForProvider(instanceId));
