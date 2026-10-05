/// A media server's movie is the same title as everyone else's: it opens on
/// the title's own page, and a household with only a media server still sees
/// who the title is there.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/features/media/domain/media_copies.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/media/domain/media_reading.dart';
import 'package:cupola/features/media/domain/media_rows.dart';
import 'package:cupola/features/media/presentation/media_identity.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';

import '../../test_helpers/model_builders.dart';

StreamItem _item({
  StreamItemKind kind = StreamItemKind.movie,
  String? tmdb = '133701',
  String? overview,
}) => StreamItem(
  id: 'jf-1',
  title: 'Tears of Steel',
  subtitle: '2012',
  kind: kind,
  posterPath: '/Items/jf-1/Images/Primary',
  year: 2012,
  runtimeMs: 734000,
  isPlayed: false,
  resumeOffsetMs: null,
  unplayedChildCount: null,
  externalIds: StreamExternalIds(tmdb: tmdb),
  overview: overview,
);

MediaRow _row<T>(String id, ServiceKey service, T value) =>
    MediaConnectionRow<T>(
      ServiceInstance(id: id, service: service),
      MediaReadingAnswered<T>(MediaAnswer<T>(value, DateTime(2026, 10, 5))),
    );

void main() {
  group('the page a media server item opens', () {
    test('a movie with a TMDB id is that movie', () {
      expect(MediaKey.ofStreamItem(_item()), const MediaKey.movie(133701));
    });

    test('anything else keeps the server\'s own page', () {
      // A series has no page of its own yet; an episode is not a title; a
      // home video has no TMDB id, and a mangled one names nothing.
      expect(MediaKey.ofStreamItem(_item(kind: StreamItemKind.series)), isNull);
      expect(
        MediaKey.ofStreamItem(_item(kind: StreamItemKind.episode)),
        isNull,
      );
      expect(MediaKey.ofStreamItem(_item(tmdb: null)), isNull);
      expect(MediaKey.ofStreamItem(_item(tmdb: 'tt0133093')), isNull);
      expect(MediaKey.ofStreamItem(_item(tmdb: '0')), isNull);
    });
  });

  group('who the title is, when only a media server says', () {
    test('its name, year, length, synopsis and poster, with the server\'s '
        'credential', () {
      final rows = [
        _row(
          'jellyfin',
          ServiceKey.jellyfin,
          MediaStreamCopy.found(
            _item(overview: 'A group of warriors and scientists.'),
            poster: (
              url: 'https://jellyfin.local/Items/jf-1/Images/Primary',
              headers: const {'X-Emby-Token': 'token'},
            ),
          ),
        ),
      ];

      final identity = MediaIdentity.of(rows)!;

      expect(identity.title, 'Tears of Steel');
      expect(identity.year, '2012');
      expect(identity.runtime, formatRuntimeMinutes(12));
      expect(identity.overview, 'A group of warriors and scientists.');
      expect(
        identity.posterUrl,
        'https://jellyfin.local/Items/jf-1/Images/Primary',
      );
      expect(identity.artHeaders, const {'X-Emby-Token': 'token'});
      // TMDB's identity is Seerr's: nothing here claims a backdrop or credits.
      expect(identity.backdropUrl, isNull);
      expect(identity.creditsLine, isEmpty);
    });

    test('an arr\'s record outranks it, and sends no credential', () {
      final rows = [
        _row(
          'jellyfin',
          ServiceKey.jellyfin,
          MediaStreamCopy.found(
            _item(),
            poster: (
              url: 'https://jellyfin.local/poster',
              headers: const {'X-Emby-Token': 'token'},
            ),
          ),
        ),
        _row(
          'radarr',
          ServiceKey.radarr,
          MediaRadarrCopy(
            movie: buildMovie(id: 5, title: 'Tears of Steel (Radarr)'),
            queue: ArrQueueSnapshot.empty,
          ),
        ),
      ];

      final identity = MediaIdentity.of(rows)!;

      expect(identity.title, 'Tears of Steel (Radarr)');
      expect(identity.artHeaders, isNull);
    });

    test('a server that holds no verified copy says nothing', () {
      final rows = [
        _row(
          'jellyfin',
          ServiceKey.jellyfin,
          const MediaStreamCopy.notVerified(),
        ),
      ];

      expect(MediaIdentity.of(rows), isNull);
    });
  });
}
