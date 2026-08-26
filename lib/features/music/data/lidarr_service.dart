import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/api/base_arr_service.dart';
import 'package:cupola/features/music/domain/models/lidarr_album.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';
import 'package:cupola/features/music/domain/models/lidarr_track.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

final lidarrServiceProvider = Provider<LidarrService>((ref) {
  return LidarrService(watchApiClient(ref, ServiceKey.lidarr));
});

/// Lidarr bound to one named connection, whatever the lens is pointing at.
///
/// For the work that belongs to a *connection* rather than to a screen: a
/// release search runs on the server it was started against, and the lens can
/// move while it is queued. Empty id means the lens, which is what the plain
/// [lidarrServiceProvider] answers; an id naming nothing throws "not configured"
/// rather than quietly answering about some other server.
///
/// Not `autoDispose`: a caller reads this, awaits a request on it, and a
/// disposal scheduled at the end of the read would close the `Dio` under the
/// request. One live client per configured connection is the same bound the
/// per-service providers already carry.
final lidarrServiceForProvider = Provider.family<LidarrService, String>((
  ref,
  instanceId,
) {
  // The lens's own connection resolves to [lidarrServiceProvider] rather than to
  // a second client for the same server. Without this the app kept two live
  // `Dio`s pointed at one address whenever anything asked by id — and any
  // override of the plain provider, which is how every test supplies a fake,
  // was quietly bypassed on the path that names a connection.
  final lens = ref.watch(activeInstanceProvider(ServiceKey.lidarr))?.id ?? '';
  if (instanceId.isEmpty || instanceId == lens) {
    return ref.watch(lidarrServiceProvider);
  }
  return LidarrService(
    watchApiClient(ref, ServiceKey.lidarr, instanceId: instanceId),
  );
});

/// Service for interacting with Lidarr API.
///
/// Provides artist-specific operations plus shared activity operations
/// via [ArrActivityMixin].
class LidarrService with ArrActivityMixin {
  @override
  final ApiClient client;

  @override
  final ArrServiceConfig config = ArrServiceConfig.lidarr;

  LidarrService(this.client);

  /// Fetches all artists from Lidarr.
  Future<List<LidarrArtist>> getArtists() async {
    return fetchAllItems('artist', LidarrArtist.fromJson);
  }

  /// Fetches a single artist by ID, returning a typed model.
  Future<LidarrArtist?> getArtistById(int artistId) async {
    return fetchItem('artist', artistId, LidarrArtist.fromJson);
  }

  /// Fetches all albums for an artist.
  Future<List<LidarrAlbum>> getAlbums(int artistId) async {
    return fetchListItems('album', {
      'artistId': artistId,
    }, LidarrAlbum.fromJson);
  }

  /// Fetches all tracks for an album.
  Future<List<LidarrTrack>> getTracks(int albumId) async {
    return fetchListItems('track', {'albumId': albumId}, LidarrTrack.fromJson);
  }

  /// Triggers an automatic search for an artist.
  Future<void> searchArtist(int artistId) async {
    await client.post(
      '/api/v1/command',
      data: {'name': 'ArtistSearch', 'artistId': artistId},
    );
  }

  /// Triggers an automatic search for albums.
  Future<void> searchAlbums(List<int> albumIds) async {
    await client.post(
      '/api/v1/command',
      data: {'name': 'AlbumSearch', 'albumIds': albumIds},
    );
  }

  /// Fetches releases for interactive search.
  Future<List<dynamic>> getReleases({
    int? artistId,
    int? albumId,
    CancelToken? cancelToken,
    Duration? receiveTimeout,
  }) async {
    final params = <String, dynamic>{};
    if (artistId != null) params['artistId'] = artistId;
    if (albumId != null) params['albumId'] = albumId;

    return fetchReleases(
      params,
      cancelToken: cancelToken,
      receiveTimeout: receiveTimeout,
    );
  }

  /// Grabs a specific release for download.
  Future<void> grabRelease({
    required String guid,
    required int indexerId,
  }) async {
    await grabReleaseByGuid(guid: guid, indexerId: indexerId);
  }

  /// Searches for artists by term using the lookup API.
  ///
  /// [cancelToken] aborts the request once the search that asked for it has
  /// been superseded — see [ArrActivityMixin.lookupItems], which owns the
  /// empty-term guard, the isolate mapping and the degrade-to-`[]` rule the
  /// three arr lookups share.
  Future<List<LidarrArtist>> lookupArtists(
    String term, {
    CancelToken? cancelToken,
    bool reportFailure = false,
  }) {
    return lookupItems(
      'artist/lookup',
      term,
      LidarrArtist.fromJson,
      cancelToken: cancelToken,
      reportFailure: reportFailure,
    );
  }

  /// Fetches all quality profiles.
  Future<List<Map<String, dynamic>>> getQualityProfiles() async {
    return fetchQualityProfiles();
  }

  /// Updates an artist's quality profile.
  Future<void> updateArtistProfile(int artistId, int qualityProfileId) async {
    await updateItemProfile('artist', artistId, qualityProfileId);
  }

  /// Updates an artist's monitored state.
  Future<void> updateArtistMonitored(int artistId, bool monitored) async {
    await updateItemMonitored('artist', artistId, monitored);
  }

  /// Deletes an artist from Lidarr.
  Future<void> deleteArtist(
    int artistId, {
    bool deleteFiles = false,
    bool addImportListExclusion = false,
  }) async {
    await client.delete(
      '/api/v1/artist/$artistId',
      queryParameters: {
        'deleteFiles': deleteFiles,
        'addImportListExclusion': addImportListExclusion,
      },
    );
  }
}
