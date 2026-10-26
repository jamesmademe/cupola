import 'package:flutter_test/flutter_test.dart';
import 'package:cupola/features/import/domain/manual_import_models.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

void main() {
  group('ManualImportItem', () {
    test('does not treat zero file ids as already imported', () {
      final sonarrItem = ManualImportItem.fromJson({
        'path': '/downloads/Frieren.S02E05.mkv',
        'name': 'Frieren.S02E05.mkv',
        'episodeFileId': 0,
      });
      final radarrItem = ManualImportItem.fromJson({
        'path': '/downloads/Movie.mkv',
        'name': 'Movie.mkv',
        'movieFileId': 0,
      });

      expect(sonarrItem.isAlreadyImported, isFalse);
      expect(sonarrItem.isSelectable, isTrue);
      expect(radarrItem.isAlreadyImported, isFalse);
      expect(radarrItem.isSelectable, isTrue);
    });

    group('isSample', () {
      ManualImportItem itemWith(String reason) => ManualImportItem.fromJson({
        'path': '/downloads/sample-do-not-import.mkv',
        'movie': {'id': 42, 'title': 'Some Movie'},
        'rejections': [
          {'reason': reason, 'type': 'permanent'},
        ],
      });

      test('reads the service\u2019s own word for it', () {
        // A sample is matched exactly like the rip beside it, so nothing else
        // in the payload tells them apart; only the rejection does.
        expect(itemWith('Sample').isSample, isTrue);
        expect(itemWith('File is a sample').isSample, isTrue);
        expect(itemWith('Sample file').isSample, isTrue);
      });

      test('is a whole word, not a substring', () {
        // Lidarr states real audio facts about resampling, and a file the
        // service resampled is not a trailer.
        expect(itemWith('Audio was resampled to 48 kHz').isSample, isFalse);
        expect(itemWith('Oversampling detected').isSample, isFalse);
      });

      test('an ordinary rejection is not one', () {
        expect(itemWith('Not a preferred word upgrade').isSample, isFalse);
        expect(
          ManualImportItem.fromJson({'path': '/downloads/x.mkv'}).isSample,
          isFalse,
        );
      });

      test('stays importable: the badge removes a default, not a choice', () {
        // The row keeps its match and its checkbox. A user who wants the
        // sample taken can still take it. Only the preselect changed.
        final sample = itemWith('Sample');
        expect(sample.isReadyForImportFor(ServiceKey.radarr), isTrue);
        expect(sample.isSubmittableFor(ServiceKey.radarr), isTrue);
      });
    });

    test('treats positive file ids as already imported', () {
      final sonarrItem = ManualImportItem.fromJson({
        'path': '/downloads/Frieren.S02E01.mkv',
        'name': 'Frieren.S02E01.mkv',
        'episodeFileId': 42,
      });
      final radarrItem = ManualImportItem.fromJson({
        'path': '/downloads/Movie.mkv',
        'name': 'Movie.mkv',
        'movieFileId': 99,
      });

      expect(sonarrItem.isAlreadyImported, isTrue);
      expect(sonarrItem.isSelectable, isFalse);
      expect(radarrItem.isAlreadyImported, isTrue);
      expect(radarrItem.isSelectable, isFalse);
    });

    test('includes episode code in sonarr media subtitle', () {
      final item = ManualImportItem.fromJson({
        'path': '/downloads/Frieren.S02E05.mkv',
        'name': 'Frieren.S02E05.mkv',
        'series': {'id': 10, 'title': 'Frieren', 'year': 2023},
        'seasonNumber': 2,
        'episodes': [
          {
            'id': 50,
            'seasonNumber': 2,
            'episodeNumber': 5,
            'title': 'Episode 5',
          },
        ],
      });

      expect(item.mediaSubtitle, contains('S2 E5'));
    });

    test('preserves original size when resolved with assignment', () {
      final original = ManualImportItem.fromJson({
        'path': '/downloads/Frieren.S02E05.mkv',
        'name': 'Frieren.S02E05.mkv',
        'size': 1300000000,
      });
      final assignment = ManualImportFixAssignment(
        match: ManualImportLookupResult(
          id: 10,
          title: 'Frieren',
          raw: {'id': 10, 'title': 'Frieren', 'year': 2023},
        ),
      );

      final resolved = original.resolvedWithAssignment(
        ServiceKey.sonarr,
        assignment,
      );

      expect(resolved.size, 1300000000);
    });

    test('resolved assignment keeps size and applies sonarr episode', () {
      final original = ManualImportItem.fromJson({
        'path': '/downloads/Frieren.S02E05.mkv',
        'name': 'Frieren.S02E05.mkv',
        'size': 1300000000,
      });
      final assignment = ManualImportFixAssignment(
        match: ManualImportLookupResult(
          id: 10,
          title: 'Frieren',
          raw: {'id': 10, 'title': 'Frieren', 'year': 2023},
        ),
        episode: ManualImportEpisode(
          id: 50,
          seasonNumber: 2,
          episodeNumber: 5,
          title: 'Episode 5',
          raw: {
            'id': 50,
            'seasonNumber': 2,
            'episodeNumber': 5,
            'title': 'Episode 5',
          },
        ),
      );

      final resolved = original.resolvedWithAssignment(
        ServiceKey.sonarr,
        assignment,
      );

      expect(resolved.size, 1300000000);
      expect(resolved.mediaSubtitle, contains('S2 E5'));
      expect(resolved.hasMatchFor(ServiceKey.sonarr), isTrue);
    });

    test('requires only import-blocking ids for sonarr readiness', () {
      final item = ManualImportItem.fromJson({
        'path': '/downloads/Frieren.S02E05.mkv',
        'name': 'Frieren.S02E05.mkv',
        'series': {'id': 10, 'title': 'Frieren'},
        'episodes': [
          {'id': 50, 'seasonNumber': 2, 'episodeNumber': 5, 'title': 'E5'},
        ],
        'rejections': [
          {'reason': 'Unable to determine quality', 'type': 'permanent'},
        ],
      });

      expect(item.hasBlockingMetadataRejection, isTrue);
      expect(item.isReadyForImportFor(ServiceKey.sonarr), isTrue);
    });

    test('reads quality label from nested quality payloads', () {
      final item = ManualImportItem.fromJson({
        'path': '/downloads/Frozen.2.mkv',
        'name': 'Frozen.2.mkv',
        'quality': {
          'quality': {
            'quality': {'id': 7, 'name': 'Bluray-1080p'},
          },
        },
      });

      expect(item.qualityLabel, 'Bluray-1080p');
      expect(item.qualityId, 7);
    });
  });

  group('ManualImportMode', () {
    test('api value uses lowercase enum name', () {
      expect(ManualImportMode.auto.apiValue, 'auto');
      expect(ManualImportMode.move.apiValue, 'move');
      expect(ManualImportMode.copy.apiValue, 'copy');
    });
  });

  group('ManualImportItem.toCommandFileJson', () {
    test('radarr file body has movieId and no other-service fields', () {
      final item = ManualImportItem.fromJson({
        'path': '/downloads/Inception.2010.mkv',
        'name': 'Inception.2010.mkv',
        'folderName': 'Inception (2010)',
        'quality': {
          'quality': {'id': 7, 'name': 'Bluray-1080p'},
          'revision': {'version': 1, 'real': 0, 'isRepack': false},
        },
        'languages': [
          {'id': 1, 'name': 'English'},
        ],
        'releaseGroup': 'SPARKS',
        'indexerFlags': 0,
        'downloadId': '',
        'movie': {'id': 123, 'title': 'Inception'},
        'series': {'id': 999, 'title': 'Inception Series'},
        'episodes': [
          {'id': 50, 'seasonNumber': 1, 'episodeNumber': 1, 'title': 'E1'},
        ],
        'tracks': [
          {'id': 4, 'title': 'Track 1'},
        ],
        'id': 99999,
        'rejections': [
          {'reason': 'old', 'type': 'permanent'},
        ],
        'customFormats': [
          {'id': 1, 'name': 'CF1'},
        ],
        'customFormatScore': 50,
      });

      final file = item.toCommandFileJson(ServiceKey.radarr);

      expect(file['path'], '/downloads/Inception.2010.mkv');
      expect(file['folderName'], 'Inception (2010)');
      expect(file['movieId'], 123);
      expect(file['releaseGroup'], 'SPARKS');
      expect(file['indexerFlags'], 0);
      // Must NOT contain other-service fields or response-only fields.
      expect(file.containsKey('seriesId'), isFalse);
      expect(file.containsKey('artistId'), isFalse);
      expect(file.containsKey('albumId'), isFalse);
      expect(file.containsKey('albumReleaseId'), isFalse);
      expect(file.containsKey('episodeIds'), isFalse);
      expect(file.containsKey('episodeFileId'), isFalse);
      expect(file.containsKey('trackIds'), isFalse);
      expect(file.containsKey('releaseType'), isFalse);
      expect(file.containsKey('disableReleaseSwitching'), isFalse);
      expect(file.containsKey('episodes'), isFalse);
      expect(file.containsKey('tracks'), isFalse);
      expect(file.containsKey('id'), isFalse);
      expect(file.containsKey('rejections'), isFalse);
      expect(file.containsKey('customFormats'), isFalse);
      expect(file.containsKey('customFormatScore'), isFalse);
      expect(file.containsKey('movie'), isFalse);
      expect(file.containsKey('series'), isFalse);
      expect(file.containsKey('artist'), isFalse);
    });

    test('sonarr file body has seriesId and episodeIds', () {
      final item = ManualImportItem.fromJson({
        'path': '/downloads/Frieren.S02E05.mkv',
        'name': 'Frieren.S02E05.mkv',
        'folderName': 'Frieren (2023) - S02',
        'quality': {
          'quality': {'id': 7, 'name': 'Bluray-1080p'},
        },
        'languages': [
          {'id': 1, 'name': 'English'},
        ],
        'series': {'id': 10, 'title': 'Frieren'},
        'episodes': [
          {'id': 50, 'seasonNumber': 2, 'episodeNumber': 5, 'title': 'E5'},
        ],
        'movie': {'id': 999, 'title': 'Some movie'},
        'tracks': [
          {'id': 4, 'title': 'Track 1'},
        ],
        'id': 11111,
        'rejections': [],
      });

      final file = item.toCommandFileJson(ServiceKey.sonarr);

      expect(file['path'], '/downloads/Frieren.S02E05.mkv');
      expect(file['folderName'], 'Frieren (2023) - S02');
      expect(file['seriesId'], 10);
      expect(file['episodeIds'], [50]);
      expect(file.containsKey('movieId'), isFalse);
      expect(file.containsKey('artistId'), isFalse);
      expect(file.containsKey('albumId'), isFalse);
      expect(file.containsKey('trackIds'), isFalse);
      expect(file.containsKey('episodes'), isFalse);
      expect(file.containsKey('tracks'), isFalse);
      expect(file.containsKey('id'), isFalse);
      expect(file.containsKey('rejections'), isFalse);
      expect(file.containsKey('movie'), isFalse);
    });

    test(
      'lidarr file body has artistId, albumId, albumReleaseId, trackIds',
      () {
        final item = ManualImportItem.fromJson({
          'path': '/downloads/Artist/Album/Track01.flac',
          'name': 'Track01.flac',
          'quality': {
            'quality': {'id': 1, 'name': 'FLAC'},
          },
          'artist': {'id': 1, 'title': 'Artist'},
          'album': {'id': 2, 'title': 'Album'},
          'albumReleaseId': 3,
          'tracks': [
            {'id': 4, 'title': 'Track 1'},
          ],
          'languages': [
            {'id': 1, 'name': 'English'},
          ],
          'movie': {'id': 999, 'title': 'Some movie'},
          'series': {'id': 999, 'title': 'Some series'},
          'episodes': [
            {'id': 50, 'seasonNumber': 1, 'episodeNumber': 1, 'title': 'E1'},
          ],
          'id': 22222,
          'rejections': [],
        });

        final file = item.toCommandFileJson(ServiceKey.lidarr);

        expect(file['path'], '/downloads/Artist/Album/Track01.flac');
        expect(file['artistId'], 1);
        expect(file['albumId'], 2);
        expect(file['albumReleaseId'], 3);
        expect(file['trackIds'], [4]);
        expect(file.containsKey('movieId'), isFalse);
        expect(file.containsKey('seriesId'), isFalse);
        expect(file.containsKey('episodeIds'), isFalse);
        expect(file.containsKey('episodes'), isFalse);
        expect(file.containsKey('tracks'), isFalse);
        expect(file.containsKey('id'), isFalse);
        // Lidarr ignores languages in the command file body.
        expect(file.containsKey('languages'), isFalse);
        expect(file.containsKey('rejections'), isFalse);
        expect(file.containsKey('movie'), isFalse);
        expect(file.containsKey('series'), isFalse);
        expect(file.containsKey('artist'), isFalse);
      },
    );

    group('a lidarr album chosen by hand sends its monitored release', () {
      // Lidarr's album and track carry no `albumReleaseId`; the release is in
      // the album's `releases`. Sending 0 makes Lidarr fail the import with
      // "AlbumRelease with ID 0 does not exist".
      ManualImportItem unmatched() => ManualImportItem.fromJson({
        'path': '/downloads/Air/Moon Safari/02.flac',
        'name': '02.flac',
        'albumReleaseId': 0,
      });

      ManualImportFixAssignment pick(Map<String, dynamic> album) =>
          ManualImportFixAssignment(
            match: ManualImportLookupResult(
              id: 7,
              title: 'Air',
              raw: {'id': 7, 'artistName': 'Air'},
            ),
            album: ManualImportAlbum(id: 9, title: 'Moon Safari', raw: album),
            track: ManualImportTrack(
              id: 42,
              title: 'Sexy Boy',
              raw: {'id': 42, 'albumId': 9, 'title': 'Sexy Boy'},
            ),
          );

      test('the monitored one among several', () {
        final resolved = unmatched().resolvedWithAssignment(
          ServiceKey.lidarr,
          pick({
            'id': 9,
            'title': 'Moon Safari',
            'releases': [
              {'id': 378, 'monitored': false},
              {'id': 385, 'monitored': true},
            ],
          }),
        );

        final file = resolved.toCommandFileJson(ServiceKey.lidarr);
        expect(file['albumId'], 9);
        expect(file['albumReleaseId'], 385);
        expect(file['trackIds'], [42]);
      });

      test('the only one when none is marked monitored', () {
        final resolved = unmatched().resolvedWithAssignment(
          ServiceKey.lidarr,
          pick({
            'id': 9,
            'releases': [
              {'id': 378, 'monitored': false},
            ],
          }),
        );

        expect(resolved.albumReleaseId, 378);
      });

      test('never the scan\'s release of another album', () {
        final scanned = ManualImportItem.fromJson({
          'path': '/downloads/Air/Moon Safari/02.flac',
          'name': '02.flac',
          'album': {'id': 1, 'title': 'Talkie Walkie'},
          'albumReleaseId': 11,
        });

        final resolved = scanned.resolvedWithAssignment(
          ServiceKey.lidarr,
          pick({'id': 9, 'releases': const []}),
        );

        expect(resolved.albumReleaseId, isNull);
        expect(
          resolved
              .toCommandFileJson(ServiceKey.lidarr)
              .containsKey('albumReleaseId'),
          isFalse,
        );
      });
    });
  });
}
