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
  //
  // `read`, deliberately, and this is the load-bearing part. Watching the lens
  // would rebuild EVERY entry of this family whenever the lens moved — entries
  // for connections that did not change — and `watchApiClient` closes the
  // outgoing client on dispose. A release search running against the seedbox
  // would have its `Dio` shut under it because the user tapped a badge on
  // another screen. The cost of reading is that an entry minted before the lens
  // landed on its id keeps a client of its own until it is disposed: one extra
  // connection, rather than a request that fails.
  final lens = ref.read(activeInstanceProvider(ServiceKey.lidarr))?.id ?? '';
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

  /// Asks for the artist and the album with every queue record.
  ///
  /// A Lidarr queue record on its own carries `artistId`/`albumId` and the raw
  /// release name, nothing else — so a row built from it could only print
  /// `Cindy.Lee-Diamond.Jubilee-WEB-2024-XYZ`. The embeds are what turn that
  /// into `Import failed · Cindy Lee — Diamond Jubilee`, and they only ride
  /// along when the request asks for them, exactly as Radarr must ask for
  /// `includeMovie` and Readarr for `includeBook`/`includeAuthor`.
  @override
  Future<List<dynamic>> getQueue({Map<String, dynamic>? queryParameters}) {
    return super.getQueue(
      queryParameters: {
        'includeArtist': true,
        'includeAlbum': true,
        ...?queryParameters,
      },
    );
  }

  /// On the **page** primitive, not on `getHistory`.
  ///
  /// `getHistory` delegates here, so both spellings pick the parameters up —
  /// but only this way round; `base_arr_service.dart` warns about precisely
  /// this. Lidarr needs it more than its siblings do, because its history is
  /// written **per track file**: the Overview's "today" section folds a page
  /// back down to one row per album, and the key it folds on is
  /// `record['album']['id']`. Without `includeAlbum` that object is absent,
  /// every track of one import lands in a group of its own, and a fourteen-track
  /// album fills the three-row cap three times over — each row titled with the
  /// raw `sourceTitle`, because `includeArtist` is what supplies the other half
  /// of `Artist — Album`. The fold and the titles are both promises this one
  /// request keeps.
  @override
  Future<ArrRecordPage> getHistoryPage({
    int page = 1,
    int pageSize = 20,
    Map<String, dynamic>? queryParameters,
  }) {
    return super.getHistoryPage(
      page: page,
      pageSize: pageSize,
      queryParameters: {
        'includeArtist': true,
        'includeAlbum': true,
        ...?queryParameters,
      },
    );
  }

  /// Fetches all artists from Lidarr.
  Future<List<LidarrArtist>> getArtists() async {
    return fetchAllItems('artist', LidarrArtist.fromJson);
  }

  /// Fetches a single artist by ID, returning a typed model.
  Future<LidarrArtist?> getArtistById(int artistId) async {
    return fetchItem('artist', artistId, LidarrArtist.fromJson);
  }

  /// Fetches all albums for an artist.
  ///
  /// Artist-scoped, and that is the whole of what Lidarr answers here today.
  /// Decision 24 merges Artists and Albums into one segmented Library tab —
  /// which is what freed Lidarr's sixth tab for History — and the Albums
  /// segment needs a library-wide list this client cannot ask for. What it
  /// would take, precisely:
  ///
  /// - `getAllAlbums()`: the same `GET /api/v1/album` with no `artistId` and
  ///   `includeArtist=true`, so each record carries the artist it belongs to.
  /// - `LidarrAlbum` gains `artistName`, `albumType` and the quality profile.
  ///   Its entire field list today is id, title, releaseDate, monitored,
  ///   images and statistics, so the drawn album table has no column to fill
  ///   beyond the title — the list arriving would not be enough on its own.
  /// - a segment slot on `MediaBrowseScaffold`, which has none: its only
  ///   injectable widget is `kpiPeek`. That is a shared change in
  ///   `lib/core/widgets/`, outside this feature.
  ///
  /// None of it is added speculatively here: an unused client method is the
  /// same defect as Prowlarr's `getStatus()`, which this pass deleted.
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

  /// Fetches the metadata profiles — the axis only Lidarr has.
  ///
  /// It decides which release types (studio albums, EPs, live records…) the
  /// artist's discography is built from, and an add without one is rejected,
  /// so it is not optional the way it looks.
  Future<List<Map<String, dynamic>>> fetchMetadataProfiles() async {
    final response = await client.get('/api/v1/metadataprofile');
    final data = response.data as List<dynamic>;
    return data.cast<Map<String, dynamic>>();
  }

  /// Fetches the root folders configured on this Lidarr.
  Future<List<Map<String, dynamic>>> getRootFolders() async {
    return fetchRootFolders();
  }

  /// Adds [artist] — an `artist/lookup` row — to this Lidarr's library.
  ///
  /// [artist] must carry a [LidarrArtist.foreignArtistId]: Lidarr identifies an
  /// artist by its MusicBrainz id and by nothing else, so an add without it is
  /// rejected outright. That id is why the model parses it at all.
  ///
  /// Throws on failure rather than degrading; see [RadarrService.addMovie].
  Future<LidarrArtist> addArtist(
    LidarrArtist artist, {
    required int qualityProfileId,
    required int metadataProfileId,
    required String rootFolderPath,
    bool monitored = true,
    bool searchForMissingAlbums = true,
  }) async {
    final response = await client.post(
      '/api/v1/artist',
      data: {
        'artistName': artist.artistName,
        'foreignArtistId': artist.foreignArtistId,
        'images': artist.images,
        'qualityProfileId': qualityProfileId,
        'metadataProfileId': metadataProfileId,
        'rootFolderPath': rootFolderPath,
        'monitored': monitored,
        'addOptions': {
          'monitored': monitored,
          'searchForMissingAlbums': searchForMissingAlbums,
        },
      },
    );
    return LidarrArtist.fromJson(response.data as Map<String, dynamic>);
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
