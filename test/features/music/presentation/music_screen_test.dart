import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/music/domain/models/lidarr_artist.dart';
import 'package:cupola/features/music/presentation/music_screen.dart';

LidarrArtist _artist({Map<String, dynamic>? statistics}) {
  return LidarrArtist.fromJson({
    'id': 1,
    'artistName': 'Boards of Canada',
    'foreignArtistId': 'x',
    'status': 'continuing',
    'monitored': true,
    'images': const <dynamic>[],
    // Absent and explicitly null are the same answer to `fromJson`, and the
    // absent case is the one this file cares about.
    'statistics': statistics,
  });
}

void main() {
  group('lidarrArtistCaption', () {
    test('an artist Lidarr has not counted reads a dash, never a zero', () {
      // `statistics` absent is no answer, not "0 albums". A zero here would be
      // the app inventing a fact about a library it has not scanned.
      expect(lidarrArtistCaption(_artist()), '—');
    });

    test('every track on disk reads complete', () {
      expect(
        lidarrArtistCaption(
          _artist(
            statistics: const {
              'albumCount': 6,
              'trackCount': 71,
              'trackFileCount': 71,
            },
          ),
        ),
        '6 albums · complete',
      );
    });

    test('the shortfall is stated in the unit Lidarr counts', () {
      // The board writes "9 albums · 1 missing", but the artist payload carries
      // no per-album file state: the only shortfall this endpoint can support
      // is in tracks, and naming it in albums would be a number in the wrong
      // unit dressed as the drawn one.
      expect(
        lidarrArtistCaption(
          _artist(
            statistics: const {
              'albumCount': 9,
              'trackCount': 104,
              'trackFileCount': 103,
            },
          ),
        ),
        '9 albums · 1 track missing',
      );
    });

    test('albums with no tracks counted claim no completeness', () {
      expect(
        lidarrArtistCaption(
          _artist(statistics: const {'albumCount': 1, 'trackCount': 0}),
        ),
        '1 album',
      );
    });
  });
}
