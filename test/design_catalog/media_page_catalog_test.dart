@Tags(['catalog'])
library;

import 'dart:io' as io;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/core/title_light.dart';
import 'package:cupola/features/bazarr/domain/models/bazarr_models.dart';
import 'package:cupola/features/media/domain/media_copies.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/media/domain/media_reading.dart';
import 'package:cupola/features/media/domain/media_rows.dart';
import 'package:cupola/core/widgets/app_bottom_sheet.dart';
import 'package:cupola/features/media/presentation/media_add_sheet.dart';
import 'package:cupola/features/media/presentation/media_page.dart';
import 'package:cupola/features/search/presentation/arr_add_form_provider.dart';
import 'package:cupola/features/media/presentation/media_sources_provider.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';

import '../test_helpers/settings_scope.dart';
import 'catalog.dart';

const _key = MediaKey.movie(653);

/// Each catalog picture's light, from the same `titleLightFromPixels` the app
/// runs. Read before the sheets: the app's own read goes through an image
/// stream and an isolate, which the sheet's fake time never finishes.
final _lights = <String, TitleLight?>{};

Future<void> _readLights() async {
  for (final (url, file) in [
    (CatalogArt.backdrop, 'backdrop'),
    (CatalogArt.poster, 'poster'),
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
  // The same pictures where Seerr's record links them.
  _lights['https://image.tmdb.org/t/p/w1280${CatalogArt.tmdbBackdrop}'] =
      _lights[CatalogArt.backdrop];
  _lights['https://image.tmdb.org/t/p/w500${CatalogArt.tmdbPoster}'] =
      _lights[CatalogArt.poster];
}

ServiceInstance _connection(
  ServiceKey service,
  String id, {
  String label = '',
}) => ServiceInstance(
  id: id,
  service: service,
  label: label,
  url: 'http://nas.home.arpa',
  credential: 'catalog',
);

final _jellyfin = _connection(ServiceKey.jellyfin, 'jellyfin');
final _plex = _connection(ServiceKey.plex, 'plex');
final _radarr = _connection(ServiceKey.radarr, 'radarr');
final _radarr4k = _connection(ServiceKey.radarr, 'radarr-4k', label: '4K');
final _bazarr = _connection(ServiceKey.bazarr, 'bazarr');
final _seerr = _connection(ServiceKey.seerr, 'seerr');

final _at = DateTime(2026, 10, 3, 20, 41);

MediaReading<T> _answered<T>(T value) =>
    MediaReadingAnswered(MediaAnswer(value, _at));

/// The household's copy of the catalog's title, with [images] as Radarr links
/// them (`CatalogArt`, read from disk).
RadarrMovie _movie({List<Object?> images = const [], bool uhd = false}) =>
    RadarrMovie.fromJson({
      'id': 7,
      'title': 'Nosferatu',
      'sortTitle': 'nosferatu',
      'tmdbId': 653,
      'year': 1922,
      'runtime': 94,
      'status': 'released',
      'hasFile': true,
      'monitored': true,
      'isAvailable': true,
      'studio': 'Prana Film',
      'genres': ['Horror', 'Fantasy'],
      'overview':
          'Thomas Hutter travels to the Carpathians to sell a house to Count '
          'Orlok, who has seen a portrait of Hutter\'s wife, and follows the '
          'young man home by sea.',
      'images': images,
      'ratings': {
        'imdb': {'value': 7.8, 'votes': 113000},
        'tmdb': {'value': 7.6, 'votes': 2400},
        'rottenTomatoes': {'value': 97},
      },
      'movieFile': {
        'id': 70,
        'movieId': 7,
        'relativePath': 'Nosferatu (1922).mkv',
        'path': '/data/movies/Nosferatu (1922)/Nosferatu (1922).mkv',
        'size': uhd ? 41200000000 : 9400000000,
        'dateAdded': '2026-09-28T21:04:00Z',
        'quality': {
          'quality': {
            'id': uhd ? 19 : 7,
            'name': uhd ? 'Bluray-2160p' : 'Bluray-1080p',
            'resolution': uhd ? 2160 : 1080,
          },
        },
      },
    });

const _art = [
  {'coverType': 'poster', 'remoteUrl': CatalogArt.poster},
  {'coverType': 'fanart', 'remoteUrl': CatalogArt.backdrop},
];

StreamItem _item({StreamVideo? video, int? resumeMs}) => StreamItem(
  id: 'jf-653',
  title: 'Nosferatu',
  subtitle: '1922',
  kind: StreamItemKind.movie,
  posterPath: null,
  year: 1922,
  runtimeMs: 94 * 60000,
  isPlayed: false,
  resumeOffsetMs: resumeMs,
  unplayedChildCount: null,
  video: video,
);

/// The full household: Jellyfin part-way through, Plex silent since the
/// evening with its last answer, two Radarr copies, Bazarr wanting German,
/// and no Seerr.
List<MediaRow> _household({List<Object?> images = _art}) => [
  MediaConnectionRow<MediaStreamCopy>(
    _jellyfin,
    _answered(
      MediaStreamCopy.found(
        _item(
          video: const StreamVideo(width: 3840, height: 2160, range: 'HDR10'),
          resumeMs: 31 * 60000,
        ),
      ),
    ),
  ),
  MediaConnectionRow<MediaStreamCopy>(
    _plex,
    MediaReadingFailed(
      ServiceFailureReason.unreachable,
      lastKnown: MediaAnswer(
        MediaStreamCopy.found(
          _item(video: const StreamVideo(width: 1920, height: 1080)),
        ),
        DateTime(2026, 10, 3, 18, 12),
      ),
    ),
  ),
  MediaConnectionRow<MediaRadarrCopy>(
    _radarr,
    _answered(
      MediaRadarrCopy(
        movie: _movie(images: images),
        queue: ArrQueueSnapshot.empty,
      ),
    ),
  ),
  MediaConnectionRow<MediaRadarrCopy>(
    _radarr4k,
    _answered(
      MediaRadarrCopy(
        movie: _movie(images: images, uhd: true),
        queue: ArrQueueSnapshot.empty,
      ),
    ),
  ),
  MediaConnectionRow<MediaBazarrCopy?>(
    _bazarr,
    _answered(
      const MediaBazarrCopy(
        arrConnectionId: 'radarr',
        movie: BazarrMovie(
          radarrId: 7,
          monitored: true,
          presentLanguages: [
            BazarrSubtitleLanguage(name: 'English', code2: 'en'),
          ],
          missingLanguages: [
            BazarrSubtitleLanguage(name: 'German', code2: 'de'),
          ],
        ),
      ),
    ),
  ),
  const MediaNotSetUpRow(ServiceKey.seerr),
];

/// The household with Seerr in place of its setup row: TMDB's record names
/// the title, and the collection it belongs to.
List<MediaRow> _withSeerr() => [
  ..._household().where((row) => row is! MediaNotSetUpRow),
  MediaConnectionRow<MediaSeerrRecord>(
    _seerr,
    _answered(
      const MediaSeerrRecord(
        details: {
          'id': 653,
          'title': 'Nosferatu',
          'releaseDate': '1922-02-16',
          'runtime': 94,
          'genres': [
            {'id': 27, 'name': 'Horror'},
          ],
          'overview':
              'Thomas Hutter travels to the Carpathians to sell a house to '
              'Count Orlok, and the count follows him home by sea.',
          'posterPath': CatalogArt.tmdbPoster,
          'backdropPath': CatalogArt.tmdbBackdrop,
          'voteAverage': 7.6,
          'credits': {
            'crew': [
              {'id': 1, 'name': 'F. W. Murnau', 'job': 'Director'},
            ],
          },
          'collection': {
            'id': 1,
            'name': 'Silent Horror',
            'backdropPath': CatalogArt.tmdbBackdrop,
          },
          'mediaInfo': {'status': 5},
        },
      ),
    ),
  ),
];

/// A film nobody holds: Jellyfin has none, neither Radarr tracks it.
List<MediaRow> _notHeld() => [
  MediaConnectionRow<MediaStreamCopy>(
    _jellyfin,
    _answered(const MediaStreamCopy.notInLibrary()),
  ),
  for (final radarr in [_radarr, _radarr4k])
    MediaConnectionRow<MediaRadarrCopy>(
      radarr,
      _answered(
        const MediaRadarrCopy(movie: null, queue: ArrQueueSnapshot.empty),
      ),
    ),
  const MediaNotSetUpRow(ServiceKey.seerr),
];

/// The add form as a Radarr answers it: two profiles, one folder, fourteen
/// indexers.
class _CatalogAddForm extends ArrAddFormNotifier {
  _CatalogAddForm(super.arg);

  @override
  ArrAddFormState build() => const ArrAddFormState(
    profiles: [(id: 1, name: 'HD-1080p'), (id: 2, name: 'Any')],
    rootFolders: ['/mnt/tank/media/movies'],
    freeSpace: {'/mnt/tank/media/movies': 13600000000000},
    searchingIndexers: 14,
    profileId: 1,
    rootFolder: '/mnt/tank/media/movies',
    isLoading: false,
  );
}

/// The add sheet, open over a page that holds nothing of the film: the
/// panel drawn in place, as `AppBottomSheet`'s card draws its panels.
CatalogScene _addScene() => CatalogScene(
  'Add · over a film nobody holds: which Radarr, its profile and '
  'folder, Monitor and Search when added',
  (context) => Stack(
    fit: StackFit.expand,
    children: [
      const MediaPage(mediaKey: _key),
      const ColoredBox(color: Colors.black54),
      Align(
        alignment: Alignment.bottomCenter,
        child: AppBottomSheet(
          title: 'Add to Radarr',
          subtitle: 'Nosferatu · 1922',
          showClose: true,
          child: MediaAddSheet(
            tmdbId: 653,
            connections: [_radarr, _radarr4k],
            name: (c) => c.label.isEmpty ? 'Radarr' : 'Radarr ${c.label}',
            light: _lights[CatalogArt.backdrop],
          ),
        ),
      ),
    ],
  ),
  width: 390,
  height: 844,
  overrides: [
    mediaRowsProvider.overrideWith((ref, key) => _notHeld()),
    audienceProvider.overrideWithValue(Audience.operator),
    titleLightProvider.overrideWith((ref, url) async => null),
    arrAddFormProvider.overrideWith2(_CatalogAddForm.new),
    mediaAddLookupProvider.overrideWith(
      (ref, target) async => _movie(images: _art),
    ),
  ],
);

/// One Radarr copy and nothing else, with [images].
List<MediaRow> _bare(List<Object?> images) => [
  MediaConnectionRow<MediaRadarrCopy>(
    _radarr,
    _answered(
      MediaRadarrCopy(
        movie: _movie(images: images),
        queue: ArrQueueSnapshot.empty,
      ),
    ),
  ),
  const MediaNotSetUpRow(ServiceKey.seerr),
];

CatalogScene _scene(
  String caption,
  List<MediaRow> rows, {
  double width = 390,
  double height = 1960,
  Audience audience = Audience.operator,
  double textScale = 1,
}) => CatalogScene(
  caption,
  (_) => const MediaPage(mediaKey: _key),
  width: width,
  height: height,
  textScale: textScale,
  overrides: [
    mediaRowsProvider.overrideWith((ref, key) => rows),
    audienceProvider.overrideWithValue(audience),
    titleLightProvider.overrideWith((ref, url) async => _lights[url]),
    mediaCollectionHeldProvider.overrideWith(
      (ref, collection) async => (held: 5, total: 8),
    ),
    mediaRecommendationsProvider.overrideWith((ref, source) async => []),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_readLights);
  catalogCard(
    'MediaPage',
    width: 1240,
    overrides: () => settingsScopeOverrides(
      customize: (settings) => [
        _jellyfin,
        _plex,
        _radarr,
        _radarr4k,
        _bazarr,
        _seerr,
      ].fold(settings, (s, c) => s.copyWithInstance(c)),
    ),
    scenes: [
      _scene(
        'Operator · Resume on Jellyfin, lit by the backdrop; every row shape: '
        'a fact with its picture, a failure with its last answer, two copies, '
        'Bazarr, Seerr not set up',
        _household(),
      ),
      _scene(
        'Requester · the media servers only, no Manage',
        _household(),
        height: 1100,
        audience: Audience.requester,
      ),
      _scene(
        'No backdrop · the poster, veiled, carries the slab',
        _bare(const [
          {'coverType': 'poster', 'remoteUrl': CatalogArt.poster},
        ]),
        height: 760,
      ),
      _scene(
        'No artwork · the plate, dark in both rooms',
        _bare(const []),
        height: 760,
      ),
      _scene('Waiting · nobody has said who the title is yet', [
        MediaConnectionRow<MediaRadarrCopy>(
          _radarr,
          const MediaReadingWaiting(),
        ),
      ], height: 760),
      _scene(
        'With Seerr · TMDB names the title, and the collection it belongs '
        'to: 5 of 8 on your server',
        _withSeerr(),
        height: 1660,
      ),
      _scene(
        'Tablet · a detail pane: the phone column, wider',
        _withSeerr(),
        width: 592,
        height: 1900,
      ),
      _scene(
        'Tablet · full screen: two tracks, the servers and Manage beside',
        _withSeerr(),
        width: 1180,
        height: 1400,
      ),
      _addScene(),
      _scene(
        'Twice the reading size',
        _household(),
        height: 2400,
        textScale: catalogTextScale,
      ),
    ],
  );
}
