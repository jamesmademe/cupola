import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/media_names.dart';
import 'package:cupola/features/services/domain/download_names.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

void main() {
  group('arrForClientCategory', () {
    test('the arrs\' own categories and the usual hand-set ones', () {
      expect(arrForClientCategory('radarr'), ServiceKey.radarr);
      expect(arrForClientCategory('Movies'), ServiceKey.radarr);
      expect(arrForClientCategory('tv-sonarr'), ServiceKey.sonarr);
      expect(arrForClientCategory('tv'), ServiceKey.sonarr);
      expect(arrForClientCategory('lidarr'), ServiceKey.lidarr);
      expect(arrForClientCategory('music'), ServiceKey.lidarr);
    });

    test('no category, or one that names no arr, points at none', () {
      expect(arrForClientCategory(null), isNull);
      expect(arrForClientCategory(' '), isNull);
      expect(arrForClientCategory('linux-isos'), isNull);
    });
  });

  group('namesFromParse', () {
    const release = 'Tears.of.Steel.2012.2160p.WEB';

    test('Radarr: a film it holds is the library\'s title', () {
      expect(
        namesFromParse(ServiceKey.radarr, release, {
          'title': release,
          'parsedMovieInfo': {
            'movieTitles': ['Tears of Steel'],
            'year': 2012,
          },
          'movie': {'id': 5, 'title': 'Tears of Steel', 'year': 2012},
        }),
        const MediaNames(
          title: 'Tears of Steel',
          machineName: release,
          machineKind: MachineNameKind.release,
        ),
      );
    });

    test('Radarr: a film it does not hold is its parser\'s reading', () {
      final names = namesFromParse(ServiceKey.radarr, release, {
        'title': release,
        'parsedMovieInfo': {
          'movieTitles': ['Tears of Steel'],
        },
      });
      expect(names?.title, 'Tears of Steel');
      expect(names?.source, MediaTitleSource.parser);
      expect(names?.machineName, release);
    });

    test('a name the parser cannot read is nothing', () {
      for (final arr in [
        ServiceKey.radarr,
        ServiceKey.sonarr,
        ServiceKey.lidarr,
      ]) {
        expect(
          namesFromParse(arr, 'ubuntu.iso', {'title': 'ubuntu.iso'}),
          isNull,
          reason: arr.name,
        );
      }
    });

    test('Sonarr: the series it holds, with the parsed episode', () {
      final names = namesFromParse(
        ServiceKey.sonarr,
        'Night.Shift.S02E07.1080p.WEB',
        {
          'parsedEpisodeInfo': {
            'seriesTitle': 'Night Shift',
            'seasonNumber': 2,
            'episodeNumbers': [7],
          },
          'series': {'id': 2, 'title': 'Night Shift'},
        },
      );
      expect(names?.title, startsWith('Night Shift\u00A0· S'));
      expect(names?.source, MediaTitleSource.library);

      final parsedOnly = namesFromParse(
        ServiceKey.sonarr,
        'Night.Shift.S02.1080p.WEB',
        {
          'parsedEpisodeInfo': {
            'seriesTitle': 'Night Shift',
            'seasonNumber': 2,
            'episodeNumbers': <int>[],
          },
        },
      );
      expect(parsedOnly?.title, 'Night Shift');
      expect(parsedOnly?.source, MediaTitleSource.parser);
    });

    test('Lidarr: the album and its artist', () {
      expect(
        namesFromParse(ServiceKey.lidarr, 'Hans.Erdmann-Nosferatu-FLAC', {
          'artist': {'artistName': 'Hans Erdmann'},
          'albums': [
            {'title': 'Nosferatu'},
          ],
        })?.title,
        'Nosferatu\u00A0· Hans Erdmann',
      );
      expect(
        namesFromParse(ServiceKey.lidarr, 'Hans.Erdmann-Nosferatu-FLAC', {
          'parsedAlbumInfo': {
            'albumTitle': 'Nosferatu',
            'artistName': 'Hans Erdmann',
          },
        })?.source,
        MediaTitleSource.parser,
      );
    });
  });
}
