import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/api/base_arr_service.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';
import 'package:cupola/features/music/presentation/lidarr_overview_provider.dart';

import '../../../test_helpers/fake_services.dart';

void main() {
  final now = DateTime(2026, 9, 16, 14, 30);
  final today = DateTime(now.year, now.month, now.day);

  // ─── The em dash ──────────────────────────────────────────────────────────

  group('lidarrCountLabel', () {
    test('a figure nobody answered reads an em dash, never zero', () {
      expect(lidarrCountLabel(null, noun: 'artist'), '—');
    });

    test('a real zero is still allowed to be zero', () {
      // The distinction the em dash exists for: "the server said none" and
      // "nobody asked" must not print the same thing.
      expect(lidarrCountLabel(0, noun: 'artist'), '0 artists');
    });

    test('one is singular', () {
      expect(lidarrCountLabel(1, noun: 'artist'), '1 artist');
      expect(lidarrCountLabel(4, noun: 'folder'), '4 folders');
    });
  });

  // ─── Recently added ───────────────────────────────────────────────────────

  group('lidarrRecentlyAdded', () {
    test('orders by arrival, newest first, and honours the limit', () {
      final artists = lidarrRecentlyAdded([
        _artist(id: 1, name: 'Oldest', added: _iso(today, days: -10)),
        _artist(id: 2, name: 'Newest', added: _iso(today)),
        _artist(id: 3, name: 'Middle', added: _iso(today, days: -2)),
      ], limit: 2);

      expect(artists.map((a) => a.artistName), ['Newest', 'Middle']);
    });

    test('an artist with no arrival time is dropped, not sorted to an end', () {
      final artists = lidarrRecentlyAdded([
        _artist(id: 1, name: 'Undated'),
        _artist(id: 2, name: 'Dated', added: _iso(today)),
      ]);

      expect(artists.map((a) => a.artistName), ['Dated']);
    });
  });

  // ─── Needs attention ──────────────────────────────────────────────────────

  group('lidarrQueueFaults', () {
    test('a stalled transfer is read as stalled, not as a failed import', () {
      // Lidarr marks both with the same `trackedDownloadStatus: warning`, so
      // the order of the two tests is what tells them apart.
      final items = lidarrQueueFaults([
        {
          'artist': {'artistName': 'Alvvays'},
          'album': {'title': 'Blue Rev'},
          'trackedDownloadState': 'importPending',
          'errorMessage': 'The download is stalled with no connections',
          'downloadClient': 'qBittorrent',
        },
      ], now: now);

      expect(items, hasLength(1));
      expect(items.single.kind, LidarrAttentionKind.stalled);
      expect(items.single.headline, 'Stuck · Alvvays, Blue Rev');
      expect(items.single.detail, contains('qBittorrent'));
    });

    test('a pending import carrying a status message is a fault', () {
      final items = lidarrQueueFaults([
        {
          'artist': {'artistName': 'Mk.gee'},
          'album': {'title': 'Two Star'},
          'trackedDownloadState': 'importPending',
          'statusMessages': [
            {'title': 'One or more tracks were not imported'},
          ],
        },
      ], now: now);

      expect(items.single.kind, LidarrAttentionKind.importFailed);
      expect(items.single.tone, StatusTone.warning);
    });

    test('a healthy transfer is not a fault', () {
      // The board draws an in-flight import under this heading; it is
      // informational, and a blue row under "Needs attention" makes the
      // heading wrong about its own contents.
      final items = lidarrQueueFaults([
        {
          'artist': {'artistName': 'Godspeed You! Black Emperor'},
          'album': {'title': 'Luciferian Towers'},
          'trackedDownloadState': 'downloading',
          'status': 'downloading',
        },
      ], now: now);

      expect(items, isEmpty);
    });

    test('the row is spoken as one sentence, with no em dash in it', () {
      final items = lidarrQueueFaults([
        {
          'artist': {'artistName': 'Alvvays'},
          'album': {'title': 'Blue Rev'},
          'trackedDownloadState': 'failed',
          'errorMessage': 'Could not move the file',
        },
      ], now: now);

      expect(
        items.single.spoken,
        'Import failed, Alvvays, Blue Rev, Could not move the file',
      );
    });
  });

  group('lidarrMissingAlbumsItem', () {
    test('counts the envelope total, not the page it happened to fetch', () {
      final item = lidarrMissingAlbumsItem(
        ArrRecordPage(records: List.generate(20, (i) => {'id': i}), total: 312),
      );

      expect(item!.headline, '312 missing monitored albums');
    });

    test('backlog is neutral — never the amber of a fault', () {
      final item = lidarrMissingAlbumsItem(
        const ArrRecordPage(
          records: [
            {'id': 1},
          ],
          total: 1,
        ),
      );

      expect(item!.tone, StatusTone.neutral);
    });

    test('names the artist spread only when the page holds the whole set', () {
      final complete = lidarrMissingAlbumsItem(
        const ArrRecordPage(
          records: [
            {
              'id': 1,
              'artist': {'artistName': 'The Cure'},
            },
            {
              'id': 2,
              'artist': {'artistName': 'The Cure'},
            },
            {
              'id': 3,
              'artist': {'artistName': 'Alvvays'},
            },
          ],
          total: 3,
        ),
      );
      expect(complete!.detail, startsWith('across 2 artists'));

      final truncated = lidarrMissingAlbumsItem(
        const ArrRecordPage(
          records: [
            {
              'id': 1,
              'artist': {'artistName': 'The Cure'},
            },
          ],
          total: 90,
        ),
      );
      // A spread counted from one row of ninety would be a precise-looking
      // lie, so the clause is dropped rather than qualified.
      expect(truncated!.detail, isNot(contains('across')));
    });

    test('an unreadable total is stated as a floor, never as a total', () {
      final item = lidarrMissingAlbumsItem(
        const ArrRecordPage(
          records: [
            {'id': 1},
            {'id': 2},
          ],
          total: null,
        ),
      );

      expect(item!.headline, 'At least 2 missing monitored albums');
    });

    test('nothing outstanding is no row at all', () {
      expect(
        lidarrMissingAlbumsItem(const ArrRecordPage(records: [], total: 0)),
        isNull,
      );
      expect(
        lidarrMissingAlbumsItem(const ArrRecordPage(records: [], total: null)),
        isNull,
      );
    });
  });

  // ─── History today ────────────────────────────────────────────────────────

  group('lidarrHistoryPageIsComplete', () {
    test('a total the page covers means we hold every record', () {
      expect(
        lidarrHistoryPageIsComplete(
          ArrRecordPage(records: List.generate(7, (i) => {'id': i}), total: 7),
          pageSize: 20,
        ),
        isTrue,
      );
    });

    test('a full page with no total may have been truncated', () {
      expect(
        lidarrHistoryPageIsComplete(
          ArrRecordPage(
            records: List.generate(20, (i) => {'id': i}),
            total: null,
          ),
          pageSize: 20,
        ),
        isFalse,
      );
    });

    test('a short page with no total cannot have been truncated', () {
      expect(
        lidarrHistoryPageIsComplete(
          const ArrRecordPage(
            records: [
              {'id': 1},
            ],
            total: null,
          ),
          pageSize: 20,
        ),
        isTrue,
      );
    });
  });

  group('lidarrHistoryToday', () {
    test('yesterday at 23:50 is not today, however recent it is', () {
      final entries = lidarrHistoryToday(
        [
          _history(
            album: 'Yesterday',
            date: today.subtract(const Duration(minutes: 40)),
          ),
          _history(album: 'Today', date: today.add(const Duration(hours: 1))),
        ],
        now: now,
        complete: true,
      );

      expect(entries.map((e) => e.title), ['Alvvays, Today']);
    });

    test('an album imported track by track is one row, not fourteen', () {
      final entries = lidarrHistoryToday(
        [
          for (var i = 0; i < 14; i++)
            _history(
              albumId: 9,
              album: 'Blue Rev',
              date: today.add(Duration(hours: 9, minutes: i)),
              size: 10 * 1024 * 1024,
            ),
        ],
        now: now,
        complete: true,
      );

      expect(entries, hasLength(1));
      expect(entries.single.trackCount, 14);
      expect(entries.single.detail, contains('14 tracks'));
      // The face of the group is its newest record, so the age is the age of
      // the last track to land.
      expect(
        entries.single.date,
        today.add(const Duration(hours: 9, minutes: 13)),
      );
    });

    test('a truncated page states no track count and no size', () {
      final entries = lidarrHistoryToday(
        [
          for (var i = 0; i < 3; i++)
            _history(
              albumId: 9,
              album: 'Blue Rev',
              date: today.add(Duration(hours: 9, minutes: i)),
              size: 10 * 1024 * 1024,
            ),
        ],
        now: now,
        complete: false,
      );

      // Three of an unknown number: a count would be a floor wearing the
      // clothes of a total, and one track's size read as the album's is the
      // same error in bytes.
      expect(entries.single.trackCount, isNull);
      expect(entries.single.detail, isNot(contains('tracks')));
      expect(entries.single.detail, isNot(contains('MB')));
    });

    test('a lone record keeps its own size whatever the page', () {
      final entries = lidarrHistoryToday(
        [
          _history(
            albumId: 4,
            album: 'Diamond Jubilee',
            date: today.add(const Duration(hours: 11)),
            size: 1181116006,
            quality: 'FLAC',
          ),
        ],
        now: now,
        complete: false,
      );

      expect(entries.single.detail, startsWith('FLAC · 1.10 GB'));
    });

    test('different events on one album stay different rows', () {
      final entries = lidarrHistoryToday(
        [
          _history(
            albumId: 9,
            album: 'Blue Rev',
            date: today.add(const Duration(hours: 8)),
            eventType: 'grabbed',
          ),
          _history(
            albumId: 9,
            album: 'Blue Rev',
            date: today.add(const Duration(hours: 9)),
            eventType: 'trackFileImported',
          ),
        ],
        now: now,
        complete: true,
      );

      // Newest first: the import happened after the grab.
      expect(entries.map((e) => e.event), ['Imported', 'Grabbed']);
    });

    test('a completed import is green, not a humanised camel case shrug', () {
      final entries = lidarrHistoryToday(
        [
          _history(
            album: 'Blue Rev',
            date: today.add(const Duration(hours: 9)),
            eventType: 'trackFileImported',
          ),
        ],
        now: now,
        complete: true,
      );

      expect(entries.single.event, 'Imported');
      expect(entries.single.tone, StatusTone.success);
    });

    test('an incomplete album import is a fault, and amber', () {
      final entries = lidarrHistoryToday(
        [
          _history(
            album: 'Blue Rev',
            date: today.add(const Duration(hours: 9)),
            eventType: 'albumImportIncomplete',
          ),
        ],
        now: now,
        complete: true,
      );

      expect(entries.single.event, 'Import incomplete');
      expect(entries.single.tone, StatusTone.warning);
    });

    test('the row is spoken with the em dash resolved into a pause', () {
      final entries = lidarrHistoryToday(
        [
          _history(
            album: 'Blue Rev',
            date: today.add(const Duration(hours: 13)),
            eventType: 'trackFileRetagged',
            quality: 'FLAC',
          ),
        ],
        now: now,
        complete: true,
      );

      expect(
        entries.single.spoken,
        'Alvvays, Blue Rev, Retagged, FLAC, 1 h ago',
      );
    });

    test('only the newest few rows are drawn', () {
      final entries = lidarrHistoryToday(
        [
          for (var i = 0; i < 6; i++)
            _history(
              albumId: i,
              album: 'Album $i',
              date: today.add(Duration(hours: i)),
            ),
        ],
        now: now,
        complete: true,
        limit: 3,
      );

      expect(entries.map((e) => e.title), [
        'Alvvays, Album 5',
        'Alvvays, Album 4',
        'Alvvays, Album 3',
      ]);
    });
  });

  // ─── Root folders ─────────────────────────────────────────────────────────

  group('lidarrRootFolders', () {
    test('free space that was not reported reads an em dash', () {
      final folders = lidarrRootFolders([
        {'path': '/data/music'},
      ]);

      expect(folders.single.freeLabel, '—');
    });

    test('a record with no path is not a folder', () {
      final folders = lidarrRootFolders([
        {'freeSpace': 1000},
        {'path': '/data/music', 'freeSpace': 1979120929996},
      ]);

      expect(folders, hasLength(1));
      expect(folders.single.freeLabel, endsWith('free'));
    });
  });

  // ─── The wiring ───────────────────────────────────────────────────────────

  test(
    'the rail and the backlog come off the calls the client really makes',
    () async {
      final service = _ScriptedLidarr(
        artists: [_artist(id: 1, name: 'Alvvays', added: _iso(today))],
        missing: const ArrRecordPage(
          records: [
            {
              'id': 1,
              'artist': {'artistName': 'Alvvays'},
            },
          ],
          total: 1,
        ),
      );
      final container = ProviderContainer(
        overrides: [lidarrServiceProvider.overrideWith((ref) => service)],
      );
      addTearDown(container.dispose);

      expect(
        (await container.read(
          lidarrRecentlyAddedProvider.future,
        )).single.artistName,
        'Alvvays',
      );
      final attention = await container.read(
        lidarrNeedsAttentionProvider.future,
      );
      expect(attention.single.kind, LidarrAttentionKind.missingAlbums);
      expect(attention.single.headline, '1 missing monitored album');
    },
  );
}

// ─── Harness ────────────────────────────────────────────────────────────────

/// A [FakeLidarrService] with a scripted library, queue, wishlist and history.
///
/// Extends the shared fake rather than editing it: every other test that builds
/// a `FakeLidarrService` keeps the empty defaults it relies on.
class _ScriptedLidarr extends FakeLidarrService {
  _ScriptedLidarr({
    this.artists = const [],
    this.missing = const ArrRecordPage(records: [], total: 0),
  });

  final List<LidarrArtist> artists;
  final ArrRecordPage missing;

  @override
  Future<List<LidarrArtist>> getArtists() async => artists;

  @override
  Future<ArrRecordPage> getMissingPage({
    int page = 1,
    int pageSize = 20,
    Map<String, dynamic>? queryParameters,
  }) async => missing;
}

LidarrArtist _artist({
  required int id,
  String name = 'Artist',
  String? added,
  int albumCount = 0,
}) => LidarrArtist(
  id: id,
  artistName: name,
  status: 'continuing',
  monitored: true,
  images: const [],
  genres: const [],
  added: added,
  statistics: {'albumCount': albumCount},
);

String _iso(DateTime day, {int days = 0}) =>
    day.add(Duration(days: days)).toIso8601String();

/// One history record, in the shape Lidarr answers with: the artist and the
/// album as embedded objects, the event as a camel-cased type.
Map<String, dynamic> _history({
  required String album,
  required DateTime date,
  int? albumId,
  String artist = 'Alvvays',
  String eventType = 'trackFileImported',
  String? quality,
  int? size,
}) => {
  'eventType': eventType,
  'date': date.toIso8601String(),
  'artist': {'artistName': artist},
  'album': {'title': album, 'id': ?albumId},
  'quality': ?(quality == null
      ? null
      : {
          'quality': {'name': quality},
        }),
  'size': ?size,
};
