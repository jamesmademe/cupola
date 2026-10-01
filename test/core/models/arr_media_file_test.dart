import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/models/arr_media_file.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';

/// `movieFile` as Radarr v3 embeds it in `GET /api/v3/movie/{id}`
/// (`MovieFileResource`), trimmed to the fields that matter here.
Map<String, dynamic> _movieFile({
  String? relativePath = 'Coffee Run (2020) WEBDL-1080p.mkv',
  String? sceneName = 'Coffee.Run.2020.1080p.WEB-DL.DDP5.1.H.264-WORLD',
  String? originalFilePath =
      'Coffee.Run.2020.1080p.WEB-DL.DDP5.1.H.264-WORLD/coffee.run.mkv',
}) => {
  'id': 31,
  'movieId': 3,
  'relativePath': relativePath,
  'path':
      '/mnt/tank/media/films/Coffee Run (2020)/'
      'Coffee Run (2020) WEBDL-1080p.mkv',
  'size': 1203741824,
  'dateAdded': '2026-09-30T19:42:11Z',
  'sceneName': sceneName,
  'releaseGroup': 'WORLD',
  'quality': {
    'quality': {
      'id': 3,
      'name': 'WEBDL-1080p',
      'source': 'webdl',
      'resolution': 1080,
    },
    'revision': {'version': 1, 'real': 0, 'isRepack': false},
  },
  'originalFilePath': originalFilePath,
  'qualityCutoffNotMet': false,
};

void main() {
  group('ArrMediaFile.fromJson', () {
    test('reads the file, its size, quality, date and its original names', () {
      final file = ArrMediaFile.fromJson(_movieFile());

      expect(file.relativePath, 'Coffee Run (2020) WEBDL-1080p.mkv');
      expect(
        file.path,
        '/mnt/tank/media/films/Coffee Run (2020)/'
        'Coffee Run (2020) WEBDL-1080p.mkv',
      );
      expect(file.size, 1203741824);
      expect(file.qualityName, 'WEBDL-1080p');
      expect(file.dateAdded, DateTime.utc(2026, 9, 30, 19, 42, 11));
      expect(file.sceneName, 'Coffee.Run.2020.1080p.WEB-DL.DDP5.1.H.264-WORLD');
      expect(
        file.originalFilePath,
        'Coffee.Run.2020.1080p.WEB-DL.DDP5.1.H.264-WORLD/coffee.run.mkv',
      );
    });

    test('keeps a name exactly as sent, and a blank one is absent', () {
      final file = ArrMediaFile.fromJson(
        _movieFile(relativePath: ' Odd name .mkv', sceneName: '   '),
      );
      expect(file.relativePath, ' Odd name .mkv');
      expect(file.sceneName, isNull);
    });
  });

  group('ArrMediaFile.fileName', () {
    test('is the relative path, in full', () {
      expect(
        ArrMediaFile.fromJson(_movieFile()).fileName,
        'Coffee Run (2020) WEBDL-1080p.mkv',
      );
    });

    test('falls back to the last part of the absolute path', () {
      expect(
        ArrMediaFile.fromJson(_movieFile(relativePath: null)).fileName,
        'Coffee Run (2020) WEBDL-1080p.mkv',
      );
    });

    test('is null when the service named no file', () {
      expect(const ArrMediaFile().fileName, isNull);
    });
  });

  group('ArrMediaFile.releasedAs', () {
    test('is the scene name when the file was renamed', () {
      expect(
        ArrMediaFile.fromJson(_movieFile()).releasedAs,
        'Coffee.Run.2020.1080p.WEB-DL.DDP5.1.H.264-WORLD',
      );
    });

    test('is null when the file still carries its release name', () {
      // Renaming off: the file is the release, plus its extension, and the
      // scene name has none.
      expect(
        ArrMediaFile.fromJson(
          _movieFile(
            relativePath: 'Tears.of.Steel.2012.1080p.BluRay.x264-WORLD.mkv',
            sceneName: 'Tears.of.Steel.2012.1080p.BluRay.x264-WORLD',
          ),
        ).releasedAs,
        isNull,
      );
    });

    test('falls back to the original file path, exactly as recorded', () {
      expect(
        ArrMediaFile.fromJson(_movieFile(sceneName: null)).releasedAs,
        'Coffee.Run.2020.1080p.WEB-DL.DDP5.1.H.264-WORLD/coffee.run.mkv',
      );
    });

    test('is null when the original path names the same file', () {
      expect(
        ArrMediaFile.fromJson(
          _movieFile(
            sceneName: null,
            originalFilePath: 'Some.Folder/Coffee Run (2020) WEBDL-1080p.mkv',
          ),
        ).releasedAs,
        isNull,
      );
    });

    test('is null when the service recorded no original', () {
      expect(
        ArrMediaFile.fromJson(
          _movieFile(sceneName: null, originalFilePath: null),
        ).releasedAs,
        isNull,
      );
    });
  });

  group('RadarrMovie.movieFile', () {
    test('is read from the movie resource', () {
      final movie = RadarrMovie.fromJson({
        'id': 3,
        'title': 'Coffee Run',
        'hasFile': true,
        'path': '/mnt/tank/media/films/Coffee Run (2020)',
        'movieFile': _movieFile(),
      });
      expect(movie.movieFile?.fileName, 'Coffee Run (2020) WEBDL-1080p.mkv');
    });

    test('is null without a file', () {
      final movie = RadarrMovie.fromJson(const {
        'id': 1,
        'title': 'Sprite Fright',
        'hasFile': false,
      });
      expect(movie.movieFile, isNull);
    });
  });
}
