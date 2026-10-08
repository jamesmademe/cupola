@Tags(['catalog'])
library;

import 'dart:async';
import 'dart:io' as io;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/core/title_light.dart';
import 'package:cupola/features/discover/domain/models/collection_detail.dart';
import 'package:cupola/features/discover/domain/models/person_credits.dart';
import 'package:cupola/features/discover/domain/models/person_detail.dart';
import 'package:cupola/features/discover/presentation/collection_page.dart';
import 'package:cupola/features/discover/presentation/discover_details_provider.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/discover/presentation/person_page.dart';
import 'package:cupola/features/discover/presentation/widgets/catalog_title_row.dart';
import 'package:cupola/features/media/presentation/media_parts.dart';
import 'package:cupola/features/media/presentation/media_split.dart';
import 'package:cupola/features/media/presentation/shelf_page.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/music/domain/lidarr_queue_snapshots.dart';
import 'package:cupola/features/music/domain/models/lidarr_album.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';
import 'package:cupola/features/music/domain/models/lidarr_track.dart';
import 'package:cupola/features/music/presentation/artist_page.dart';
import 'package:cupola/features/music/presentation/artist_page_providers.dart';
import 'package:cupola/features/readarr/data/readarr_service.dart';
import 'package:cupola/features/readarr/domain/models/readarr_models.dart';
import 'package:cupola/features/readarr/presentation/author_page.dart';
import 'package:cupola/features/readarr/presentation/author_page_providers.dart';
import 'package:cupola/features/readarr/presentation/readarr_provider.dart';
import 'package:cupola/features/series/presentation/series_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../test_helpers/fake_api_client.dart';
import '../test_helpers/settings_scope.dart';
import 'catalog.dart';

/// Each catalog picture's light, as the app reads it.
final _lights = <String, TitleLight?>{};

Future<void> _readLights() async {
  for (final (url, file) in [
    (CatalogArt.poster, 'poster'),
    (CatalogArt.backdrop, 'backdrop'),
  ]) {
    final bytes = io.File(
      'design/system/assets/Imagery/$file.jpg',
    ).readAsBytesSync();
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: titleLightDecodeSize,
      targetHeight: titleLightDecodeSize,
    );
    final frame = await codec.getNextFrame();
    final rgba = (await frame.image.toByteData())!;
    _lights[url] = await titleLightFromPixels([
      for (var i = 0; i + 3 < rgba.lengthInBytes; i += 4)
        0xFF000000 |
            rgba.getUint8(i) << 16 |
            rgba.getUint8(i + 1) << 8 |
            rgba.getUint8(i + 2),
    ]);
  }
}

ServiceInstance _connection(ServiceKey service) => ServiceInstance(
  id: service.name,
  service: service,
  label: '',
  url: 'http://nas.home.arpa',
  credential: 'catalog',
);

/// The profiles' Lidarr and Readarr answer their quality profiles; nothing
/// else is asked of them here.
class _Lidarr extends LidarrService {
  _Lidarr() : super(FakeApiClient());

  @override
  Future<List<Map<String, dynamic>>> getQualityProfiles() async => [
    {'id': 1, 'name': 'Lossless'},
    {'id': 2, 'name': 'Standard'},
  ];
}

class _Readarr extends ReadarrService {
  _Readarr() : super(FakeApiClient());

  @override
  Future<List<Map<String, dynamic>>> getQualityProfiles() async => [
    {'id': 1, 'name': 'eBook'},
    {'id': 2, 'name': 'Spoken'},
  ];
}

List<Object?> _cover(String url) => [
  {'coverType': 'cover', 'remoteUrl': url},
];

LidarrArtist _artist() => LidarrArtist.fromJson({
  'id': 1,
  'artistName': 'Jan Morgenstern',
  'foreignArtistId': 'jm',
  'status': 'continuing',
  'monitored': true,
  'monitorNewItems': 'all',
  'path': '/mnt/tank/media/music/Jan Morgenstern',
  'qualityProfileId': 1,
  'images': const <Object?>[],
  'statistics': {'albumCount': 4, 'trackFileCount': 18, 'trackCount': 23},
});

List<LidarrAlbum> _albums({bool art = true, bool wanted = false}) => [
  for (final (id, title, year, files, total, url) in [
    (3, 'Sintel', 2010, 5, 5, CatalogArt.poster),
    (2, 'Big Buck Bunny', 2008, 6, 6, CatalogArt.backdrop),
    (1, 'Elephants Dream', 2006, wanted ? 0 : 7, 7, CatalogArt.poster),
  ])
    LidarrAlbum.fromJson({
      'id': id,
      'title': title,
      'monitored': true,
      'releaseDate': '$year-01-01T00:00:00Z',
      'duration': id == 3 ? 1260000 : 0,
      'images': art ? _cover(url) : const <Object?>[],
      'statistics': {'trackFileCount': files, 'totalTrackCount': total},
    }),
  LidarrAlbum.fromJson({
    'id': 4,
    'title': 'Sintel (Anniversary Edition)',
    'monitored': true,
    'releaseDate': DateTime.now()
        .add(const Duration(days: 3))
        .toUtc()
        .toIso8601String(),
    'images': art ? _cover(CatalogArt.backdrop) : const <Object?>[],
    'statistics': {'trackFileCount': 0, 'totalTrackCount': 5},
  }),
];

final _tracks = [
  for (final (number, title, ms) in [
    (1, 'Opening', 168000),
    (2, 'Scales', 252000),
    (3, 'The Dragon', 336000),
    (4, 'Snow', 234000),
    (5, 'Finale', 270000),
  ])
    LidarrTrack.fromJson({
      'id': number,
      'trackNumber': '$number',
      'title': title,
      'duration': ms,
      'hasFile': true,
    }),
];

CatalogScene _artistScene(
  String caption, {
  double width = 390,
  double height = 1700,
  double textScale = 1,
  bool art = true,
  bool wanted = false,
  Future<LidarrArtist>? artist,
}) => CatalogScene(
  caption,
  (_) => const ArtistPage(artistId: 1),
  width: width,
  height: height,
  textScale: textScale,
  overrides: [
    lidarrServiceProvider.overrideWithValue(_Lidarr()),
    lidarrArtistProvider.overrideWith((ref, item) => artist ?? _artist()),
    lidarrArtistAlbumsProvider.overrideWith(
      (ref, item) async => _albums(art: art, wanted: wanted),
    ),
    lidarrAlbumTracksProvider.overrideWith((ref, album) async => _tracks),
    lidarrQueueSnapshotsForProvider.overrideWith(
      (ref, id) async => LidarrQueueSnapshots.empty,
    ),
    titleLightProvider.overrideWith((ref, url) async => _lights[url]),
  ],
);

ReadarrAuthor _author() => ReadarrAuthor.fromJson({
  'id': 1,
  'authorName': 'Jules Verne',
  'titleSlug': 'jules-verne',
  'monitored': true,
  'path': '/mnt/user/media/books/Jules Verne',
  'qualityProfileId': 1,
  'images': const <Object?>[],
  'statistics': {'bookCount': 7, 'bookFileCount': 6},
});

final _books = [
  for (final (id, title, year, onDisk) in const [
    (1, 'Five Weeks in a Balloon', 1863, false),
    (2, 'Journey to the Centre of the Earth', 1864, true),
    (3, 'From the Earth to the Moon', 1865, true),
    (4, 'Twenty Thousand Leagues Under the Seas', 1870, true),
    (5, 'Around the World in Eighty Days', 1872, true),
    (6, 'The Mysterious Island', 1875, true),
    (7, 'Michael Strogoff', 1876, true),
  ])
    ReadarrBook.fromJson({
      'id': id,
      'title': title,
      'monitored': true,
      'releaseDate': '$year-01-01T00:00:00Z',
      'statistics': {'bookFileCount': onDisk ? 1 : 0},
    }),
];

CatalogScene _authorScene(
  String caption, {
  double height = 1500,
  double textScale = 1,
}) => CatalogScene(
  caption,
  (_) => const AuthorPage(authorId: 1),
  width: 390,
  height: height,
  textScale: textScale,
  overrides: [
    readarrServiceProvider.overrideWithValue(_Readarr()),
    readarrAuthorProvider.overrideWith((ref, item) async => _author()),
    readarrAuthorBooksProvider.overrideWith((ref, item) async => _books),
    readarrQueueSnapshotForProvider.overrideWith(
      (ref, id) async => ArrQueueSnapshot.empty,
    ),
    titleLightProvider.overrideWith((ref, url) async => _lights[url]),
  ],
);

/// The catalog's TMDB pictures, lit as the app lights them.
Future<TitleLight?> _tmdbLight(String url) async =>
    _lights[url.contains(CatalogArt.tmdbBackdrop)
        ? CatalogArt.backdrop
        : url.contains(CatalogArt.tmdbPoster)
        ? CatalogArt.poster
        : url];

Map<String, Object?> _directed(
  int id,
  String title,
  String date, {
  String type = 'movie',
  int? status,
  bool art = false,
}) => {
  'id': id,
  'mediaType': type,
  if (type == 'tv') 'name': title else 'title': title,
  type == 'tv' ? 'firstAirDate' : 'releaseDate': date,
  'voteAverage': type == 'tv' ? null : 6.6,
  'posterPath': art ? CatalogArt.tmdbPoster : null,
  'job': 'Director',
  'department': 'Directing',
  if (status != null) 'mediaInfo': {'status': status, 'status4k': 5},
};

CatalogScene _personScene(
  String caption, {
  double width = 390,
  double height = 1100,
  double textScale = 1,
  bool seerrSends = true,
  bool paned = false,
}) => CatalogScene(
  caption,
  (_) => paned
      ? MediaPane(
          canGoBack: false,
          onBack: () {},
          child: const PersonPage(personId: 1),
        )
      : const PersonPage(personId: 1),
  width: width,
  height: height,
  textScale: textScale,
  overrides: [
    personDetailProvider.overrideWith(
      (ref, id) async => const PersonDetail(
        id: 1,
        name: 'Ian Hubert',
        knownForDepartment: 'Directing',
        biography:
            'Filmmaker and visual effects artist, known for short films made '
            'with free software and for the lazy tutorials.',
        placeOfBirth: 'Seattle, Washington, USA',
      ),
    ),
    personCreditsProvider.overrideWith(
      (ref, id) async => PersonCombinedCredits.fromJson({
        'crew': [
          _directed(1, 'Dynamo Dream', '2019-02-01', type: 'tv'),
          _directed(2, 'Tears of Steel', '2012-09-26', status: 5, art: true),
          _directed(3, 'Project London', '2011-06-01'),
        ],
      }),
    ),
    seerrNumberingProvider.overrideWith((ref) async => null),
    seerrSendsToProvider.overrideWith((ref, arr) async => seerrSends),
    seriesForProvider.overrideWith((ref, id) async => const []),
    titleLightProvider.overrideWith((ref, url) => _tmdbLight(url)),
  ],
);

CatalogScene _collectionScene(String caption, {double height = 1700}) =>
    CatalogScene(
      caption,
      (_) => const CollectionPage(collectionId: 1),
      width: 390,
      height: height,
      overrides: [
        collectionDetailProvider.overrideWith(
          (ref, id) async => CollectionDetail(
            id: 1,
            name: 'Blender Open Movies',
            backdropPath: CatalogArt.tmdbBackdrop,
            parts: [
              for (final (id, title, year, status) in const [
                (1, 'Elephants Dream', 2006, 5),
                (2, 'Big Buck Bunny', 2008, 3),
                (3, 'Sintel', 2010, 5),
                (4, 'Tears of Steel', 2012, 5),
                (5, 'Spring', 2019, 5),
                (6, 'Coffee Run', 2020, 5),
                (7, 'Sprite Fright', 2021, 3),
                (8, 'Charge', 2022, 2),
              ])
                MediaPreview(
                  id: id,
                  title: title,
                  mediaType: 'movie',
                  releaseDate: '$year-04-10',
                  voteAverage: 7.4,
                  posterPath: CatalogArt.tmdbPoster,
                  mediaInfo: {'status': status},
                ),
            ],
          ),
        ),
        seerrNumberingProvider.overrideWith((ref) async => null),
        activeRequestsForProvider.overrideWith((ref, id) async => const []),
        titleLightProvider.overrideWith((ref, url) => _tmdbLight(url)),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_readLights);
  catalogCard(
    'ShelfPage',
    width: 1240,
    overrides: () => settingsScopeOverrides(
      // Seerr and Sonarr for the person and the collection, Radarr not.
      customize: (settings) => [
        _connection(ServiceKey.lidarr),
        _connection(ServiceKey.readarr),
        _connection(ServiceKey.seerr),
        _connection(ServiceKey.sonarr),
      ].fold(settings, (s, c) => s.copyWithInstance(c)),
    ),
    scenes: [
      _artistScene(
        'ArtistPage · lit by the first cover; announced, on disk, the '
        'settings and the way to Lidarr',
      ),
      _artistScene(
        'ArtistPage · no artwork: the initials, the plates, the lamp; one '
        'album wanted',
        art: false,
        wanted: true,
      ),
      CatalogScene(
        'ShelfWorkRow · open on its tracks (AlbumTracks): a complete album '
        'asks for no search',
        (_) => MediaGroup(
          children: [
            ShelfWorkRow(
              initiallyOpen: true,
              cover: const ShelfCover(
                art: (url: CatalogArt.poster, headers: null),
                size: Size.square(64),
                fallback: SizedBox.shrink(),
              ),
              title: 'Sintel',
              facts: '2010 · 5 tracks · 21\u00A0min',
              state: (
                word: 'Complete',
                tone: StatusTone.success,
                hollow: false,
              ),
              spoken: 'Sintel',
              body: (context) => AlbumTracks(
                album: _albums().first,
                record: (instanceId: 'lidarr', id: 3),
                searching: false,
                onSearch: null,
                onSearchReleases: () {},
              ),
            ),
          ],
        ),
        width: 390,
        height: 470,
        overrides: [
          lidarrAlbumTracksProvider.overrideWith((ref, album) async => _tracks),
        ],
      ),
      _authorScene(
        'AuthorPage · Readarr retired, said once; the books by year, the '
        'wanted one dashed and searched for from its card',
      ),
      _personScene(
        'PersonPage · a director by Seerr\'s credits: the role, one dot per '
        'title, the plus to Sonarr, Request where Seerr sends a movie to its '
        'Radarr, then who they are and where the credits come from',
      ),
      _personScene(
        'PersonPage where nothing set up can add a movie · the plus stays, '
        'dimmed',
        height: 760,
        seerrSends: false,
      ),
      _collectionScene(
        'CollectionPage (ShelfPage.banner) · the still lights the room; how '
        'much is on the server, the strip, the movies in release order',
      ),
      _personScene(
        'PersonPage in a tablet\'s pane, opened from a list · Close, and the '
        'light coming up from the list\'s side',
        width: 660,
        height: 820,
        paned: true,
      ),
      _personScene(
        'PersonPage at twice the reading size',
        height: 2000,
        textScale: catalogTextScale,
      ),
      _artistScene(
        'ArtistPage at twice the reading size · the name under the disc, the '
        'value under its label',
        height: 2600,
        textScale: catalogTextScale,
      ),
      _authorScene(
        'AuthorPage at twice the reading size · two books to a row',
        height: 3000,
        textScale: catalogTextScale,
      ),
      _artistScene(
        'Reading the artist · nothing to show yet',
        height: 700,
        artist: Completer<LidarrArtist>().future,
      ),
      _artistScene(
        'A wide window · the phone\'s column, centred',
        width: 1240,
        height: 1700,
      ),
    ],
  );
}
