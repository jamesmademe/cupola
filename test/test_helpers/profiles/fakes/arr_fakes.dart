/// Radarr, Sonarr, Lidarr, Readarr, Prowlarr and Bazarr on the fake network.
///
/// The arrs share one wire shape — `X-Api-Key`, `/api/<v>/…`, the paged
/// envelope — so they share [ArrFake]; each subclass supplies its library. A
/// server's library is chosen by which connection it is (Radarr or Radarr 4K,
/// Sonarr or Sonarr Anime), never by which profile, so the same Radarr answers
/// the same way wherever it appears.
library;

import 'package:cupola/features/settings/domain/service_key.dart';

import '../profile_network.dart';
import '../service_fakes.dart';
import '../world.dart';

/// The shared arr surface: status, health, queue, history, calendar, wanted,
/// profiles, root folders, commands.
abstract class ArrFake extends ServiceFake {
  const ArrFake();

  String get apiVersion;
  String get appName;
  String get version;

  String get _base => '/api/$apiVersion';

  List<JsonMap> queue(ServerContext c) => const [];
  List<JsonMap> history(ServerContext c) => const [];
  List<JsonMap> calendar(ServerContext c) => const [];
  List<JsonMap> missing(ServerContext c) => const [];

  /// `/parse?title=`: the arr reading a release name. Unread by default, the
  /// way an arr answers a name its parser cannot place: the title echoed and
  /// nothing else.
  JsonMap parse(ServerContext c, String title) => {'title': title};

  /// The world title [release] is a release of, read the way the fakes write
  /// release names (`Sprite.Fright.2021.1080p.WEB`), or null.
  static WorldTitle? titleOfRelease(String release) {
    for (final title in WorldTitles.all) {
      if (release.startsWith('${title.title.replaceAll(' ', '.')}.')) {
        return title;
      }
    }
    return null;
  }

  /// The service's own routes, tried after the shared ones.
  NetworkReply? own(NetworkRequest r, ServerContext c) => null;

  /// The indexers the arr searches with: three, two of which an automatic
  /// search asks. Null for Prowlarr, whose indexers are its own routes.
  List<JsonMap>? get indexers => const [
    {'id': 1, 'name': 'Nyaa', 'enableAutomaticSearch': true},
    {'id': 2, 'name': 'Torrentio', 'enableAutomaticSearch': true},
    {'id': 3, 'name': 'Archive', 'enableAutomaticSearch': false},
  ];

  @override
  NetworkReply? answer(NetworkRequest r, ServerContext c) {
    final path = r.path;
    if (r.method == 'GET') {
      switch (path) {
        case final p when p == '$_base/system/status':
          return NetworkReply.json({
            'appName': appName,
            'instanceName': c.server.label.isEmpty
                ? appName
                : '$appName ${c.server.label}',
            'version': version,
            'isProduction': true,
            'osName': 'debian',
          });
        case final p when p == '$_base/health':
          return NetworkReply.json(const <Object?>[]);
        case final p when p == '$_base/queue':
          return NetworkReply.json(pagedEnvelope(r, queue(c)));
        case final p when p == '$_base/queue/details':
          return NetworkReply.json(queue(c));
        case final p when p == '$_base/history':
          return NetworkReply.json(pagedEnvelope(r, history(c)));
        case final p when p == '$_base/history/since':
          return NetworkReply.json(history(c));
        case final p when p == '$_base/calendar':
          return NetworkReply.json(calendar(c));
        case final p when p == '$_base/wanted/missing':
          return NetworkReply.json(pagedEnvelope(r, missing(c)));
        case final p when p == '$_base/wanted/cutoff':
          return NetworkReply.json(pagedEnvelope(r, const []));
        case final p when p == '$_base/blocklist':
          return NetworkReply.json(pagedEnvelope(r, const []));
        case final p when p == '$_base/parse':
          return NetworkReply.json(parse(c, r.query['title'] ?? ''));
        case final p when p == '$_base/qualityprofile':
          // The first asks for 1080p (2160p on a 4K server) and stops there.
          final top = c.server.is4k ? 2160 : 1080;
          return NetworkReply.json([
            {
              'id': 1,
              'name': c.server.is4k ? 'Ultra-HD' : 'HD-1080p',
              'cutoff': top == 2160 ? 19 : 3,
              'items': [
                {
                  'quality': {'id': 5, 'name': 'WEBDL-720p', 'resolution': 720},
                  'allowed': true,
                },
                {
                  'quality': {
                    'id': 3,
                    'name': 'WEBDL-1080p',
                    'resolution': 1080,
                  },
                  'allowed': true,
                },
                if (top == 2160)
                  {
                    'quality': {
                      'id': 19,
                      'name': 'Bluray-2160p',
                      'resolution': 2160,
                    },
                    'allowed': true,
                  },
              ],
            },
            {'id': 2, 'name': 'Any'},
          ]);
        case final p when p == '$_base/rootfolder':
          return NetworkReply.json([
            {
              'id': 1,
              'path': rootFolder(c),
              'accessible': true,
              'freeSpace': 12400000000000,
            },
          ]);
        case final p when p == '$_base/tag':
          return NetworkReply.json(const <Object?>[]);
        // No command running: nothing is being searched for.
        case final p when p == '$_base/command':
          return NetworkReply.json(const <Object?>[]);
        case final p when p == '$_base/indexer' && indexers != null:
          return NetworkReply.json(indexers);
        case final p when p == '$_base/manualimport':
          return NetworkReply.json(manualImport(r, c));
        case final p when p == '$_base/filesystem':
          return NetworkReply.json({
            'parent': '/mnt/tank/downloads/',
            'directories': [
              for (final d in arrDownloads(c))
                {
                  'type': 'folder',
                  'name': d.release,
                  'path': '/mnt/tank/downloads/complete/${d.release}',
                },
            ],
            'files': const <Object?>[],
          });
        case final p when p == '$_base/diskspace':
          return NetworkReply.json([
            {
              'path': '/mnt/tank',
              'label': 'tank',
              'freeSpace': 12400000000000,
              'totalSpace': 43600000000000,
            },
          ]);
      }
    }
    if (r.method == 'POST' && path == '$_base/command') {
      final body = r.json;
      return NetworkReply.json({
        'id': 1,
        'name': body is Map ? body['name'] : 'Command',
        'status': 'queued',
        'queued': c.ago(Duration.zero),
      }, status: 201);
    }
    if (r.method == 'DELETE' && path.startsWith('$_base/queue/')) {
      return NetworkReply.json(const <String, Object?>{});
    }
    return own(r, c);
  }

  String rootFolder(ServerContext c) => '/mnt/tank/media';

  /// What `GET manualimport` finds in a download's folder: one file per
  /// download of this server whose folder or id the request names. A
  /// download the arr cannot place (Sonarr's tapes) comes back with no
  /// episodes and a rejection, as it does live.
  List<JsonMap> manualImport(NetworkRequest r, ServerContext c) {
    final folder = r.query['folder'];
    final downloadId = r.query['downloadId']?.toLowerCase();
    return [
      for (final (i, d) in arrDownloads(c).indexed)
        if ((folder != null && folder.contains(d.release)) ||
            (downloadId != null && downloadId == d.id.toLowerCase()))
          manualImportItem(c, d, id: i + 1),
    ];
  }

  JsonMap manualImportItem(
    ServerContext c,
    WorldDownload d, {
    required int id,
  }) {
    final folder = '/mnt/tank/downloads/complete/${d.release}';
    return {
      'id': id,
      'path': '$folder/${d.release}.mkv',
      'relativePath': '${d.release}.mkv',
      'folderName': d.release,
      'name': d.release,
      'size': d.size,
      'downloadId': d.id.toUpperCase(),
      'quality': _quality('WEBDL-1080p'),
      'languages': const [
        {'id': 1, 'name': 'English'},
      ],
      'releaseGroup': 'WORLD',
      'customFormats': const <Object?>[],
      'rejections': const <Object?>[],
    };
  }
}

// === Radarr ================================================================

class RadarrFake extends ArrFake {
  const RadarrFake();

  @override
  String get apiVersion => 'v3';
  @override
  String get appName => 'Radarr';
  @override
  String get version => '5.14.0.9383';

  @override
  String rootFolder(ServerContext c) =>
      c.server.is4k ? '/mnt/tank/media/films-4k' : '/mnt/tank/media/films';

  /// `(id, title, hasFile, added ago)` on the first Radarr. The ids restart
  /// at 1 on each server, as they do live: the same id names a different film
  /// on Radarr 4K, which is what makes a manual import that lands on the wrong
  /// server testable at all.
  static const libraryHd = [
    (1, WorldTitles.spriteFright, false, Duration(days: 20)),
    (2, WorldTitles.bigBuckBunny, false, Duration(days: 4)),
    (3, WorldTitles.coffeeRun, true, Duration(hours: 2, minutes: 15)),
    (4, WorldTitles.sintel, true, Duration(days: 2)),
    (5, WorldTitles.tearsOfSteel, true, Duration(days: 17)),
    (6, WorldTitles.elephantsDream, true, Duration(days: 40)),
  ];

  /// The same, on Radarr 4K.
  static const library4k = [
    (1, WorldTitles.elephantsDream, false, Duration(days: 3)),
    (2, WorldTitles.sintel, false, Duration(days: 1)),
    (3, WorldTitles.spring, true, Duration(hours: 2, minutes: 1)),
    (4, WorldTitles.tearsOfSteel, true, Duration(days: 1, hours: 2)),
  ];

  /// The id [title] has on the HD or the 4K Radarr, or null.
  static int? idOf(WorldTitle title, {required bool is4k}) {
    for (final entry in is4k ? library4k : libraryHd) {
      if (entry.$2 == title) return entry.$1;
    }
    return null;
  }

  List<(int, WorldTitle, bool, Duration)> _library(ServerContext c) =>
      c.server.is4k ? library4k : libraryHd;

  JsonMap _movie(ServerContext c, (int, WorldTitle, bool, Duration) entry) {
    final (id, title, hasFile, added) = entry;
    final spriteFright = title == WorldTitles.spriteFright;
    return {
      'id': id,
      'title': title.title,
      'sortTitle': title.title.toLowerCase(),
      'titleSlug': '${title.slug}-${title.tmdbId}',
      'year': title.year,
      'tmdbId': title.tmdbId,
      if (title.imdbId != null) 'imdbId': title.imdbId,
      'status': 'released',
      'monitored': true,
      'hasFile': hasFile,
      'isAvailable': true,
      'sizeOnDisk': hasFile ? (c.server.is4k ? 9800000000 : 1200000000) : 0,
      'runtime': 12,
      'qualityProfileId': 1,
      'minimumAvailability': 'released',
      'path': '${rootFolder(c)}/${title.title} (${title.year})',
      if (hasFile) 'movieFile': _movieFile(c, id, title),
      'added': c.ago(added),
      if (spriteFright) 'digitalRelease': c.ago(const Duration(hours: 6)),
      if (spriteFright) 'physicalRelease': c.ahead(const Duration(days: 13)),
      'images': const <Object?>[],
      'genres': const ['Animation'],
      'ratings': const <String, Object?>{},
    };
  }

  /// The file a movie with one carries, as Radarr embeds it
  /// (`MovieFileResource`). The titles cover the ways a file relates to its
  /// release: renamed, with the scene name kept (Coffee Run, Spring); kept as
  /// released (Tears of Steel); renamed, with only the original path kept
  /// (Sintel); renamed with no original recorded (Elephants Dream).
  JsonMap _movieFile(ServerContext c, int id, WorldTitle title) {
    final is4k = c.server.is4k;
    final release =
        '${title.title.replaceAll(' ', '.')}.${title.year}.'
        '${is4k ? '2160p.UHD.BluRay.x265' : '1080p.BluRay.x264'}-WORLD';
    final quality = is4k ? 'Bluray-2160p' : 'Bluray-1080p';
    final renamed = '${title.title} (${title.year}) $quality.mkv';
    final keptAsReleased = title == WorldTitles.tearsOfSteel;
    final relativePath = keptAsReleased ? '$release.mkv' : renamed;
    final folder = '${rootFolder(c)}/${title.title} (${title.year})';
    return {
      'id': 100 + id,
      'movieId': id,
      'relativePath': relativePath,
      'path': '$folder/$relativePath',
      'size': is4k ? 9800000000 : 1200000000,
      'dateAdded': c.ago(const Duration(days: 1)),
      if (title != WorldTitles.sintel && title != WorldTitles.elephantsDream)
        'sceneName': release,
      if (title == WorldTitles.sintel)
        'originalFilePath': '$release/${title.slug}.mkv'
      else if (title != WorldTitles.elephantsDream)
        'originalFilePath': '$release.mkv',
      'releaseGroup': 'WORLD',
      'quality': _quality(quality),
    };
  }

  @override
  JsonMap parse(ServerContext c, String title) {
    final world = ArrFake.titleOfRelease(title);
    if (world == null || world.isSeries) return {'title': title};
    return {
      'title': title,
      'parsedMovieInfo': {
        'movieTitles': [world.title],
        'primaryMovieTitle': world.title,
        'year': world.year,
      },
      'movie': ?_movieFor(c, world),
    };
  }

  List<JsonMap> movies(ServerContext c) => [
    for (final entry in _library(c)) _movie(c, entry),
  ];

  JsonMap? _movieFor(ServerContext c, WorldTitle? title) {
    for (final entry in _library(c)) {
      if (entry.$2 == title) return _movie(c, entry);
    }
    return null;
  }

  @override
  List<JsonMap> queue(ServerContext c) => [
    for (final (i, d) in arrDownloads(c).indexed)
      arrQueueRecord(
        c,
        d,
        index: i + 1,
        media: 'movie',
        item: _movieFor(c, d.title),
      ),
  ];

  @override
  List<JsonMap> history(ServerContext c) => [
    for (final entry in _library(c))
      if (entry.$3)
        {
          'id': entry.$1,
          'movieId': entry.$1,
          'eventType': 'downloadFolderImported',
          'sourceTitle':
              '${entry.$2.title.replaceAll(' ', '.')}.${entry.$2.year}'
              '${c.server.is4k ? '.2160p' : '.1080p'}',
          'date': c.ago(entry.$4),
          'quality': _quality(c.server.is4k ? 'Bluray-2160p' : 'Bluray-1080p'),
          'movie': _movie(c, entry),
          // An import names the file it dropped and the one it became.
          'data': {
            'droppedPath':
                '/mnt/tank/downloads/complete/'
                '${entry.$2.title.replaceAll(' ', '.')}.${entry.$2.year}.mkv',
            'importedPath':
                '${rootFolder(c)}/${entry.$2.title} (${entry.$2.year})/'
                '${entry.$2.title} (${entry.$2.year}).mkv',
          },
        },
  ];

  @override
  List<JsonMap> calendar(ServerContext c) => [
    for (final entry in _library(c))
      if (entry.$2 == WorldTitles.spriteFright) _movie(c, entry),
  ];

  @override
  List<JsonMap> missing(ServerContext c) => [
    for (final entry in _library(c))
      if (!entry.$3) _movie(c, entry),
  ];

  @override
  NetworkReply? own(NetworkRequest r, ServerContext c) {
    if (r.method == 'GET' && r.path == '/api/v3/movie') {
      final tmdb = r.query['tmdbId'];
      final all = movies(c);
      return NetworkReply.json(
        tmdb == null
            ? all
            : all.where((m) => '${m['tmdbId']}' == tmdb).toList(),
      );
    }
    final one = RegExp(r'^/api/v3/movie/(\d+)$').firstMatch(r.path);
    if (r.method == 'GET' && one != null) {
      final id = int.parse(one.group(1)!);
      for (final entry in _library(c)) {
        if (entry.$1 == id) return NetworkReply.json(_movie(c, entry));
      }
      return NetworkReply.json({'message': 'NotFound'}, status: 404);
    }
    if (r.method == 'GET' && r.path == '/api/v3/movie/lookup') {
      return NetworkReply.json(movies(c));
    }
    // One film looked up by its TMDB id, as Radarr answers it whether or not
    // it holds it: a film it does not hold has no id of its own.
    if (r.method == 'GET' && r.path == '/api/v3/movie/lookup/tmdb') {
      final tmdb = r.query['tmdbId'];
      for (final title in WorldTitles.all) {
        if (!title.isSeries && '${title.tmdbId}' == tmdb) {
          final held = [
            for (final entry in _library(c))
              if (entry.$2 == title) _movie(c, entry),
          ];
          return NetworkReply.json(
            held.firstOrNull ??
                {
                  'title': title.title,
                  'titleSlug': '${title.slug}-${title.tmdbId}',
                  'year': title.year,
                  'tmdbId': title.tmdbId,
                  'images': const <Object?>[],
                  'minimumAvailability': 'released',
                },
          );
        }
      }
      return NetworkReply.json({'message': 'NotFound'}, status: 404);
    }
    // An add: Radarr answers with the new record. The world does not keep it.
    if (r.method == 'POST' && r.path == '/api/v3/movie') {
      final body = r.json;
      return NetworkReply.json({
        if (body is Map) ...body.cast<String, Object?>(),
        'id': 100,
        'hasFile': false,
      }, status: 201);
    }
    if (r.method == 'DELETE' && one != null) {
      return NetworkReply.json(const <String, Object?>{});
    }
    // An edit: Radarr answers with the record as it now stands.
    if (r.method == 'PUT' && one != null) {
      return NetworkReply.json(r.json);
    }
    // One film's history, unpaged, as `/history/movie` answers it.
    if (r.method == 'GET' && r.path == '/api/v3/history/movie') {
      final id = r.query['movieId'];
      return NetworkReply.json([
        for (final record in history(c))
          if ('${record['movieId']}' == id) record,
      ]);
    }
    if (r.method == 'GET' && r.path == '/api/v3/moviefile') {
      return NetworkReply.json(const <Object?>[]);
    }
    return null;
  }
}

// === Sonarr ================================================================

class SonarrFake extends ArrFake {
  const SonarrFake();

  @override
  String get apiVersion => 'v3';
  @override
  String get appName => 'Sonarr';
  @override
  String get version => '4.0.9.2244';

  bool _anime(ServerContext c) =>
      c.server.label.toLowerCase().contains('anime');

  @override
  String rootFolder(ServerContext c) =>
      _anime(c) ? '/mnt/tank/media/anime' : '/mnt/tank/media/series';

  JsonMap _series(ServerContext c, int id, WorldTitle title) {
    final cosmos = title == WorldTitles.cosmosLaundromat;
    return {
      'id': id,
      'title': title.title,
      'sortTitle': title.title.toLowerCase(),
      'titleSlug': title.slug,
      'year': title.year,
      'tvdbId': title.tvdbId,
      'tmdbId': title.tmdbId,
      'status': 'continuing',
      'monitored': true,
      'seriesType': _anime(c) ? 'anime' : 'standard',
      'path': '${rootFolder(c)}/${title.title}',
      'qualityProfileId': 1,
      'added': c.ago(const Duration(days: 300)),
      'images': const <Object?>[],
      'genres': const ['Animation'],
      if (cosmos) 'nextAiring': c.ahead(const Duration(days: 3, minutes: 7)),
      if (title == WorldTitles.nightShift)
        'nextAiring': c.ahead(const Duration(days: 1, hours: 1, minutes: 7)),
      'seasons': cosmos
          ? [_season(1, 10, 10, 10), _season(2, 3, 10, 10), _season(3, 0, 0, 8)]
          : [_season(1, 8, 8, 8), _season(2, 4, 5, 10)],
      'statistics': cosmos
          ? {
              'seasonCount': 3,
              'episodeFileCount': 13,
              'episodeCount': 20,
              'totalEpisodeCount': 28,
              'sizeOnDisk': 15000000000,
              'percentOfEpisodes': 65.0,
            }
          : {
              'seasonCount': 2,
              'episodeFileCount': 12,
              'episodeCount': 13,
              'totalEpisodeCount': 18,
              'sizeOnDisk': 9000000000,
              'percentOfEpisodes': 92.3,
            },
    };
  }

  static JsonMap _season(int number, int files, int aired, int total) => {
    'seasonNumber': number,
    'monitored': true,
    'statistics': {
      'episodeFileCount': files,
      'episodeCount': aired,
      'totalEpisodeCount': total,
      'sizeOnDisk': files * 1100000000,
      'percentOfEpisodes': aired == 0 ? 0.0 : files * 100.0 / aired,
    },
  };

  static const libraryMain = [
    (1, WorldTitles.cosmosLaundromat),
    (2, WorldTitles.nightShift),
  ];
  static const libraryAnime = [(1, WorldTitles.agent327)];

  /// The id [title] has on the main Sonarr, or null.
  static int? idOf(WorldTitle title) {
    for (final (id, t) in libraryMain) {
      if (t == title) return id;
    }
    return null;
  }

  List<(int, WorldTitle)> _library(ServerContext c) =>
      _anime(c) ? libraryAnime : libraryMain;

  /// A release of a series this Sonarr holds names the series; the episode is
  /// read off its `S02E04`.
  @override
  JsonMap parse(ServerContext c, String title) {
    final world = ArrFake.titleOfRelease(title);
    if (world == null || !world.isSeries) return {'title': title};
    final code = RegExp(r'S(\d+)E(\d+)').firstMatch(title);
    final held = [
      for (final (id, t) in _library(c))
        if (t == world) _series(c, id, t),
    ];
    return {
      'title': title,
      'parsedEpisodeInfo': {
        'seriesTitle': world.title,
        if (code != null) 'seasonNumber': int.parse(code.group(1)!),
        'episodeNumbers': [if (code != null) int.parse(code.group(2)!)],
      },
      if (held.isNotEmpty) 'series': held.first,
    };
  }

  List<JsonMap> series(ServerContext c) => [
    for (final (id, t) in _library(c)) _series(c, id, t),
  ];

  /// Cosmos Laundromat's episodes: S1 on disk, S2 E1–E3 on disk, E4–E10
  /// aired and missing (E4, E5 downloading), S3 announced.
  List<JsonMap> _episodes(ServerContext c, int seriesId) {
    if (_anime(c) || seriesId != 1) return const [];
    var id = 1000;
    JsonMap episode(
      int season,
      int number, {
      required bool file,
      Duration? airedAgo,
      Duration? airsIn,
    }) => {
      'id': ++id,
      'seriesId': 1,
      'seasonNumber': season,
      'episodeNumber': number,
      'title': switch ((season, number)) {
        (2, 3) => 'The Second Cycle',
        (2, 6) => 'The Seventh Cycle',
        _ => 'Episode $number',
      },
      'hasFile': file,
      if (file) 'episodeFileId': id + 5000,
      'monitored': true,
      'airDateUtc': airsIn != null
          ? c.ahead(airsIn)
          : c.ago(airedAgo ?? const Duration(days: 400)),
    };
    return [
      for (var e = 1; e <= 10; e++) episode(1, e, file: true),
      for (var e = 1; e <= 10; e++)
        episode(
          2,
          e,
          file: e <= 3,
          // The tenth aired yesterday: every one of them has.
          airedAgo: Duration(days: 71 - e * 7),
        ),
      for (var e = 1; e <= 8; e++)
        episode(
          3,
          e,
          file: false,
          airsIn: Duration(days: 3 + (e - 1) * 7, minutes: 7),
        ),
    ];
  }

  JsonMap _episodeFile(JsonMap e, String quality, int resolution, String at) {
    final code =
        'S${'${e['seasonNumber']}'.padLeft(2, '0')}'
        'E${'${e['episodeNumber']}'.padLeft(2, '0')}';
    return {
      'id': e['episodeFileId'],
      'seriesId': e['seriesId'],
      'seasonNumber': e['seasonNumber'],
      'relativePath':
          'Season ${'${e['seasonNumber']}'.padLeft(2, '0')}/'
          'Cosmos Laundromat - $code - ${e['title']} $quality.mkv',
      'size': resolution == 1080 ? 1200000000 : 640000000,
      'dateAdded': at,
      'quality': {
        'quality': {'name': quality, 'resolution': resolution},
      },
      'qualityCutoffNotMet': resolution < 1080,
    };
  }

  /// The id Sonarr gives episode [episode] of season [season] of series
  /// [seriesId]: Cosmos Laundromat's are its episode list's, 1001 onwards;
  /// another series' sit in their own thousand (Night Shift's S2 E5, on the
  /// calendar, is 2105).
  static int episodeIdOf(int seriesId, int season, int episode) => seriesId == 1
      ? 1000 + (season - 1) * 10 + episode
      : seriesId * 1000 + (season - 1) * 100 + episode;

  /// The series this Sonarr holds [title] under, as its id and its record.
  (int, JsonMap)? _seriesFor(ServerContext c, WorldTitle? title) {
    for (final (id, t) in _library(c)) {
      if (t == title) return (id, _series(c, id, t));
    }
    return null;
  }

  /// Each record names its own series and episode: Night Shift's are Night
  /// Shift's, never Cosmos Laundromat's.
  @override
  List<JsonMap> queue(ServerContext c) => [
    for (final (i, d) in arrDownloads(c).indexed)
      if (_seriesFor(c, d.title) case final held)
        arrQueueRecord(
          c,
          d,
          index: i + 1,
          media: 'series',
          item: held?.$2,
          episodeId: held == null || d.season == null || d.episode == null
              ? null
              : episodeIdOf(held.$1, d.season!, d.episode!),
        ),
  ];

  @override
  List<JsonMap> history(ServerContext c) => _anime(c)
      ? const []
      : [
          {
            'id': 1,
            'seriesId': 1,
            'episodeId': 1013,
            'eventType': 'downloadFolderImported',
            'sourceTitle': 'Cosmos.Laundromat.S02E03.1080p.WEB',
            'date': c.ago(const Duration(hours: 2, minutes: 43)),
            'quality': _quality('WEBDL-1080p'),
            'series': _series(c, 1, WorldTitles.cosmosLaundromat),
            'episode': _episodes(c, 1)[12],
            'data': const <String, Object?>{},
          },
        ];

  @override
  List<JsonMap> calendar(ServerContext c) {
    if (_anime(c)) return const [];
    final cosmos = _series(c, 1, WorldTitles.cosmosLaundromat);
    return [
      {..._episodes(c, 1)[20], 'series': cosmos},
      {
        'id': 2105,
        'seriesId': 2,
        'seasonNumber': 2,
        'episodeNumber': 5,
        'title': 'Episode 5',
        'hasFile': false,
        'monitored': true,
        'airDateUtc': c.ahead(const Duration(days: 1, hours: 1, minutes: 7)),
        'series': _series(c, 2, WorldTitles.nightShift),
      },
    ];
  }

  @override
  List<JsonMap> missing(ServerContext c) => [
    for (final e in _episodes(c, 1))
      if (e['seasonNumber'] == 2 && e['hasFile'] == false)
        {...e, 'series': _series(c, 1, WorldTitles.cosmosLaundromat)},
  ];

  @override
  JsonMap manualImportItem(
    ServerContext c,
    WorldDownload d, {
    required int id,
  }) {
    final base = super.manualImportItem(c, d, id: id);
    final placed = d.season != null && d.episode != null;
    final (seriesId, series) =
        _seriesFor(c, d.title) ??
        (1, _series(c, 1, WorldTitles.cosmosLaundromat));
    return {
      ...base,
      'series': series,
      if (placed) 'seasonNumber': d.season,
      'episodes': placed
          ? [
              {
                'id': episodeIdOf(seriesId, d.season!, d.episode!),
                'seriesId': seriesId,
                'seasonNumber': d.season,
                'episodeNumber': d.episode,
                'title': 'Episode ${d.episode}',
                'hasFile': true,
              },
            ]
          : const <Object?>[],
      'rejections': placed
          ? const <Object?>[]
          : const [
              {
                'reason': 'Unable to determine episode from the file name',
                'type': 'permanent',
              },
            ],
    };
  }

  @override
  NetworkReply? own(NetworkRequest r, ServerContext c) {
    if (r.method == 'GET' && r.path == '/api/v3/series') {
      // `?tvdbId=` filters, as Sonarr's own route does.
      final tvdb = r.query['tvdbId'];
      final all = series(c);
      return NetworkReply.json(
        tvdb == null
            ? all
            : all.where((s) => '${s['tvdbId']}' == tvdb).toList(),
      );
    }
    final one = RegExp(r'^/api/v3/series/(\d+)$').firstMatch(r.path);
    if (r.method == 'GET' && one != null) {
      final id = int.parse(one.group(1)!);
      for (final (sid, t) in _library(c)) {
        if (sid == id) return NetworkReply.json(_series(c, sid, t));
      }
      return NetworkReply.json({'message': 'NotFound'}, status: 404);
    }
    if (r.method == 'GET' && r.path == '/api/v3/episode') {
      final id = int.tryParse(r.query['seriesId'] ?? '') ?? 0;
      return NetworkReply.json(_episodes(c, id));
    }
    if (r.method == 'GET' && r.path == '/api/v3/series/lookup') {
      return NetworkReply.json(series(c));
    }
    if (r.method == 'GET' && r.path == '/api/v3/episodefile') {
      final id = int.tryParse(r.query['seriesId'] ?? '') ?? 0;
      // The first season and the second's first two in 720p, below the
      // profile's 1080p; the third episode in 1080p, imported this evening.
      return NetworkReply.json([
        for (final e in _episodes(c, id))
          if (e['hasFile'] == true)
            if (e['seasonNumber'] == 2 && e['episodeNumber'] == 3)
              _episodeFile(
                e,
                'WEBDL-1080p',
                1080,
                c.ago(const Duration(hours: 2, minutes: 43)),
              )
            else
              _episodeFile(
                e,
                'WEBDL-720p',
                720,
                c.ago(const Duration(days: 40)),
              ),
      ]);
    }
    if (r.method == 'PUT' && r.path == '/api/v3/episode/monitor') {
      return const NetworkReply(202);
    }
    return null;
  }
}

// === Lidarr ================================================================

class LidarrFake extends ArrFake {
  const LidarrFake();

  @override
  String get apiVersion => 'v1';
  @override
  String get appName => 'Lidarr';
  @override
  String get version => '2.6.4.4402';

  @override
  String rootFolder(ServerContext c) => '/mnt/tank/media/music';

  JsonMap _artist(ServerContext c) => {
    'id': 1,
    'artistName': 'Jan Morgenstern',
    'sortName': 'morgenstern, jan',
    'foreignArtistId': 'b3c7d8e9-0000-4000-8000-00000000jm01',
    'status': 'continuing',
    'monitored': true,
    'path': '/mnt/tank/media/music/Jan Morgenstern',
    'qualityProfileId': 1,
    'metadataProfileId': 1,
    'added': c.ago(const Duration(days: 500)),
    'images': const <Object?>[],
    'statistics': {
      'albumCount': 4,
      'trackFileCount': 15,
      'trackCount': 20,
      'totalTrackCount': 20,
      'sizeOnDisk': 900000000,
      'percentOfTracks': 75.0,
    },
  };

  List<JsonMap> _albums(ServerContext c) => [
    for (final (id, title, year, onDisk) in const [
      (1, 'Elephants Dream', 2006, true),
      (2, 'Big Buck Bunny', 2008, true),
      (3, 'Sintel', 2010, true),
      (4, 'Sintel (Anniversary Edition)', 2026, false),
    ])
      {
        'id': id,
        'artistId': 1,
        'title': title,
        'foreignAlbumId': 'album-jm-$id',
        'albumType': 'Album',
        'monitored': true,
        'releaseDate': id == 4
            ? c.ahead(const Duration(days: 2, hours: 3))
            : '$year-01-01T00:00:00Z',
        'images': const <Object?>[],
        'artist': _artist(c),
        'statistics': {
          'trackFileCount': onDisk ? 5 : 0,
          'trackCount': 5,
          'totalTrackCount': 5,
          'sizeOnDisk': onDisk ? 300000000 : 0,
          'percentOfTracks': onDisk ? 100.0 : 0.0,
        },
      },
  ];

  @override
  List<JsonMap> calendar(ServerContext c) => [
    for (final album in _albums(c))
      if (album['id'] == 4) album,
  ];

  @override
  NetworkReply? own(NetworkRequest r, ServerContext c) {
    if (r.method != 'GET') return null;
    return switch (r.path) {
      '/api/v1/artist' => NetworkReply.json([_artist(c)]),
      '/api/v1/artist/1' => NetworkReply.json(_artist(c)),
      // The search route, as Radarr's and Sonarr's fakes answer theirs: the
      // world's artist, with its library id, whatever the term.
      '/api/v1/artist/lookup' => NetworkReply.json([_artist(c)]),
      '/api/v1/album' => NetworkReply.json(_albums(c)),
      '/api/v1/metadataprofile' => NetworkReply.json([
        {'id': 1, 'name': 'Standard'},
      ]),
      '/api/v1/track' ||
      '/api/v1/trackfile' => NetworkReply.json(const <Object?>[]),
      _ => null,
    };
  }
}

// === Readarr (World B) ======================================================

class ReadarrFake extends ArrFake {
  const ReadarrFake();

  @override
  String get apiVersion => 'v1';
  @override
  String get appName => 'Readarr';
  @override
  String get version => '0.4.3.2665';

  @override
  NetworkReply? own(NetworkRequest r, ServerContext c) {
    if (r.method != 'GET') return null;
    return switch (r.path) {
      '/api/v1/author' ||
      '/api/v1/book' => NetworkReply.json(const <Object?>[]),
      _ => null,
    };
  }
}

// === Prowlarr ==============================================================

class ProwlarrFake extends ArrFake {
  const ProwlarrFake();

  @override
  List<JsonMap>? get indexers => null;

  @override
  String get apiVersion => 'v1';
  @override
  String get appName => 'Prowlarr';
  @override
  String get version => '1.24.3.4754';

  static const indexerNames = [
    'Atlas NZB',
    'Beacon Usenet',
    'Cedar Index',
    'Delta Newz',
    'Ember NZB',
    'Fjord Tracker',
    'Grove Index',
    'Harbor Newz',
    'Iris Tracker',
    'Juniper NZB',
    'Kestrel Index',
    'Lumen Tracker',
    'Meridian NZB',
    'Nova Index',
  ];

  static const _grabs = {
    'Atlas NZB': 12,
    'Beacon Usenet': 9,
    'Fjord Tracker': 7,
    'Harbor Newz': 5,
  };

  /// One application as `GET /api/v1/applications` sends it: an
  /// `ApplicationResource` whose fields are the implementation's settings
  /// (`Applications/Radarr/RadarrSettings.cs`: `prowlarrUrl`, `baseUrl`,
  /// `apiKey`, `syncCategories`), the key masked as `ClientSchema/
  /// SchemaBuilder.cs` masks every `ApiKey` field. Under `withDockerHostnames`
  /// both addresses are the containers'.
  static JsonMap _application(
    int id,
    String name, {
    required String baseUrl,
    required bool docker,
  }) {
    final implementation = name.split(' ').first;
    return {
      'id': id,
      'name': name,
      'syncLevel': 'fullSync',
      'fields': [
        {
          'order': 0,
          'name': 'prowlarrUrl',
          'label': 'Prowlarr Server',
          'value': docker ? WorldContainers.prowlarr : WorldHosts.prowlarr,
          'type': 'textbox',
          'advanced': false,
          'privacy': 'normal',
          'isFloat': false,
        },
        {
          'order': 1,
          'name': 'baseUrl',
          'label': '$implementation Server',
          'value': baseUrl,
          'type': 'textbox',
          'advanced': false,
          'privacy': 'normal',
          'isFloat': false,
        },
        {
          'order': 2,
          'name': 'apiKey',
          'label': 'API Key',
          'value': '********',
          'type': 'textbox',
          'advanced': false,
          'privacy': 'apiKey',
          'isFloat': false,
        },
        {
          'order': 5,
          'name': 'syncCategories',
          'label': 'Sync Categories',
          'value': const [2000, 2010, 2020, 2030, 2040, 2045, 2050, 2060],
          'type': 'select',
          'advanced': true,
          'privacy': 'normal',
          'isFloat': false,
        },
      ],
      'implementationName': implementation,
      'implementation': implementation,
      'configContract': '${implementation}Settings',
      'infoLink':
          'https://wiki.servarr.com/prowlarr/supported#'
          '${implementation.toLowerCase()}',
      'tags': const <Object?>[],
    };
  }

  @override
  NetworkReply? own(NetworkRequest r, ServerContext c) {
    if (r.method != 'GET') return null;
    switch (r.path) {
      case '/api/v1/indexer':
        return NetworkReply.json([
          for (final (i, name) in indexerNames.indexed)
            {
              'id': i + 1,
              'name': name,
              'enable': true,
              'protocol': name.contains('Tracker') ? 'torrent' : 'usenet',
              'privacy': 'private',
              'priority': 25,
              'appProfileId': 1,
              'tags': const <Object?>[],
              'fields': const <Object?>[],
            },
        ]);
      case '/api/v1/indexerstatus':
        return NetworkReply.json(const <Object?>[]);
      case '/api/v1/indexerstats':
        return NetworkReply.json({
          'indexers': [
            for (final (i, name) in indexerNames.indexed)
              {
                'indexerId': i + 1,
                'indexerName': name,
                'numberOfQueries': 90 + i,
                'numberOfGrabs': _grabs[name] ?? 1,
                'numberOfFailedQueries': 0,
                'numberOfFailedGrabs': 0,
                'averageResponseTime': 420,
              },
          ],
          'userAgents': const <Object?>[],
          'hosts': const <Object?>[],
        });
      case '/api/v1/applications':
        return NetworkReply.json([
          for (final (i, (name, id, url)) in const [
            ('Radarr', WorldIds.radarr, WorldHosts.radarr),
            ('Radarr 4K', WorldIds.radarr4k, WorldHosts.radarr4k),
            ('Sonarr', WorldIds.sonarr, WorldHosts.sonarr),
            ('Lidarr', WorldIds.lidarr, WorldHosts.lidarr),
          ].indexed)
            _application(
              i + 1,
              name,
              docker: c.profile.dockerHostnames,
              baseUrl: c.profile.dockerHostnames
                  ? WorldContainers.of(id) ?? url
                  : url,
            ),
        ]);
      case '/api/v1/appprofile':
        return NetworkReply.json([
          {'id': 1, 'name': 'Standard'},
        ]);
      case '/api/v1/indexer/categories':
        return NetworkReply.json(const <Object?>[]);
    }
    return null;
  }
}

// === Bazarr ================================================================

/// Bazarr follows the Radarr and Sonarr it was pointed at in its own
/// settings; it has no idea which Cupola connection that is.
class BazarrFake extends ServiceFake {
  const BazarrFake();

  // Bazarr takes its key as `X-API-KEY` and answers a bad one with 401.

  @override
  NetworkReply? answer(NetworkRequest r, ServerContext c) {
    if (r.method != 'GET') {
      return NetworkReply.json(const <String, Object?>{}, status: 204);
    }
    switch (r.path) {
      case '/api/system/status':
        return NetworkReply.json({
          'data': {
            'bazarr_version': '1.5.1',
            'sonarr_version': '4.0.9.2244',
            'radarr_version': '5.14.0.9383',
            'operating_system': 'Linux',
          },
        });
      case '/api/badges':
        final followsSonarr = c.profile.bazarrFollows.contains(
          ServiceKey.sonarr,
        );
        return NetworkReply.json({
          'episodes': followsSonarr ? 49 : 0,
          'movies': 8,
          'providers': 0,
          'status': 0,
          'sonarr_signalr': followsSonarr ? 'LIVE' : '',
          'radarr_signalr': 'LIVE',
          'announcements': 0,
        });
      case '/api/system/health':
        return NetworkReply.json({'data': const <Object?>[]});
      case '/api/providers':
        return NetworkReply.json({
          'data': [
            for (final name in const ['opensubtitlescom', 'podnapisi', 'subdl'])
              {'name': name, 'status': 'Good', 'retry': '-'},
          ],
        });
      case '/api/system/languages/profiles':
        return NetworkReply.json(const <Object?>[]);
      case '/api/movies/wanted':
        final rows = [
          {
            'title': WorldTitles.tearsOfSteel.title,
            'radarrId': _tearsOfSteel,
            'missing_subtitles': _german,
            'sceneName': 'Tears.of.Steel.2012.1080p',
          },
        ];
        final ids = _ids(r, 'radarrid[]');
        if (ids == null) return NetworkReply.json({'data': rows, 'total': 8});
        return _rows([
          for (final row in rows)
            if (ids.contains(row['radarrId'])) row,
        ]);
      case '/api/episodes/wanted'
          when !c.profile.bazarrFollows.contains(ServiceKey.sonarr):
        return NetworkReply.json({'data': const <Object?>[], 'total': 0});
      case '/api/episodes/wanted':
        final rows = [
          for (var e = 1; e <= 3; e++)
            {
              'seriesTitle': WorldTitles.cosmosLaundromat.title,
              'episode_number': '2x0$e',
              'episodeTitle': 'Episode $e',
              'sonarrSeriesId': _cosmosLaundromat,
              'sonarrEpisodeId': 1010 + e,
              'missing_subtitles': _italian,
            },
        ];
        // Wanted filters by episode, never by series.
        final ids = _ids(r, 'episodeid[]');
        if (ids == null) return NetworkReply.json({'data': rows, 'total': 49});
        return _rows([
          for (final row in rows)
            if (ids.contains(row['sonarrEpisodeId'])) row,
        ]);
      case '/api/movies/history':
      case '/api/episodes/history':
        return NetworkReply.json({'data': const <Object?>[], 'total': 0});
      // By id, the one title each page of the world opens; the whole
      // library is not modelled and reads empty.
      case '/api/movies':
        final ids = _ids(r, 'radarrid[]');
        return _rows([
          if (ids != null && ids.contains(_tearsOfSteel))
            {
              'radarrId': _tearsOfSteel,
              'title': WorldTitles.tearsOfSteel.title,
              'year': WorldTitles.tearsOfSteel.year,
              'monitored': true,
              'missing_subtitles': _german,
              'subtitles': const <Object?>[],
            },
        ]);
      case '/api/series':
        final ids = _ids(r, 'seriesid[]');
        return _rows([
          if (ids != null &&
              ids.contains(_cosmosLaundromat) &&
              c.profile.bazarrFollows.contains(ServiceKey.sonarr))
            {
              'sonarrSeriesId': _cosmosLaundromat,
              'title': WorldTitles.cosmosLaundromat.title,
              'year': WorldTitles.cosmosLaundromat.year,
              'monitored': true,
              'episodeMissingCount': 3,
              'episodeFileCount': 4,
            },
        ]);
      case '/api/episodes':
        // Bazarr refuses this read without an id.
        final ids = _ids(r, 'seriesid[]');
        if (ids == null) {
          return NetworkReply.json(
            'Series or Episode ID not provided',
            status: 404,
          );
        }
        return _rows([
          if (ids.contains(_cosmosLaundromat) &&
              c.profile.bazarrFollows.contains(ServiceKey.sonarr))
            for (var e = 1; e <= 4; e++)
              {
                'sonarrSeriesId': _cosmosLaundromat,
                'sonarrEpisodeId': 1010 + e,
                'season': 2,
                'episode': e,
                'title': 'Episode $e',
                'monitored': true,
                // The fourth has its subtitles.
                'missing_subtitles': e < 4 ? _italian : const <Object?>[],
              },
        ]);
    }
    return null;
  }

  /// The Radarr and Sonarr ids Bazarr follows the world's titles under.
  static const _tearsOfSteel = 5;
  static const _cosmosLaundromat = 1;

  static const _german = [
    {'name': 'German', 'code2': 'de', 'code3': 'deu'},
  ];
  static const _italian = [
    {'name': 'Italian', 'code2': 'it', 'code3': 'ita'},
  ];

  /// The ids a `name[]` filter asked for, or null when it asked for none.
  static Set<int>? _ids(NetworkRequest r, String name) {
    final values = r.uri.queryParametersAll[name];
    if (values == null || values.isEmpty) return null;
    return {for (final v in values) ?int.tryParse(v)};
  }

  static NetworkReply _rows(List<Map<String, Object?>> rows) =>
      NetworkReply.json({'data': rows, 'total': rows.length});
}

// === Shared builders =======================================================

/// The world's downloads whose arr row lives on the server [c] reached.
List<WorldDownload> arrDownloads(ServerContext c) => [
  for (final d in c.profile.downloads)
    if (d.arr == c.server.id &&
        d.state != DownloadState.seeding &&
        d.state != DownloadState.stopped &&
        (!d.onlyWithClient ||
            c.profile.connections.any((x) => x.service.name == d.client)))
      d,
];

/// One arr queue record for [d], the shape Radarr/Sonarr/Lidarr share.
Map<String, Object?> arrQueueRecord(
  ServerContext c,
  WorldDownload d, {
  required int index,
  required String media,
  Map<String, Object?>? item,
  int? episodeId,
}) {
  final (status, trackedStatus, trackedState, messages) = switch (d.state) {
    DownloadState.stuck => (
      'warning',
      'warning',
      'downloading',
      [
        {
          'title': d.release,
          'messages': ['The download is stalled with no connections'],
        },
      ],
    ),
    DownloadState.queued => ('queued', 'ok', 'downloading', const <Object?>[]),
    // The client, or somebody, paused it; the arr only reports the pause.
    DownloadState.heldByClient ||
    DownloadState.paused => ('paused', 'ok', 'downloading', const <Object?>[]),
    DownloadState.importBlocked => (
      'completed',
      'warning',
      'importBlocked',
      [
        {
          'title': d.release,
          'messages': [WorldDownloads.blockedImportMessage],
        },
      ],
    ),
    _ => ('downloading', 'ok', 'downloading', const <Object?>[]),
  };
  final eta = d.eta;
  return {
    'id': index,
    if (media == 'movie') 'movieId': item?['id'],
    if (media == 'movie' && item != null) 'movie': item,
    if (media == 'series') 'seriesId': item?['id'],
    if (media == 'series' && item != null) 'series': item,
    if (media == 'series' && d.season != null) 'seasonNumber': d.season,
    if (media == 'series' && episodeId != null) 'episodeId': episodeId,
    if (media == 'series' && episodeId != null)
      'episode': {
        'id': episodeId,
        'seriesId': item?['id'],
        'seasonNumber': d.season,
        'episodeNumber': d.episode,
        'title': 'Episode ${d.episode}',
        'hasFile': false,
        'monitored': true,
      },
    'title': d.release,
    'size': d.size,
    'sizeleft': d.sizeLeft,
    if (eta != null) 'timeleft': _clock(eta),
    if (eta != null) 'estimatedCompletionTime': c.ahead(eta),
    'added': c.ago(const Duration(hours: 3, minutes: 20)),
    'status': status,
    'trackedDownloadStatus': trackedStatus,
    'trackedDownloadState': trackedState,
    'statusMessages': messages,
    if (d.state == DownloadState.stuck)
      'errorMessage': 'The download is stalled with no connections',
    // A torrent's hash upper-cased, as the arrs record it; a usenet job's
    // id as its client handed it out.
    'downloadId': _usenet(d) ? d.id : d.id.toUpperCase(),
    'protocol': _usenet(d) ? 'usenet' : 'torrent',
    'downloadClient': switch (d.client) {
      'sabnzbd' => 'SABnzbd',
      'nzbget' => 'NZBGet',
      'transmission' => 'Transmission',
      _ => 'qBittorrent',
    },
    'indexer': _usenet(d) ? 'Atlas NZB' : 'Fjord Tracker',
    'outputPath': '/mnt/tank/downloads/complete/${d.release}',
    'quality': _quality(
      d.release.contains('2160p')
          ? 'Bluray-2160p'
          : d.release.contains('720p')
          ? 'WEBDL-720p'
          : 'WEBDL-1080p',
    ),
    'languages': const [
      {'id': 1, 'name': 'English'},
    ],
    'customFormats': const <Object?>[],
  };
}

bool _usenet(WorldDownload d) => d.client == 'sabnzbd' || d.client == 'nzbget';

Map<String, Object?> _quality(String name) => {
  'quality': {
    'id': 7,
    'name': name,
    'resolution': name.contains('2160')
        ? 2160
        : name.contains('720')
        ? 720
        : 1080,
  },
  'revision': {'version': 1, 'real': 0, 'isRepack': false},
};

String _clock(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
}
